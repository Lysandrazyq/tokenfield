import SwiftUI
import TokenfieldCore

enum NativeFormat {
    static func money(_ amount: Double, currency: Currency = .cny) -> String {
        guard amount.isFinite else { return "超出显示范围" }
        if amount.isFinite, amount >= 1e15 {
            return currency.symbol + amount.formatted(.number.notation(.scientific).precision(.significantDigits(1...6)).locale(Locale(identifier: "zh_CN")))
        }
        return currency.symbol + amount.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "zh_CN")))
    }

    static func progressValue(numerator: Double, denominator: Double) -> Double? {
        guard !numerator.isNaN, !denominator.isNaN,
              numerator.isFinite || denominator.isFinite else { return nil }
        return min(1, max(0, denominator > 0 ? numerator / denominator : 1))
    }

    static func color(_ hex: String) -> Color {
        let value = UInt64(hex.replacingOccurrences(of: "#", with: ""), radix: 16) ?? 0x6E6E6E
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct ProviderBadge: View {
    let provider: Provider
    var size: CGFloat = 36
    private let assetKeys = ["chatgpt", "claude", "gemini", "deepseek", "kimi", "glm", "qwen", "doubao", "minimax"]

    var body: some View {
        Group {
            if assetKeys.contains(provider.key) {
                Image(provider.key).resizable().scaledToFit().padding(6)
            } else {
                Text(String(provider.name.prefix(1))).font(.headline).foregroundStyle(NativeFormat.color(provider.color))
            }
        }
        .frame(width: size, height: size)
        .background(Color.white.opacity(0.9), in: RoundedRectangle(cornerRadius: size * 0.28))
        .accessibilityHidden(true)
    }
}

struct NativeCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 16) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(Color.nativeCardBackground, in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.primary.opacity(contrast == .increased ? 0.35 : 0.1), lineWidth: 1)
            }
    }
}

struct NativeSectionTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NativeControlGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // Content controls use standard surfaces; system navigation owns Liquid Glass.
        content
    }
}

struct SecondaryActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 10))
            .tint(.primary).controlSize(.large)
    }
}
