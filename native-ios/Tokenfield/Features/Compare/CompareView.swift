import SwiftUI
import TokenfieldCore

private enum CompareRegion: String, CaseIterable {
    case all = "全部", domestic = "国内", global = "海外"
    func includes(_ provider: String) -> Bool {
        let domestic = ["deepseek", "kimi", "glm", "qwen", "doubao", "minimax"].contains(provider)
        return self == .all || (self == .domestic ? domestic : !domestic)
    }
}

private struct ModelEstimate: Identifiable {
    let model: APIModel
    let monthly: Double
    var id: String { model.id }
}

struct CompareView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var personaKey = "casual"
    @State private var intensity: Intensity = .chat
    @State private var uses = 150.0
    @State private var region: CompareRegion = .all
    @State private var showAll = false

    private var profile: UsageProfile { UsageProfile.profile(for: intensity) }
    private var persona: Persona? { store.catalog.personas.first { $0.key == personaKey } }
    private var coding: Bool { intensity == .code || intensity == .agent }
    private var maxUses: Double { intensity == .agent ? 600 : 3000 }
    private var models: [ModelEstimate] {
        store.catalog.models.filter { region.includes($0.provider) }.map {
            ModelEstimate(model: $0, monthly: Finance.cny(Finance.costPerUse(profile: profile, model: $0), currency: $0.currency, rate: store.settings.usdRate) * uses)
        }.sorted { $0.monthly == $1.monthly ? $0.id < $1.id : $0.monthly < $1.monthly }
    }
    private var plans: [Plan] {
        store.catalog.plans.filter {
            region.includes($0.provider) && (coding ? $0.coding == true : $0.codingOnly != true)
        }.sorted {
            let a = fee($0), b = fee($1)
            return a == b ? $0.id < $1.id : a < b
        }
    }

    var body: some View {
        ExperiencePage { width in
            VStack(alignment: .leading, spacing: 24) {
                PageIntro(eyebrow: "费用对比", title: "会员还是按量？", detail: "按你的使用频率，比较不同付费方式的参考费用。")
                AdaptiveColumns(wide: width >= 720 && !typeSize.isAccessibilitySize) {
                    VStack(spacing: 22) {
                        scenarioCard
                        estimateControls
                        assumptions
                        sources
                    }
                } trailing: {
                    VStack(spacing: 22) {
                        if let lowest = models.first?.monthly { conclusion(api: lowest) }
                        if models.isEmpty && plans.isEmpty {
                            ContentUnavailableView("暂无价格数据", systemImage: "chart.bar.xaxis", description: Text("当前筛选下没有收录的价格，请切换地区或使用强度。"))
                        } else {
                            modelList
                            planList
                        }
                    }
                }
                Text("最近核对 \(store.catalog.latestCheck) · 各项日期见官网链接，价格未实时更新")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("会员还是按量？").nativeInlineTitle()
    }

    private var scenarioCard: some View {
        NativeCard {
            SectionHeading(title: "先选一种用法", subtitle: "可以随时调整，不会修改你的真实服务记录")
            Picker("使用场景", selection: Binding(get: { personaKey }, set: pickPersona)) {
                ForEach(store.catalog.personas) { Text($0.name).tag($0.key) }
            }.pickerStyle(.menu).accessibilityIdentifier("compare.persona")
            if let persona {
                Text(persona.who).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var estimateControls: some View {
        NativeCard {
            Picker("主要拿来做什么", selection: $intensity) {
                ForEach(Intensity.allCases, id: \.self) { Text($0.label).tag($0) }
            }.pickerStyle(.menu).accessibilityIdentifier("compare.intensity")
            .onChange(of: intensity) { _, _ in uses = min(uses, maxUses) }
            Text("\(profile.example)。按每次约 \(tokenNumber(profile.input))k 输入 + \(tokenNumber(profile.output))k 输出估算。")
                .font(.subheadline).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text("每月大约用几次").font(.subheadline.weight(.medium))
                Text("\(Int(uses)) 次 · 每天约 \(Int((uses / 30).rounded())) 次").monospacedDigit()
                Slider(value: $uses, in: 10...maxUses, step: 10) { Text("每月使用次数") }
                    .accessibilityValue("\(Int(uses)) 次").accessibilityIdentifier("compare.uses")
            }
            if typeSize.isAccessibilitySize {
                regionPicker.pickerStyle(.menu)
            } else { regionPicker.pickerStyle(.segmented) }
        }
    }

    private var regionPicker: some View {
        Picker("地区", selection: $region) {
            ForEach(CompareRegion.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.accessibilityIdentifier("compare.region")
    }

    private func conclusion(api: Double) -> some View {
        NativeCard {
            SectionHeading(title: "这份用量，怎么付更合适")
            Text(conclusionText(api: api)).font(.headline)
            if let persona { Text(persona.advice).font(.subheadline).foregroundStyle(.secondary) }
            Text("仅比较费用；模型能力、使用入口和会员额度限制也会影响选择。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var modelList: some View {
        if !models.isEmpty {
            NativeCard {
                SectionHeading(title: "按量付费", subtitle: "按你选择的使用频率估算每月费用")
                Text("\(Int(uses)) 次 · \(profile.label)").font(.caption).foregroundStyle(.secondary)
                ForEach(showAll ? models : Array(models.prefix(8))) { estimate in
                    CompareModelRow(model: estimate.model, provider: store.catalog.provider(estimate.model.provider), monthly: estimate.monthly, best: estimate.id == models.first?.id)
                    if estimate.id != (showAll ? models.last?.id : models.prefix(8).last?.id) { Divider() }
                }
                if models.count > 8 {
                    Button(showAll ? "收起" : "显示全部 \(models.count) 个模型") { showAll.toggle() }
                        .frame(maxWidth: .infinity).accessibilityIdentifier("compare.show-all")
                }
            }
        }
    }

    @ViewBuilder private var planList: some View {
        if !plans.isEmpty {
            NativeCard {
                SectionHeading(title: coding ? "支持代码工作的会员" : "会员订阅")
                Text("\(plans.count) 个套餐 · 按月费从低到高").font(.caption).foregroundStyle(.secondary)
                ForEach(plans) { plan in
                    ComparePlanRow(plan: plan, provider: store.catalog.provider(plan.provider), fee: fee(plan), apiBest: models.first?.monthly)
                    if plan.id != plans.last?.id { Divider() }
                }
                Text("会员有用量上限，超过需要等待重置或另买额度；按量付费用多少付多少。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var assumptions: some View {
        NativeCard {
            DisclosureGroup("怎么算的") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("按量费用 = 每月次数 × 每次 token 数 × 官方单价。每次「\(profile.label)」约 \(tokenNumber(profile.input))k 输入、\(tokenNumber(profile.output))k 输出，其中 \(Int((profile.cacheRatio * 100).rounded()))% 的输入按缓存命中价算。")
                    Text(profile.basis)
                    Text("1 美元 = \(store.settings.usdRate.formatted()) 元。DeepSeek 按高峰价计，空闲时段可能更低。")
                    Text("会员实际额度以服务商为准。价格来自本机目录，未实时更新。")
                }
                .font(.subheadline).foregroundStyle(.secondary).padding(.top, 8)
            }
            .accessibilityLabel("怎么算的")
            .accessibilityIdentifier("compare.assumptions")
        }
    }

    private var sources: some View {
        NativeCard {
            NavigationLink { PricingSourcesView(catalog: store.catalog) } label: {
                Label("价格来源", systemImage: "link")
            }
            .accessibilityLabel("价格来源")
            .accessibilityIdentifier("compare.sources")
            NavigationLink { DisclaimerView(catalog: store.catalog) } label: {
                Label("免责声明", systemImage: "doc.text")
            }
            .accessibilityLabel("免责声明")
            .accessibilityIdentifier("compare.disclaimer")
        }
    }

    private func pickPersona(_ key: String) {
        guard let value = store.catalog.personas.first(where: { $0.key == key }) else { return }
        personaKey = key
        intensity = value.intensity
        uses = Double(value.usesPerMonth)
    }

    private func fee(_ plan: Plan) -> Double { Finance.cny(plan.price, currency: plan.currency, rate: store.settings.usdRate) }

    private func conclusionText(api: Double) -> String {
        guard let plan = plans.first else { return "按量付费最低每月约 \(NativeFormat.money(api))。" }
        let planFee = fee(plan)
        if api < planFee {
            return "按量付费更省：最低每月约 \(NativeFormat.money(api))，比最便宜的会员少 \(NativeFormat.money(planFee - api))。"
        }
        return "会员更划算：同样用量按量付费最低也要 \(NativeFormat.money(api))，最便宜的会员 \(NativeFormat.money(planFee))。"
    }

    private func tokenNumber(_ number: Double) -> String { (number / 1000).formatted(.number.precision(.fractionLength(0...1))) }
}

private struct CompareModelRow: View {
    let model: APIModel
    let provider: Provider
    let monthly: Double
    let best: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ProviderBadge(provider: provider, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name).font(.caption).foregroundStyle(.secondary)
                    Text(model.name).font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 4)
                Text(NativeFormat.money(monthly)).font(.subheadline.bold()).monospacedDigit()
                    .foregroundStyle(best ? Color.green : Color.primary).fixedSize(horizontal: false, vertical: true)
            }
            Text("\(model.currency.symbol)\(model.input.formatted()) 输入 / \(model.currency.symbol)\(model.output.formatted()) 输出 · 每百万 token")
                .font(.caption).foregroundStyle(.secondary)
            if let note = model.note { Text(note).font(.caption).foregroundStyle(.secondary) }
            if let url = URL(string: model.source) {
                Link("官网 · 核对于 \(model.checked)", destination: url).font(.caption)
            }
        }.padding(.vertical, 4)
    }
}

private struct ComparePlanRow: View {
    let plan: Plan
    let provider: Provider
    let fee: Double
    let apiBest: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ProviderBadge(provider: provider, size: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.name).font(.caption).foregroundStyle(.secondary)
                    Text(plan.name).font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(NativeFormat.money(fee)).font(.subheadline.bold()).monospacedDigit()
                        .foregroundStyle(apiBest.map { fee < $0 } == true ? Color.green : Color.primary)
                    Text("\(NativeFormat.money(plan.price, currency: plan.currency))/月").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(plan.limits).font(.caption).foregroundStyle(.secondary)
            if let fit = plan.fit { Text(fit).font(.caption).foregroundStyle(.secondary) }
            if plan.codingOnly == true { Text("编程专用").font(.caption).foregroundStyle(.tint) }
            else if plan.coding == true { Text("含编程工具").font(.caption).foregroundStyle(.tint) }
            if let url = URL(string: plan.source) {
                Link("官网 · 核对于 \(plan.checked)", destination: url).font(.caption)
            }
        }.padding(.vertical, 4)
    }
}
