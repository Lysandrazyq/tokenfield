import Foundation

public enum CatalogIssue: LocalizedError, Equatable {
    case tooLarge
    case invalid(String)
    public var errorDescription: String? {
        switch self {
        case .tooLarge: return "价格目录超过允许的大小或条目数量。"
        case .invalid(let field): return "价格目录无效：\(field)。"
        }
    }
}

public extension Catalog {
    static let maximumDataBytes = 2_000_000
    static let maximumModels = 2_000

    static func decode(_ data: Data) throws -> Catalog {
        guard data.count <= maximumDataBytes else { throw CatalogIssue.tooLarge }
        return try JSONDecoder().decode(Catalog.self, from: data).validated()
    }

    func encoded() throws -> Data {
        _ = try validated()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(self)
        guard data.count <= Self.maximumDataBytes else { throw CatalogIssue.tooLarge }
        return data
    }

    @discardableResult func validated() throws -> Catalog {
        guard !providers.isEmpty, !plans.isEmpty, !models.isEmpty, !personas.isEmpty else {
            throw CatalogIssue.invalid("服务商、套餐、模型和使用场景不能为空")
        }
        guard providers.count <= 100, plans.count <= 2_000, models.count <= Self.maximumModels, personas.count <= 100 else { throw CatalogIssue.tooLarge }
        try Self.unique(providers.map(\.key), field: "服务商 ID")
        try Self.unique(plans.map(\.id), field: "套餐 ID")
        try Self.unique(models.map(\.id), field: "模型 ID")
        try Self.unique(personas.map(\.key), field: "场景 ID")
        let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.key, $0) })
        for provider in providers {
            try Self.text(provider.name, field: "服务商名称", required: true)
            try Self.text(provider.note, field: "服务商说明")
            guard provider.color.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { throw CatalogIssue.invalid("服务商颜色") }
            if let url = provider.pricingUrl { try Self.source(url, provider: provider) }
        }
        for plan in plans {
            guard let provider = providerMap[plan.provider] else { throw CatalogIssue.invalid("套餐服务商引用") }
            try Self.amount(plan.price, field: "套餐价格")
            try Self.text(plan.name, field: "套餐名称", required: true)
            try Self.text(plan.limits, field: "套餐限制", required: true)
            try Self.text(plan.fit, field: "套餐适用场景")
            try Self.day(plan.checked)
            try Self.source(plan.source, provider: provider)
            if let hours = plan.resetHours {
                guard hours.isFinite, hours > 0, hours <= 24 * 366 else { throw CatalogIssue.invalid("重置小时数") }
            }
            if plan.resetKind == .hours, plan.resetHours == nil { throw CatalogIssue.invalid("缺少重置小时数") }
        }
        for model in models {
            guard let provider = providerMap[model.provider] else { throw CatalogIssue.invalid("模型服务商引用") }
            try Self.amount(model.input, field: "模型输入价格")
            try Self.amount(model.output, field: "模型输出价格")
            if let cached = model.cachedInput { try Self.amount(cached, field: "模型缓存价格") }
            try Self.text(model.name, field: "模型名称", required: true)
            try Self.text(model.tier, field: "模型分档", required: true)
            try Self.text(model.note, field: "模型说明")
            try Self.day(model.checked)
            try Self.source(model.source, provider: provider)
        }
        for persona in personas {
            try Self.text(persona.name, field: "场景名称", required: true)
            try Self.text(persona.who, field: "适用人群", required: true)
            try Self.text(persona.advice, field: "场景建议", required: true)
            guard (0...1_000_000).contains(persona.usesPerMonth) else { throw CatalogIssue.invalid("每月使用次数") }
        }
        return self
    }

    private static func unique(_ identifiers: [String], field: String) throws {
        guard Set(identifiers).count == identifiers.count,
              identifiers.allSatisfy({ $0.range(of: "^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$", options: .regularExpression) != nil }) else { throw CatalogIssue.invalid("\(field) 为空、重复或格式错误") }
    }

    private static func amount(_ value: Double, field: String) throws {
        guard value.isFinite, value >= 0, value <= 1_000_000_000 else { throw CatalogIssue.invalid(field) }
    }

    private static func text(_ value: String?, field: String, required: Bool = false) throws {
        guard let value else { if required { throw CatalogIssue.invalid(field) }; return }
        guard value.utf8.count <= 8_192, !required || !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw CatalogIssue.invalid(field) }
    }

    private static func day(_ value: String) throws {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { throw CatalogIssue.invalid("核验日期格式") }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard parts[0] >= 2000, parts[0] <= 9999, let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { throw CatalogIssue.invalid("核验日期不存在") }
    }

    private static func source(_ value: String, provider: Provider) throws {
        guard value.utf8.count <= 2_048,
              !value.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URLComponents(string: value), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              host.range(of: "^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,63}$", options: .regularExpression) != nil else { throw CatalogIssue.invalid("来源必须是 HTTPS 官网链接") }
        // These existing provider IDs have established official domains. New providers
        // declare their own website; this validates link structure, not the site's claims.
        let knownDomains: [String: [String]] = [
            "chatgpt": ["openai.com", "chatgpt.com"], "claude": ["claude.com", "anthropic.com"],
            "gemini": ["google.com", "google.dev", "gemini.google"], "deepseek": ["deepseek.com"],
            "kimi": ["kimi.com", "moonshot.cn", "moonshot.ai"], "glm": ["bigmodel.cn", "z.ai"],
            "qwen": ["aliyun.com", "qwen.ai"], "doubao": ["volcengine.com", "volcengineapi.com"],
            "minimax": ["minimaxi.com", "minimax.io", "minimax.cn"]
        ]
        let domains = knownDomains[provider.key] ?? provider.pricingUrl.flatMap { URLComponents(string: $0)?.host }.map { [$0.lowercased()] } ?? []
        guard domains.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { throw CatalogIssue.invalid("来源域名与服务商官网不匹配") }
    }
}
