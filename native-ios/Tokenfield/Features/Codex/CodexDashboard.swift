#if os(macOS)
import SwiftUI
import TokenfieldCore

struct CodexDashboard: View {
    @Environment(CodexMonitorStore.self) private var monitor
    @Environment(NotificationService.self) private var notifications
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: String?
    @State private var showingQuotaAlerts = false
    var focusRequest = 0
    var alertsRequest = 0

    var body: some View {
        ScrollViewReader { proxy in
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ExperiencePage { width in
                VStack(alignment: .leading, spacing: 24) {
                    PageIntro(eyebrow: "本机实时看板", title: "Codex 额度与任务")
                        .id("codex.top")
                    connectionBar
                    if let issue = monitor.issue {
                        Label(issue, systemImage: "exclamationmark.circle").font(.subheadline).textSelection(.enabled)
                            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
                    }
                    if let snapshot = monitor.snapshot {
                        quotaCard(snapshot.quota, now: context.date, wide: width >= 620 && !typeSize.isAccessibilitySize)
                            .id("codex.quota-section")
                        if snapshot.sessions.isEmpty {
                            NativeCard {
                                SectionHeading(title: "已连接，等待任务活动", subtitle: "在 Codex 中开始或继续一个任务，这里会自动发现日志。新会话最多约 5 秒出现。")
                            }
                        } else {
                            AdaptiveColumns(wide: width >= 760 && !typeSize.isAccessibilitySize) {
                                sessionsCard(snapshot, now: context.date)
                            } trailing: {
                                if let selected = resolvedSelection(in: snapshot) {
                                    detailCard(selected, now: context.date)
                                        .id(selected.id)
                                        .transition(reduceMotion ? .identity : .opacity)
                                }
                            }
                        }
                        if snapshot.warnings > 0 {
                            Text("已跳过部分过大、无法读取或格式不支持的记录（\(snapshot.warnings)）。后续有效日志仍会继续更新。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    } else if monitor.isConnecting {
                        ProgressView("正在读取最近会话…").frame(maxWidth: .infinity).padding(40)
                    } else if monitor.directory == nil {
                        connectionGuide
                    }
                    Text("仅提取授权目录中的任务元数据与用量；不保存聊天正文、推理或命令输出，也不上传。token 累计含缓存及重复上下文，不等于实际账单或额度百分比。")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: focusRequest) { _, _ in
            showingQuotaAlerts = false
            proxy.scrollTo(monitor.snapshot == nil ? "codex.top" : "codex.quota-section", anchor: .top)
        }
        .task {
            if focusRequest > 0 { proxy.scrollTo(monitor.snapshot == nil ? "codex.top" : "codex.quota-section", anchor: .top) }
            presentRequestedAlerts()
        }
        .onChange(of: alertsRequest) { _, _ in presentRequestedAlerts() }
        }
        .navigationTitle("Codex 实时")
        .accessibilityIdentifier("codex.dashboard")
        .sheet(isPresented: $showingQuotaAlerts) { CodexQuotaAlertSettingsView() }
        .onChange(of: showingQuotaAlerts) { _, visible in notifications.codexNavigation.alertsSheetVisible = visible }
        .onDisappear { notifications.codexNavigation.alertsSheetVisible = false }
    }

    private func presentRequestedAlerts() {
        if notifications.codexNavigation.takeAlertsPresentation() { showingQuotaAlerts = true }
    }

    private var connectionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack { connectionStatus; Spacer(minLength: 16); connectionActions }
            VStack(alignment: .leading, spacing: 14) { connectionStatus; connectionActions }
        }
    }
    private var connectionStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(monitor.directory == nil ? "连接本机数据" : monitor.issue == nil ? (monitor.automaticallyConnected ? "已自动连接 Codex" : "本机日志已连接") : "连接需要检查",
                  systemImage: monitor.directory == nil ? "link" : monitor.issue == nil ? "circle.inset.filled" : "exclamationmark.circle")
                .font(.subheadline.weight(.medium))
            if monitor.directory != nil {
                Text(monitor.issue == nil ? "自动读取本机日志 · 无需 API Key" : "请检查目录权限，或重新连接")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else { Text("自动检测本机日志，也可选择自定义目录。") .font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var connectionActions: some View {
        HStack(spacing: 10) {
            Button { showingQuotaAlerts = true } label: { Label("额度提醒", systemImage: "bell") }
                .modifier(SecondaryActionStyle()).fixedSize()
                .accessibilityIdentifier("codex.alerts")
            if monitor.directory != nil {
                Button { Task { await monitor.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                    .modifier(SecondaryActionStyle()).disabled(monitor.isRefreshing).accessibilityIdentifier("codex.refresh")
                Menu {
                    if let directory = monitor.directory { Text("数据目录：\(directory.path)") }
                    Button("重新选择目录") { monitor.chooseDirectory() }
                    Button("断开连接", role: .destructive) { monitor.disconnect(); selectedID = nil }
                        .accessibilityIdentifier("codex.disconnect")
                } label: { Image(systemName: "ellipsis").frame(minWidth: 30, minHeight: 30) }
                    .modifier(SecondaryActionStyle()).accessibilityLabel("连接选项")
            } else {
                Button { Task { await monitor.connectAutomatically() } } label: { Label("自动连接", systemImage: "bolt.horizontal") }
                    .modifier(PrimaryActionStyle()).disabled(monitor.isConnecting).accessibilityIdentifier("codex.autoconnect")
                Button { monitor.chooseDirectory() } label: { Label("选择目录", systemImage: "folder") }
                    .modifier(SecondaryActionStyle()).disabled(monitor.isConnecting).accessibilityIdentifier("codex.connect")
            }
        }
    }

    private var connectionGuide: some View {
        NativeCard {
            SectionHeading(title: "连接本机 Codex", subtitle: "连接后继续使用 Codex，任务与额度上报会自动出现。")
            NumberedGuideRow(number: 1, title: "自动连接本机日志", detail: "打开应用会自动检测 ~/.codex，已保存的目录会优先恢复。找不到时可点「自动连接」重试，或用「选择目录」连接自定义位置。主动断开后，需要再次点击才会恢复自动连接。")
            Divider()
            NumberedGuideRow(number: 2, title: "查看真实的上报数据", detail: "额度按 Codex 上报显示已用比例和重置时间；没有数据时会显示等待，过期后也不会假装已刷新。")
            Divider()
            NumberedGuideRow(number: 3, title: "跟踪最近任务", detail: "查看任务是否活动、完成或停止，以及最近的工具活动。任务没有确定总量，因此不显示虚构的完成百分比。")
        }
    }

    private func quotaCard(_ quota: CodexQuotaSnapshot?, now: Date, wide: Bool) -> some View {
        NativeCard {
            SectionHeading(title: "剩余额度", subtitle: quota == nil ? "等待 Codex 上报" : "本地日志最近上报 · \(quota!.plan?.uppercased() ?? "账户")")
            if let quota {
                AdaptiveColumns(wide: wide) {
                    quotaWindow(quota.primary, fallback: "主要窗口", now: now)
                } trailing: {
                    quotaWindow(quota.secondary, fallback: "第二窗口", now: now)
                }
                Divider()
                Label("上报于 \(quota.reportedAt.formatted(date: .abbreviated, time: .standard))\(quota.isStale(at: now) ? " · 数据较旧" : "")", systemImage: "clock")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("这是最近一次服务上报；Codex 没有新活动时不会主动请求服务器。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("在 Codex 中继续一个任务后自动读取。不支持或没有上报时，保持未知，不用 token 数推算订阅额度。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("codex.quota")
    }

    private func quotaWindow(_ window: CodexQuotaWindow?, fallback: String, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(window.map { duration($0.durationMinutes) + "窗口" } ?? fallback).font(.headline)
            if let window {
                if let remaining = window.remainingPercent(at: now) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(remaining.formatted(.number.precision(.fractionLength(0...1))))%")
                            .font(.largeTitle.weight(.semibold)).monospacedDigit()
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("上报剩余 \(remaining.formatted())%")
                        Text("剩余").font(.subheadline).foregroundStyle(.secondary)
                    }
                    ProgressView(value: remaining, total: 100).tint(BrandPalette.accent)
                        .accessibilityLabel("上报剩余额度").accessibilityValue("\(remaining.formatted())%")
                    Text("已用 \(window.usedPercent.formatted(.number.precision(.fractionLength(0...1))))%")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Label("重置 \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "arrow.clockwise")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("等待新上报").font(.title2.weight(.semibold))
                    Text("上次窗口已过重置时间，当前额度未知。") .font(.caption).foregroundStyle(.secondary)
                }
            } else { Text("暂未提供").font(.title2.weight(.semibold)).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func sessionsCard(_ snapshot: CodexMonitorSnapshot, now: Date) -> some View {
        NativeCard {
            SectionHeading(title: "最近任务", subtitle: "最多 30 个会话 · 检测 \(snapshot.scannedAt.formatted(date: .omitted, time: .standard))")
            ForEach(snapshot.sessions) { session in
                let isSelected = resolvedSelection(in: snapshot)?.id == session.id
                Button {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { selectedID = session.id }
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .top) {
                            Text(session.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            Spacer(minLength: 8)
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "chevron.right")
                                .font(.caption).foregroundStyle(isSelected ? BrandPalette.accent : Color.secondary)
                        }
                        HStack {
                            Label(phaseLabel(session.phase(at: now)), systemImage: phaseSymbol(session.phase(at: now)))
                            Spacer(minLength: 8)
                            if let date = session.lastActivityAt { Text(date, style: .relative).monospacedDigit() }
                        }.font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(12)
                        .background(isSelected ? BrandPalette.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("codex.session.\(session.id)")
            }
        }
    }

    private func resolvedSelection(in snapshot: CodexMonitorSnapshot) -> CodexSessionSnapshot? {
        snapshot.sessions.first(where: { $0.id == selectedID }) ?? snapshot.sessions.first
    }

    private func detailCard(_ session: CodexSessionSnapshot, now: Date) -> some View {
        VStack(spacing: 22) {
            NativeCard {
                SectionHeading(title: session.title)
                Label(phaseLabel(session.phase(at: now)), systemImage: phaseSymbol(session.phase(at: now)))
                    .font(.headline).accessibilityIdentifier("codex.task-status")
                if let project = session.project { Text(project).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                if let model = session.model { LabeledContent("模型", value: model).font(.caption) }
                if let date = session.lastActivityAt { LabeledContent("最近活动", value: date.formatted(date: .abbreviated, time: .standard)).font(.caption) }
                Divider()
                ForEach(session.activities.reversed()) { activity in
                    HStack(alignment: .firstTextBaseline) {
                        Text(activity.timestamp.formatted(date: .omitted, time: .standard)).monospacedDigit().foregroundStyle(.secondary)
                        Text(activityLabel(activity.kind))
                        Spacer(minLength: 0)
                    }.font(.caption)
                }
                if session.phase(at: now) == .quiet {
                    Text("超过 90 秒没有新活动。这不代表失败或完成；Codex 落盘后会继续更新。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            NativeCard {
                SectionHeading(title: "会话 token", subtitle: "累计统计，包含缓存和多轮上下文")
                LabeledContent("累计总量", value: number(session.tokens?.total))
                LabeledContent("输入", value: number(session.tokens?.input))
                LabeledContent("其中缓存命中", value: number(session.tokens?.cachedInput))
                LabeledContent("输出", value: number(session.tokens?.output))
                LabeledContent("其中推理输出", value: number(session.tokens?.reasoningOutput))
                Text("缓存已计入输入，推理已计入输出，不重复相加。这些数值不代表账单或剩余额度。")
                    .font(.caption).foregroundStyle(.secondary)
            }.accessibilityIdentifier("codex.tokens")
        }
    }

    private func number(_ value: Int64?) -> String { value.map { $0.formatted() } ?? "暂未上报" }
    private func duration(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时" }
        return "\(minutes) 分钟"
    }
    private func phaseLabel(_ phase: CodexTaskPhase) -> String {
        switch phase {
        case .running: return "正在活动"
        case .completed: return "本轮已完成"
        case .stopped: return "本轮已停止"
        case .quiet: return "暂无新活动"
        case .unknown: return "等待状态上报"
        }
    }
    private func phaseSymbol(_ phase: CodexTaskPhase) -> String {
        switch phase {
        case .running: return "waveform.path"
        case .completed: return "checkmark.circle"
        case .stopped: return "stop.circle"
        case .quiet, .unknown: return "clock"
        }
    }
    private func activityLabel(_ kind: CodexActivity.Kind) -> String {
        switch kind {
        case .started: return "任务开始"
        case .command: return "执行命令"
        case .fileChange: return "修改文件"
        case .tool: return "调用工具"
        case .message: return "生成回复"
        case .thinking: return "生成中"
        case .compaction: return "整理上下文"
        case .completed: return "本轮完成"
        case .stopped: return "任务已停止"
        }
    }
}
#endif
