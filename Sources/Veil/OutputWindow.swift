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

extension VeilModel {
    /// Menyesuaikan jendela Output dan Preview yang sudah ada ke
    /// rasio sumber saat ini (sourceAspectRatio): kunci contentAspectRatio
    /// ke rasio itu, lalu resize konten dengan lebar yang sama (tinggi
    /// = lebar / rasio), dijepit ke layar supaya tidak keluar layar.
    /// Kalau rasio tidak berubah, fungsi ini tidak mengubah apa-apa
    /// yang terlihat — jadi aman dipanggil dari onChange ratio.
    func applySourceRatioToWindows() {
        let ratio = sourceAspectRatio
        guard ratio > 0 else { return }
        for window in [OutputWindowStore.shared.window, PreviewWindowStore.shared.window].compactMap({ $0 }) {
            window.contentAspectRatio = NSSize(width: ratio, height: 1)
            let current = window.contentRect(forFrameRect: window.frame).size
            var width = current.width
            var height = width / ratio
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                let maxHeight = max(180, visible.height - 100)
                let maxWidth = max(320, visible.width - 80)
                if height > maxHeight { height = maxHeight; width = height * ratio }
                if width > maxWidth { width = maxWidth; height = width / ratio }
            }
            width = max(320, width)
            height = max(180, height)
            if abs(height - current.height) > 1 || abs(width - current.width) > 1 {
                window.setContentSize(NSSize(width: width, height: height))
            }
        }
    }

    /// Ukuran awal sebuah jendela baru dari rasio sumber: lebar dasar
    /// yang diminta, tinggi = lebar / rasio, dijepit ke layar.
    private func initialContentSize(baseWidth: CGFloat) -> NSSize {
        let ratio = sourceAspectRatio > 0 ? sourceAspectRatio : (16.0 / 9.0)
        var width = baseWidth
        var height = width / ratio
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let maxHeight = max(180, visible.height - 100)
            let maxWidth = max(320, visible.width - 80)
            if height > maxHeight { height = maxHeight; width = height * ratio }
            if width > maxWidth { width = maxWidth; height = width / ratio }
        }
        return NSSize(width: max(320, width), height: max(180, height))
    }

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
        window.title = "Veil File Control"
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
        // Ukuran Preview mengikuti rasio sumber yang dipilih, bukan
        // 16:9 tetap dan bukan lagi lebar jendela kontrol: lebar dasar
        // 680 (lebar kontrol), tinggi = 680 / rasio sumber, dijepit
        // ke layar. Preview kini bisa di-resize manual, tapi
        // contentAspectRatio mengunci rasionya ke rasio sumber, jadi
        // resize hanya mengubah ukuran, bukan bentuk gambar.
        updateSourceAspectRatio()
        let previewSize = initialContentSize(baseWidth: 680)
        let previewWidth = previewSize.width
        let previewHeight = previewSize.height
        if let window = PreviewWindowStore.shared.window {
            applySourceRatioToWindows()
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
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Preview — preview only, not for sharing"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: sourceAspectRatio, height: 1)
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
            applySourceRatioToWindows()
            window.makeKeyAndOrderFront(nil)
            isOutputVisible = true
            return
        }
        // Ukuran awal Output mengikuti rasio sumber yang dipilih,
        // bukan 16:9 tetap: lebar dasar 960, tinggi = 960 / rasio.
        updateSourceAspectRatio()
        let outputSize = initialContentSize(baseWidth: 960)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: outputSize.width, height: outputSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Output — share this window"
        // Rasio dikunci ke rasio sumber: saat jendela Output
        // di-resize, macOS menjaga rasio kontennya, jadi gambar
        // tidak melar / berubah bentuk dan tidak terpotong.
        window.contentAspectRatio = NSSize(width: sourceAspectRatio, height: 1)
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
