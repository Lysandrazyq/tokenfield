import SwiftUI
import TokenfieldCore

struct AccountEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(NotificationService.self) private var notifications
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var draft: Account
    @State private var costText: String
    @State private var balanceText: String
    @State private var hoursText: String
    @State private var confirmingDelete = false
    @State private var validationMessage: String?
    @State private var step = 0
    @State private var showingResetOptions = false
    @State private var showingModelOptions = false
    private enum Field: Hashable { case name, cost, balance, hours, models, note }
    @FocusState private var editingField: Field?
    private let originalAccount: Account
    private let originalNotifyReset: Bool

    init(account: Account) {
        _draft = State(initialValue: account)
        _costText = State(initialValue: Self.number(account.monthlyCost))
        _balanceText = State(initialValue: Self.number(account.balance ?? 0))
        _hoursText = State(initialValue: Self.number(account.resetHours ?? 5))
        originalNotifyReset = account.notifyReset
        originalAccount = account
    }

    private var provider: Provider { store.catalog.provider(draft.provider) }
    private var plans: [Plan] { store.catalog.plans(for: draft.provider) }
    private var comparisonModels: [APIModel] {
        let own = store.catalog.models(for: draft.provider)
        return own.isEmpty ? store.catalog.models : own
    }
    private var billingOptions: [Billing] {
        Billing.allCases.filter { $0 != .subscription || provider.hasSubscription || draft.billing == .subscription }
    }

    private var isNew: Bool { draft.id == 0 }
    private var hasChanges: Bool {
        draft != originalAccount || costText != Self.number(originalAccount.monthlyCost)
            || balanceText != Self.number(originalAccount.balance ?? 0)
            || hoursText != Self.number(originalAccount.resetHours ?? 5)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isNew {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(step == 0 ? "01 / 选择服务" : "02 / 核对费用")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(step == 0 ? "先从一个常用服务开始" : "按你的实际账单填写")
                                .font(.title2.weight(.semibold))
                            Text(step == 0 ? "选服务和套餐，默认信息会帮你填好。" : "参考价格可以修改，额度和提醒也可以以后再补。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            ProgressView(value: step == 0 ? 0.5 : 1).tint(.primary)
                        }.padding(.vertical, 8)
                    }
                }
                if !isNew || step == 0 {
                    if isNew { quickProviders }
                    basicSection
                    if draft.billing == .subscription && !plans.isEmpty { planSection }
                }
                if !isNew || step == 1 {
                    if isNew {
                        Section {
                            HStack(spacing: 12) {
                                ProviderBadge(provider: provider, size: 42)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.name.isEmpty ? provider.name : draft.name).font(.headline)
                                    Text(draft.billing.label).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 5)
                            Button("上一步，修改服务", systemImage: "arrow.left") { editingField = nil; step = 0 }
                                .font(.subheadline).frame(minHeight: 44)
                                .accessibilityIdentifier("account.back")
                        }
                    }
                    paymentSection
                    Section {
                        DisclosureGroup("额度与提醒（可选）", isExpanded: $showingResetOptions) { resetFields }
                    } footer: {
                        Text("不确定重置规则，可以先保留默认值。")
                    }
                    Section {
                        DisclosureGroup("模型与备注（可选）", isExpanded: $showingModelOptions) { modelFields }
                    } footer: {
                        Text("对照模型用于估算按量费用，不需要 API Key。")
                    }
                }
                #if os(macOS)
                if let message = validationMessage {
                    Section { Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.red).accessibilityIdentifier("editor.validation") }
                }
                #endif
                if !isNew {
                    Section {
                        Button("删除服务", role: .destructive) { confirmingDelete = true }
                            .accessibilityIdentifier("account.delete")
                    }
                }
            }
            .nativeGroupedForm()
            .scrollContentBackground(.hidden)
            .background { AppBackdrop() }
            .nativeScrollDismissesKeyboard()
            .nativeEditingBar(isEditing: true) {
                VStack(alignment: .leading, spacing: 10) {
                    if let message = validationMessage {
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(.caption).foregroundStyle(.red).accessibilityIdentifier("editor.validation")
                    }
                    HStack {
                        Button("取消") { dismiss() }.modifier(SecondaryActionStyle()).accessibilityIdentifier("editor.cancel")
                        if editingField != nil {
                            Button { editingField = nil } label: { Image(systemName: "keyboard.chevron.compact.down") }
                                .modifier(SecondaryActionStyle()).accessibilityLabel("收起键盘")
                                .accessibilityIdentifier("editor.dismiss-keyboard")
                        }
                        Spacer()
                        if isNew && step == 0 {
                            Button("下一步") { editingField = nil; step = 1 }
                                .modifier(PrimaryActionStyle()).accessibilityIdentifier("account.next")
                        } else {
                            Button("保存服务", action: save).modifier(PrimaryActionStyle()).accessibilityIdentifier("editor.save")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "添加服务" : "编辑服务")
            .nativeInlineTitle()
            .animation(reduceMotion ? nil : .smooth(duration: 0.22), value: step)
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.keyboardShortcut(.cancelAction).accessibilityIdentifier("editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isNew && step == 0 {
                        Button("下一步") { editingField = nil; step = 1 }
                            .fontWeight(.semibold).accessibilityIdentifier("account.next")
                    } else {
                        Button("保存服务", action: save).keyboardShortcut(.defaultAction)
                            .fontWeight(.semibold).accessibilityIdentifier("editor.save")
                    }
                }
                #endif
            }
            .confirmationDialog("删除「\(draft.name)」？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除服务和关联数据", role: .destructive) {
                    if store.deleteAccount(id: draft.id) { dismiss() }
                }
                Button("取消", role: .cancel) { }
            } message: { Text("它的到期项和使用记录也会一起删除。已保存月报不会改变。") }
        }
        .interactiveDismissDisabled(hasChanges)
        .nativeEditorSize(height: 720)
    }

    private var quickProviders: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 82), spacing: 8)], spacing: 8) {
                ForEach(store.catalog.providers.filter { ["chatgpt", "claude", "gemini", "deepseek", "kimi", "custom"].contains($0.key) }) { item in
                    Button { pickProvider(item.key) } label: {
                        VStack(spacing: 8) {
                            ProviderBadge(provider: item, size: 32)
                            Text(item.name).font(.caption.weight(.medium)).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .padding(6)
                        .background(Color.primary.opacity(item.key == draft.provider ? 0.06 : 0.015), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(item.key == draft.provider ? 0.5 : 0.04), lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                    .accessibilityValue(item.key == draft.provider ? "已选择" : "")
                    .accessibilityIdentifier("account.provider-option.\(item.key)")
                }
            }.padding(.vertical, 4)
        }
    }

    private var basicSection: some View {
        Section("服务信息") {
            TextField("名称", text: $draft.name).focused($editingField, equals: .name).accessibilityIdentifier("account.name")
            Picker("全部服务商", selection: Binding(get: { draft.provider }, set: pickProvider)) {
                ForEach(store.catalog.providers) { Text($0.name).tag($0.key) }
                if !store.catalog.providers.contains(where: { $0.key == draft.provider }) {
                    Text("其他（\(draft.provider)）").tag(draft.provider)
                }
            }.accessibilityIdentifier("account.provider")
            Picker("怎么付费", selection: $draft.billing) {
                ForEach(billingOptions, id: \.self) { Text($0.label).tag($0) }
            }.accessibilityIdentifier("account.billing")
            if let note = provider.note {
                DisclosureGroup("服务说明") { Text(note).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
    }

    private var modelFields: some View {
        Group {
            Picker(draft.billing == .subscription ? "对照 API 模型" : "主要模型", selection: $draft.modelId) {
                Text("不对照").tag(String?.none)
                ForEach(comparisonModels) { model in
                    Text("\(store.catalog.provider(model.provider).name) · \(model.name)").tag(Optional(model.id))
                }
                if let id = draft.modelId, !comparisonModels.contains(where: { $0.id == id }) {
                    Text(store.catalog.models.first(where: { $0.id == id })?.name ?? id).tag(Optional(id))
                }
            }.accessibilityIdentifier("account.model")
            TextField("月报显示的模型（选填）", text: $draft.models, axis: .vertical).focused($editingField, equals: .models)
            TextField("备注（选填）", text: $draft.note, axis: .vertical).focused($editingField, equals: .note).lineLimit(1...4)
                .accessibilityIdentifier("account.note")
        }
    }

    private var planSection: some View {
        Section {
            Picker("套餐", selection: Binding(get: { draft.planId }, set: pickPlan)) {
                Text("自定义").tag(String?.none)
                ForEach(plans) { Text("\($0.name) · \(NativeFormat.money($0.price, currency: $0.currency))/月").tag(Optional($0.id)) }
                if let id = draft.planId, !plans.contains(where: { $0.id == id }) { Text(id).tag(Optional(id)) }
            }.accessibilityIdentifier("account.plan")
            if let plan = plans.first(where: { $0.id == draft.planId }) {
                DisclosureGroup("套餐说明") {
                    Text(plan.limits).font(.subheadline).foregroundStyle(.secondary)
                    if let fit = plan.fit { Text(fit).font(.subheadline).foregroundStyle(.secondary) }
                    if let url = URL(string: plan.source) { Link("官网 · 核对于 \(plan.checked)", destination: url).font(.subheadline) }
                }
            }
        } header: { Text("套餐") } footer: { Text("自动填入价格与重置规则，可手动调整。") }
    }

    private var paymentSection: some View {
        Section("费用") {
            LabeledContent(draft.billing.costLabel) {
                TextField(draft.billing.costLabel, text: $costText).focused($editingField, equals: .cost).nativeDecimalInput().labelsHidden()
                    .multilineTextAlignment(.trailing).accessibilityIdentifier("account.cost")
                    .onChange(of: costText) { _, newValue in
                        if let value = Self.parse(newValue), value != draft.monthlyCost { draft.planId = nil }
                    }
                }
            Picker("币种", selection: $draft.currency) {
                Text("美元 USD").tag(Currency.usd)
                Text("人民币 CNY").tag(Currency.cny)
            }
            if draft.billing == .subscription {
                Toggle("记录续费时间", isOn: Binding(get: { draft.renewAt != nil }, set: {
                    draft.renewAt = $0 ? DateCodec.iso(Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()) : nil
                }))
                if draft.renewAt != nil {
                    DatePicker("下次续费", selection: dateBinding(\.renewAt), displayedComponents: [.date, .hourAndMinute])
                }
            }
            if draft.billing == .balance {
                LabeledContent("当前余额") {
                    TextField("当前余额", text: $balanceText).focused($editingField, equals: .balance).nativeDecimalInput().labelsHidden()
                        .multilineTextAlignment(.trailing).accessibilityIdentifier("account.balance")
                }
            }
        }
    }

    private var resetFields: some View {
        Group {
            Picker("额度重置", selection: $draft.resetKind) {
                ForEach(ResetKind.allCases, id: \.self) { Text($0.label).tag($0) }
            }.accessibilityIdentifier("account.reset-kind")
            .onChange(of: draft.resetKind) { _, kind in
                if kind != .none && draft.resetAnchor == nil { draft.resetAnchor = DateCodec.iso(Date()) }
            }
            if draft.resetKind != .none {
                if draft.resetKind == .hours {
                    LabeledContent("每隔几小时") {
                        TextField("每隔几小时", text: $hoursText).focused($editingField, equals: .hours).nativeDecimalInput().labelsHidden()
                            .multilineTextAlignment(.trailing).accessibilityIdentifier("account.reset-hours")
                    }
                }
                DatePicker("重置锚点", selection: dateBinding(\.resetAnchor), displayedComponents: [.date, .hourAndMinute])
                Toggle("重置后通知我", isOn: $draft.notifyReset).accessibilityIdentifier("account.notify-reset")
            }
        }
    }

    private func dateBinding(_ keyPath: WritableKeyPath<Account, String?>) -> Binding<Date> {
        Binding(get: { DateCodec.date(draft[keyPath: keyPath]) ?? Date() }, set: { draft[keyPath: keyPath] = DateCodec.iso($0) })
    }

    private func pickProvider(_ key: String) {
        let previous = store.catalog.provider(draft.provider)
        let wasDefaultName = draft.name.isEmpty || store.catalog.providers.contains { $0.name == draft.name } || draft.name == "ChatGPT Plus" || store.catalog.plans.contains { "\(previous.name) \($0.name)" == draft.name }
        let next = store.catalog.provider(key)
        draft.provider = key
        draft.billing = next.defaultBilling
        draft.currency = next.currency
        draft.planId = nil
        let models = store.catalog.models(for: key)
        draft.modelId = (models.first { $0.tier == "balanced" } ?? models.first)?.id
        if wasDefaultName { draft.name = next.name }
        let options = store.catalog.plans(for: key)
        if next.defaultBilling == .subscription, let plan = options.dropFirst().first ?? options.first {
            applyPlan(plan)
        } else {
            draft.monthlyCost = 0
            costText = "0"
        }
    }

    private func pickPlan(_ id: String?) {
        guard let plan = plans.first(where: { $0.id == id }) else { draft.planId = nil; return }
        applyPlan(plan)
    }

    private func applyPlan(_ plan: Plan) {
        draft.planId = plan.id
        draft.billing = .subscription
        draft.monthlyCost = plan.price
        costText = Self.number(plan.price)
        draft.currency = plan.currency
        draft.resetKind = plan.resetKind
        draft.resetHours = plan.resetHours ?? draft.resetHours
        hoursText = Self.number(draft.resetHours ?? 5)
        if plan.resetKind != .none && draft.resetAnchor == nil { draft.resetAnchor = DateCodec.iso(Date()) }
    }

    private func save() {
        guard let cost = Self.parse(costText), cost.isFinite, cost >= 0 else {
            validationMessage = "费用需要填写大于或等于 0 的数字。"; return
        }
        if draft.billing == .balance {
            guard let balance = Self.parse(balanceText), balance.isFinite, balance >= 0 else {
                validationMessage = "余额需要填写大于或等于 0 的数字。"; return
            }
            draft.balance = balance
        } else { draft.balance = nil }
        if draft.resetKind == .hours {
            guard let hours = Self.parse(hoursText), hours.isFinite, hours > 0 else {
                validationMessage = "重置间隔需要填写大于 0 的小时数。"; return
            }
            draft.resetHours = hours
        }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.name.isEmpty { draft.name = provider.name }
        draft.monthlyCost = cost
        if draft.billing != .subscription { draft.planId = nil; draft.renewAt = nil }
        if draft.resetKind == .none { draft.notifyReset = false }
        if draft.resetKind != .none && draft.resetAnchor == nil { draft.resetAnchor = DateCodec.iso(Date()) }
        if store.saveAccount(draft) {
            if draft.notifyReset && !originalNotifyReset {
                Task { await notifications.request(backup: store.backup) }
            }
            dismiss()
        } else { validationMessage = store.errorMessage ?? "保存失败，请检查输入后重试。" }
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...8)).locale(.current))
    }
    private static func parse(_ value: String) -> Double? {
        let separator = Locale.current.decimalSeparator ?? "."
        return Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: separator, with: "."))
    }
}
