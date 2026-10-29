import AppKit
import SwiftUI

/// Penyimpan jendela Output yang dibuat sekali dan dipakai ulang.
/// Jendela inilah yang dibagikan di Zoom/Meet/Teams lewat
/// Share Screen > Window, bukan seluruh layar.
final class OutputWindowStore {
    static let shared = OutputWindowStore()
    var window: NSWindow?
    var closeObserver: NSObjectProtocol?
    private init() {}
}

final class PreviewWindowStore {
    static let shared = PreviewWindowStore()
    var window: NSWindow?
    var closeObserver: NSObjectProtocol?
    private init() {}
}

final class FileControlWindowStore {
    static let shared = FileControlWindowStore()
    var window: NSWindow?
    private init() {}
}

extension PilihLayarModel {
    func openFileControlWindow() {
        if let window = FileControlWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 480, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "PilihLayar Kontrol File"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: FileControlView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        FileControlWindowStore.shared.window = window
    }

    func closeFileControlWindow() {
        if let window = FileControlWindowStore.shared.window {
            window.close()
            FileControlWindowStore.shared.window = nil
        }
    }

    func togglePreviewWindow() {
        if isPreviewVisible { closePreviewWindow() } else { openPreviewWindow() }
    }

    func openPreviewWindow() {
        let controlWidth = NSApp.keyWindow?.frame.width ?? 680
        let previewWidth = max(controlWidth, 320)
        let previewHeight = previewWidth * 9 / 16
        if let window = PreviewWindowStore.shared.window {
            window.setContentSize(NSSize(width: previewWidth, height: previewHeight))
            window.makeKeyAndOrderFront(nil)
            isPreviewVisible = true
            return
        }
        var frame = NSRect(x: 200, y: 400, width: previewWidth, height: previewHeight)
        if let control = NSApp.keyWindow {
            let controlFrame = control.frame
            frame.origin.x = controlFrame.midX - frame.width / 2
            frame.origin.y = controlFrame.maxY + 12
            if let screen = control.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
                if frame.minX < visible.minX { frame.origin.x = visible.minX }
                if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            }
        }
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PilihLayar Preview — pratinjau, bukan untuk di-share"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.contentView = NSHostingView(rootView: PreviewContentView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        PreviewWindowStore.shared.window = window
        isPreviewVisible = true
        PreviewWindowStore.shared.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isPreviewVisible = false }
        }
    }

    func closePreviewWindow() {
        if let window = PreviewWindowStore.shared.window { window.orderOut(nil) }
        isPreviewVisible = false
    }

    func toggleOutputWindow() {
        if isOutputVisible {
            if let window = OutputWindowStore.shared.window { window.orderOut(nil) }
            isOutputVisible = false
        } else {
            openOutputWindow()
        }
    }

    func openOutputWindow() {
        if let window = OutputWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            isOutputVisible = true
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PilihLayar Output — bagikan jendela ini"
        window.contentAspectRatio = NSSize(width: 16, height: 9)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OutputContentView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        OutputWindowStore.shared.window = window
        isOutputVisible = true
        OutputWindowStore.shared.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isOutputVisible = false }
        }
    }
}
