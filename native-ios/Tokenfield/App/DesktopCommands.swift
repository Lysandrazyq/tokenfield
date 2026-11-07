#if os(macOS)
import SwiftUI

private struct NavigateDestinationKey: FocusedValueKey {
    typealias Value = (Int) -> Void
}
private struct NewAccountActionKey: FocusedValueKey {
    typealias Value = () -> Void
}
extension FocusedValues {
    var navigateDestination: ((Int) -> Void)? {
        get { self[NavigateDestinationKey.self] }
        set { self[NavigateDestinationKey.self] = newValue }
    }
    var newAccountAction: (() -> Void)? {
        get { self[NewAccountActionKey.self] }
        set { self[NewAccountActionKey.self] = newValue }
    }
}

struct DesktopCommands: Commands {
    @FocusedValue(\.navigateDestination) private var navigate
    @FocusedValue(\.newAccountAction) private var addAccount

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("添加 AI") { addAccount?() }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(addAccount == nil)
        }
        CommandGroup(replacing: .appSettings) {
            Button("设置…") { navigate?(3) }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(navigate == nil)
        }
        CommandMenu("前往") {
            Button("概览") { navigate?(0) }.keyboardShortcut("1", modifiers: .command)
            Button("比价") { navigate?(1) }.keyboardShortcut("2", modifiers: .command)
            Button("月报") { navigate?(2) }.keyboardShortcut("3", modifiers: .command)
            Button("Codex 实时") { navigate?(4) }.keyboardShortcut("4", modifiers: .command)
        }
        SidebarCommands()
    }
}
#endif
