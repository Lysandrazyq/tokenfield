import SwiftUI
import TokenfieldCore

extension Intensity {
    /// User-facing purpose names; persisted raw values remain unchanged.
    var usageTitle: String { self == .agent ? "长任务" : label }
}

/// Uses the offered scene width, including after a fold or live window resize.
struct ExperiencePage<Content: View>: View {
    var maximumWidth: CGFloat = 1160
    @ViewBuilder var content: (CGFloat) -> Content

    var body: some View {
        GeometryReader { geometry in
            let margin: CGFloat = geometry.size.width < 390 ? 16 : 24
            let width = max(0, min(maximumWidth, geometry.size.width - margin * 2))
            ScrollView {
                content(width)
                    .frame(maxWidth: maximumWidth, alignment: .leading)
                    .padding(.horizontal, margin)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .nativeScrollDismissesKeyboard()
        }
        .background { AppBackdrop() }
    }
}

/// AnyLayout keeps the two children in the same identity positions while resizing.
struct AdaptiveColumns<Leading: View, Trailing: View>: View {
    let wide: Bool
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let layout = wide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 22))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 22))
        layout {
            leading.frame(maxWidth: .infinity, alignment: .topLeading)
            trailing.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct PageIntro: View {
    let eyebrow: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow).font(.subheadline).foregroundStyle(.secondary)
            Text(title).font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.title3.weight(.semibold))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SummaryMetric: View {
    let title: String
    let value: String
    let symbol: String
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                .modifier(NativeNumericFeedback()).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct NumberedGuideRow: View {
    let number: Int
    let title: String
    let detail: String
    var complete = false
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Group {
                if complete { Image(systemName: "checkmark").font(.caption.weight(.bold)) }
                else { Text("\(number)").font(.caption.monospacedDigit().weight(.semibold)) }
            }
            .frame(width: 30, height: 30)
            .foregroundStyle(complete ? Color.green : Color.secondary)
            .background(Color.primary.opacity(0.045), in: Circle())
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct UsageFeedback: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let text: String
    var body: some View {
        Label { Text(text) } icon: {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background {
                if reduceTransparency { RoundedRectangle(cornerRadius: 14).fill(Color.nativePageBackground) }
                else { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial) }
            }
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.16), lineWidth: 1) }
            .accessibilityIdentifier("home.usage-feedback")
    }
}

/// Restrict number rolling to explicit user actions, and honor Reduce Motion.
struct NativeNumericFeedback: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.contentTransition(reduceMotion ? .identity : .numericText())
    }
}

func usageSymbol(_ key: String) -> String {
        switch key {
        case "chat": return "bubble.left.and.bubble.right"
        case "write": return "pencil.line"
        case "code": return "chevron.left.forwardslash.chevron.right"
        default: return "sparkles"
        }
}
