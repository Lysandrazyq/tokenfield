import SwiftUI

struct CloudSyncSettingsSection: View {
    let service: CloudSyncService
    let store: AppStore
    @State private var confirmingSwitch = false

    var body: some View {
        Section {
            HStack(spacing: 10) {
                Image(systemName: service.lastSynced == nil ? "icloud" : "checkmark.icloud")
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 5) {
                    Text(service.headline).font(.body.weight(.medium))
                    Text(service.detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if service.isSyncing { ProgressView().controlSize(.small) }
            }
            .accessibilityIdentifier("settings.icloud-status")
            if let date = service.lastSynced {
                LabeledContent("上次同步") { Text(date, format: .dateTime.hour().minute()).foregroundStyle(.secondary) }
            }
            if service.requiresAccountSwitch {
                Button("保留备份并切换 iCloud 账号") { confirmingSwitch = true }
                    .disabled(service.isSyncing)
            } else if service.canRetry {
                Button("立即同步") { Task { await service.syncNow(store: store) } }
                    .disabled(service.isSyncing)
                    .accessibilityIdentifier("settings.icloud-sync")
            }
            if let backup = service.archivedBackupURL {
                ShareLink(item: backup) { Label("导出切换前备份", systemImage: "square.and.arrow.up") }
            }
        } header: { Text("iCloud 同步") } footer: {
            Text("可用时在同一 Apple 账号的设备间同步，离线时先存本机。")
        }
        .confirmationDialog("切换到当前 iCloud 账号？", isPresented: $confirmingSwitch, titleVisibility: .visible) {
            Button("保留备份并切换", role: .destructive) { Task { await service.switchToCurrentAccount(store: store) } }
            Button("取消", role: .cancel) { }
        } message: {
            Text("会先保存原账号的本机备份，再加载当前 iCloud 账号的数据。原账号的数据不会自动上传到新账号。")
        }
    }
}
