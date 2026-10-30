import AppKit
import SwiftUI
final class OutputWindowStore {
    static let shared = OutputWindowStore()
    var window: NSWindow?
    var closeObserver: NSObjectProtocol?
    var resizeObserver: NSObjectProtocol?
    private init() {}
}
final class PreviewWindowStore {
    static let shared = PreviewWindowStore()
    var window: NSWindow?
    var closeObserver: NSObjectProtocol?
    var resizeObserver: NSObjectProtocol?
    var controlObservers: [NSObjectProtocol] = []
    private init() {}
}
final class FileControlWindowStore {
    static let shared = FileControlWindowStore()
    var window: NSWindow?
    var outputObservers: [NSObjectProtocol] = []
    private init() {}
}
extension VeilModel {
    private func configureFramelessSecondaryWindow(_ window: NSWindow) {
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
    }
    func screenFitContentSize(for screen: NSScreen?) -> NSSize {
        let ratio = sourceAspectRatio > 0 ? sourceAspectRatio : (16.0 / 9.0)
        var width: CGFloat = 960
        var height = width / ratio
        if let screen = screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            let maxHeight = max(180, visible.height - 100)
            let maxWidth = max(320, visible.width - 80)
            width = maxWidth
            height = width / ratio
            if height > maxHeight { height = maxHeight; width = height * ratio }
        }
        return NSSize(width: max(320, width), height: max(180, height))
    }
    func previewDockedFrame() -> CGRect? {
        guard let controlFrame = lastControlFrame,
              let screen = NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let ratio = sourceAspectRatio > 0 ? sourceAspectRatio : (16.0 / 9.0)
        var width = controlFrame.width
        var height = width / ratio
        let aboveTop = controlFrame.maxY + 6
        let availableHeight = max(180, visible.maxY - aboveTop)
        if height > availableHeight {
            height = availableHeight
            width = height * ratio
        }
        var frame = NSRect(x: controlFrame.minX, y: aboveTop, width: width, height: height)
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        return frame
    }
    func startFollowingControl(_ control: NSWindow) {
        for observer in PreviewWindowStore.shared.controlObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        PreviewWindowStore.shared.controlObservers.removeAll()
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = NotificationCenter.default.addObserver(
                forName: name, object: control, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.lastControlFrame = control.frame
                    if self?.isPreviewVisible == true {
                        self?.updatePreviewFrameFromSource()
                    }
                }
            }
            PreviewWindowStore.shared.controlObservers.append(observer)
        }
    }
    func previewFrameAvoidingControl(_ frame: CGRect) -> CGRect {
        guard let controlFrame = lastControlFrame,
              let screen = NSScreen.main else { return frame }
        let visible = screen.visibleFrame
        var result = frame
        guard result.intersects(controlFrame.insetBy(dx: -6, dy: -6)) else { return result }
        let aboveTop = controlFrame.maxY + 6
        if aboveTop + result.height <= visible.maxY {
            result.origin.y = aboveTop
        } else {
            let availableHeight = max(180, visible.maxY - aboveTop)
            let ratio = result.width > 0 && result.height > 0 ? result.width / result.height : sourceAspectRatio
            result.size.height = availableHeight
            result.size.width = availableHeight * ratio
            result.origin.y = aboveTop
        }
        result.origin.x = max(visible.minX, min(result.origin.x, visible.maxX - result.width))
        result.origin.y = max(visible.minY, min(result.origin.y, visible.maxY - result.height))
        return result
    }
    func previewSourceFrame() -> CGRect? {
        if mode == .allow, selectedWindowIDs.count == 1,
           let onlyID = selectedWindowIDs.first,
           let frame = capturedWindows.first(where: { $0.windowID == onlyID })?.frame {
            return frame
        }
        if mode == .allow, framing == .dynamic, !selectedWindowIDs.isEmpty {
            let frames = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }.map { $0.frame }
            return frames.reduce(nil as CGRect?, { $0 == nil ? $1 : $0!.union($1) })
        }
        return nil
    }
    func applySourceRatioToWindows() {
        let ratio = sourceAspectRatio
        guard ratio > 0 else { return }
        for window in [OutputWindowStore.shared.window, PreviewWindowStore.shared.window].compactMap({ $0 }) {
            window.contentAspectRatio = NSSize(width: ratio, height: 1)
            if window == PreviewWindowStore.shared.window, let docked = previewDockedFrame() {
                if abs(docked.width - window.frame.width) > 1 || abs(docked.height - window.frame.height) > 1
                    || abs(docked.origin.x - window.frame.origin.x) > 1 || abs(docked.origin.y - window.frame.origin.y) > 1 {
                    window.setFrame(docked, display: true)
                }
                continue
            }
            let current = window.contentRect(forFrameRect: window.frame).size
            var width = current.width
            var height = width / ratio
            if let screen = window.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                let maxHeight = max(180, visible.height - 100)
                var maxWidth = max(320, visible.width - 80)
                if window == PreviewWindowStore.shared.window,
                   let controlWidth = lastControlFrame?.width {
                    maxWidth = min(maxWidth, max(320, controlWidth))
                }
                if height > maxHeight { height = maxHeight; width = height * ratio }
                if width > maxWidth { width = maxWidth; height = width / ratio }
            }
            width = max(320, width)
            height = max(180, height)
            if abs(height - current.height) > 1 || abs(width - current.width) > 1 {
                window.setContentSize(NSSize(width: width, height: height))
            }
        }
        dockFileControlToOutput()
    }
    private func initialContentSize(baseWidth: CGFloat) -> NSSize {
        screenFitContentSize(for: NSScreen.main)
    }
    private func previewInitialContentSize() -> NSSize {
        let ratio = sourceAspectRatio > 0 ? sourceAspectRatio : (16.0 / 9.0)
        var width: CGFloat = 680
        if let controlWidth = lastControlFrame?.width {
            width = controlWidth
        }
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
    func dockFileControlToOutput() {
        guard let flyer = FileControlWindowStore.shared.window,
              let output = OutputWindowStore.shared.window,
              output.isVisible, flyer.isVisible else { return }
        let gap: CGFloat = 8
        let size = flyer.frame.size
        var x = output.frame.maxX + gap
        var y = output.frame.maxY - size.height
        if let screen = output.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if x + size.width > visible.maxX {
                x = output.frame.minX - gap - size.width
            }
            if x < visible.minX { x = visible.minX }
            if x + size.width > visible.maxX { x = visible.maxX - size.width }
            if y < visible.minY { y = visible.minY }
            if y + size.height > visible.maxY { y = visible.maxY - size.height }
        }
        flyer.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func startFollowingOutput() {
        stopFollowingOutput()
        guard let output = OutputWindowStore.shared.window else { return }
        let center = NotificationCenter.default
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            let observer = center.addObserver(
                forName: name, object: output, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.dockFileControlToOutput() }
            }
            FileControlWindowStore.shared.outputObservers.append(observer)
        }
    }
    func stopFollowingOutput() {
        let center = NotificationCenter.default
        for observer in FileControlWindowStore.shared.outputObservers {
            center.removeObserver(observer)
        }
        FileControlWindowStore.shared.outputObservers.removeAll()
    }
    func openFileControlWindow() {
        guard activeFile != nil else {
            closeFileControlWindow()
            return
        }
        if let window = FileControlWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            dockFileControlToOutput()
            startFollowingOutput()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 140, height: 290),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil File Control"
        window.level = .floating
        window.isReleasedWhenClosed = false
        configureFramelessSecondaryWindow(window)
        window.contentView = NSHostingView(rootView: FileControlView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        FileControlWindowStore.shared.window = window
        dockFileControlToOutput()
        startFollowingOutput()
    }
    func closeFileControlWindow() {
        stopFollowingOutput()
        if let window = FileControlWindowStore.shared.window {
            window.close()
            FileControlWindowStore.shared.window = nil
        }
    }
    func togglePreviewWindow() {
        if isPreviewVisible { closePreviewWindow() } else { openPreviewWindow() }
    }
    func openPreviewWindow() {
        if let control = NSApp.keyWindow, control != PreviewWindowStore.shared.window {
            lastControlFrame = control.frame
            startFollowingControl(control)
        }
        updateSourceAspectRatio()
        if !isSharing {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
        let previewSize = previewInitialContentSize()
        let previewWidth = previewSize.width
        let previewHeight = previewSize.height
        if let window = PreviewWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            isPreviewVisible = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces]
            window.styleMask.remove(.resizable)
            window.styleMask.remove(.miniaturizable)
            window.isMovableByWindowBackground = false
            previewNeedsReposition = true
            updatePreviewFrameFromSource()
            if !selectedWindowIDs.isEmpty {
                refreshSources()
            }
            window.orderFrontRegardless()
            return
        }
        var frame = NSRect(x: 200, y: 400, width: previewWidth, height: previewHeight)
        if let control = NSApp.keyWindow {
            let controlFrame = control.frame
            frame.origin.x = controlFrame.midX - frame.width / 2
            frame.origin.y = controlFrame.maxY + 6
            if let screen = control.screen ?? NSScreen.main {
                let visible = screen.visibleFrame
                if frame.maxY > visible.maxY { frame.origin.y = visible.maxY - frame.height }
                if frame.minX < visible.minX { frame.origin.x = visible.minX }
                if frame.maxX > visible.maxX { frame.origin.x = visible.maxX - frame.width }
            }
        }
        if let docked = previewDockedFrame() {
            frame = docked
        }
        frame = previewFrameAvoidingControl(frame)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Preview — preview only, not for sharing"
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.isReleasedWhenClosed = false
        window.contentAspectRatio = NSSize(width: sourceAspectRatio, height: 1)
        configureFramelessSecondaryWindow(window)
        window.isMovableByWindowBackground = false
        window.contentView = NSHostingView(rootView: PreviewWindowRootView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        PreviewWindowStore.shared.window = window
        isPreviewVisible = true
        if !selectedWindowIDs.isEmpty {
            previewNeedsReposition = true
            refreshSources()
        } else {
            previewNeedsReposition = false
        }
        window.orderFrontRegardless()
        PreviewWindowStore.shared.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPreviewVisible = false
                self?.previewNeedsReposition = true
            }
        }
        if PreviewWindowStore.shared.resizeObserver == nil {
            PreviewWindowStore.shared.resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applySourceRatioToWindows() }
            }
        }
    }
    func updatePreviewFrameFromSource() {
        guard let window = PreviewWindowStore.shared.window, isPreviewVisible,
              let docked = previewDockedFrame() else { return }
        window.contentAspectRatio = NSSize(width: sourceAspectRatio, height: 1)
        var frame = docked
        frame = previewFrameAvoidingControl(frame)
        let current = window.frame
        if abs(frame.width - current.width) > 1 || abs(frame.height - current.height) > 1
            || abs(frame.origin.x - current.origin.x) > 1 || abs(frame.origin.y - current.origin.y) > 1 {
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
        }
    }
    func closePreviewWindow() {
        previewNeedsReposition = true
        if let window = PreviewWindowStore.shared.window { window.orderOut(nil) }
        isPreviewVisible = false
    }
    func toggleOutputWindow() {
        if isOutputVisible {
            closeOutputWindow()
        } else {
            openOutputWindow()
        }
    }
    func closeOutputWindow() {
        closeFileControlWindow()
        stopFollowingOutput()
        if let window = OutputWindowStore.shared.window {
            if let observer = OutputWindowStore.shared.closeObserver {
                NotificationCenter.default.removeObserver(observer)
                OutputWindowStore.shared.closeObserver = nil
            }
            if let observer = OutputWindowStore.shared.resizeObserver {
                NotificationCenter.default.removeObserver(observer)
                OutputWindowStore.shared.resizeObserver = nil
            }
            window.contentView = nil
            window.close()
            OutputWindowStore.shared.window = nil
        }
        isOutputVisible = false
    }
    func reopenFileControlIfNeeded() {
        if isSharing, activeFile != nil, FileControlWindowStore.shared.window == nil {
            openFileControlWindow()
        }
    }
    func openOutputWindow() {
        if let window = OutputWindowStore.shared.window {
            applySourceRatioToWindows()
            window.makeKeyAndOrderFront(nil)
            isOutputVisible = true
            dockFileControlToOutput()
            startFollowingOutput()
            reopenFileControlIfNeeded()
            return
        }
        updateSourceAspectRatio()
        let outputSize = initialContentSize(baseWidth: 960)
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: outputSize.width, height: outputSize.height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Output — share this window"
        window.contentAspectRatio = NSSize(width: sourceAspectRatio, height: 1)
        configureFramelessSecondaryWindow(window)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OutputWindowRootView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        OutputWindowStore.shared.window = window
        isOutputVisible = true
        dockFileControlToOutput()
        startFollowingOutput()
        reopenFileControlIfNeeded()
        OutputWindowStore.shared.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isOutputVisible = false }
        }
        if OutputWindowStore.shared.resizeObserver == nil {
            OutputWindowStore.shared.resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.applySourceRatioToWindows() }
            }
        }
    }
}
