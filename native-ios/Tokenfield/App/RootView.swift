import SwiftUI
import TokenfieldCore
#if os(macOS)
import AppKit
#endif

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(NotificationService.self) private var notifications
    @Environment(CloudSyncService.self) private var cloud
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(CodexMonitorStore.self) private var codexMonitor
    @Environment(CodexQuotaAlertStore.self) private var quotaAlerts
    @State private var codexFocusRequest = 0
    @State private var codexAlertsRequest = 0
    #endif
    @State private var tab = 0
    @State private var settingsEditing = SettingsEditSession()
    @State private var newAccount: Account?
    @AppStorage("experience.welcome.completed.v1") private var welcomeCompleted = false
    @AppStorage("experience.welcome.test.completed.v1") private var testWelcomeCompleted = false
    @State private var checkedWelcome = false
    @State private var showingWelcome = false
    @State private var addAfterWelcome = false

    var body: some View {
        navigation
        .task { prepareWelcome() }
        .task { await refreshExchangeRate() }
        #if os(macOS)
        .task { await codexMonitor.restore() }
        .task {
            if notifications.codexNavigation.hasPendingRequest { openCodexQuota() }
        }
        .onChange(of: notifications.codexNavigation.revision) { _, _ in openCodexQuota() }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showingWelcome, onDismiss: {
            rememberWelcomeDismissal()
            if addAfterWelcome {
                addAfterWelcome = false
                newAccount = .blank(catalog: store.catalog)
            }
        }) {
            WelcomeView(onAddAccount: { finishWelcome(addAccount: true) }, onDismiss: { finishWelcome(addAccount: false) })
        }
        #endif
        .sheet(item: $newAccount) { AccountEditor(account: $0) }
        .task { await cloud.start(store: store) }
        .task(id: store.revision) { await notifications.refresh(backup: store.backup) }
        .onChange(of: store.revision) { _, _ in
            Task { await cloud.localDataChanged(store: store) }
        }
        .onChange(of: scenePhase) { _, phase in
            #if os(macOS)
            codexMonitor.setForeground(phase == .active)
            #endif
            if phase == .active {
                Task { await refreshExchangeRate() }
                Task {
                    await notifications.refresh(backup: store.backup)
                    #if os(macOS)
                    await quotaAlerts.refresh()
                    #endif
                    await cloud.syncNow(store: store)
                }
            }
        }
        .alert("需要处理", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    @ViewBuilder private var navigation: some View {
        #if os(macOS)
        NavigationSplitView {
            List(selection: Binding<Int?>(get: { tab }, set: { if let value = $0 { tab = value } })) {
                Section("工作台") {
                    Label("概览", systemImage: "square.grid.2x2").listItemTint(.monochrome).tag(0)
                    Label("Codex 实时", systemImage: "terminal").listItemTint(.monochrome).tag(4)
                }
                Section("账本") {
                    Label("比价", systemImage: "chart.bar.xaxis").listItemTint(.monochrome).tag(1)
                    Label("月报", systemImage: "chart.pie").listItemTint(.monochrome).tag(2)
                }
                Section {
                    Label("设置", systemImage: "gearshape").listItemTint(.monochrome).tag(3)
                }
            }
            .listStyle(.sidebar)
            .tint(BrandPalette.control)
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 280)
            .safeAreaInset(edge: .bottom, alignment: .leading) {
                Text("Tokenfield 额度终端")
                    .font(.caption).foregroundStyle(.secondary).padding(16)
            }
        } detail: {
            NavigationStack {
                switch tab {
                case 1: CompareView()
                case 2: ReportView()
                case 3: SettingsView(editing: $settingsEditing)
                case 4: CodexDashboard(focusRequest: codexFocusRequest, alertsRequest: codexAlertsRequest)
                default: HomeView(onShowReport: { tab = 2 }, onShowCompare: { tab = 1 }, onShowSettings: { tab = 3 }, onShowCodex: { tab = 4 })
                }
            }
            .tint(BrandPalette.accent)
        }
        .navigationSplitViewStyle(.balanced)
        .background { MainWindowConfiguration().frame(width: 0, height: 0).accessibilityHidden(true) }
        .focusedSceneValue(\.navigateDestination, { tab = $0 })
        .focusedSceneValue(\.newAccountAction, { newAccount = .blank(catalog: store.catalog) })
        #else
        TabView(selection: $tab) {
            NavigationStack { HomeView(onShowReport: { tab = 2 }, onShowCompare: { tab = 1 }, onShowSettings: { tab = 3 }) }
                .tabItem { Label("概览", systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { CompareView() }
                .tabItem { Label("比价", systemImage: "chart.bar.xaxis") }.tag(1)
            NavigationStack { ReportView() }
                .tabItem { Label("月报", systemImage: "doc.richtext") }.tag(2)
            NavigationStack { SettingsView(editing: $settingsEditing) }
                .tabItem { Label("设置", systemImage: "gearshape") }.tag(3)
        }
        #endif
    }

    #if os(macOS)
    private func openCodexQuota() {
        let navigation = notifications.codexNavigation
        guard navigation.hasPendingRequest else { return }
        if navigation.alertsSheetVisible && navigation.destination == .alerts {
            navigation.markHandled()
            return
        }
        // Preserve drafts owned by the current screen. Replay after the user ends the sheet.
        guard navigation.alertsSheetVisible || !NSApp.windows.contains(where: { $0.attachedSheet != nil }) else { return }
        tab = 4
        if navigation.destination == .alerts { codexAlertsRequest &+= 1 }
        else { codexFocusRequest &+= 1 }
        navigation.markHandled(prepareAlerts: navigation.destination == .alerts)
    }
    #endif

    private func prepareWelcome() {
        guard !checkedWelcome else { return }
        checkedWelcome = true
        #if os(macOS)
        // Mac opens directly into the workspace. The visible home checklist and Settings guide remain available.
        return
        #else
        let arguments = ProcessInfo.processInfo.arguments
        let testing = arguments.contains("--ui-testing")
        if testing && arguments.contains("--reset-onboarding") { testWelcomeCompleted = false }
        guard !(testing && arguments.contains("--skip-onboarding")) else { return }
        showingWelcome = WelcomePolicy.shouldPresent(backup: store.backup,
            completed: testing ? testWelcomeCompleted : welcomeCompleted, hasLoadError: store.errorMessage != nil)
        if !showingWelcome && store.errorMessage == nil && !(testing ? testWelcomeCompleted : welcomeCompleted) {
            // Existing users stay past onboarding even if they later clear their records.
            rememberWelcomeDismissal()
        }
        #endif
    }

    private func refreshExchangeRate() async {
        guard !ProcessInfo.processInfo.arguments.contains("--ui-testing") else { return }
        await exchangeRates.refreshIfNeeded(apply: store.applyExchangeRate)
    }

    private func finishWelcome(addAccount: Bool) {
        rememberWelcomeDismissal()
        showingWelcome = false
        #if os(macOS)
        if addAccount { newAccount = .blank(catalog: store.catalog) }
        #else
        addAfterWelcome = addAccount
        #endif
    }

    private func rememberWelcomeDismissal() {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") { testWelcomeCompleted = true }
        else { welcomeCompleted = true }
    }
}

struct AppBackdrop: View {
    var body: some View {
        Color.nativePageBackground
            .ignoresSafeArea()
    }
}

struct PrimaryActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        let button = content.buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 10)).controlSize(.large).tint(BrandPalette.control)
        #if os(macOS)
        // AppKit draws prominent labels in white. Its accent must support that contrast.
        button
        #else
        button
            .foregroundStyle(Color.nativePageBackground)
        #endif
    }
}
