import AppKit
import AVFoundation
import CoreVideo
import Metal
import QuartzCore
import SwiftUI
final class CaptureAreaWindowStore {
    static let shared = CaptureAreaWindowStore()
    var window: NSWindow?
    var closeObserver: NSObjectProtocol?
    var resizeObserver: NSObjectProtocol?
    private init() {}
}
final class FileControlWindowStore {
    static let shared = FileControlWindowStore()
    var window: NSWindow?
    private init() {}
}
final class TimerControlWindowStore {
    static let shared = TimerControlWindowStore()
    var window: NSWindow?
    private init() {}
}
final class AnnotationControlWindowStore {
    static let shared = AnnotationControlWindowStore()
    var window: NSWindow?
    private init() {}
}
final class PanelWindowStore {
    static let shared = PanelWindowStore()
    var window: NSWindow?
    var resizeObserver: NSObjectProtocol?
    var anchoredBottom: CGFloat?
    private init() {}
}
extension VeilModel {
    func capturedRatio() -> CGFloat {
        if canvasMode == .fullDisplay, let size = fullDisplayFrameSize(), size.height > 0 {
            return size.width / size.height
        }
        if sourceAspectRatio > 0 { return sourceAspectRatio }
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
           display.height > 0 {
            return CGFloat(display.width) / CGFloat(display.height)
        }
        if let screen = NSScreen.main, screen.frame.height > 0 {
            return screen.frame.width / screen.frame.height
        }
        return 1
    }
    func previewRatio() -> CGFloat {
        if canvasAspectRatio() > 0 {
            return canvasAspectRatio()
        }
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
           display.height > 0 {
            return CGFloat(display.width) / CGFloat(display.height)
        }
        if let screen = NSScreen.main, screen.frame.height > 0 {
            return screen.frame.width / screen.frame.height
        }
        if let contentSize = sourceContentSize(), contentSize.height > 0 {
            return contentSize.width / contentSize.height
        }
        return capturedRatio()
    }
    func sourceWindowSize() -> CGSize? {
        guard filePreviewImage == nil, let frame = previewSourceFrame(),
              frame.width > 0, frame.height > 0 else { return nil }
        return frame.size
    }
    func fullscreenSourceScreen() -> NSScreen? {
        guard filePreviewImage == nil, mode == .allow, selectedWindowIDs.count == 1,
              let onlyID = selectedWindowIDs.first,
              let frame = capturedWindows.first(where: { $0.windowID == onlyID })?.frame,
              frame.width > 0, frame.height > 0 else { return nil }
        for screen in NSScreen.screens where screen.frame.intersects(frame) {
            let visible = screen.visibleFrame
            if frame.width >= visible.width - 1, frame.height >= visible.height - 1 {
                return screen
            }
        }
        return nil
    }
    func fullscreenVisibleSize() -> CGSize? {
        fullscreenSourceScreen()?.visibleFrame.size
    }
    var isFullscreenCanvas: Bool {
        fullscreenVisibleSize() != nil
    }
    func nativeFullscreenScreen() -> NSScreen? {
        guard filePreviewImage == nil, mode == .allow, selectedWindowIDs.count == 1,
              framing == .full, canvasMode == .isolated,
              let onlyID = selectedWindowIDs.first else { return nil }
        let frame: CGRect?
        if let live = livePositionedFrame, livePositionedWindowID == onlyID {
            frame = live
        } else {
            frame = previewSourceFrame()
        }
        guard let frame, frame.width > 0, frame.height > 0 else { return nil }
        for screen in NSScreen.screens where screen.frame.intersects(frame) {
            if abs(frame.width - screen.frame.width) < 1, abs(frame.height - screen.frame.height) < 1 {
                return screen
            }
        }
        return nil
    }
    func positionedCanvasScreen() -> NSScreen? {
        guard filePreviewImage == nil, mode == .allow,
              framing == .full, canvasMode == .isolated,
              selectedWindowIDs.count == 1 || dynamicUnionWindows().count == 1 else { return nil }
        if let frame = previewSourceFrame() {
            return NSScreen.screens.first(where: { $0.frame.intersects(frame) }) ?? NSScreen.main
        }
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first {
            return NSScreen.screens.first { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
                return number.uint32Value == display.displayID
            } ?? NSScreen.main
        }
        return NSScreen.main
    }
    var isPositionedCanvas: Bool {
        positionedCanvasScreen() != nil
    }
    func positionedSourceFrame() -> CGRect? {
        if let live = livePositionedFrame, let liveID = livePositionedWindowID,
           mode == .allow, let effectiveID = effectiveSingleWindowID, effectiveID == liveID {
            return live
        }
        return previewSourceFrame()
    }
    func positionedCanvasRect(for screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let displayMinusMenuBar = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: screen.frame.height - menuBarHeight)
        if nativeFullscreenScreen() != nil {
            return displayMinusMenuBar
        }
        guard let frame = positionedSourceFrame() else { return visible }
        let mainHeight = NSScreen.main?.frame.height ?? screen.frame.height
        let screenQuartzTop = mainHeight - screen.frame.maxY
        let windowTopRel = frame.origin.y - screenQuartzTop
        let windowBottomRel = windowTopRel + frame.height
        let visibleBottomRel = menuBarHeight + visible.height
        let canvasBottomRel = min(screen.frame.height, max(visibleBottomRel, windowBottomRel))
        let canvasLeft = max(screen.frame.minX, min(visible.minX, frame.origin.x))
        let canvasRight = min(screen.frame.maxX, max(visible.maxX, frame.origin.x + frame.width))
        let width = max(1, canvasRight - canvasLeft)
        let height = max(1, canvasBottomRel - menuBarHeight)
        return CGRect(x: canvasLeft, y: screen.frame.maxY - canvasBottomRel, width: width, height: height)
    }
    func positionedImageFrame(in canvasSize: CGSize) -> CGRect? {
        guard let screen = positionedCanvasScreen() else { return nil }
        let frame: CGRect
        if let live = livePositionedFrame, let liveID = livePositionedWindowID,
           mode == .allow, let effectiveID = effectiveSingleWindowID, effectiveID == liveID {
            frame = live
        } else if let sourceFrame = previewSourceFrame() {
            frame = sourceFrame
        } else { return nil }
        let canvas = positionedCanvasRect(for: screen)
        guard canvas.width > 0, canvas.height > 0, canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let mainHeight = NSScreen.main?.frame.height ?? screen.frame.height
        let screenQuartzTop = mainHeight - screen.frame.maxY
        let canvasTop = screenQuartzTop + menuBarHeight
        let scale = canvasSize.width / canvas.width
        let width = frame.width * scale
        let height = frame.height * scale
        let x = (frame.origin.x - canvas.minX) * scale
        let y = (frame.origin.y - canvasTop) * scale
        return CGRect(x: x, y: y, width: width, height: height)
    }
    func dynamicImageSize(in outputSize: CGSize) -> CGSize? {
        guard framing == .dynamic, canvasMode == .isolated,
              let union = previewSourceFrame(), union.width > 0, union.height > 0,
              outputSize.width > 0, outputSize.height > 0 else { return nil }
        let scale = min(outputSize.width / (union.width + 10), outputSize.height / (union.height + 10))
        guard scale > 0 else { return nil }
        return CGSize(width: union.width * scale, height: union.height * scale)
    }
    func canvasAspectRatio() -> CGFloat {
        if canvasMode == .fullDisplay, let size = fullDisplayFrameSize(), size.height > 0 {
            return size.width / size.height
        }
        if let screen = positionedCanvasScreen() {
            let canvas = positionedCanvasRect(for: screen)
            if canvas.height > 0 {
                return canvas.width / canvas.height
            } else if let fullscreen = nativeFullscreenScreen(), fullscreen.frame.height > 0 {
                return fullscreen.frame.width / fullscreen.frame.height
            } else if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
                      let (rect, _) = displayWithoutMenuBar(for: display), rect.height > 0 {
                return rect.width / rect.height
            }
        }
        if canvasMode == .isolated, framing == .full,
           let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
           let (rect, _) = displayWithoutMenuBar(for: display), rect.height > 0 {
            return rect.width / rect.height
        }
        if framing == .dynamic, canvasMode == .isolated,
           let frame = previewSourceFrame(), frame.width > 0, frame.height > 0 {
            return (frame.width + 10) / (frame.height + 10)
        }
        if let size = fullscreenVisibleSize(), size.height > 0 {
            return size.width / size.height
        }
        if filePreviewImage == nil {
            if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
               let (rect, _) = displayWithoutMenuBar(for: display), rect.height > 0 {
                return rect.width / rect.height
            }
            if let screen = NSScreen.main, screen.frame.height > 0 {
                return screen.frame.width / screen.frame.height
            }
        }
        return sourceAspectRatio
    }
    func sourceContentSize() -> CGSize? {
        guard filePreviewImage == nil else { return nil }
        if canvasMode == .fullDisplay, let size = fullDisplayFrameSize() {
            return size
        }
        if let screen = positionedCanvasScreen() {
            return positionedCanvasRect(for: screen).size
        }
        if let fullscreen = nativeFullscreenScreen() {
            return fullscreen.frame.size
        }
        if canvasMode == .isolated, framing == .full,
           let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
           let (rect, _) = displayWithoutMenuBar(for: display), rect.height > 0 {
            return rect.size
        }
        if framing == .dynamic, canvasMode == .isolated,
           let frame = previewSourceFrame(), frame.width > 0, frame.height > 0 {
            return CGSize(width: frame.width + 10, height: frame.height + 10)
        }
        if let visibleSize = fullscreenVisibleSize() {
            return visibleSize
        }
        var scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 1
        if let frame = previewSourceFrame(),
           let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }) {
            scale = screen.backingScaleFactor
        }
        if scale > 0 {
            if isSharing, let image = previewImage, image.size.width > 0, image.size.height > 0 {
                return CGSize(width: image.size.width / scale, height: image.size.height / scale)
            }
            if !isSharing, let image = previewSnapshotImage, image.size.width > 0, image.size.height > 0 {
                return CGSize(width: image.size.width / scale, height: image.size.height / scale)
            }
        }
        return sourceWindowSize()
    }
    func previewSourceFrame() -> CGRect? {
        if mode == .allow, selectedWindowIDs.count == 1,
           let onlyID = selectedWindowIDs.first,
           let frame = capturedWindows.first(where: { $0.windowID == onlyID })?.frame {
            return frame
        }
        if mode == .allow, framing == .full, canvasMode == .isolated,
           let singleWindow = dynamicUnionWindows().first, dynamicUnionWindows().count == 1 {
            return singleWindow.frame
        }
        if isSharing, mode == .allow, framing == .dynamic, canvasMode == .isolated,
           selectedWindowIDs.count > 1, let captureUnion = dynamicCaptureUnion {
            return captureUnion
        }
        if mode == .allow, framing == .dynamic, !selectedWindowIDs.isEmpty {
            return dynamicUnionFrame()
        }
        return nil
    }
    func registerPanelWindow(_ window: NSWindow) {
        if PanelWindowStore.shared.window === window, PanelWindowStore.shared.resizeObserver != nil { return }
        if let observer = PanelWindowStore.shared.resizeObserver {
            NotificationCenter.default.removeObserver(observer)
            PanelWindowStore.shared.resizeObserver = nil
        }
        PanelWindowStore.shared.window = window
        PanelWindowStore.shared.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { _ in
            if let bottom = PanelWindowStore.shared.anchoredBottom,
               let panelWindow = PanelWindowStore.shared.window {
                panelWindow.setFrameOrigin(NSPoint(x: panelWindow.frame.minX, y: bottom))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    PanelWindowStore.shared.anchoredBottom = nil
                }
            }
        }
    }
    func togglePreviewWindow() {
        isPreviewVisible.toggle()
        if isPreviewVisible, !isSharing {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
    }
    private func configureCaptureAreaWindow(_ window: NSWindow) {
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
    private var captureAreaRatio: CGFloat {
        (isPreviewVisible && previewRenderedRatio > 0) ? previewRenderedRatio : previewRatio()
    }
    func captureAreaWindowSize(width: CGFloat) -> CGSize {
        let ratio = captureAreaRatio
        guard ratio > 0 else { return CGSize(width: width, height: width) }
        var w = width
        var h = w / ratio
        if let screen = NSScreen.main {
            let visible = nativeFullscreenScreen()?.frame ?? screen.visibleFrame
            let maxH = max(180, visible.height - 100)
            let maxW = max(320, visible.width - 80)
            if h > maxH { h = maxH; w = h * ratio }
            if w > maxW { w = maxW; h = w / ratio }
        }
        if w < 320 { h = h * 320 / w; w = 320 }
        if h < 180 { w = w * 180 / h; h = 180 }
        return CGSize(width: w, height: h)
    }
    func openFileControlWindow() {
        guard activeFile != nil else {
            closeFileControlWindow()
            return
        }
        if let window = FileControlWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            attachFileControlWindow()
            dockFileControlToCaptureArea()
            dockTimerControlToCaptureArea()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 280, height: 36),
            styleMask: [.closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil File Control"
        window.level = .floating
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        configureCaptureAreaWindow(window)
        window.contentView = NSHostingView(rootView: PreviewFileControls().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        FileControlWindowStore.shared.window = window
        attachFileControlWindow()
        dockFileControlToCaptureArea()
        dockTimerControlToCaptureArea()
    }
    func closeFileControlWindow() {
        if let window = FileControlWindowStore.shared.window {
            if let output = CaptureAreaWindowStore.shared.window {
                output.removeChildWindow(window)
            }
            window.close()
            FileControlWindowStore.shared.window = nil
        }
        dockTimerControlToCaptureArea()
    }
    func attachFileControlWindow() {
        guard let output = CaptureAreaWindowStore.shared.window,
              let flyer = FileControlWindowStore.shared.window,
              output.childWindows?.contains(flyer) != true else { return }
        output.addChildWindow(flyer, ordered: .above)
    }
    func dockFileControlToCaptureArea() {
        guard let flyer = FileControlWindowStore.shared.window,
              let output = CaptureAreaWindowStore.shared.window,
              output.isVisible, flyer.isVisible else { return }
        let gap: CGFloat = 8
        let size = CGSize(width: flyer.frame.width, height: 36)
        var x = output.frame.maxX - size.width - gap
        var y = output.frame.minY + gap
        if let screen = output.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            if x < visible.minX { x = visible.minX }
            if x + size.width > visible.maxX { x = visible.maxX - size.width }
            if y < visible.minY { y = visible.minY }
            if y + size.height > visible.maxY { y = visible.maxY - size.height }
        }
        let frame = NSRect(x: x, y: y, width: size.width, height: size.height)
        let current = flyer.frame
        if abs(frame.width - current.width) > 1 || abs(frame.height - current.height) > 1
            || abs(frame.origin.x - current.origin.x) > 1 || abs(frame.origin.y - current.origin.y) > 1 {
            flyer.setFrame(frame, display: true)
        }
    }
    func reopenFileControlIfNeeded() {
        if isCaptureAreaVisible, activeFile != nil, FileControlWindowStore.shared.window == nil {
            openFileControlWindow()
        }
    }
    func timerControlSize(expanded: Bool) -> CGSize {
        guard expanded else { return CGSize(width: 36, height: 36) }
        return presentationTimerMode == .countDown ? CGSize(width: 280, height: 36) : CGSize(width: 240, height: 36)
    }
    func timerControlFrame(expanded: Bool) -> CGRect? {
        guard let output = CaptureAreaWindowStore.shared.window, output.isVisible,
              let screen = output.screen ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let size = timerControlSize(expanded: expanded)
        let gap: CGFloat = 8
        var x: CGFloat
        if let flyer = FileControlWindowStore.shared.window, flyer.isVisible {
            x = flyer.frame.minX - gap - size.width
        } else {
            x = output.frame.maxX - size.width - gap
        }
        var y: CGFloat
        if let flyer = FileControlWindowStore.shared.window, flyer.isVisible {
            y = flyer.frame.minY
        } else {
            y = output.frame.minY + gap
        }
        if x < visible.minX { x = visible.minX }
        if x + size.width > visible.maxX { x = visible.maxX - size.width }
        if y < visible.minY { y = visible.minY }
        if y + size.height > visible.maxY { y = visible.maxY - size.height }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    func openTimerControlWindow() {
        guard CaptureAreaWindowStore.shared.window != nil, isCaptureAreaVisible else { return }
        if let window = TimerControlWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            attachTimerControlWindow()
            dockTimerControlToCaptureArea()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 36, height: 36),
            styleMask: [.closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Timer Control"
        window.level = .floating
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        configureCaptureAreaWindow(window)
        window.contentView = NSHostingView(rootView: TimerControlView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        TimerControlWindowStore.shared.window = window
        attachTimerControlWindow()
        dockTimerControlToCaptureArea()
    }
    func closeTimerControlWindow() {
        if let window = TimerControlWindowStore.shared.window {
            if let output = CaptureAreaWindowStore.shared.window {
                output.removeChildWindow(window)
            }
            window.close()
            TimerControlWindowStore.shared.window = nil
        }
    }
    func attachTimerControlWindow() {
        guard let output = CaptureAreaWindowStore.shared.window,
              let timer = TimerControlWindowStore.shared.window,
              output.childWindows?.contains(timer) != true else { return }
        output.addChildWindow(timer, ordered: .above)
    }
    func dockTimerControlToCaptureArea() {
        guard let timer = TimerControlWindowStore.shared.window,
              let output = CaptureAreaWindowStore.shared.window,
              output.isVisible, timer.isVisible else { return }
        guard let frame = timerControlFrame(expanded: presentationTimerExpanded) else { return }
        let current = timer.frame
        if abs(frame.width - current.width) > 1 || abs(frame.height - current.height) > 1
            || abs(frame.origin.x - current.origin.x) > 1 || abs(frame.origin.y - current.origin.y) > 1 {
            timer.setFrame(frame, display: true)
        }
        dockAnnotationControlToCaptureArea()
    }
    func setTimerControlExpanded(_ expanded: Bool) {
        guard let window = TimerControlWindowStore.shared.window else {
            presentationTimerExpanded = expanded
            return
        }
        if expanded {
            if let frame = timerControlFrame(expanded: true) {
                window.setFrame(frame, display: true)
                window.contentView?.layoutSubtreeIfNeeded()
            }
            presentationTimerExpanded = true
            dockAnnotationControlToCaptureArea()
        } else {
            presentationTimerExpanded = false
            guard let frame = timerControlFrame(expanded: false) else { return }
            let annotationFrame = annotationFrame(forTimerFrame: frame, expanded: annotationExpanded)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.55
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
                if let annotationFrame, let annotationWindow = AnnotationControlWindowStore.shared.window {
                    annotationWindow.animator().setFrame(annotationFrame, display: true)
                }
            }, completionHandler: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard !self.presentationTimerExpanded else { return }
                    self.dockTimerControlToCaptureArea()
                    self.dockAnnotationControlToCaptureArea()
                }
            })
        }
    }
    func reopenTimerControlIfNeeded() {
        if isCaptureAreaVisible, TimerControlWindowStore.shared.window == nil {
            openTimerControlWindow()
        }
    }
    func annotationControlSize(expanded: Bool) -> CGSize {
        expanded ? CGSize(width: 172, height: 36) : CGSize(width: 36, height: 36)
    }
    func annotationFrame(forTimerFrame timerFrame: CGRect, expanded: Bool) -> CGRect? {
        guard let output = CaptureAreaWindowStore.shared.window, output.isVisible,
              let screen = output.screen ?? NSScreen.main else { return nil }
        let visible = screen.visibleFrame
        let size = annotationControlSize(expanded: expanded)
        let gap: CGFloat = 8
        var x = timerFrame.minX - gap - size.width
        var y = timerFrame.minY
        if x < visible.minX { x = visible.minX }
        if x + size.width > visible.maxX { x = visible.maxX - size.width }
        if y < visible.minY { y = visible.minY }
        if y + size.height > visible.maxY { y = visible.maxY - size.height }
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }
    func annotationControlFrame(expanded: Bool) -> CGRect? {
        if let timerWindow = TimerControlWindowStore.shared.window {
            return annotationFrame(forTimerFrame: timerWindow.frame, expanded: expanded)
        }
        guard let timerFrame = timerControlFrame(expanded: presentationTimerExpanded) else { return nil }
        return annotationFrame(forTimerFrame: timerFrame, expanded: expanded)
    }
    func openAnnotationControlWindow() {
        guard CaptureAreaWindowStore.shared.window != nil, isCaptureAreaVisible else { return }
        if let window = AnnotationControlWindowStore.shared.window {
            window.makeKeyAndOrderFront(nil)
            attachAnnotationControlWindow()
            dockAnnotationControlToCaptureArea()
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 36, height: 36),
            styleMask: [.closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Annotation Control"
        window.level = .floating
        window.sharingType = .none
        window.isReleasedWhenClosed = false
        configureCaptureAreaWindow(window)
        window.contentView = NSHostingView(rootView: AnnotationControlView().environmentObject(self))
        window.makeKeyAndOrderFront(nil)
        AnnotationControlWindowStore.shared.window = window
        attachAnnotationControlWindow()
        dockAnnotationControlToCaptureArea()
    }
    func closeAnnotationControlWindow() {
        if let window = AnnotationControlWindowStore.shared.window {
            if let output = CaptureAreaWindowStore.shared.window {
                output.removeChildWindow(window)
            }
            window.close()
            AnnotationControlWindowStore.shared.window = nil
        }
    }
    func attachAnnotationControlWindow() {
        guard let output = CaptureAreaWindowStore.shared.window,
              let annotation = AnnotationControlWindowStore.shared.window,
              output.childWindows?.contains(annotation) != true else { return }
        output.addChildWindow(annotation, ordered: .above)
    }
    func dockAnnotationControlToCaptureArea() {
        guard let annotation = AnnotationControlWindowStore.shared.window,
              let output = CaptureAreaWindowStore.shared.window,
              output.isVisible, annotation.isVisible else { return }
        guard let frame = annotationControlFrame(expanded: annotationExpanded) else { return }
        let current = annotation.frame
        if abs(frame.width - current.width) > 1 || abs(frame.height - current.height) > 1
            || abs(frame.origin.x - current.origin.x) > 1 || abs(frame.origin.y - current.origin.y) > 1 {
            annotation.setFrame(frame, display: true)
        }
    }
    func setAnnotationControlExpanded(_ expanded: Bool) {
        guard let window = AnnotationControlWindowStore.shared.window else {
            annotationExpanded = expanded
            return
        }
        if expanded {
            if let frame = annotationControlFrame(expanded: true) {
                window.setFrame(frame, display: true)
                window.contentView?.layoutSubtreeIfNeeded()
            }
            annotationExpanded = true
        } else {
            annotationExpanded = false
            guard let frame = annotationControlFrame(expanded: false) else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.55
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                Task { @MainActor in
                    guard !self.annotationExpanded else { return }
                    self.dockAnnotationControlToCaptureArea()
                }
            })
        }
    }
    func reopenAnnotationControlIfNeeded() {
        if isCaptureAreaVisible, AnnotationControlWindowStore.shared.window == nil {
            openAnnotationControlWindow()
        }
    }
    func resizeCaptureAreaWindow() {
        guard let window = CaptureAreaWindowStore.shared.window else {
            dockFileControlToCaptureArea()
            dockTimerControlToCaptureArea()
            dockAnnotationControlToCaptureArea()
            return
        }
        guard isCaptureAreaVisible else { return }
        let size = captureAreaWindowSize(width: window.frame.width)
        if let screen = window.screen ?? NSScreen.main {
            let visible = nativeFullscreenScreen()?.frame ?? screen.visibleFrame
            if abs(window.frame.width - visible.width) < 2 && abs(window.frame.height - visible.height) < 2
                && abs(window.frame.minX - visible.minX) < 2 && abs(window.frame.minY - visible.minY) < 2 {
                dockFileControlToCaptureArea()
                dockTimerControlToCaptureArea()
                dockAnnotationControlToCaptureArea()
                return
            }
        }
        var frame = window.frame
        frame.size = size
        if let screen = window.screen ?? NSScreen.main {
            let visible = nativeFullscreenScreen()?.frame ?? screen.visibleFrame
            if positionedCanvasScreen() != nil || fullscreenVisibleSize() != nil {
                frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
                let oldTop = window.frame.maxY
                frame.origin.y = max(visible.minY, min(oldTop - frame.height, visible.maxY - frame.height))
            } else {
                frame.origin.x = max(visible.minX - frame.width + 100, min(frame.origin.x, visible.maxX - 100))
                frame.origin.y = max(visible.minY - frame.height + 100, min(frame.origin.y, visible.maxY - 100))
            }
        }
        if abs(frame.width - window.frame.width) > 1 || abs(frame.height - window.frame.height) > 1
            || abs(frame.origin.x - window.frame.origin.x) > 1 || abs(frame.origin.y - window.frame.origin.y) > 1 {
            window.setFrame(frame, display: true)
        }
        dockFileControlToCaptureArea()
        dockTimerControlToCaptureArea()
        dockAnnotationControlToCaptureArea()
    }
    func toggleCaptureAreaWindow() {
        if isCaptureAreaVisible {
            closeCaptureAreaWindow()
        } else {
            openCaptureAreaWindow()
        }
    }
    private func moveCaptureAreaOffScreen(_ window: NSWindow) {
        let screen = window.screen ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        window.setFrameOrigin(CGPoint(x: visible.maxX, y: visible.minY - window.frame.height))
    }
    func closeCaptureAreaWindow() {
        closeFileControlWindow()
        closeTimerControlWindow()
        closeAnnotationControlWindow()
        if let window = CaptureAreaWindowStore.shared.window {
            moveCaptureAreaOffScreen(window)
        }
        isCaptureAreaVisible = false
    }
    func openCaptureAreaWindow(hidden: Bool = false) {
        if let window = CaptureAreaWindowStore.shared.window {
            if hidden {
                moveCaptureAreaOffScreen(window)
                window.orderFront(nil)
                isCaptureAreaVisible = false
                return
            }
            isCaptureAreaVisible = true
            if let screen = NSScreen.main {
                let visible = screen.visibleFrame
                let origin = CGPoint(
                    x: max(visible.minX, visible.midX - window.frame.width / 2),
                    y: max(visible.minY, visible.midY - window.frame.height / 2)
                )
                window.setFrameOrigin(origin)
            }
            resizeCaptureAreaWindow()
            window.makeKeyAndOrderFront(nil)
            dockFileControlToCaptureArea()
            attachFileControlWindow()
            reopenFileControlIfNeeded()
            openTimerControlWindow()
            openAnnotationControlWindow()
            refreshCaptureFilter()
            return
        }
        updateSourceAspectRatio()
        let size = captureAreaWindowSize(width: 960)
        var origin = CGPoint(x: 100, y: 100)
        if let screen = nativeFullscreenScreen() {
            origin = screen.frame.origin
        } else if let screen = positionedCanvasScreen() ?? fullscreenSourceScreen() {
            origin = screen.visibleFrame.origin
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            origin = CGPoint(
                x: max(visible.minX, visible.midX - size.width / 2),
                y: max(visible.minY, visible.midY - size.height / 2)
            )
            origin.x = min(origin.x, visible.maxX - size.width)
            origin.y = min(origin.y, visible.maxY - size.height)
        }
        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Veil Output — share this window"
        window.contentMinSize = NSSize(width: 320, height: 180)
        configureCaptureAreaWindow(window)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: CaptureAreaRootView().environmentObject(self))
        CaptureAreaWindowStore.shared.window = window
        if hidden {
            moveCaptureAreaOffScreen(window)
            window.orderFront(nil)
            isCaptureAreaVisible = false
        } else {
            window.makeKeyAndOrderFront(nil)
            isCaptureAreaVisible = true
            dockFileControlToCaptureArea()
            attachFileControlWindow()
            reopenFileControlIfNeeded()
            openTimerControlWindow()
            openAnnotationControlWindow()
            refreshCaptureFilter()
        }
        CaptureAreaWindowStore.shared.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isCaptureAreaVisible = false }
        }
        CaptureAreaWindowStore.shared.resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dockFileControlToCaptureArea()
                self?.dockTimerControlToCaptureArea()
                self?.dockAnnotationControlToCaptureArea()
            }
        }
    }
}
final class MetalDisplayLayer: CAMetalLayer {
    var gravity: AVLayerVideoGravity = .resize
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var pipelineState: MTLRenderPipelineState?
    private var samplerState: MTLSamplerState?
    private var positionBuffer: MTLBuffer?
    private var texCoordBuffer: MTLBuffer?
    private var nilDrawableCount = 0
    private var setupNilCount = 0
    private let logLock = NSLock()
    override init() {
        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        metalDevice = device
        self.device = device
        pixelFormat = .bgra8Unorm
        framebufferOnly = true
        commandQueue = device.makeCommandQueue()
        var cache: CVMetalTextureCache?
        if CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) == kCVReturnSuccess {
            textureCache = cache
        }
        let shader = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        vertex VertexOut vertex_main(uint vertexID [[vertex_id]], constant float4 *positions [[buffer(0)]], constant float2 *texCoords [[buffer(1)]]) {
            VertexOut out;
            out.position = positions[vertexID];
            out.texCoord = texCoords[vertexID];
            return out;
        }
        fragment float4 fragment_main(VertexOut in [[stage_in]], texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]) {
            return tex.sample(samp, in.texCoord);
        }
        """
        if let library = try? device.makeLibrary(source: shader, options: nil),
           let vertexFunction = library.makeFunction(name: "vertex_main"),
           let fragmentFunction = library.makeFunction(name: "fragment_main") {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = vertexFunction
            descriptor.fragmentFunction = fragmentFunction
            descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
        positionBuffer = device.makeBuffer(length: 16 * 4, options: [])
        texCoordBuffer = device.makeBuffer(length: 8 * 4, options: [])
    }
    required init?(coder: NSCoder) {
        fatalError()
    }
    func render(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        render(pixelBuffer: pixelBuffer)
    }
    func render(pixelBuffer: CVPixelBuffer) {
        guard metalDevice != nil,
              let commandQueue,
              let pipelineState,
              let textureCache,
              let samplerState else {
            logLock.lock()
            setupNilCount += 1
            let count = setupNilCount
            logLock.unlock()
            if count <= 3 {
                DebugLog.log("metal: render setup nil count=\(count) device=\(metalDevice != nil) pipeline=\(pipelineState != nil) cache=\(textureCache != nil) sampler=\(samplerState != nil)")
            }
            return
        }
        guard let drawable = nextDrawable() else {
            logLock.lock()
            nilDrawableCount += 1
            let count = nilDrawableCount
            logLock.unlock()
            if count <= 3 || count % 600 == 0 {
                DebugLog.log("metal: nextDrawable nil count=\(count) drawableSize=\(drawableSize) bounds=\(bounds.size)")
            }
            return
        }
        let textureWidth = CVPixelBufferGetWidth(pixelBuffer)
        let textureHeight = CVPixelBufferGetHeight(pixelBuffer)
        guard textureWidth > 0, textureHeight > 0 else { return }
        var cvTexture: CVMetalTexture?
        let textureResult = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .bgra8Unorm, textureWidth, textureHeight, 0, &cvTexture)
        guard textureResult == kCVReturnSuccess, let cvTexture, let texture = CVMetalTextureGetTexture(cvTexture) else { return }
        let drawableWidth = drawable.texture.width
        let drawableHeight = drawable.texture.height
        guard drawableWidth > 0, drawableHeight > 0 else { return }
        var texX0: Float = 0
        var texX1: Float = 1
        var texY0: Float = 0
        var texY1: Float = 1
        if gravity.rawValue == AVLayerVideoGravity.resizeAspectFill.rawValue {
            let textureAspect = Float(textureWidth) / Float(textureHeight)
            let drawableAspect = Float(drawableWidth) / Float(drawableHeight)
            if textureAspect > drawableAspect {
                let croppedWidth = drawableAspect / textureAspect
                texX0 = (1 - croppedWidth) / 2
                texX1 = texX0 + croppedWidth
            } else if drawableAspect > textureAspect {
                let croppedHeight = textureAspect / drawableAspect
                texY0 = (1 - croppedHeight) / 2
                texY1 = texY0 + croppedHeight
            }
        }
        let positions: [Float] = [-1, -1, 0, 1, 1, -1, 0, 1, -1, 1, 0, 1, 1, 1, 0, 1]
        let texCoords: [Float] = [texX0, texY1, texX1, texY1, texX0, texY0, texX1, texY0]
        guard let positionBuffer, let texCoordBuffer else { return }
        positions.withUnsafeBytes { source in
            if let base = source.baseAddress {
                positionBuffer.contents().copyMemory(from: base, byteCount: positions.count * 4)
            }
        }
        texCoords.withUnsafeBytes { source in
            if let base = source.baseAddress {
                texCoordBuffer.contents().copyMemory(from: base, byteCount: texCoords.count * 4)
            }
        }
        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        let passDescriptor = MTLRenderPassDescriptor()
        passDescriptor.colorAttachments[0].texture = drawable.texture
        passDescriptor.colorAttachments[0].loadAction = .clear
        passDescriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        passDescriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: passDescriptor) else { return }
        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(positionBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.setFragmentSamplerState(samplerState, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    func flushCache() {
        guard let textureCache else { return }
        CVMetalTextureCacheFlush(textureCache, 0)
    }
}
final class StreamDisplayLayers {
    static let shared = StreamDisplayLayers()
    let preview = MetalDisplayLayer()
    let output = MetalDisplayLayer()
    private var lastPixelBuffer: CVPixelBuffer?
    private init() {
        preview.gravity = .resize
        output.gravity = .resize
    }
    func render(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastPixelBuffer = pixelBuffer
        preview.render(pixelBuffer: pixelBuffer)
        output.render(pixelBuffer: pixelBuffer)
        preview.flushCache()
        output.flushCache()
    }
    func renderLastFrame() {
        guard let pixelBuffer = lastPixelBuffer else { return }
        preview.render(pixelBuffer: pixelBuffer)
        output.render(pixelBuffer: pixelBuffer)
        preview.flushCache()
        output.flushCache()
    }
    func flush() {
        preview.flushCache()
        output.flushCache()
    }
}
final class CaptureRouting {
    static let shared = CaptureRouting()
    private let lock = NSLock()
    private var mainStreamID: ObjectIdentifier?
    private var snapshotStreamID: ObjectIdentifier?
    private var paused = false
    private var firstFrame = false
    private var lastRatio: CGFloat = 0
    private var consecutiveBlackFrames = 0
    private var lastBlackRestart = Date.distantPast
    private var droppedFrames = 0
    private var lastDroppedStatus = ""
    private var mainFrameCount = 0
    private init() {}
    func recordDroppedFrame(status: String) {
        lock.lock()
        droppedFrames += 1
        lastDroppedStatus = status
        lock.unlock()
    }
    func droppedSummary() -> (Int, String) {
        lock.lock()
        let value = (droppedFrames, lastDroppedStatus)
        lock.unlock()
        return value
    }
    func nextMainFrameIndex() -> Int {
        lock.lock()
        mainFrameCount += 1
        let value = mainFrameCount
        lock.unlock()
        return value
    }
    func setMainStreamID(_ id: ObjectIdentifier?) {
        lock.lock()
        mainStreamID = id
        lock.unlock()
    }
    func setSnapshotStreamID(_ id: ObjectIdentifier?) {
        lock.lock()
        snapshotStreamID = id
        lock.unlock()
    }
    func isMainStreamID(_ id: ObjectIdentifier) -> Bool {
        lock.lock()
        let value = mainStreamID == id
        lock.unlock()
        return value
    }
    func isSnapshotStreamID(_ id: ObjectIdentifier) -> Bool {
        lock.lock()
        let value = snapshotStreamID == id
        lock.unlock()
        return value
    }
    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        lock.unlock()
    }
    func isPaused() -> Bool {
        lock.lock()
        let value = paused
        lock.unlock()
        return value
    }
    func setFirstFrame(_ value: Bool) {
        lock.lock()
        firstFrame = value
        lock.unlock()
    }
    func takeFirstFrame() -> Bool {
        lock.lock()
        let value = !firstFrame
        if value {
            firstFrame = true
        }
        lock.unlock()
        return value
    }
    func checkRatio(_ ratio: CGFloat) -> Bool {
        lock.lock()
        let changed = abs(ratio - lastRatio) > 0.0005
        if changed {
            lastRatio = ratio
        }
        lock.unlock()
        return changed
    }
    func recordBlackFrame() -> Bool {
        lock.lock()
        consecutiveBlackFrames += 1
        let shouldRestart = consecutiveBlackFrames >= 15 && Date().timeIntervalSince(lastBlackRestart) > 3
        if shouldRestart {
            consecutiveBlackFrames = 0
            lastBlackRestart = Date()
        }
        lock.unlock()
        return shouldRestart
    }
    func resetBlackFrames() {
        lock.lock()
        consecutiveBlackFrames = 0
        lock.unlock()
    }
}
final class DirectStreamNSView: NSView {
    let displayLayer: MetalDisplayLayer
    init(layer: MetalDisplayLayer) {
        displayLayer = layer
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) {
        fatalError()
    }
    override func makeBackingLayer() -> CALayer {
        return displayLayer
    }
    func syncDrawableSize() {
        let scale = window?.backingScaleFactor ?? layer?.contentsScale ?? 1
        displayLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        displayLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DebugLog.log("view: didMoveToWindow window=\(window != nil) bounds=\(bounds) layerIsShared=\(layer === displayLayer)")
        if window != nil {
            syncDrawableSize()
            DispatchQueue.main.async {
                StreamDisplayLayers.shared.renderLastFrame()
            }
        }
    }
    override func layout() {
        super.layout()
        syncDrawableSize()
    }
}
struct DirectStreamView: NSViewRepresentable {
    let layer: MetalDisplayLayer
    let gravity: AVLayerVideoGravity
    func makeNSView(context: Context) -> DirectStreamNSView {
        let view = DirectStreamNSView(layer: layer)
        layer.gravity = gravity
        return view
    }
    func updateNSView(_ nsView: DirectStreamNSView, context: Context) {
        layer.gravity = gravity
        nsView.syncDrawableSize()
    }
}
