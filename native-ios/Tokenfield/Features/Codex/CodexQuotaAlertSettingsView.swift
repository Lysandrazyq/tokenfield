#if os(macOS)
import SwiftUI

struct CodexQuotaAlertSettingsView: View {
    @Environment(CodexQuotaAlertStore.self) private var alerts
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var confirmingEnable = false
    @State private var confirmingSource = false

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Form {
                    Section {
                        Toggle("启用额度提醒", isOn: Binding(get: { alerts.isEnabled }, set: { value in
                            if value { confirmingEnable = true }
                            else { Task { await alerts.disable() } }
                        }))
                        .disabled((!alerts.isConnected && !alerts.isEnabled) || alerts.isRequestingPermission)
                        .accessibilityIdentifier("codex.alerts.enabled")
                        Label(alerts.status(at: context.date), systemImage: alerts.isEnabled ? "bell" : "bell.slash")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("codex.alerts.status")
                        if alerts.isRequestingPermission { ProgressView("正在确认通知权限…").controlSize(.small) }
                    } header: { Text("Codex 额度提醒") } footer: {
                        Text("只根据最近有效上报提醒，不用 token 数推算额度。请保持额度终端运行；关闭窗口仍可检测，退出应用后停止检测。")
                    }
                    Section {
                        Toggle("剩余 20% 时预警", isOn: Binding(get: { alerts.includeEarlyWarning }, set: { value in
                            Task { await alerts.setEarlyWarning(value) }
                        })).disabled(!alerts.isEnabled || alerts.isRequestingPermission)
                            .accessibilityIdentifier("codex.alerts.early")
                        LabeledContent("紧急提醒", value: "剩余 10%")
                    } header: { Text("提醒时机") } footer: {
                        Text("每个额度窗口、每个周期最多提醒一次同等级。首次已低于 10% 时只提醒紧急等级；两个窗口同时低位会合并。")
                    }
                    Section {
                        Text(alerts.isConnected ? (alerts.needsSourceConfirmation ? "当前日志来源需要重新确认。" : "使用当前连接的本机 Codex 日志。") : "请先在看板连接 Codex。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button(alerts.needsSourceConfirmation ? "确认当前日志来源" : "切换账号后重新确认") { confirmingSource = true }
                            .disabled(!alerts.isEnabled || !alerts.isConnected || alerts.isRequestingPermission)
                            .accessibilityIdentifier("codex.alerts.reconfirm")
                    } header: { Text("日志来源") } footer: {
                        Text("日志不提供可靠的账号标识。更换目录或切换 Codex 账号后，请重新确认；之后会等待新的额度上报，不沿用旧数据。不会读取登录凭据。")
                    }
                    if alerts.isEnabled {
                        Section("通知状态") {
                            if alerts.permission == .denied || alerts.permission == .unavailable {
                                Button("打开系统通知设置") { PlatformSettings.openNotifications(using: openURL) }
                                    .accessibilityIdentifier("codex.alerts.system-settings")
                            } else if alerts.permission == .notDetermined {
                                Button("允许系统通知") { Task { await alerts.enableConfirmedSource() } }
                                    .disabled(!alerts.isConnected || alerts.needsSourceConfirmation || alerts.isRequestingPermission)
                            }
                            if let date = alerts.lastQueuedAt {
                                LabeledContent("最近提醒请求", value: date.formatted(date: .abbreviated, time: .shortened))
                            } else { Text("尚未提交提醒请求").foregroundStyle(.secondary) }
                            Text("通知交由系统显示，可能受专注模式和通知设置影响。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let issue = alerts.lastIssue {
                        Section {
                            Label(issue, systemImage: "exclamationmark.circle").font(.subheadline)
                                .accessibilityIdentifier("codex.alerts.error")
                            Button("重试") { Task { await alerts.retry() } }
                                .accessibilityIdentifier("codex.alerts.retry")
                        }
                    }
                    if let notice = alerts.interruptionNotice {
                        Section {
                            Text(notice).font(.subheadline).foregroundStyle(.secondary)
                            Button("知道了") { alerts.dismissInterruptionNotice() }
                        }
                    }
                }.nativeGroupedForm()
            }
            .navigationTitle("额度提醒")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.tint(BrandPalette.control).accessibilityIdentifier("codex.alerts.done")
                }
            }
        }
        .nativeEditorSize(height: 680)
        .task { await alerts.refresh() }
        .confirmationDialog("确认额度提醒来源", isPresented: $confirmingEnable, titleVisibility: .visible) {
            Button("启用并确认通知权限") { Task { await alerts.enableConfirmedSource() } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("提醒跟随当前连接的本机日志，不区分账号。首次开启会检查最近有效上报；切换账号后请重新确认来源。")
        }
        .confirmationDialog("重新确认日志来源？", isPresented: $confirmingSource, titleVisibility: .visible) {
            Button("确认并等待新上报") { Task { await alerts.reconfirmSource() } }
            Button("取消", role: .cancel) { }
        } message: { Text("将停止旧范围的待发提醒，并等待 Codex 新的额度上报。旧账号的上报不会立即触发新范围提醒。") }
    }
}
#endif
