#if os(macOS)
import AppKit
import SwiftUI
import os

/// Keep the native window limit independent of the responsive content's fitting size.
struct MainWindowConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowConfigurationView { WindowConfigurationView() }
    func updateNSView(_ nsView: WindowConfigurationView, context: Context) { }

    final class WindowConfigurationView: NSView {
        private var observer: NSObjectProtocol?
        private var reported = false
        private let logger = Logger(subsystem: "space.lysandra.quotakeeper", category: "Startup")

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            guard let window else { return }
            let minimum = NSSize(width: 840, height: 620)
            if window.contentMinSize != minimum { window.contentMinSize = minimum }
            reportVisibleWindow()
            if !reported {
                observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.reportVisibleWindow() }
                }
            }
        }

        private func reportVisibleWindow() {
            guard !reported, window?.isVisible == true else { return }
            reported = true
            let launched = NSRunningApplication.current.launchDate ?? Date()
            let milliseconds = Int(max(0, Date().timeIntervalSince(launched) * 1000))
            logger.notice("main-window-visible elapsed-ms=\(milliseconds, privacy: .public)")
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
        }

        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
#endif
