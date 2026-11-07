import SwiftUI
import TokenfieldCore
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

struct ReportView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shared: SharedFile?
    @State private var sheet: ReportSheet?
    @State private var selectedStatementID: String?
    @State private var pendingOverwrite: MonthlyStatement?
    @State private var confirmingOverwrite = false
    @State private var confirmingDelete = false
    @State private var rendering = false

    private var selectedStatement: MonthlyStatement? {
        store.statements.first { $0.id == selectedStatementID }
    }
    private var displayedBackup: Backup { selectedStatement?.reportBackup ?? store.backup }
    private var savedStatements: [MonthlyStatement] { store.statements.sorted { $0.month > $1.month } }

    var body: some View {
        ExperiencePage(maximumWidth: 1120) { width in
            VStack(alignment: .leading, spacing: 24) {
                PageIntro(eyebrow: "月度账本", title: "本月花费", detail: "保存每月记录，或导出一张月报。")
                NativeCard { monthControls }
                AdaptiveColumns(wide: width >= 720 && !typeSize.isAccessibilitySize) {
                    TimelineView(.periodic(from: .now, by: 60)) { timeline in
                        ReportCard(backup: displayedBackup, catalog: store.catalog,
                                   context: reportContext(liveDate: timeline.date))
                    }
                    .frame(maxWidth: 420).frame(maxWidth: .infinity)
                } trailing: {
                    VStack(alignment: .leading, spacing: 22) {
                        NativeCard {
                            SectionHeading(title: selectedStatement == nil ? "当前是实时预览" : "这是一份已保存账本")
                            Text(selectedStatement == nil ? "费用会随服务记录更新。点「保存本月」，留下这个月的账本；漏记的月份也可以补录。" : "保存时的服务、金额与模型信息已冻结。你可以编辑这份账本，其他月份不会改变。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if displayedBackup.accounts.isEmpty {
                                Text(selectedStatement == nil ? "先在概览里添加服务，月报就会自动生成。" : "这份账本暂时没有费用，可以点「编辑」补充。")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        Button(action: exportImage) {
                            Label(rendering ? "正在生成" : exportButtonTitle, systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity, minHeight: 34)
                        }
                        .modifier(PrimaryActionStyle())
                        .disabled(displayedBackup.accounts.isEmpty || rendering)
                        .accessibilityIdentifier("report.share")
                        #if os(macOS)
                        if let shared {
                            ShareLink(item: shared.url) { Label("分享已保存的月报", systemImage: "square.and.arrow.up") }
                                .modifier(SecondaryActionStyle())
                        }
                        #endif
                        Text("仅分享这张月报图片，完整数据请在设置中导出备份。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("月报").nativeInlineTitle()
        .sheet(item: $sheet) { destination in
            switch destination {
            case .editor(let statement, let existing):
                MonthlyStatementEditor(statement: statement, isExisting: existing) { saved in
                    selectedStatementID = saved.id
                    shared = nil
                }
            #if os(iOS)
            case .share(let file): ShareSheet(file: file.url)
            #endif
            }
        }
        .confirmationDialog("覆盖 \(pendingOverwrite?.month ?? "") 的已保存月报？", isPresented: $confirmingOverwrite, titleVisibility: .visible) {
            Button("覆盖保存", role: .destructive) {
                if let statement = pendingOverwrite { saveAndSelect(statement) }
                pendingOverwrite = nil
            }
            Button("取消", role: .cancel) { pendingOverwrite = nil }
        } message: { Text("将用当前费用替换这份月报。") }
        .confirmationDialog("删除 \(selectedStatement?.month ?? "") 的月报？", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("删除月报", role: .destructive) {
                if let statement = selectedStatement, store.deleteStatement(id: statement.id) {
                    selectedStatementID = nil
                    shared = nil
                }
            }
            Button("取消", role: .cancel) { }
        } message: { Text("实时账号和其他月份不受影响。") }
        .onChange(of: selectedStatementID) { _, _ in shared = nil }
        .onChange(of: store.statements) { _, statements in
            if let selectedStatementID, !statements.contains(where: { $0.id == selectedStatementID }) {
                self.selectedStatementID = nil
            }
        }
    }

    private var monthControls: some View {
        VStack(spacing: 14) {
            HStack {
                Menu {
                    Button("本月实时预览") { selectedStatementID = nil }
                    ForEach(savedStatements) { statement in
                        Button(statement.month) { selectedStatementID = statement.id }
                            .accessibilityIdentifier("report.month.\(statement.month)")
                    }
                } label: {
                    Label(selectedStatement?.month ?? "本月实时预览", systemImage: "calendar")
                }
                .modifier(SecondaryActionStyle())
                .accessibilityIdentifier("report.month-picker")
                Spacer()
                Text(selectedStatement == nil ? "未保存" : "已保存")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("report.save-status")
            }
            HStack {
                if let statement = selectedStatement {
                    Button { sheet = .editor(statement, existing: true) } label: {
                        Label("编辑", systemImage: "pencil")
                    }.accessibilityIdentifier("report.edit-history")
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        Label("删除", systemImage: "trash")
                    }.accessibilityIdentifier("report.delete-history")
                } else {
                    Button(action: saveCurrentMonth) {
                        Label("保存本月", systemImage: "bookmark")
                    }
                    .disabled(store.accounts.isEmpty)
                    .accessibilityIdentifier("report.save-current")
                }
                Spacer()
                Button(action: addHistory) {
                    Label("补录月份", systemImage: "plus")
                }.accessibilityIdentifier("report.add-history")
            }
            .modifier(SecondaryActionStyle())
        }
    }

    private func reportContext(liveDate: Date = Date()) -> ReportDateContext {
        ReportDateContext(date: selectedStatement.flatMap { StatementMonth.date($0.month) } ?? liveDate)
    }

    private func saveCurrentMonth() {
        let statement = MonthlyStatement(month: StatementMonth.key(for: Date()), accounts: store.accounts, settings: store.settings)
        if store.statements.contains(where: { $0.month == statement.month }) {
            pendingOverwrite = statement
            confirmingOverwrite = true
        } else { saveAndSelect(statement) }
    }

    private func saveAndSelect(_ statement: MonthlyStatement) {
        if store.saveStatement(statement) {
            selectedStatementID = store.statements.first { $0.month == statement.month }?.id
            shared = nil
        }
    }

    private func addHistory() {
        let previousMonth = ReportDateContext().calendar.date(byAdding: .month, value: -1, to: Date()) ?? Date()
        let statement = MonthlyStatement(month: StatementMonth.key(for: previousMonth), accounts: store.accounts, settings: store.settings)
        sheet = .editor(statement, existing: false)
    }

    private var exportButtonTitle: String {
        #if os(macOS)
        "保存月报图片"
        #else
        "保存 / 分享图片"
        #endif
    }

    @MainActor private func exportImage() {
        rendering = true
        defer { rendering = false }
        let context = reportContext()
        let backup = displayedBackup
        let renderer = ImageRenderer(content: ReportCard(backup: backup, catalog: store.catalog, context: context)
            .frame(width: 360).environment(\.colorScheme, colorScheme).environment(\.dynamicTypeSize, .large))
        renderer.scale = max(3, displayScale)
        #if os(macOS)
        let png = renderer.cgImage.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
        #else
        let png = renderer.uiImage?.pngData()
        #endif
        guard let png else {
            store.errorMessage = "月报图片生成失败，请重试。"; return
        }
        do {
            #if os(macOS)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.nameFieldStringValue = "Tokenfield-\(context.month).png"
            panel.title = "保存月报图片"
            guard panel.runModal() == .OK, let file = panel.url else { return }
            try png.write(to: file, options: .atomic)
            shared = SharedFile(url: file)
            #else
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("Tokenfield-\(context.month)-\(UUID().uuidString.prefix(8)).png")
            try png.write(to: file, options: .atomic)
            sheet = .share(SharedFile(url: file))
            #endif
        } catch { store.errorMessage = "无法导出月报：\(error.localizedDescription)" }
    }
}

private enum ReportSheet: Identifiable {
    case editor(MonthlyStatement, existing: Bool)
    #if os(iOS)
    case share(SharedFile)
    #endif
    var id: String {
        switch self {
        case .editor(let statement, _): "editor-" + statement.id
        #if os(iOS)
        case .share(let file): "share-" + file.id.uuidString
        #endif
        }
    }
}

struct ReportCard: View {
    let backup: Backup
    let catalog: Catalog
    var context = ReportDateContext()
    private var spend: SpendPresentation { SpendPresentation(backup: backup, catalog: catalog) }
    private var slices: [SpendSlice] { spend.slices }
    private var models: [String] {
        Array(Set(backup.accounts.flatMap { $0.models.components(separatedBy: CharacterSet(charactersIn: ",，、")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Tokenfield").fontWeight(.semibold)
                Spacer()
                Text(context.month)
            }.font(.caption).foregroundStyle(Color.primary.opacity(0.7))

            VStack(alignment: .leading, spacing: 6) {
                Text("这个月我在 AI 上花了").font(.subheadline).foregroundStyle(Color.primary.opacity(0.7))
                Text(spend.totalMoney).font(.system(size: 54, weight: .semibold))
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.4)
                Text("平均每天 \(spend.dailyMoney(days: context.days)) · \(backup.accounts.count) 个 AI")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 32)
            VStack(spacing: 12) {
                GeometryReader { geometry in
                    HStack(spacing: 3) {
                        ForEach(slices) { slice in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(reportColor(slice.color))
                                .frame(width: max(0, geometry.size.width - Double(max(0, slices.count - 1)) * 3) * spend.fraction(for: slice))
                        }
                    }
                }.frame(height: 7).accessibilityHidden(true)
                ForEach(slices.prefix(4)) { slice in
                    HStack(spacing: 8) {
                        Circle().fill(reportColor(slice.color)).frame(width: 8, height: 8)
                        Text(slice.account.name).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        Text(spend.money(for: slice)).monospacedDigit()
                        Text("\(spend.percentage(for: slice))%")
                            .font(.caption2).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .trailing)
                    }.font(.caption)
                }
                if slices.count > 4 { Text("还有 \(slices.count - 4) 个 AI").font(.caption).foregroundStyle(.secondary) }
                if !models.isEmpty {
                    Text(models.prefix(6).joined(separator: " · "))
                        .font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            HStack(alignment: .lastTextBaseline) {
                Text(backup.settings.handle.isEmpty ? "Tokenfield 额度终端" : "@" + backup.settings.handle.trimmingCharacters(in: CharacterSet(charactersIn: "@")))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(spend.serial).fontDesign(.monospaced)
            }.font(.caption2).foregroundStyle(.secondary)
        }
        .padding(26).frame(minHeight: 460)
        .foregroundStyle(.primary)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Color.nativePageBackground)
        }
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color.primary.opacity(0.15), lineWidth: 1) }
    }
}

private func reportColor(_ hex: String) -> Color {
    let number = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x8172EF
    return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
}
