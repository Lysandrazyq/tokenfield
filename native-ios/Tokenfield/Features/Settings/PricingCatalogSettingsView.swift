import SwiftUI
import UniformTypeIdentifiers
import TokenfieldCore

struct PricingCatalogSettingsView: View {
    let service: PricingCatalogService
    @State private var importing = false
    @State private var exporting = false
    @State private var confirmRestore = false
    @State private var confirmImport = false
    @State private var pendingData: Data?
    @State private var pendingSummary = ""
    @State private var document: JSONDocument?
    @State private var actionMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("来源", value: service.isBundled ? "内置目录" : "导入的本地目录")
                LabeledContent("套餐", value: "\(service.catalog.plans.count) 个")
                LabeledContent("API 模型", value: "\(service.catalog.models.count) 个")
                LabeledContent("最近条目核验日期", value: service.catalog.latestCheck)
                Text(service.statusText).font(.footnote).foregroundStyle(.secondary)
                if let error = service.errorMessage { Text(error).font(.footnote).foregroundStyle(.red) }
            } header: { Text("当前目录") } footer: {
                Text("日期属于各个条目，不代表整个目录均已在该日核验。目录只保存在这台设备，不通过 iCloud 同步。")
            }

            Section {
                Button { importing = true } label: { Label("导入价格目录 JSON", systemImage: "square.and.arrow.down") }
                    .accessibilityIdentifier("catalog.import")
                Button { exportCatalog() } label: { Label("导出当前价格目录", systemImage: "square.and.arrow.up") }
                    .accessibilityIdentifier("catalog.export")
                Button("恢复内置目录", role: .destructive) { confirmRestore = true }
                    .accessibilityIdentifier("catalog.restore")
                if let actionMessage { Text(actionMessage).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("更新目录") } footer: {
                Text("从可信来源取得维护后的 JSON，核对官网价格后导入。App 会校验数据格式；格式有效不代表价格已获官方认证。套餐和 API 的实际价格、地区与税费以各官网为准。")
            }

            ForEach(service.catalog.providers.filter { provider in
                !service.catalog.plans(for: provider.key).isEmpty || !service.catalog.models(for: provider.key).isEmpty
            }) { provider in
                Section(provider.name) {
                    ForEach(service.catalog.plans(for: provider.key)) { plan in
                        VStack(alignment: .leading, spacing: 5) {
                            LabeledContent(plan.name, value: "\(plan.currency.rawValue) \(plan.price.formatted()) / 月")
                            Text(plan.limits).font(.caption).foregroundStyle(.secondary)
                            sourceLink(plan.source, checked: plan.checked)
                        }.padding(.vertical, 3)
                    }
                    ForEach(service.catalog.models(for: provider.key)) { model in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.name).font(.subheadline.weight(.medium))
                            Text("每百万 token：输入 \(model.currency.rawValue) \(model.input.formatted()) · 输出 \(model.output.formatted())")
                                .font(.caption).foregroundStyle(.secondary)
                            if let cached = model.cachedInput {
                                Text("缓存命中输入 \(model.currency.rawValue) \(cached.formatted()) / 百万 token")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if let note = model.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                            sourceLink(model.source, checked: model.checked)
                        }.padding(.vertical, 3)
                    }
                }
            }
        }
        .nativeGroupedForm()
        .scrollContentBackground(.hidden)
        .background { AppBackdrop() }
        .navigationTitle("价格目录")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: readImport)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json,
                      defaultFilename: "tokenfield-pricing-catalog") { result in
            switch result {
            case .success: actionMessage = "当前价格目录已导出"
            case .failure(let error): if !isCancelled(error) { actionMessage = "导出失败：\(error.localizedDescription)" }
            }
        }
        .confirmationDialog("替换本机价格目录？", isPresented: $confirmImport, titleVisibility: .visible) {
            Button("导入并替换") {
                guard let pendingData else { return }
                do { try service.importData(pendingData); actionMessage = nil } catch { actionMessage = nil }
                self.pendingData = nil
            }
            Button("取消", role: .cancel) { pendingData = nil }
        } message: {
            Text("\(pendingSummary)。只影响本机后续的价格参考，已保存的账号费用和历史月报保持原值。")
        }
        .confirmationDialog("恢复内置价格目录？", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("恢复内置目录", role: .destructive) {
                do { try service.restoreBundled(); actionMessage = nil } catch { actionMessage = nil }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("本机导入的目录将被替换。可先导出当前目录留存。") }
    }

    private func sourceLink(_ source: String, checked: String) -> some View {
        HStack {
            if let url = URL(string: source) { Link("官网价格", destination: url) }
            Spacer()
            Text("核验 \(checked)").foregroundStyle(.secondary)
        }.font(.caption)
    }

    private func exportCatalog() {
        do { document = JSONDocument(data: try service.exportData()); exporting = true }
        catch { actionMessage = "无法生成价格目录：\(error.localizedDescription)" }
    }

    private func readImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= Catalog.maximumDataBytes else { throw CatalogIssue.tooLarge }
                let data = try Data(contentsOf: url)
                let catalog = try Catalog.decode(data)
                pendingData = data
                pendingSummary = "包含 \(catalog.providers.count) 个服务商、\(catalog.plans.count) 个套餐、\(catalog.models.count) 个 API 模型"
                confirmImport = true
            } catch { actionMessage = "无法导入这个价格目录，当前目录已保留。\n\(error.localizedDescription)" }
        case .failure(let error):
            if !isCancelled(error) { actionMessage = "读取失败：\(error.localizedDescription)" }
        }
    }

    private func isCancelled(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError
    }
}
