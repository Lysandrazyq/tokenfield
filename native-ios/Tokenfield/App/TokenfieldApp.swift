import SwiftUI
import TokenfieldCore

@main
struct TokenfieldApp: App {
    @State private var store: AppStore
    @State private var notifications: NotificationService
    @State private var cloud = CloudSyncService()
    @State private var exchangeRates = ExchangeRateStore()
    @AppStorage("appearance") private var appearance = "system"
    #if os(macOS)
    @State private var codexMonitor: CodexMonitorStore
    @State private var quotaAlerts: CodexQuotaAlertStore
    @State private var codexStatusBar: CodexStatusBarController
    #endif

    init() {
        let notifications = NotificationService()
        _notifications = State(initialValue: notifications)
        #if os(macOS)
        let alerts = CodexQuotaAlertStore(transport: notifications.quotaTransport())
        let monitor = CodexMonitorStore()
        let statusBar = CodexStatusBarController(navigation: notifications.codexNavigation)
        monitor.onQuotaContextChange = { [weak alerts, weak statusBar, weak monitor] quota, directory, healthy in
            alerts?.updateContext(quota: quota, directory: directory, healthy: healthy)
            statusBar?.update(snapshot: monitor?.snapshot, connected: healthy)
        }
        _codexStatusBar = State(initialValue: statusBar)
        _quotaAlerts = State(initialValue: alerts)
        _codexMonitor = State(initialValue: monitor)
        #endif
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        let directory = URL.applicationSupportDirectory.appendingPathComponent("Tokenfield", isDirectory: true)
        let file = directory.appendingPathComponent(testing ? "ui-tests.json" : "data.json")
        if testing && arguments.contains("--reset-ui-data") { try? FileManager.default.removeItem(at: file) }
        _store = State(initialValue: AppStore(fileURL: file))
    }

    var body: some Scene {
        WindowGroup(id: "tokenfield-main") {
            RootView()
                .environment(store)
                .environment(notifications)
                .environment(cloud)
                .environment(exchangeRates)
                #if os(macOS)
                .environment(codexMonitor)
                .environment(quotaAlerts)
                .task { codexStatusBar.startAfterWindow() }
                #endif
                .tint(Color.accentColor)
                .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 780)
        .commands { DesktopCommands() }
        #endif
    }
}
