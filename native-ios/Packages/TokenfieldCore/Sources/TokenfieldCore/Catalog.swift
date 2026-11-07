import Foundation

public struct Provider: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var color: String
    public var hasSubscription: Bool
    public var defaultBilling: Billing
    public var currency: Currency
    public var pricingUrl: String?
    public var note: String?
    public var id: String { key }
    public init(key: String, name: String, color: String, hasSubscription: Bool, defaultBilling: Billing, currency: Currency, pricingUrl: String? = nil, note: String? = nil) {
        self.key = key; self.name = name; self.color = color; self.hasSubscription = hasSubscription; self.defaultBilling = defaultBilling; self.currency = currency; self.pricingUrl = pricingUrl; self.note = note
    }
}
public struct Plan: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var price: Double
    public var currency: Currency
    public var limits: String
    public var resetKind: ResetKind
    public var resetHours: Double?
    public var fit: String?
    public var coding: Bool?
    public var codingOnly: Bool?
    public var source: String
    public var checked: String
    public init(id: String, provider: String, name: String, price: Double, currency: Currency, limits: String, resetKind: ResetKind, resetHours: Double? = nil, fit: String? = nil, coding: Bool? = nil, codingOnly: Bool? = nil, source: String, checked: String) {
        self.id = id; self.provider = provider; self.name = name; self.price = price; self.currency = currency; self.limits = limits; self.resetKind = resetKind; self.resetHours = resetHours; self.fit = fit; self.coding = coding; self.codingOnly = codingOnly; self.source = source; self.checked = checked
    }
}
public struct APIModel: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: String
    public var name: String
    public var input: Double
    public var output: Double
    public var cachedInput: Double?
    public var currency: Currency
    public var tier: String
    public var note: String?
    public var source: String
    public var checked: String
    public init(id: String, provider: String, name: String, input: Double, output: Double, cachedInput: Double? = nil, currency: Currency, tier: String, note: String? = nil, source: String, checked: String) {
        self.id = id; self.provider = provider; self.name = name; self.input = input; self.output = output; self.cachedInput = cachedInput; self.currency = currency; self.tier = tier; self.note = note; self.source = source; self.checked = checked
    }
}
public struct Persona: Codable, Equatable, Sendable, Identifiable {
    public var key: String
    public var name: String
    public var who: String
    public var intensity: Intensity
    public var usesPerMonth: Int
    public var advice: String
    public var id: String { key }
    public init(key: String, name: String, who: String, intensity: Intensity, usesPerMonth: Int, advice: String) {
        self.key = key; self.name = name; self.who = who; self.intensity = intensity; self.usesPerMonth = usesPerMonth; self.advice = advice
    }
}
public struct Catalog: Codable, Equatable, Sendable {
    public var providers: [Provider]
    public var plans: [Plan]
    public var models: [APIModel]
    public var personas: [Persona]
    public init(providers: [Provider] = [], plans: [Plan] = [], models: [APIModel] = [], personas: [Persona] = []) { self.providers = providers; self.plans = plans; self.models = models; self.personas = personas }
    public static let bundled: Catalog = {
        guard let url = Bundle.module.url(forResource: "catalog", withExtension: "json"), let data = try? Data(contentsOf: url), let catalog = try? JSONDecoder().decode(Catalog.self, from: data) else { preconditionFailure("Bundled pricing catalog is missing or invalid") }
        return catalog
    }()
    public func provider(_ key: String) -> Provider {
        providers.first { $0.key == key } ?? providers.first { $0.key == "custom" } ?? Provider(key: "custom", name: "其他", color: "#8e8e93", hasSubscription: true, defaultBilling: .subscription, currency: .usd)
    }
    public func plans(for key: String) -> [Plan] { plans.filter { $0.provider == key } }
    public func models(for key: String) -> [APIModel] { models.filter { $0.provider == key } }
    public var latestCheck: String { (plans.map(\.checked) + models.map(\.checked)).max() ?? "" }
}

public struct UsageProfile: Codable, Equatable, Sendable {
    public var key: Intensity
    public var short: String
    public var label: String
    public var input: Double
    public var output: Double
    public var cacheRatio: Double
    public var example: String
    public var basis: String
    public init(key: Intensity, short: String, label: String, input: Double, output: Double, cacheRatio: Double, example: String, basis: String) { self.key = key; self.short = short; self.label = label; self.input = input; self.output = output; self.cacheRatio = cacheRatio; self.example = example; self.basis = basis }
    public static let all: [UsageProfile] = [
        .init(key: .chat, short: "问答", label: "日常问答", input: 1500, output: 500, cacheRatio: 0.3, example: "查资料、问问题、翻译一段话", basis: "回答约 800 字、带几轮历史；官方换算 1 token ≈ 1.5–2 个汉字"),
        .init(key: .write, short: "写作", label: "写作 / 读文档", input: 8000, output: 1500, cacheRatio: 0.4, example: "改一篇稿子、总结一份 PDF、写邮件", basis: "贴进去约 1 万字的材料，输出两千来字"),
        .init(key: .code, short: "写代码", label: "写代码（对话式）", input: 20000, output: 2500, cacheRatio: 0.6, example: "在网页里贴代码、让它改 bug、解释报错", basis: "每次带上几个文件和报错，输出一段代码"),
        .init(key: .agent, short: "Agent", label: "编程 Agent", input: 2000000, output: 20000, cacheRatio: 0.92, example: "Claude Code / Codex / Cursor 自动改一整个功能", basis: "一个任务要反复读文件、跑命令几十轮，九成以上输入命中缓存。按 Anthropic 官方数据校准：Claude Code 平均每人每个工作日约 $13、每月 $150–250")
    ]
    public static func profile(for intensity: Intensity) -> UsageProfile { all.first { $0.key == intensity }! }
}
