import Foundation

public enum WelcomePolicy {
    public static func shouldPresent(backup: Backup, completed: Bool, hasLoadError: Bool = false) -> Bool {
        !completed && !hasLoadError && backup.accounts.isEmpty && backup.expiries.isEmpty
            && backup.usage.isEmpty && backup.statements.isEmpty && backup.settings == AppSettings()
    }
}

/// Keeps local edits through background refreshes, while explicit replacements win.
public struct SettingsEditSession: Equatable, Sendable {
    public var draft: AppSettings
    private var baseline: AppSettings?
    public init() { draft = AppSettings() }
    public var hasChanges: Bool { baseline.map { draft != $0 } ?? false }
    public mutating func receive(_ incoming: AppSettings) {
        guard baseline == nil || !hasChanges else { return }
        baseline = incoming
        draft = incoming
    }
    public mutating func acceptReplacement(_ incoming: AppSettings) {
        baseline = incoming
        draft = incoming
    }
}
