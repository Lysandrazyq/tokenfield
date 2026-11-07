import Foundation
import TokenfieldCore

struct ReminderReconciliation {
    var history: [String: Double]
    let reminders: [Reminder]
    let obsolete: [String]
    static let prefix = "tokenfield."

    init(backup: Backup, now: Date, history previous: [String: Double], pendingIDs: Set<String>, deliveredIDs: Set<String>) {
        history = previous.filter { $0.value > now.addingTimeInterval(-50 * 86400).timeIntervalSince1970 }
        let alreadyDue = Set(history.filter { $0.value <= now.timeIntervalSince1970 }.map(\.key))
        reminders = Schedule.reminders(backup: backup, now: now).filter {
            !alreadyDue.contains(Self.prefix + $0.id) && !deliveredIDs.contains(Self.prefix + $0.id)
        }
        let wanted = Set(reminders.map { Self.prefix + $0.id })
        obsolete = pendingIDs.filter { $0.hasPrefix(Self.prefix) && !wanted.contains($0) }.sorted()
        for id in obsolete where !deliveredIDs.contains(id) {
            if let scheduled = history[id], scheduled > now.timeIntervalSince1970 {
                history.removeValue(forKey: id)
            }
        }
    }
}
