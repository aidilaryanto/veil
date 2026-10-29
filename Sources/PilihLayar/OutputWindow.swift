import AppKit
import SwiftUI

/// Penyimpan jendela Output yang dibuat sekali dan dipakai ulang.
/// Jendela inilah yang dibagikan di Zoom/Meet/Teams lewat
/// Share Screen > Window, bukan seluruh layar.
final class OutputWindowStore {
    static let shared = OutputWindowStore()
    var window: NSWindow?
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
            contentRect: NSRect(x: 120, y: 120, width: 340, height: 150),
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

    func openOutputWindow() {
        if let window = OutputWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 960, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PilihLayar Output — bagikan jendela ini"
        window.contentView = NSHostingView(rootView: OutputContentView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        OutputWindowStore.shared.window = window
    }
}
