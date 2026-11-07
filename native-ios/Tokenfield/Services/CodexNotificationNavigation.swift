#if os(macOS)
import Foundation
import Observation
import AppKit

@MainActor @Observable
final class CodexNotificationNavigation {
    enum Destination { case quota, alerts }
    private(set) var revision = 0
    private(set) var hasPendingRequest = false
    private(set) var destination = Destination.quota
    @ObservationIgnored private var pendingAlertsPresentation = false
    var alertsSheetVisible = false
    @ObservationIgnored private var sheetObserver: NSObjectProtocol?
    @ObservationIgnored var openMainWindow: (() -> Void)?

    init() {
        sheetObserver = NotificationCenter.default.addObserver(forName: NSWindow.didEndSheetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resumeAfterSheet() }
        }
    }
    func openQuota() { request(.quota) }
    func openAlerts() { request(.alerts) }
    private func request(_ target: Destination) {
        destination = target
        hasPendingRequest = true
        revision &+= 1
        openMainWindow?()
    }
    func resumeAfterSheet() { if hasPendingRequest { revision &+= 1 } }
    func markHandled(prepareAlerts: Bool = false) {
        hasPendingRequest = false
        pendingAlertsPresentation = prepareAlerts
    }
    func takeAlertsPresentation() -> Bool {
        defer { pendingAlertsPresentation = false }
        return pendingAlertsPresentation
    }
    deinit { if let sheetObserver { NotificationCenter.default.removeObserver(sheetObserver) } }
}
#endif
