import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

extension Color {
    static var nativePageBackground: Color { Color("PageBackground") }

    static var nativeCardBackground: Color {
        Color("CardBackground")
    }
}

extension View {
    @ViewBuilder func nativeEditingBar<Controls: View>(isEditing: Bool, @ViewBuilder controls: () -> Controls) -> some View {
        #if os(iOS)
        safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                NativeControlGroup { controls() }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(.bar)
            }
        }
        #else
        self
        #endif
    }

    @ViewBuilder func nativeDecimalInput() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    @ViewBuilder func nativeNoCapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never)
        #else
        self
        #endif
    }

    @ViewBuilder func nativeInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    @ViewBuilder func nativeScrollDismissesKeyboard() -> some View {
        #if os(iOS)
        scrollDismissesKeyboard(.interactively)
        #else
        self
        #endif
    }

    @ViewBuilder func nativeGroupedForm() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    @ViewBuilder func nativeEditorSize(height: CGFloat) -> some View {
        #if os(macOS)
        frame(width: 580, height: height)
        #else
        self
        #endif
    }
}

enum PlatformSettings {
    @MainActor static func openNotifications(using openURL: OpenURLAction) {
        #if os(macOS)
        let identifier = Bundle.main.bundleIdentifier ?? "space.lysandra.quotakeeper"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?\(identifier)") { openURL(url) }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    @MainActor static func dismissKeyboard() {
        #if os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #else
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
}
