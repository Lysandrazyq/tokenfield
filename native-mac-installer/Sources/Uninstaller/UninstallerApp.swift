import AppKit
import SwiftUI
import UniformTypeIdentifiers
#if !INSTALLER_STANDALONE
import InstallerCore
#endif

@MainActor
final class UninstallerModel: ObservableObject {
    @Published var apps: [OldApplication] = []
    @Published var selected: Set<String> = []
    @Published var isBusy = false
    @Published var message: String?
    @Published var error: String?
    let latestVersion: String
    private let finder: OldAppFinder
    private var additionalApps: [URL] = []

    init() {
        let info = Bundle.main.infoDictionary ?? [:]
        latestVersion = info["TokenfieldLatestVersion"] as? String ?? "未知"
        finder = OldAppFinder(
            latestVersion: latestVersion,
            latestBuild: info["TokenfieldLatestBuild"] as? String ?? "",
            protectedApps: [Bundle.main.bundleURL, Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("额度终端.app")]
        )
    }

    var selectedApps: [OldApplication] { apps.filter { selected.contains($0.id) } }

    func scan(clearMessage: Bool = true) {
        let fm = FileManager.default
        let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
        let legacy = [
            fm.temporaryDirectory.appendingPathComponent("TokenfieldLocal/TokenfieldMac.app"),
            URL(fileURLWithPath: "/private/tmp/TokenfieldLocal/TokenfieldMac.app")
        ]
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == OldAppFinder.bundleID }.compactMap(\.bundleURL)
        apps = finder.scan(roots: roots, additionalApps: additionalApps + running + legacy)
        selected.formIntersection(Set(apps.map(\.id)))
        if clearMessage { message = nil }
    }

    func chooseOtherApp() {
        let panel = NSOpenPanel()
        panel.title = "选择其他位置的旧版额度终端"
        panel.prompt = "检查应用"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.applicationBundle]
        panel.treatsFilePackagesAsDirectories = false
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first(where: { $0.isVisible && $0.canBecomeKey }) else {
            error = "请重新打开卸载窗口后再选择应用。"
            return
        }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            var failures: [String] = []
            for url in panel.urls {
                do {
                    let app = try self.finder.inspect(url)
                    self.additionalApps.append(app.url)
                    self.selected.insert(app.id)
                } catch { failures.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
            }
            self.scan()
            if !failures.isEmpty { self.error = failures.joined(separator: "\n") }
        }
    }

    func removeSelected() async {
        let targets = selectedApps
        guard !targets.isEmpty, !isBusy else { return }
        isBusy = true
        message = "正在处理所选旧版本…"
        var failures: [String] = []
        var moved = 0
        let uninstaller = OldAppUninstaller(finder: finder)
        for app in targets {
            do {
                try uninstaller.validate(app)
                try await quitIfRunning(app)
                _ = try uninstaller.trash(app)
                selected.remove(app.id)
                moved += 1
            } catch { failures.append("\(app.url.path)\n\(error.localizedDescription)") }
        }
        scan(clearMessage: false)
        message = moved > 0 ? "已将 \(moved) 个旧版本移到废纸篓。账号、月报和备份已保留。" : "没有移走任何应用。"
        if !failures.isEmpty { error = failures.joined(separator: "\n\n") }
        isBusy = false
    }

    private func quitIfRunning(_ app: OldApplication) async throws {
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.bundleIdentifier == OldAppFinder.bundleID &&
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == app.url
        }
        for process in running where !process.isTerminated {
            guard process.terminate() else {
                throw NSError(domain: "TokenfieldUninstaller", code: 1, userInfo: [NSLocalizedDescriptionKey: "请先正常退出这个旧版本，再重新扫描。"])
            }
        }
        for _ in 0..<50 {
            if running.allSatisfy(\.isTerminated) { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw NSError(domain: "TokenfieldUninstaller", code: 2, userInfo: [NSLocalizedDescriptionKey: "旧版本尚未退出。请处理它的未保存提示并退出后，再重新扫描；没有强制关闭应用。"])
    }
}

struct UninstallerView: View {
    @StateObject private var model = UninstallerModel()
    @State private var confirming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                    .resizable().scaledToFit()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 5) {
                    Text("清理旧版本").font(.system(size: 26, weight: .semibold))
                    Text("额度终端 · 安装包 \(model.latestVersion)").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "externaldrive.badge.checkmark").font(.title3)
                VStack(alignment: .leading, spacing: 5) {
                    Text("保留你的使用记录").font(.headline)
                    Text("只将选中的旧应用移到废纸篓，可随时恢复。账号、用量、月报、备份与设置都会保留。")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))

            HStack {
                Text("可清理的旧应用").font(.headline)
                Spacer()
                Button("重新扫描", systemImage: "arrow.clockwise") { model.scan() }
                    .disabled(model.isBusy)
            }
            if model.apps.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle").font(.system(size: 34, weight: .light))
                    Text("没有发现旧版本").font(.headline)
                    Text("已检查应用程序文件夹和本地运行副本。\n其他位置的旧应用可以手动选择。")
                        .multilineTextAlignment(.center).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.apps) { app in
                            HStack(alignment: .top, spacing: 12) {
                                Toggle("选择 \(app.url.lastPathComponent) \(app.version)", isOn: Binding(
                                    get: { model.selected.contains(app.id) },
                                    set: { if $0 { model.selected.insert(app.id) } else { model.selected.remove(app.id) } }
                                )).labelsHidden().toggleStyle(.checkbox)
                                    .accessibilityIdentifier("uninstaller.select.\(app.url.lastPathComponent)")
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(app.url.deletingPathExtension().lastPathComponent).font(.headline)
                                        Spacer()
                                        Text("\(app.version) (\(app.build))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                    }
                                    Text(app.url.path).font(.caption).foregroundStyle(.secondary)
                                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .disabled(model.isBusy)
            }
            if let message = model.message {
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("uninstaller.result")
            }
            Divider()
            HStack {
                Button("选择其他位置…") { model.chooseOtherApp() }.disabled(model.isBusy)
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button(model.selected.isEmpty ? "移到废纸篓" : "移走 \(model.selectedApps.count) 个旧版本") { confirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedApps.isEmpty || model.isBusy)
                    .accessibilityIdentifier("uninstaller.remove")
            }
        }
        .padding(28)
        .frame(minWidth: 620, minHeight: 570)
        .tint(Color.primary)
        .task { model.scan() }
        .alert("移走已选的 \(model.selectedApps.count) 个旧版本？", isPresented: $confirming) {
            Button("取消", role: .cancel) {}
            Button("移到废纸篓", role: .destructive) { Task { await model.removeSelected() } }
        } message: {
            Text(model.selectedApps.map { "\($0.url.path)\n版本 \($0.version) (\($0.build))" }.joined(separator: "\n\n") + "\n\n正在运行的旧版本会先正常退出。使用记录和备份将保留。")
        }
        .alert("部分操作未完成", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("知道了") { model.error = nil }
        } message: { Text(model.error ?? "") }
    }
}

final class UninstallerDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct TokenfieldUninstallerApp: App {
    @NSApplicationDelegateAdaptor(UninstallerDelegate.self) private var delegate
    var body: some Scene {
        Window("卸载旧版本", id: "uninstaller") { UninstallerView() }
            .defaultSize(width: 700, height: 640)
            .windowResizability(.contentMinSize)
    }
}
