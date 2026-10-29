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

extension PilihLayarModel {
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
