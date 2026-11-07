#if os(macOS)
import AppKit
import TokenfieldCore

/// A native status item, created after the main window rather than on the launch path.
@MainActor
final class CodexStatusBarController: NSObject, NSMenuDelegate {
    private let navigation: CodexNotificationNavigation
    private var item: NSStatusItem?
    private var snapshot: CodexMonitorSnapshot?
    private var connected = false
    private var startup: Task<Void, Never>?
    private var animation: Timer?
    private var menuIsOpen = false
    private var lastSummary: CodexStatusSummary?
    private var accessibilityObserver: NSObjectProtocol?
    private var terminationObserver: NSObjectProtocol?

    init(navigation: CodexNotificationNavigation) { self.navigation = navigation }

    func startAfterWindow() {
        guard item == nil, startup == nil else { return }
        startup = Task { @MainActor [weak self] in
            for _ in 0..<10 {
                if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain && !$0.isSheet }) { break }
                do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
            }
            guard !Task.isCancelled else { return }
            self?.install()
        }
    }

    func update(snapshot: CodexMonitorSnapshot?, connected: Bool) {
        self.snapshot = snapshot
        self.connected = connected
        refresh()
    }

    private func install() {
        guard item == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.setAccessibilityIdentifier("codex.statusitem")
        self.item = item
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.refresh(force: true) } }
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.stop() } }
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        guard let button = item?.button else { return }
        let summary = CodexStatusSummary.make(snapshot: snapshot, connected: connected, now: Date())
        let animate = summary.phase == .running && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !menuIsOpen
        if animate && animation == nil {
            let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refresh(force: true) }
            }
            timer.tolerance = 0.03
            RunLoop.main.add(timer, forMode: .common)
            animation = timer
        } else if !animate {
            animation?.invalidate()
            animation = nil
        }
        guard force || lastSummary != summary else { return }
        lastSummary = summary
        button.image = Self.image(summary: summary, animate: animate,
                                  highContrast: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
        let quota = summary.remainingPercent.map { "剩余 \(Self.percent($0))%" } ?? "额度等待新上报"
        let label = "Tokenfield，\(quota)，\(Self.taskText(summary))"
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuIsOpen = true
        refresh(force: true)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let now = Date()
        let summary = CodexStatusSummary.make(snapshot: snapshot, connected: connected, now: now)
        addInfo("Tokenfield · Codex", to: menu)
        if let remaining = summary.remainingPercent {
            addInfo("剩余 \(Self.percent(remaining))% · 环显示较低额度", to: menu)
            if let quota = snapshot?.quota {
                for window in [quota.primary, quota.secondary].compactMap({ $0 }) where
                    window.usedPercent.isFinite && (0...100).contains(window.usedPercent)
                    && (1...525_600).contains(window.durationMinutes) && window.resetsAt > now {
                    addInfo("\(Self.duration(window.durationMinutes)) · 剩余 \(Self.percent(100 - window.usedPercent))%", to: menu)
                }
                addInfo("上报于 \(quota.reportedAt.formatted(date: .omitted, time: .standard))", to: menu)
            }
        } else {
            addInfo(connected ? "额度等待新上报" : "本机 Codex 尚未连接", to: menu)
        }
        addInfo(Self.taskText(summary), to: menu)
        menu.addItem(.separator())
        addAction("打开 Codex 看板", selector: #selector(openDashboard), to: menu)
        addAction("额度提醒…", selector: #selector(openAlerts), to: menu)
        menu.addItem(.separator())
        addAction("退出额度终端", selector: #selector(quit), to: menu)
    }

    func menuDidClose(_ menu: NSMenu) { menuIsOpen = false; refresh(force: true) }

    private func addInfo(_ text: String, to menu: NSMenu) {
        let row = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        row.isEnabled = false
        menu.addItem(row)
    }
    private func addAction(_ title: String, selector: Selector, to menu: NSMenu) {
        let row = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        row.target = self
        menu.addItem(row)
    }
    @objc private func openDashboard() { navigation.openQuota() }
    @objc private func openAlerts() { navigation.openAlerts() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func percent(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    private static func duration(_ minutes: Int) -> String {
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天窗口" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时窗口" }
        return "\(minutes) 分钟窗口"
    }
    private static func taskText(_ summary: CodexStatusSummary) -> String {
        switch summary.phase {
        case .running: return summary.activeTasks > 1 ? "\(summary.activeTasks) 个任务活动中" : "任务活动中"
        case .completed: return "最近任务已完成"
        case .stopped: return "最近任务已停止"
        case .quiet: return "任务暂无新活动"
        case .unknown: return "等待任务活动"
        }
    }

    static func image(summary: CodexStatusSummary, animate: Bool, highContrast: Bool) -> NSImage {
        // Rasterize at 2x, then let AppKit tint this template for the current menu bar.
        let context = CGContext(data: nil, width: 44, height: 44, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.scaleBy(x: 2, y: 2)
        // Keep the visible glyph near 15 pt, like neighboring menu bar symbols.
        // The 22 pt canvas preserves the native click target and spacing.
        context.translateBy(x: 11, y: 11)
        context.scaleBy(x: 0.8, y: 0.8)
        context.translateBy(x: -11, y: -11)
        context.setLineCap(.round)
        context.setLineWidth(1.8)
        let center = CGPoint(x: 11, y: 11)
        let ring = CGRect(x: 2.3, y: 2.3, width: 17.4, height: 17.4)
        context.setStrokeColor(CGColor(gray: 0, alpha: highContrast ? 0.55 : 0.25))
        if summary.remainingPercent == nil { context.setLineDash(phase: 0, lengths: [1.8, 2.2]) }
        context.strokeEllipse(in: ring)
        context.setLineDash(phase: 0, lengths: [])
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        if let remaining = summary.remainingPercent, remaining > 0 {
            context.addArc(center: center, radius: 8.7, startAngle: .pi / 2,
                           endAngle: .pi / 2 - 2 * .pi * remaining / 100, clockwise: true)
            context.strokePath()
        }
        context.setLineWidth(1.6)
        switch summary.phase {
        case .running:
            if animate {
                let angle = -ProcessInfo.processInfo.systemUptime * 4.5
                context.addArc(center: center, radius: 3.5, startAngle: angle, endAngle: angle + .pi * 1.25, clockwise: false)
                context.strokePath()
            } else {
                context.setFillColor(CGColor(gray: 0, alpha: 1))
                context.fillEllipse(in: CGRect(x: 8.7, y: 8.7, width: 4.6, height: 4.6))
            }
        case .completed:
            context.move(to: CGPoint(x: 7.7, y: 11)); context.addLine(to: CGPoint(x: 10, y: 8.7))
            context.addLine(to: CGPoint(x: 14.4, y: 13.2)); context.strokePath()
        case .stopped:
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 8.6, y: 8.6, width: 4.8, height: 4.8))
        case .quiet, .unknown:
            context.strokeEllipse(in: CGRect(x: 9.2, y: 9.2, width: 3.6, height: 3.6))
        }
        let image = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 22, height: 22))
        image.isTemplate = true
        return image
    }

    private func stop() {
        startup?.cancel()
        animation?.invalidate(); animation = nil
        if let item { NSStatusBar.system.removeStatusItem(item); self.item = nil }
    }
    deinit {
        startup?.cancel(); animation?.invalidate()
        if let accessibilityObserver { NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver) }
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }
}
#endif
