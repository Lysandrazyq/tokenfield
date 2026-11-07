#if os(macOS)
import Foundation
import UserNotifications

enum CodexQuotaNotificationPermission: Equatable { case notDetermined, allowed, denied, unavailable }

struct CodexQuotaNotificationRequest: Equatable {
    static let prefix = "tokenfield-codex-quota."
    let identifier: String
    let title: String
    let body: String
}

@MainActor protocol CodexQuotaAlertTransport: AnyObject {
    func authorization() async -> CodexQuotaNotificationPermission
    func requestAuthorization() async throws -> CodexQuotaNotificationPermission
    func enqueue(_ request: CodexQuotaNotificationRequest) async throws
    func cancelPending(prefix: String) async
    func cancelPending(identifier: String) async
}

/// Uses the same notification center and delegate as renewal/expiry reminders.
@MainActor final class UNCodexQuotaAlertTransport: CodexQuotaAlertTransport {
    private let center: UNUserNotificationCenter
    private let updateAuthorization: (UNAuthorizationStatus) -> Void
    init(center: UNUserNotificationCenter, updateAuthorization: @escaping (UNAuthorizationStatus) -> Void) {
        self.center = center; self.updateAuthorization = updateAuthorization
    }
    func authorization() async -> CodexQuotaNotificationPermission {
        let status = await center.notificationSettings().authorizationStatus
        updateAuthorization(status)
        return Self.permission(status)
    }
    func requestAuthorization() async throws -> CodexQuotaNotificationPermission {
        _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await authorization()
    }
    func enqueue(_ request: CodexQuotaNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title; content.body = request.body; content.sound = .default
        content.userInfo = ["destination": "codex-quota"]
        // A short trigger allows a superseded in-flight add to be cancelled before presentation.
        try await center.add(UNNotificationRequest(identifier: request.identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)))
    }
    func cancelPending(prefix: String) async {
        let requests = await center.pendingNotificationRequests()
        let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    func cancelPending(identifier: String) async { center.removePendingNotificationRequests(withIdentifiers: [identifier]) }
    private static func permission(_ status: UNAuthorizationStatus) -> CodexQuotaNotificationPermission {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .provisional: return .allowed
        case .denied: return .denied
        @unknown default: return .unavailable
        }
    }
}
#endif
