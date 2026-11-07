import SwiftUI
import TokenfieldCore

enum BrandPalette {
    static let accent = Color("ContentAccent")
    static let control = Color("AccentColor")
    static let signal = Color.green
}

#if os(macOS)
struct CodexStatusCard: View {
    @Environment(CodexMonitorStore.self) private var monitor
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            NativeCard {
                HStack(alignment: .center, spacing: 14) {
                    Image(systemName: "terminal")
                        .font(.title2).foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Codex 实时").font(.headline)
                        if monitor.issue != nil {
                            Label("连接需要检查", systemImage: "exclamationmark.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else if let snapshot = monitor.snapshot {
                            let now = Date()
                            let active = snapshot.sessions.filter { $0.phase(at: now) == .running }.count
                            Text(active > 0 ? "\(active) 个任务正在活动" : "已连接，等待任务活动")
                                .font(.subheadline).foregroundStyle(.secondary)
                            if let quota = snapshot.quota {
                                if let remaining = quota.primary?.remainingPercent(at: now) {
                                    Text("上报剩余 \(remaining.formatted(.number.precision(.fractionLength(0...1))))%")
                                        .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                                } else {
                                    Text("额度待更新").font(.subheadline).foregroundStyle(.secondary)
                                }
                                Text("上报 \(quota.reportedAt.formatted(date: .omitted, time: .shortened))\(quota.isStale(at: now) ? " · 数据较旧" : "")")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text("额度等待上报").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(monitor.isConnecting ? "正在连接本机日志…" : "查看本机任务与额度")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.medium)).foregroundStyle(.tertiary)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.codex")
        .accessibilityHint("打开 Codex 实时看板，查看任务、完整额度和上报时间")
    }
}
#endif
