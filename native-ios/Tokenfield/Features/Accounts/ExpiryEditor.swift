import SwiftUI
import TokenfieldCore

struct ExpiryEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Expiry
    @State private var confirmingDelete = false
    @State private var validationMessage: String?
    @FocusState private var editingTitle: Bool
    private let quickTitles = ["完全重置券", "免费试用到期", "中转站额度到期", "活动赠送额度"]

    init(expiry: Expiry) { _draft = State(initialValue: expiry) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $draft.title).focused($editingTitle).accessibilityIdentifier("expiry.title")
                    Menu("快速填写") {
                        ForEach(quickTitles, id: \.self) { title in Button(title) { draft.title = title } }
                    }
                    Picker("关联账号", selection: $draft.accountId) {
                        Text("不关联").tag(Int?.none)
                        ForEach(store.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }.accessibilityIdentifier("expiry.account")
                    DatePicker("到期时间", selection: Binding(get: {
                        DateCodec.date(draft.expiresAt) ?? Date()
                    }, set: { draft.expiresAt = DateCodec.iso($0) }), displayedComponents: [.date, .hourAndMinute])
                    Toggle("已经用掉了 / 已完成", isOn: $draft.done).accessibilityIdentifier("expiry.done")
                } footer: { Text("重置券、试用期、赠送额度，到期前提醒你用掉。提醒可在设置中开启。") }
                #if os(macOS)
                if let message = validationMessage { Section { Text(message).foregroundStyle(.red) } }
                #endif
                if draft.id != 0 {
                    Section {
                        Button("删除到期项", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("expiry.delete")
                    }
                }
            }
            .nativeGroupedForm()
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .nativeScrollDismissesKeyboard()
            .nativeEditingBar(isEditing: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let message = validationMessage { Text(message).font(.caption).foregroundStyle(.red) }
                    HStack {
                        Button("取消") { dismiss() }.modifier(SecondaryActionStyle()).accessibilityIdentifier("editor.cancel")
                        Spacer()
                        Button("保存", action: save).modifier(PrimaryActionStyle()).accessibilityIdentifier("editor.save")
                    }
                }
            }
            .navigationTitle(draft.id == 0 ? "添加到期项" : "编辑到期项")
            .nativeInlineTitle()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save) .keyboardShortcut(.defaultAction).fontWeight(.semibold).accessibilityIdentifier("editor.save")
                }
                #endif
            }
            .confirmationDialog("删除「\(draft.title)」？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除到期项", role: .destructive) {
                    if store.deleteExpiry(id: draft.id) { dismiss() }
                }
                Button("取消", role: .cancel) { }
            }
        }
        .nativeEditorSize(height: 480)
    }

    private func save() {
        editingTitle = false
        draft.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.title.isEmpty { draft.title = "到期项" }
        if store.saveExpiry(draft) { dismiss() }
        else { validationMessage = store.errorMessage ?? "保存失败，请重试。" }
    }
}
