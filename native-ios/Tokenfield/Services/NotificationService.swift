import Foundation
import Observation
import UserNotifications
import TokenfieldCore
#if os(macOS)
import AppKit
#endif

private final class ForegroundNotifications: NSObject, UNUserNotificationCenterDelegate {
    #if os(macOS)
    var onQuotaResponse: (@Sendable () async -> Void)?
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           response.notification.request.identifier.hasPrefix(CodexQuotaNotificationRequest.prefix) {
            await onQuotaResponse?()
        }
    }
    #endif
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}

@MainActor @Observable
final class NotificationService {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var pendingCount = 0
    private(set) var errorMessage: String?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()
    @ObservationIgnored private let delegate = ForegroundNotifications()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let historyKey = "native-notification-schedule"
    #if os(macOS)
    let codexNavigation = CodexNotificationNavigation()
    #endif

    init() {
        #if os(macOS)
        let navigation = codexNavigation
        delegate.onQuotaResponse = { [weak navigation] in
            await navigation?.openQuota()
        }
        navigation.openMainWindow = {
            if let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isSheet && !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
            } else {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                configuration.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration, completionHandler: nil)
            }
        }
        #endif
        center.delegate = delegate
    }

    #if os(macOS)
    func quotaTransport() -> any CodexQuotaAlertTransport {
        UNCodexQuotaAlertTransport(center: center, updateAuthorization: { [weak self] status in self?.authorization = status })
    }
    #endif

    var isEnabled: Bool {
        #if os(iOS)
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        #else
        authorization == .authorized || authorization == .provisional
        #endif
    }

    func request(backup: Backup) async {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refresh(backup: backup)
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh(backup: Backup) async {
        guard !Task.isCancelled else { return }
        let previous = refreshTask
        previous?.cancel()
        let work = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled else { return }
            await self.performRefresh(backup: backup)
        }
        refreshTask = work
        await work.value
    }

    private func performRefresh(backup: Backup) async {
        let settings = await center.notificationSettings()
        guard !Task.isCancelled else { return }
        authorization = settings.authorizationStatus
        guard isEnabled else { pendingCount = 0; return }

        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        let delivered = await center.deliveredNotifications()
        guard !Task.isCancelled else { return }
        let now = Date()
        let prefix = ReminderReconciliation.prefix
        let previous = UserDefaults.standard.dictionary(forKey: historyKey) as? [String: Double] ?? [:]
        let reconciliation = ReminderReconciliation(backup: backup, now: now, history: previous,
            pendingIDs: Set(pending.map(\.identifier)), deliveredIDs: Set(delivered.map { $0.request.identifier }))
        var history = reconciliation.history
        let reminders = reconciliation.reminders
        let obsolete = reconciliation.obsolete
        if !obsolete.isEmpty { center.removePendingNotificationRequests(withIdentifiers: obsolete) }
        // Save cancellation history before the scheduling loop can be superseded.
        UserDefaults.standard.set(history, forKey: historyKey)
        let pendingByID = Dictionary(uniqueKeysWithValues: pending.map { ($0.identifier, $0) })

        do {
            for reminder in reminders {
                guard !Task.isCancelled else { return }
                let id = prefix + reminder.id
                // Preserve an imminent pending reminder instead of postponing it on every refresh.
                if reminder.at.timeIntervalSince(now) <= 11,
                   let existing = (pendingByID[id]?.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate(), existing > now {
                    history[id] = existing.timeIntervalSince1970
                    UserDefaults.standard.set(history, forKey: historyKey)
                    continue
                }
                let content = UNMutableNotificationContent()
                content.title = reminder.title
                content.body = reminder.body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, reminder.at.timeIntervalSinceNow), repeats: false)
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
                history[id] = reminder.at.timeIntervalSince1970
                UserDefaults.standard.set(history, forKey: historyKey)
            }
            UserDefaults.standard.set(history, forKey: historyKey)
            pendingCount = reminders.count
            errorMessage = nil
        } catch { errorMessage = "提醒安排失败：\(error.localizedDescription)" }
    }
}
