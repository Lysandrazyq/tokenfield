import SwiftUI
import TokenfieldCore

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        Form {
            Section("Tokenfield 额度终端") {
                Text("管理 AI 订阅、用量和到期提醒。")
                LabeledContent("版本", value: version)
            }
            Section("联系开发者") {
                Link("X · @Lysandra_zyq", destination: URL(string: "https://x.com/Lysandra_zyq")!)
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("关于应用").nativeInlineTitle()
    }
}

struct DisclaimerView: View {
    let catalog: Catalog

    var body: some View {
        Form {
            Section("价格与估算") {
                Text("价格来自本机价格目录，未实时更新。服务商可能调整价格与套餐，请以官网为准。")
                Text("费用和使用价值根据你填写的记录与假设用量估算，仅供参考，不代表实际账单或可用额度。")
                NavigationLink("查看价格来源") { PricingSourcesView(catalog: catalog) }
                    .accessibilityIdentifier("disclaimer.sources")
            }
            Section("品牌与独立性") {
                Text("服务商名称、商标和图标归各自公司所有，仅用于识别服务。额度终端为独立开发者作品，与这些服务商无合作或从属关系。")
                Text("使用本应用不影响你与服务商之间的协议。")
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("免责声明").nativeInlineTitle()
    }
}

struct PrivacyView: View {
    var body: some View {
        Form {
            Section("本机记录") {
                Text("账号、金额、日期和用量保存在你的设备上。应用不收集这些记录，也没有开发者自建服务器。")
            }
            Section("自动汇率") {
                Text("自动模式向 Frankfurter 请求 ECB 的美元兑人民币参考汇率，不发送账号、金额、用量或 Codex 数据。可在设置中切换为手动；断网时继续使用上次汇率。")
            }
            Section("iCloud 同步") {
                Text("启用后，记录同步至你的 iCloud 私有数据库，供同一 Apple 账号的设备使用。离线时先保存在本机，重新联网并打开应用后继续同步。")
                Text("外观和通知授权分别保留在各台设备。当前是否可用，请查看设置中的 iCloud 状态。")
            }
            Section("导出与分享") {
                Text("备份与月报仅在你主动导出或分享时交给所选位置或接收方。分享前请确认其中的账号名称、金额和署名。")
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("数据隐私").nativeInlineTitle()
    }
}

struct PricingSourcesView: View {
    let catalog: Catalog

    var body: some View {
        Form {
            Section {
                ForEach(catalog.providers.filter { provider in
                    catalog.plans.contains { $0.provider == provider.key } || catalog.models.contains { $0.provider == provider.key }
                }) { provider in
                    if let source = catalog.plans.first(where: { $0.provider == provider.key })?.source ?? catalog.models.first(where: { $0.provider == provider.key })?.source,
                       let url = URL(string: source) {
                        Link(destination: url) { Label(provider.name, systemImage: "arrow.up.right.square") }
                    }
                }
            } header: { Text("服务商官网") } footer: {
                Text("最近核对：\(catalog.latestCheck)。各条价格的核对日期见比价页。")
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("价格来源").nativeInlineTitle()
    }
}
