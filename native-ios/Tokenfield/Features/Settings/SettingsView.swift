import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import TokenfieldCore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(CloudSyncService.self) private var cloud
    @Environment(NotificationService.self) private var notifications
    @Environment(ExchangeRateStore.self) private var exchangeRates
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage("appearance") private var appearance = "system"
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmImport = false
    @State private var pendingImport: Data?
    @State private var importCount = 0
    @State private var document = JSONDocument(data: Data())
    @State private var statusText: String?
    @Binding var editing: SettingsEditSession
    private var draft: AppSettings { editing.draft }
    private var settingsChanged: Bool { editing.hasChanges }
    private enum Field: Hashable { case reminder, rate, handle }
    @FocusState private var editingSettings: Field?

    var body: some View {
        Form {
            Section {
                NavigationLink { GettingStartedGuide() } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "book.closed").font(.title2).frame(width: 36)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("使用指南").font(.headline)
                            Text("添加服务、记录用量、看懂月报").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                }
                .accessibilityIdentifier("settings.guide")
            }
            Section("外观") {
                if typeSize.isAccessibilitySize { appearancePicker.pickerStyle(.menu) }
                else { appearancePicker.pickerStyle(.segmented) }
            }
            Section {
                HStack {
                    Label("通知", systemImage: "bell.badge")
                    Spacer()
                    if notifications.isEnabled {
                        Text("已开启").foregroundStyle(.green)
                    } else if notifications.authorization == .denied {
                        Button("前往系统设置") { PlatformSettings.openNotifications(using: openURL) }
                    } else {
                        Button("开启") { Task { await notifications.request(backup: store.backup) } }
                            .accessibilityIdentifier("settings.notifications")
                    }
                }
                LabeledContent("提前提醒（小时）") {
                    TextField("24", value: $editing.draft.remindHours, format: .number)
                        .focused($editingSettings, equals: .reminder)
                        .nativeDecimalInput().labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 100)
                        .accessibilityLabel("提前提醒小时数")
                }
                if notifications.isEnabled {
                    Text("已安排 \(notifications.pendingCount) 条近期提醒。再次打开 App 会更新后续计划。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = notifications.errorMessage { Text(error).font(.caption).foregroundStyle(.red) }
            } header: { Text("提醒") } footer: {
                Text("关闭 App 后也可提醒，显示方式受系统通知设置影响。")
            }

            CloudSyncSettingsSection(service: cloud, store: store)

            Section {
                NavigationLink { PricingCatalogSettingsView(service: store.pricing) } label: {
                    Label("价格目录", systemImage: "tag")
                }
                .accessibilityIdentifier("settings.pricing")
            }

            Section {
                Picker("汇率更新", selection: Binding(get: { exchangeRates.isAutomatic }, set: { automatic in
                    editing.draft.usdRate = store.settings.usdRate
                    exchangeRates.setAutomatic(automatic)
                    if automatic { Task { await updateExchangeRate() } }
                })) {
                    Text("自动").tag(true)
                    Text("手动").tag(false)
                }.pickerStyle(.segmented).accessibilityIdentifier("settings.rate-mode")
                if exchangeRates.isAutomatic {
                    LabeledContent("1 美元", value: "\(store.settings.usdRate.formatted(.number.precision(.fractionLength(2...4)))) 人民币")
                        .monospacedDigit().accessibilityIdentifier("settings.current-rate")
                    HStack {
                        if exchangeRates.isRefreshing { ProgressView().controlSize(.small); Text("正在同步…").foregroundStyle(.secondary) }
                        Spacer()
                        Button("立即更新") { Task { await updateExchangeRate(force: true) } }
                            .disabled(exchangeRates.isRefreshing).accessibilityIdentifier("settings.refresh-rate")
                    }
                } else { LabeledContent("1 美元等于（元）") {
                    TextField("7.1", value: $editing.draft.usdRate, format: .number)
                        .focused($editingSettings, equals: .rate)
                        .nativeDecimalInput().labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 100)
                        .accessibilityLabel("美元汇率")
                } }
                if let issue = exchangeRates.lastIssue { Text(issue).font(.caption).foregroundStyle(.secondary) }
            } header: { Text("美元兑人民币") } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if exchangeRates.isAutomatic, let quote = exchangeRates.quote {
                        Text("\(USDExchangeRateQuote.source) · 参考日期 \(quote.date)")
                        if let fetchedAt = exchangeRates.fetchedAt { Text("最近同步 \(fetchedAt.formatted(date: .abbreviated, time: .shortened))") }
                    }
                    Text(exchangeRates.isAutomatic ? "每日参考汇率，非实时成交价。打开应用时检查更新，离线保留上次值；已保存月报不重算。" : "手动填写后保存。只影响当前计算，已保存月报保留原记录。")
                }
            }

            Section("月报署名") {
                TextField("月报署名（选填）", text: $editing.draft.handle).nativeNoCapitalization().focused($editingSettings, equals: .handle)
                if settingsChanged {
                    Button("保存计算与提醒设置") { saveSettings() }
                        .accessibilityIdentifier("settings.save")
                }
            }

            Section {
                Button { exportBackup() } label: { Label("导出备份", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("settings.export")
                Button { importing = true } label: { Label("导入备份", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("settings.import")
                if let statusText { Text(statusText).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("数据") } footer: {
                Text("备份含历史账本；网站仅支持基础记录。导入会替换现有数据，并在启用 iCloud 时同步。")
            }

            Section("关于") {
                NavigationLink { AboutView() } label: { Label("关于应用", systemImage: "info.circle") }
                    .accessibilityIdentifier("settings.about")
                NavigationLink { DisclaimerView(catalog: store.catalog) } label: { Label("免责声明", systemImage: "doc.text") }
                    .accessibilityIdentifier("settings.disclaimer")
                NavigationLink { PrivacyView() } label: { Label("数据隐私", systemImage: "hand.raised") }
                    .accessibilityIdentifier("settings.privacy")
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .nativeEditingBar(isEditing: editingSettings != nil) {
            HStack {
                Button { editingSettings = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                    .modifier(SecondaryActionStyle()).accessibilityLabel("收起键盘")
                Spacer()
                Button("完成") { editingSettings = nil; if settingsChanged { saveSettings() } }
                    .modifier(PrimaryActionStyle())
            }
        }
        .navigationTitle("设置")
        .onAppear { editing.receive(store.settings) }
        .onChange(of: store.settings) { _, value in editing.receive(value) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: readImport)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "tokenfield-backup-\(DateCodec.day(Date()))") { result in
            switch result {
            case .success: statusText = "备份已导出"
            case .failure(let error): store.errorMessage = "导出失败：\(error.localizedDescription)"
            }
        }
        .confirmationDialog("替换当前所有数据？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入并覆盖", role: .destructive) {
                if let data = pendingImport, store.importData(data) {
                    editing.acceptReplacement(store.settings)
                    editingSettings = nil
                    statusText = "已导入 \(importCount) 个 AI 账号"
                }
                pendingImport = nil
            }
            Button("取消", role: .cancel) { pendingImport = nil }
        } message: { Text("备份包含 \(importCount) 个 AI 账号。当前账号、到期事项、使用记录、历史账本及计算设置将被替换；启用 iCloud 后，替换结果也会同步到其他设备。") }
    }

    private var appearancePicker: some View {
        Picker("显示模式", selection: $appearance) {
            Text("跟随系统").tag("system")
            Text("浅色").tag("light")
            Text("深色").tag("dark")
        }.accessibilityIdentifier("settings.appearance")
    }

    private func saveSettings() {
        var value = draft
        if exchangeRates.isAutomatic { value.usdRate = store.settings.usdRate }
        guard value.usdRate.isFinite, value.usdRate > 0, value.remindHours.isFinite, value.remindHours >= 0 else {
            store.errorMessage = "汇率需要大于 0，提前提醒小时数不能为负数。"; return
        }
        if store.updateSettings(value) { editing.acceptReplacement(store.settings); statusText = "设置已保存" }
    }

    private func updateExchangeRate(force: Bool = false) async {
        await exchangeRates.refreshIfNeeded(force: force, apply: store.applyExchangeRate)
    }

    private func exportBackup() {
        do { document = JSONDocument(data: try store.exportData()); exporting = true }
        catch { store.errorMessage = "无法生成备份：\(error.localizedDescription)" }
    }

    private func readImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 20_000_000 else { throw ImportIssue.tooLarge }
                let data = try Data(contentsOf: url)
                let backup = try Backup.decode(data).validated()
                pendingImport = data
                importCount = backup.accounts.count
                confirmImport = true
            } catch { store.errorMessage = "无法导入这个备份，当前数据已保留。\n\(error.localizedDescription)" }
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError { store.errorMessage = "无法读取备份：\(error.localizedDescription)" }
        }
    }

}

private enum ImportIssue: LocalizedError {
    case tooLarge
    var errorDescription: String? { "备份文件超过 20 MB，请确认选择的是额度终端 JSON 备份。" }
}

