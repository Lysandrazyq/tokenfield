import SwiftUI
import TokenfieldCore

struct MonthlyStatementEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MonthlyStatement
    @State private var monthDate: Date
    @State private var rows: [StatementExpenseDraft]
    @State private var rateText: String
    @State private var validationMessage: String?
    @State private var pendingSave: MonthlyStatement?
    @State private var confirmingOverwrite = false
    @FocusState private var editingField: StatementField?
    let isExisting: Bool
    let onSaved: (MonthlyStatement) -> Void

    init(statement: MonthlyStatement, isExisting: Bool, onSaved: @escaping (MonthlyStatement) -> Void) {
        _draft = State(initialValue: statement)
        _monthDate = State(initialValue: StatementMonth.date(statement.month) ?? Date())
        _rows = State(initialValue: statement.accounts.map(StatementExpenseDraft.init))
        _rateText = State(initialValue: StatementNumberInput.text(statement.settings.usdRate))
        self.isExisting = isExisting
        self.onSaved = onSaved
    }

    private var month: String { isExisting ? draft.month : StatementMonth.key(for: monthDate) }

    var body: some View {
        NavigationStack {
            Form {
                #if os(macOS)
                if let validationMessage {
                    Section { Text(validationMessage).foregroundStyle(.red).accessibilityIdentifier("statement.validation") }
                }
                #endif
                Section {
                    if isExisting {
                        LabeledContent("月份", value: month)
                            .accessibilityIdentifier("statement.locked-month")
                    } else {
                        DatePicker("月份 \(month)", selection: $monthDate, displayedComponents: .date)
                            .accessibilityIdentifier("statement.month")
                    }
                } footer: {
                    if !isExisting { Text("已带入当前费用，请按该月实际情况调整。") }
                }
                ForEach($rows) { $row in
                    StatementExpenseFields(row: $row, focus: $editingField) {
                        let id = row.id
                        rows.removeAll { $0.id == id }
                    }
                }
                Section {
                    Button { addRow() } label: { Label("添加费用", systemImage: "plus") }
                        .accessibilityIdentifier("statement.add-row")
                } footer: {
                    Text("费用仅保存到这份月报。")
                }
                Section("汇率与署名") {
                    LabeledContent("1 美元等于（元）") {
                        TextField("人民币汇率", text: $rateText).focused($editingField, equals: .rate).nativeDecimalInput().labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("statement.rate")
                    }
                    TextField("署名（选填）", text: $draft.settings.handle).focused($editingField, equals: .handle)
                        .nativeNoCapitalization().autocorrectionDisabled()
                        .accessibilityIdentifier("statement.handle")
                }
            }
            .nativeGroupedForm()
            .nativeScrollDismissesKeyboard()
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .nativeEditingBar(isEditing: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let validationMessage {
                        Text(validationMessage).font(.caption).foregroundStyle(.red).accessibilityIdentifier("statement.validation")
                    }
                    HStack {
                        Button("取消") { dismiss() }.modifier(SecondaryActionStyle()).accessibilityIdentifier("statement.cancel")
                        if editingField != nil {
                            Button { editingField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                                .modifier(SecondaryActionStyle()).accessibilityLabel("收起键盘")
                        }
                        Spacer()
                        Button("保存", action: prepareSave).modifier(PrimaryActionStyle()).accessibilityIdentifier("statement.save")
                    }
                }
            }
            .navigationTitle(isExisting ? "编辑月报" : "补录月份")
            .nativeInlineTitle()
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                        .accessibilityIdentifier("statement.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: prepareSave).keyboardShortcut(.defaultAction).fontWeight(.semibold)
                        .accessibilityIdentifier("statement.save")
                }
                #endif
            }
            .confirmationDialog("覆盖 \(month) 的已保存月报？", isPresented: $confirmingOverwrite, titleVisibility: .visible) {
                Button("覆盖保存", role: .destructive) {
                    if let statement = pendingSave { save(statement) }
                    pendingSave = nil
                }
                Button("取消", role: .cancel) { pendingSave = nil }
            } message: { Text("这份月报将替换原来的费用、汇率和署名。") }
        }
        .nativeEditorSize(height: 680)
    }

    private func addRow() {
        let used = Set(rows.map(\.id))
        var id = 1
        while used.contains(id) { id += 1 }
        rows.append(StatementExpenseDraft(account: Account(id: id, provider: "custom", monthlyCost: 0, currency: .cny)))
    }

    private func prepareSave() {
        validationMessage = nil
        guard StatementMonth.date(month) != nil else {
            validationMessage = "请选择有效月份。"; return
        }
        guard let rate = StatementNumberInput.parse(rateText), rate > 0 else {
            validationMessage = "汇率需要填写大于 0 的数字。"; return
        }
        var accounts: [Account] = []
        for row in rows {
            guard let amount = StatementNumberInput.parse(row.costText), amount >= 0 else {
                validationMessage = "费用需要填写大于或等于 0 的数字。"; return
            }
            var account = row.account
            account.name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !account.name.isEmpty else {
                validationMessage = "请为每项费用填写名称。"; return
            }
            account.monthlyCost = amount
            accounts.append(account)
        }
        var statement = draft
        statement.month = month
        statement.accounts = accounts
        statement.settings.usdRate = rate
        statement.capturedAt = DateCodec.iso(Date())
        if store.statements.contains(where: { $0.month == statement.month }) {
            pendingSave = statement
            confirmingOverwrite = true
        } else { save(statement) }
    }

    private func save(_ statement: MonthlyStatement) {
        if store.saveStatement(statement) {
            let saved = store.statements.first { $0.month == statement.month } ?? statement
            onSaved(saved)
            dismiss()
        } else {
            validationMessage = store.errorMessage ?? "保存失败，请重试。"
        }
    }
}

private enum StatementField: Hashable {
    case rate, handle, name(Int), cost(Int), models(Int)
}

private struct StatementExpenseDraft: Identifiable {
    var account: Account
    var costText: String
    var id: Int { account.id }
    init(account: Account) {
        self.account = account
        costText = StatementNumberInput.text(account.monthlyCost)
    }
}

private struct StatementExpenseFields: View {
    @Binding var row: StatementExpenseDraft
    let focus: FocusState<StatementField?>.Binding
    let remove: () -> Void

    var body: some View {
        Section {
            TextField("名称", text: $row.account.name).focused(focus, equals: .name(row.id))
                .accessibilityIdentifier("statement.row-name")
            LabeledContent("费用") {
                TextField("费用", text: $row.costText).focused(focus, equals: .cost(row.id)).nativeDecimalInput().labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("statement.row-cost")
            }
            Picker("币种", selection: $row.account.currency) {
                Text("人民币 CNY").tag(Currency.cny)
                Text("美元 USD").tag(Currency.usd)
            }
            TextField("模型（选填）", text: $row.account.models).focused(focus, equals: .models(row.id))
                .accessibilityIdentifier("statement.row-models")
            Button("移除费用", role: .destructive, action: remove)
                .accessibilityIdentifier("statement.remove-row")
        }
    }
}

private enum StatementNumberInput {
    static func text(_ value: Double) -> String {
        // Round-trip the stored number without silently rounding a saved amount.
        String(value).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }

    static func parse(_ text: String) -> Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^[+]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#,
                               options: .regularExpression) != nil,
              let value = Double(normalized), value.isFinite else { return nil }
        return value
    }
}
