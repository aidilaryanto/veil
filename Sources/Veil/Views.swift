import AppKit
import AVFoundation
import ScreenCaptureKit
import SwiftUI
enum PopupKind: String, Identifiable {
    case sources, display, frame, mode, canvas, presets, camera
    var id: String { rawValue }
}
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            if let window = nsView.window { onWindow(window) }
        }
    }
}
final class WindowDragNSView: NSView {
    var resizable: Bool = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if resizable, isInResizeZone(convert(event.locationInWindow, from: nil)) {
            super.mouseDown(with: event)
            return
        }
        window?.performDrag(with: event)
    }
    private func isInResizeZone(_ point: NSPoint) -> Bool {
        let thickness: CGFloat = 6
        let b = bounds
        return point.x < b.minX + thickness || point.x > b.maxX - thickness || point.y < b.minY + thickness || point.y > b.maxY - thickness
    }
    override func resetCursorRects() {
        super.resetCursorRects()
        guard resizable else { return }
        let thickness: CGFloat = 6
        let b = bounds
        addCursorRect(NSRect(x: b.minX, y: b.minY + thickness, width: thickness, height: b.height - thickness * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.maxX - thickness, y: b.minY + thickness, width: thickness, height: b.height - thickness * 2), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.minX + thickness, y: b.minY, width: b.width - thickness * 2, height: thickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: b.minX + thickness, y: b.maxY - thickness, width: b.width - thickness * 2, height: thickness), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: b.minX, y: b.minY, width: thickness, height: thickness), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.maxX - thickness, y: b.minY, width: thickness, height: thickness), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.minX, y: b.maxY - thickness, width: thickness, height: thickness), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: b.maxX - thickness, y: b.maxY - thickness, width: thickness, height: thickness), cursor: .resizeLeftRight)
    }
}
struct WindowDragView: NSViewRepresentable {
    var resizable: Bool = false
    func makeNSView(context: Context) -> NSView {
        let view = WindowDragNSView()
        view.resizable = resizable
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowDragNSView)?.resizable = resizable
    }
}
extension View {
    func pointingHandOnHover() -> some View {
        onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
struct ContentView: View {
    @EnvironmentObject var model: VeilModel
    @State private var popup: PopupKind?
    @State private var showSourcesPopover = false
    @State private var showDisplayPopover = false
    @State private var showFramePopover = false
    @State private var showModePopover = false
    @State private var showCanvasPopover = false
    @State private var showPresetsPopover = false
    @State private var showCameraPopover = false
    @State private var expandedApps: Set<String> = []
    @State private var renamingPresetID: UUID?
    @State private var renamingName = ""
    @State private var showQuitConfirmation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isPreviewVisible {
                PreviewContentView()
                    .environmentObject(model)
                    .frame(width: embeddedPreviewSize.width, height: embeddedPreviewSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear {
                        if embeddedPreviewSize.height > 0 {
                            model.previewRenderedRatio = embeddedPreviewSize.width / embeddedPreviewSize.height
                        }
                    }
                    .onChange(of: embeddedPreviewSize) { _, newSize in
                        if newSize.height > 0 {
                            model.previewRenderedRatio = newSize.width / newSize.height
                        }
                    }
            }
            VStack(alignment: .leading, spacing: 8) {
                header
                presetStrip
                popupGrid
            }
            .padding(12)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow)
                    Color.black.opacity(0.25)
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
        .frame(width: 540)
        .fixedSize(horizontal: false, vertical: true)
        .overlay {
            if showQuitConfirmation {
                quitConfirmationView
            }
        }
        .preferredColorScheme(.dark)
        .background(WindowAccessor { window in
            configureFramelessWindow(window)
        })
        .onChange(of: model.alwaysOnTop) { _, _ in
            model.applyAlwaysOnTop()
        }
        .onChange(of: model.isPreviewVisible) { _, _ in
            PanelWindowStore.shared.anchoredBottom = PanelWindowStore.shared.window?.frame.minY
        }
        .sheet(item: $popup) { kind in
            switch kind {
            case .sources: sourcesPopup
            case .display: displayPopup
            case .frame: framingPopup
            case .mode: modePopup
            case .canvas: canvasPopup
            case .presets: presetsPopup
            case .camera: cameraPopup
            }
        }
        .onChange(of: popup) { _, newValue in
            if newValue != nil { showSourcesPopover = false; showDisplayPopover = false; showFramePopover = false; showModePopover = false; showCanvasPopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showSourcesPopover) { _, newValue in
            if newValue { popup = nil; showDisplayPopover = false; showFramePopover = false; showModePopover = false; showCanvasPopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showDisplayPopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showFramePopover = false; showModePopover = false; showCanvasPopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showFramePopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showDisplayPopover = false; showModePopover = false; showCanvasPopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showModePopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showDisplayPopover = false; showFramePopover = false; showCanvasPopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showCanvasPopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showDisplayPopover = false; showFramePopover = false; showModePopover = false; showPresetsPopover = false; showCameraPopover = false }
        }
        .onChange(of: showPresetsPopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showDisplayPopover = false; showFramePopover = false; showModePopover = false; showCanvasPopover = false; showCameraPopover = false }
        }
        .onChange(of: showCameraPopover) { _, newValue in
            if newValue { popup = nil; showSourcesPopover = false; showDisplayPopover = false; showFramePopover = false; showModePopover = false; showCanvasPopover = false; showPresetsPopover = false }
        }
    }
    private var embeddedPreviewSize: CGSize {
        let ratio = model.previewRatio()
        var width: CGFloat = 540
        var height = width / ratio
        if height > 400 {
            height = 400
            width = height * ratio
        }
        return CGSize(width: width, height: height)
    }
    private func configureFramelessWindow(_ window: NSWindow) {
        if !window.styleMask.contains(.fullSizeContentView)
            || window.styleMask.contains(.resizable) {
            window.styleMask.remove(.resizable)
            window.styleMask.insert(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.isMovableByWindowBackground = true
        model.registerPanelWindow(window)
    }
    private var header: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                Circle()
                    .fill(model.isSharing ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isSharing ? "Stream Running" : (model.mode == .allow && model.selectedWindowIDs.isEmpty && model.activeFile == nil ? "Nothing is currently selected to share" : "Stream Stopped"))
                    .font(.subheadline).bold()
                Text("\(model.appCount) apps • \(model.sources.count) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
            Spacer()
            Button {
                model.toggleCaptureAreaWindow()
            } label: {
                Label(model.isCaptureAreaVisible ? "Capture Area" : "Hidden",
                      systemImage: model.isCaptureAreaVisible ? "eye.fill" : "eye.slash")
                    .font(.caption)
                    .foregroundStyle(model.isCaptureAreaVisible ? Color.blue : Color.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .pointingHandOnHover()
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPaused ? Color.green : Color.orange)
            .help(model.isPaused ? "Resume" : "Pause")
            .pointingHandOnHover()
            .disabled(!model.isSharing)
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button {
            } label: {
                Image(systemName: "info.circle")
                    .padding(6)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .pointingHandOnHover()
            .help(model.isCaptureAreaVisible ? "Output is visible" : "Output is hidden")
        }
        .background(WindowDragView())
    }
    @ViewBuilder
    private var presetStrip: some View {
        if model.isSharing, !model.presets.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Scene / Preset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(model.presets) { preset in
                            if model.activePresetID == preset.id {
                                HStack(spacing: 4) {
                                    Button {
                                        model.applyPreset(preset)
                                    } label: {
                                        Text(preset.name)
                                            .padding(.leading, 10)
                                            .padding(.trailing, 4)
                                            .padding(.vertical, 6)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentColor)
                                    .pointingHandOnHover()
                                    Button {
                                        model.clearActivePreset()
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .bold()
                                            .padding(.leading, 8)
                                            .padding(.trailing, 12)
                                            .padding(.vertical, 8)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.primary)
                                    .help("Clear preset selection")
                                    .pointingHandOnHover()
                                }
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.black.opacity(0.45))
                                )
                            } else {
                                Button {
                                    model.applyPreset(preset)
                                } label: {
                                    Text(preset.name)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.black.opacity(0.45))
                                        )
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(model.activePresetID == preset.id ? Color.accentColor : Color.primary)
                                .pointingHandOnHover()
                            }
                        }
                    }
                }
            }
        }
    }
    private var popupGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 6) {
            gridButton(title: "Preview", subtitle: model.isPreviewVisible ? "Visible" : "Hidden", icon: "eye", tint: model.isPreviewVisible ? Color.accentColor : nil) {
                model.togglePreviewWindow()
            }
            gridButton(title: "Sources", subtitle: model.canvasMode == .fullDisplay ? "Disabled" : "\(model.sourceRuleCount) rules", icon: "list.bullet", disabled: model.canvasMode == .fullDisplay) { showSourcesPopover.toggle() }
                .popover(isPresented: $showSourcesPopover, arrowEdge: .top) {
                    sourcesPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Display", subtitle: model.displaySubtitle, icon: "display") { showDisplayPopover.toggle() }
                .popover(isPresented: $showDisplayPopover, arrowEdge: .bottom) {
                    displayPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Frame", subtitle: model.canvasMode == .fullDisplay ? "Disabled" : (model.framing == .full ? "Screen" : "Dynamic"), icon: "rectangle", disabled: model.canvasMode == .fullDisplay) { showFramePopover.toggle() }
                .popover(isPresented: $showFramePopover, arrowEdge: .bottom) {
                    framingPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: model.isPanic ? "Play" : "Panic", subtitle: model.isPanic ? "Output Off" : "Blank now", icon: model.isPanic ? "play.fill" : "hand.raised", tint: model.isPanic ? .green : .red) {
                model.togglePanic()
            }
            gridButton(title: "Mode", subtitle: model.canvasMode == .fullDisplay ? "Disabled" : (model.mode == .allow ? "Allow List" : "Block List"), icon: "switch.2", disabled: model.canvasMode == .fullDisplay) { showModePopover.toggle() }
                .popover(isPresented: $showModePopover, arrowEdge: .bottom) {
                    modePopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Canvas", subtitle: model.canvasMode == .fullDisplay ? "Full Desktop" : (model.canvasBackground == .custom ? "Image" : model.canvasBackground.rawValue.capitalized), icon: "photo") { showCanvasPopover.toggle() }
                .popover(isPresented: $showCanvasPopover, arrowEdge: .bottom) {
                    canvasPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Presets", subtitle: model.activePreset?.name ?? "Choose", icon: "bookmark") { showPresetsPopover.toggle() }
                .popover(isPresented: $showPresetsPopover, arrowEdge: .bottom) {
                    presetsPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Camera", subtitle: model.cameraEnabled ? model.cameraPosition.label : "Off", icon: "video") { showCameraPopover.toggle() }
                .popover(isPresented: $showCameraPopover, arrowEdge: .bottom) {
                    cameraPopup
                        .preferredColorScheme(.dark)
                }
            gridButton(title: "Quit", subtitle: "Exit app", icon: "power", tint: .red) {
                showQuitConfirmation = true
            }
        }
    }
    private var quitConfirmationView: some View {
        ZStack {
            Button {
                showQuitConfirmation = false
            } label: {
                Color.black.opacity(0.45)
            }
            .buttonStyle(.plain)
            VStack(spacing: 12) {
                Image(systemName: "power")
                    .font(.title)
                    .foregroundStyle(.red)
                Text("Quit Veil?")
                    .font(.headline)
                Text(model.isSharing
                     ? "The stream is running. Quitting will stop the stream and close Output."
                     : "Are you sure you want to quit Veil?")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 8) {
                    Button {
                        showQuitConfirmation = false
                    } label: {
                        Text("Cancel")
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.black.opacity(0.45))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .keyboardShortcut(.escape, modifiers: [])
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        Text("Quit")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                }
            }
            .padding(20)
            .frame(width: 300)
            .background(
                ZStack {
                    VisualEffectView(material: .hudWindow)
                    Color.black.opacity(0.25)
                }
            )
            .preferredColorScheme(.dark)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 8)
        }
    }
    private func gridButton(title: String, subtitle: String, icon: String, tint: Color? = nil, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title).font(.caption)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(tint ?? .secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 60)
            .foregroundStyle(tint ?? .primary)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pointingHandOnHover()
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }
    private func popupButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        gridButton(title: title, subtitle: "", icon: icon, action: action)
    }
    private func popupHeader(_ title: String) -> some View {
        HStack {
            Text(title).font(.headline)
            Spacer()
            Button {
                popup = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .contentShape(Circle())
            .pointingHandOnHover()
            .help("Close")
        }
    }
    private func statusPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption).bold()
            .lineLimit(1)
            .foregroundStyle(color == .gray ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color == .gray ? Color.white.opacity(0.15) : color.opacity(0.2)))
    }
    private func smallPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.caption)
            .lineLimit(1)
            .foregroundStyle(color == .gray ? .white : color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color == .gray ? Color.white.opacity(0.15) : color.opacity(0.2)))
    }
    private func sourceCheckbox(selected: Bool, partial: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : Color.white.opacity(0.2))
                .frame(width: 20, height: 20)
            if selected {
                Image(systemName: "checkmark").font(.caption).bold().foregroundStyle(.white)
            } else if partial {
                Image(systemName: "minus").font(.caption).bold().foregroundStyle(.white)
            }
        }
    }
    private var sourcesPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Search apps or windows", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.12), lineWidth: 1))
                Button("Reset All Sources") { model.resetAllSources() }
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                    .buttonStyle(.plain)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .pointingHandOnHover()
            }
            Text(model.visibleSources.isEmpty
                 ? (model.sources.isEmpty ? model.status : "No matching windows for this search.")
                 : "\(model.appCount) apps • \(model.sources.count) windows ready. Expand an app to fine-tune the shared windows.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            if model.visibleSources.isEmpty {
                Text(model.sources.isEmpty ? "No on-screen windows found. Bring an app forward, reopen Sources, and check Screen Recording permission if the list stays empty." : "No Matching Sources")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.groupedSources, id: \.app) { group in
                            let allSelected = group.items.allSatisfy { model.selectedWindowIDs.contains($0.id) }
                            let noneSelected = group.items.allSatisfy { !model.selectedWindowIDs.contains($0.id) }
                            let appShown = group.items.contains { model.isWindowShown($0.id) }
                            let appActive = group.items.contains { $0.isActive }
                            let isExpanded = !model.searchText.isEmpty || expandedApps.contains(group.app)
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 10) {
                                    Button {
                                        if expandedApps.contains(group.app) {
                                            expandedApps.remove(group.app)
                                        } else {
                                            expandedApps.insert(group.app)
                                        }
                                    } label: {
                                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                            .font(.subheadline)
                                            .frame(width: 28, height: 28)
                                            .background(Circle().fill(Color.white.opacity(0.12)))
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Circle())
                                    .pointingHandOnHover()
                                    Button {
                                        model.toggleApp(group.app)
                                    } label: {
                                        sourceCheckbox(selected: allSelected, partial: !allSelected && !noneSelected)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(RoundedRectangle(cornerRadius: 6))
                                    .pointingHandOnHover()
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(group.app).font(.subheadline).bold().lineLimit(1)
                                        Text(appActive ? "Currently focused" : "On screen")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 6) {
                                        HStack(spacing: 6) {
                                            Text(group.items.count == 1 ? "1 window" : "\(group.items.count) windows")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(Capsule().fill(Color.white.opacity(0.15)))
                                            statusPill(appShown ? "Shown" : "Hidden", appShown ? .green : .gray)
                                        }
                                        .fixedSize()
                                        if appActive {
                                            statusPill("Active", .blue)
                                        }
                                    }
                                }
                                if isExpanded {
                                    Divider()
                                    VStack(alignment: .leading, spacing: 8) {
                                        ForEach(group.items) { item in
                                            Button {
                                                model.toggleSource(item.id)
                                            } label: {
                                                HStack(spacing: 10) {
                                                    sourceCheckbox(selected: model.selectedWindowIDs.contains(item.id), partial: false)
                                                    VStack(alignment: .leading, spacing: 4) {
                                                        Text(item.title).font(.subheadline).lineLimit(1)
                                                        if item.isActive {
                                                            smallPill("Focused", .blue)
                                                        }
                                                    }
                                                    Spacer()
                                                    statusPill(model.isWindowShown(item.id) ? "Shown" : "Hidden", model.isWindowShown(item.id) ? .green : .gray)
                                                }
                                                .padding(10)
                                                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
                                            }
                                            .buttonStyle(.plain)
                                            .contentShape(RoundedRectangle(cornerRadius: 12))
                                            .pointingHandOnHover()
                                        }
                                    }
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.25)))
                            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("File PDF / PPT").font(.subheadline).bold()
                Text("PDF: full pages. PPT/PPTX: first slide (QuickLook).")
                    .font(.caption).foregroundStyle(.secondary)
                if let active = model.activeFile {
                    Text("Presenting: \(active.name)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if !model.fileSources.isEmpty {
                    Text("\(model.fileSources.count) files in this preset. Select a source to start sharing and open the file controller.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("No files yet.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if model.choosePresentationFile() { popup = nil; showSourcesPopover = false }
                } label: {
                    Label("Choose PDF / PPT", systemImage: "doc")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.45))
                )
                .contentShape(RoundedRectangle(cornerRadius: 10))
                .pointingHandOnHover()
            }
        }
        .padding(12)
        .frame(width: 420, height: 440)
        .onAppear {
            for group in model.groupedSources where group.items.contains(where: { model.selectedWindowIDs.contains($0.id) }) {
                expandedApps.insert(group.app)
            }
            model.refreshSources()
        }
    }
    private func displayName(for display: SCDisplay) -> String {
        if let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID }),
           !screen.localizedName.isEmpty {
            return screen.localizedName
        }
        return "Display \(display.displayID)"
    }
    private func displayRadio(selected: Bool, accent: Color = .accentColor) -> some View {
        ZStack {
            Circle().fill(selected ? accent : Color.clear)
            Circle().stroke(selected ? accent : Color.white.opacity(0.4), lineWidth: 1.5)
            if selected {
                Image(systemName: "checkmark").font(.caption).bold().foregroundStyle(.white)
            }
        }
        .frame(width: 20, height: 20)
    }
    private func optionCard(selected: Bool, title: String, subtitle: String, accent: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                displayRadio(selected: selected, accent: accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline).bold().lineLimit(1)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                }
                Spacer()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(selected ? accent.opacity(0.12) : Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? accent.opacity(0.7) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .pointingHandOnHover()
    }
    private func backgroundCard(selected: Bool, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                displayRadio(selected: selected, accent: .red)
                Text(title).font(.subheadline).bold().lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Color.red.opacity(0.12) : Color.black.opacity(0.25)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? Color.red.opacity(0.7) : Color.white.opacity(0.08), lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .pointingHandOnHover()
    }
    private func selectDisplay(_ id: UInt32?) {
        model.selectedDisplayID = id
        if model.isSharing {
            if id == nil {
                model.stopCapture(keepSharing: true)
                model.status = "Pause the output until a display is selected."
            } else {
                model.updateCapture()
            }
        } else if id != nil {
            model.stopSnapshotStream()
            model.startCapture()
        } else {
            model.stopSnapshotStream()
            model.status = "Pause the output until a display is selected."
        }
    }
    private var displayPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Display").font(.headline).bold()
            optionCard(selected: model.selectedDisplayID == nil, title: "No Display", subtitle: "Pause the output until a display is selected.") {
                selectDisplay(nil)
            }
            ForEach(model.displays, id: \.displayID) { display in
                optionCard(selected: display.displayID == model.selectedDisplayID, title: displayName(for: display), subtitle: "\(display.width) x \(display.height)") {
                    selectDisplay(display.displayID)
                }
            }
            if model.displays.isEmpty {
                Text("No displays found. Check Screen Recording permission, then reopen this popup.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
    private func selectFraming(_ framing: Framing) {
        model.framing = framing
        model.resizeCaptureAreaWindow()
        if model.isSharing {
            model.updateCapture()
        } else {
            model.stopSnapshotStream()
            model.refreshPreviewSnapshot()
            model.startPreviewSnapshotTimer()
        }
    }
    private var framingPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame Style").font(.headline).bold()
            optionCard(selected: model.framing == .full, title: "Screen", subtitle: "Use the full selected display as the output canvas.") {
                selectFraming(.full)
            }
            optionCard(selected: model.framing == .dynamic, title: "Dynamic", subtitle: "Automatically crop the output to the outer bounds of the shared windows on the selected display.") {
                selectFraming(.dynamic)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
    private func selectMode(_ mode: ShareMode) {
        model.mode = mode
        if model.isSharing {
            model.updateCapture()
        } else {
            model.stopSnapshotStream()
            model.refreshPreviewSnapshot()
            model.startPreviewSnapshotTimer()
        }
    }
    private var modePopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Visibility Mode").font(.headline).bold()
            optionCard(selected: model.mode == .allow, title: "Allow List", subtitle: "Only checked apps and windows appear in Output.") {
                selectMode(.allow)
            }
            optionCard(selected: model.mode == .block, title: "Block List", subtitle: "Everything on the selected display appears except checked apps and windows.") {
                selectMode(.block)
            }
        }
        .padding(12)
        .frame(width: 360)
    }
    private func selectCanvasMode(_ mode: CanvasMode) {
        model.canvasMode = mode
        if model.filePreviewImage != nil {
            model.updateSourceAspectRatioFromSelection()
            model.resizeCaptureAreaWindow()
        } else if model.isSharing {
            model.updateSourceAspectRatio()
            model.updateCapture()
        } else {
            model.stopSnapshotStream()
            model.startCapture()
        }
    }
    private func selectBackground(_ background: CanvasBackground) {
        if background == .custom, model.canvasImage == nil || model.canvasBackground == .custom {
            pickCanvasImage()
        } else {
            model.canvasBackground = background
        }
    }
    private var canvasPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Canvas").font(.headline).bold()
            Text("Choose whether Output shows the full desktop or places isolated windows on a background canvas.")
                .font(.caption).foregroundStyle(Color.white.opacity(0.85))
            Text("Output").font(.subheadline).bold()
            optionCard(selected: model.canvasMode == .isolated, title: "Sanitized Windows", subtitle: "Only the selected apps and windows appear in Output.", accent: .red) {
                selectCanvasMode(.isolated)
            }
            optionCard(selected: model.canvasMode == .fullDisplay, title: "Full Desktop", subtitle: "Share the full selected display while still excluding Veil windows from the output.", accent: .red) {
                selectCanvasMode(.fullDisplay)
            }
            if model.canvasMode == .isolated {
                Text("Background").font(.subheadline).bold()
                HStack(spacing: 6) {
                    backgroundCard(selected: model.canvasBackground == .black, title: "Black") {
                        selectBackground(.black)
                    }
                    backgroundCard(selected: model.canvasBackground == .white, title: "White") {
                        selectBackground(.white)
                    }
                    backgroundCard(selected: model.canvasBackground == .gray, title: "Gray") {
                        selectBackground(.gray)
                    }
                }
                optionCard(selected: model.canvasBackground == .custom, title: "Custom Image", subtitle: "Place isolated windows over an image that you choose or drag in.", accent: .red) {
                    selectBackground(.custom)
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }
    private func pickCanvasImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .image]
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            model.canvasImage = image
            model.canvasBackground = .custom
        }
    }
    private var customPresets: [Preset] {
        model.presets.filter { !$0.isBuiltIn }
    }
    private var builtInPresets: [Preset] {
        model.presets.filter { $0.isBuiltIn }
    }
    private func presetPill(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Color.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.white.opacity(0.15)))
    }
    private func presetCard(_ preset: Preset) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if renamingPresetID == preset.id {
                    TextField("Preset name", text: $renamingName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if model.renamePreset(preset, to: renamingName) { renamingPresetID = nil }
                        }
                    Button {
                        if model.renamePreset(preset, to: renamingName) { renamingPresetID = nil }
                    } label: {
                        Label("Confirm rename", systemImage: "checkmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                    .help("Confirm rename")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                    Button { renamingPresetID = nil } label: {
                        Label("Cancel rename", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .labelStyle(.iconOnly)
                    .help("Cancel rename")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                } else {
                    Image(systemName: preset.isBuiltIn ? (preset.name == "Presentation" ? "rectangle.on.rectangle" : "person.2") : "bookmark")
                        .foregroundStyle(Color.white)
                    Text(preset.name).font(.subheadline).bold().lineLimit(1)
                    Spacer()
                    if !preset.isBuiltIn {
                        Menu {
                            Button("Move Up") { model.movePreset(preset, up: true) }
                                .disabled(customPresets.first?.id == preset.id)
                            Button("Move Down") { model.movePreset(preset, up: false) }
                                .disabled(customPresets.last?.id == preset.id)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "arrow.up.arrow.down.circle")
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white)
                        .help("Reorder preset")
                        .contentShape(Rectangle())
                        .pointingHandOnHover()
                        Menu {
                            Button("Rename") {
                                renamingPresetID = preset.id
                                renamingName = preset.name
                            }
                            Button("Delete", role: .destructive) { model.deletePreset(preset) }
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "ellipsis.circle")
                                Image(systemName: "chevron.down").font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.white)
                        .help("Preset actions")
                        .contentShape(Rectangle())
                        .pointingHandOnHover()
                    }
                }
            }
            HStack(spacing: 6) {
                presetPill(preset.isBuiltIn ? "Default" : "Custom")
                presetPill(preset.canvasMode == .isolated ? "Sanitized" : "Full Desktop")
                presetPill(preset.framing == .full ? "Screen" : "Dynamic")
            }
            Text("\(model.fileSourceLabel(for: preset) ?? (preset.selectedWindowIDs.isEmpty ? "Nothing is currently selected" : "\(preset.selectedWindowIDs.count) windows selected")) • Frame \(preset.framing == .full ? "Screen" : "Dynamic")")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(2)
            Text("\(preset.isBuiltIn ? "Built-in" : "Custom") preset slot ready")
                .font(.caption)
                .bold()
                .foregroundStyle(Color.white.opacity(0.85))
            HStack(spacing: 8) {
                Button("Apply") { model.applyPreset(preset) }
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.red))
                    .buttonStyle(.plain)
                    .help("Apply preset")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                Button("Save Current") { model.replacePreset(preset) }
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .buttonStyle(.plain)
                    .help("Save the current setup into this preset")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                Button("Reset") { model.resetPreset(preset) }
                    .font(.subheadline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .buttonStyle(.plain)
                    .help("Reset preset to default")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                    .disabled(model.isDefaultPreset(preset))
                    .opacity(model.isDefaultPreset(preset) ? 0.5 : 1.0)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.25)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
    private var presetsPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Presets").font(.headline).bold()
                Spacer()
                Button { model.saveCurrentAsPreset(named: "") } label: {
                    Label("New Preset", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .help("Save the current setup as a new preset")
                .contentShape(Rectangle())
                .pointingHandOnHover()
            }
            Text("New Preset saves the current setup as a new preset. Custom presets can be reordered.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Custom Presets").font(.subheadline).bold()
                        Spacer()
                        Text("\(customPresets.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    if customPresets.isEmpty {
                        Text("No custom presets yet. Tap New Preset to save the current setup as a new preset.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(customPresets) { preset in
                            presetCard(preset)
                        }
                    }
                    Text("Built-in Presets").font(.subheadline).bold()
                    ForEach(builtInPresets) { preset in
                        presetCard(preset)
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 360, height: 440)
    }
    private var cameraDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
    }
    private var cameraDeviceName: String {
        if let id = model.cameraDeviceID, let device = cameraDevices.first(where: { $0.uniqueID == id }) {
            return device.localizedName
        }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) ?? AVCaptureDevice.default(for: .video) {
            return device.localizedName
        }
        return "No camera found"
    }
    private var cameraTeal: Color {
        Color(red: 0.36, green: 0.88, blue: 0.78)
    }
    private var cameraPopup: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera Overlay").font(.headline).bold()
            Text("Overlay your camera feed on the screen sharing output. Choose position, shape, and margins.")
                .font(.caption)
                .foregroundStyle(Color.white.opacity(0.85))
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Image(systemName: "camera.fill")
                    .foregroundStyle(cameraTeal)
                Text("Enable Camera Overlay").font(.subheadline).bold()
                Spacer()
                Button { model.cameraEnabled.toggle() } label: {
                    ZStack(alignment: model.cameraEnabled ? .trailing : .leading) {
                        RoundedRectangle(cornerRadius: 11)
                            .fill(model.cameraEnabled ? Color.red : Color.white.opacity(0.2))
                            .frame(width: 36, height: 22)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                            .padding(3)
                    }
                }
                .buttonStyle(.plain)
                .help(model.cameraEnabled ? "Turn camera overlay off" : "Turn camera overlay on")
                .contentShape(Rectangle())
                .pointingHandOnHover()
                .animation(.easeInOut, value: model.cameraEnabled)
            }
            Text("Camera Source").font(.subheadline).bold()
            Menu {
                if cameraDevices.isEmpty {
                    Button("No cameras available") {}
                        .disabled(true)
                } else {
                    ForEach(cameraDevices, id: \.uniqueID) { device in
                        Button {
                            model.cameraDeviceID = device.uniqueID
                        } label: {
                            HStack {
                                Text(device.localizedName)
                                if model.cameraDeviceID == device.uniqueID {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(cameraDeviceName)
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Choose a camera")
            .contentShape(Rectangle())
            .pointingHandOnHover()
            Text("Position").font(.subheadline).bold()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                ForEach(CameraPosition.allCases, id: \.self) { position in
                    Button { model.cameraPosition = position } label: {
                        VStack(spacing: 4) {
                            Image(systemName: position.icon)
                                .font(position == .middleCenter ? .caption : .body)
                                .foregroundStyle(Color.white)
                            Text(position.label)
                                .font(.subheadline)
                                .foregroundStyle(Color.white)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(model.cameraPosition == position ? cameraTeal : Color.black.opacity(0.25)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.cameraPosition == position ? cameraTeal : Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(position.label)
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                }
            }
            Text("Shape").font(.subheadline).bold()
            HStack(spacing: 8) {
                ForEach(CameraShape.allCases, id: \.self) { shape in
                    Button { model.cameraShape = shape } label: {
                        VStack(spacing: 8) {
                            Group {
                                if shape == .circle {
                                    Circle().stroke(model.cameraShape == shape ? cameraTeal : Color.white, lineWidth: 2)
                                } else if shape == .square {
                                    Rectangle().stroke(model.cameraShape == shape ? cameraTeal : Color.white, lineWidth: 2)
                                } else {
                                    RoundedRectangle(cornerRadius: 10).stroke(model.cameraShape == shape ? cameraTeal : Color.white, lineWidth: 2)
                                }
                            }
                            .frame(width: 40, height: 40)
                            Text(shape.rawValue)
                                .font(.subheadline)
                                .foregroundStyle(model.cameraShape == shape ? cameraTeal : Color.white)
                        }
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 12).fill(model.cameraShape == shape ? cameraTeal.opacity(0.2) : Color.black.opacity(0.45)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.cameraShape == shape ? cameraTeal : Color.white.opacity(0.08), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .help(shape.rawValue)
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                }
            }
            Button { model.cameraMirrored.toggle() } label: {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                            .frame(width: 20, height: 20)
                        if model.cameraMirrored {
                            Image(systemName: "checkmark")
                                .font(.caption)
                                .bold()
                                .foregroundStyle(cameraTeal)
                        }
                    }
                    Text("Mirror Video")
                        .font(.subheadline)
                        .foregroundStyle(Color.white)
                }
            }
            .buttonStyle(.plain)
            .help("Mirror video")
            .contentShape(Rectangle())
            .pointingHandOnHover()
            Text("Size (\(Int((model.cameraSize / 110 * 100).rounded()))%)").font(.subheadline).bold()
            Slider(value: $model.cameraSize, in: 55...330, step: 11)
                .tint(.red)
            HStack {
                ForEach(0..<12, id: \.self) { _ in
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 3, height: 3)
                    if true {
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 4)
            if model.cameraPosition != .middleCenter {
                Text("Margins").font(.subheadline).bold()
                VStack(spacing: 12) {
                    if model.cameraPosition == .topLeft || model.cameraPosition == .topCenter || model.cameraPosition == .topRight {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up").foregroundStyle(Color.white.opacity(0.7))
                            Text("Top").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 70, alignment: .leading)
                            Slider(value: $model.cameraMarginVertical, in: 0...100, step: 1)
                                .tint(.red)
                            Text("\(Int(model.cameraMarginVertical))px").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 50, alignment: .trailing)
                        }
                    }
                    if model.cameraPosition == .bottomLeft || model.cameraPosition == .bottomCenter || model.cameraPosition == .bottomRight {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down").foregroundStyle(Color.white.opacity(0.7))
                            Text("Bottom").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 70, alignment: .leading)
                            Slider(value: $model.cameraMarginVertical, in: 0...100, step: 1)
                                .tint(.red)
                            Text("\(Int(model.cameraMarginVertical))px").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 50, alignment: .trailing)
                        }
                    }
                    if model.cameraPosition == .topLeft || model.cameraPosition == .middleLeft || model.cameraPosition == .bottomLeft {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.left").foregroundStyle(Color.white.opacity(0.7))
                            Text("Left").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 70, alignment: .leading)
                            Slider(value: $model.cameraMarginHorizontal, in: 0...100, step: 1)
                                .tint(.red)
                            Text("\(Int(model.cameraMarginHorizontal))px").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 50, alignment: .trailing)
                        }
                    }
                    if model.cameraPosition == .topRight || model.cameraPosition == .middleRight || model.cameraPosition == .bottomRight {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right").foregroundStyle(Color.white.opacity(0.7))
                            Text("Right").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 70, alignment: .leading)
                            Slider(value: $model.cameraMarginHorizontal, in: 0...100, step: 1)
                                .tint(.red)
                            Text("\(Int(model.cameraMarginHorizontal))px").font(.subheadline).bold().foregroundStyle(Color.white).frame(width: 50, alignment: .trailing)
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
        }
        .padding(12)
        .frame(width: 360)
    }
}
struct PreviewFileControls: View {
    var buttonSize: CGFloat = 36
    @EnvironmentObject var model: VeilModel
    @State private var showFilePopup = false
    var body: some View {
        if let active = model.activeFile {
            HStack(spacing: 2) {
                Button {
                    model.previousFilePage()
                } label: {
                    Color.white.opacity(0.01)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "chevron.left")
                                .font(.subheadline)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(model.filePageIndex == 0)
                .help("Previous page")
                .pointingHandOnHover()
                Text("\(model.filePageIndex + 1)/\(active.pageCount)")
                    .font(.subheadline).bold()
                    .frame(minWidth: 44)
                Button {
                    model.nextFilePage()
                } label: {
                    Color.white.opacity(0.01)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "chevron.right")
                                .font(.subheadline)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .disabled(model.filePageIndex + 1 >= active.pageCount)
                .help("Next page")
                .pointingHandOnHover()
                Button {
                    showFilePopup = true
                } label: {
                    Color.white.opacity(0.01)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "folder")
                                .font(.subheadline)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Choose file")
                .pointingHandOnHover()
                .popover(isPresented: $showFilePopup) {
                    FileListPopupView(showFilePopup: $showFilePopup)
                        .environmentObject(model)
                }
                Button {
                    model.closeFile()
                    model.clearActivePreset()
                } label: {
                    Color.white.opacity(0.01)
                        .frame(width: buttonSize, height: buttonSize)
                        .contentShape(Rectangle())
                        .overlay(
                            Image(systemName: "xmark")
                                .font(.subheadline)
                        )
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
                .help("Close file")
                .pointingHandOnHover()
            }
            .padding(.horizontal, 4)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .foregroundStyle(.white)
        }
    }
}
struct FileListPopupView: View {
    @EnvironmentObject var model: VeilModel
    @Binding var showFilePopup: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Files").font(.subheadline).bold()
            Text("PDF: full pages. PPT/PPTX: first slide (QuickLook).")
                .font(.caption).foregroundStyle(.secondary)
            if model.fileSources.isEmpty {
                Text("No files yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.fileSources) { file in
                HStack(spacing: 6) {
                    Button {
                        model.activateFile(file)
                        showFilePopup = false
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.activeFileID == file.id ? "doc.fill" : "doc")
                            Text(file.name).lineLimit(1)
                            if model.activeFileID == file.id {
                                Image(systemName: "checkmark")
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.activeFileID == file.id ? Color.accentColor : Color.primary)
                    .help("Show this file")
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                    Button {
                        model.removeFile(file)
                    } label: {
                        Image(systemName: "xmark")
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Delete file")
                    .contentShape(Circle())
                    .pointingHandOnHover()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.45)))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            Button {
                model.openFilePicker()
            } label: {
                Label("Add File", systemImage: "plus")
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.45))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .pointingHandOnHover()
        }
        .padding(14)
        .frame(width: 320)
    }
}
struct PreviewContentView: View {
    @EnvironmentObject var model: VeilModel
    var body: some View {
        ZStack(alignment: .topLeading) {
            OutputContentView(isPreview: true)
                .environmentObject(model)
            Text("PREVIEW")
                .font(.caption2).bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(10)
            WindowDragView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            VStack {
                Spacer()
                HStack {
                    if model.cameraPosition.isLeftSide {
                        Spacer()
                    }
                    PreviewFileControls(buttonSize: 28)
                        .environmentObject(model)
                        .padding(.leading, 10)
                    if !model.cameraPosition.isLeftSide {
                        Spacer()
                    }
                    Button {
                        model.cameraEnabled.toggle()
                    } label: {
                        Image(systemName: model.cameraEnabled ? "video.fill" : "video.slash.fill")
                            .font(.subheadline)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(model.cameraEnabled ? Color(red: 0.45, green: 0.80, blue: 0.60) : Color(red: 0.90, green: 0.55, blue: 0.55)))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .pointingHandOnHover()
                    .help(model.cameraEnabled ? "Turn camera overlay off" : "Turn camera overlay on")
                    .padding(10)
                }
            }
        }
        .onChange(of: model.sourceAspectRatio) { _, _ in
            model.resizeCaptureAreaWindow()
        }
    }
}
struct CaptureAreaRootView: View {
    @EnvironmentObject var model: VeilModel
    var body: some View {
        OutputContentView()
            .environmentObject(model)
            .overlay(WindowDragView(resizable: true))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .onAppear {
                model.resizeCaptureAreaWindow()
            }
    }
}
struct OutputContentView: View {
    @EnvironmentObject var model: VeilModel
    var isPreview: Bool = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if model.isPanic {
                    Color.black
                    if isPreview {
                        VStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("Veil Output is Blank")
                                .font(.headline).bold()
                                .foregroundStyle(.white)
                            Text("Panic Hide is active. Resume output when you are ready to share again.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 20)
                    }
                } else {
                    backgroundView
                    mainImageView(outputSize: geometry.size)
                }
            }
            .overlay(alignment: model.cameraPosition.alignment) {
                if !model.isPanic, model.cameraEnabled {
                    cameraOverlay(outputWidth: geometry.size.width)
                }
            }
        }
        .onChange(of: model.sourceAspectRatio) { _, _ in
            model.resizeCaptureAreaWindow()
        }
        .onChange(of: model.previewRatio()) { _, _ in
            model.resizeCaptureAreaWindow()
        }
        .onChange(of: model.previewRenderedRatio) { _, _ in
            model.resizeCaptureAreaWindow()
        }
    }
    private var backgroundView: some View {
        Group {
            if model.filePreviewImage != nil {
                Color.white
            } else if model.canvasBackground == .custom, let image = model.canvasImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                model.canvasBackground.color
            }
        }
        .ignoresSafeArea()
    }
    @ViewBuilder
    private func canvasImage(_ image: NSImage) -> some View {
        if model.isFullscreenCanvas || model.canvasMode == .fullDisplay {
            Image(nsImage: image)
                .resizable()
                .interpolation(isPreview ? .low : .medium)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
        } else {
            Image(nsImage: image)
                .resizable()
                .interpolation(isPreview ? .low : .medium)
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    @ViewBuilder
    private func positionedImage(_ image: NSImage, outputSize: CGSize) -> some View {
        if let frame = model.positionedImageFrame(in: outputSize) {
            ZStack(alignment: .topLeading) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(isPreview ? .low : .medium)
                    .scaledToFit()
                    .frame(width: frame.width, height: frame.height)
                    .offset(x: frame.origin.x, y: frame.origin.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
        } else {
            canvasImage(image)
        }
    }
    private func fitSize(in size: CGSize, aspect: CGFloat, padding: CGFloat) -> CGSize {
        let availableWidth = max(0, size.width - padding * 2)
        let availableHeight = max(0, size.height - padding * 2)
        guard aspect > 0, availableWidth > 0, availableHeight > 0 else { return .zero }
        let width = min(availableWidth, availableHeight * aspect)
        return CGSize(width: width, height: width / aspect)
    }
    @ViewBuilder
    private func mainImageView(outputSize: CGSize) -> some View {
        if let fileImage = model.filePreviewImage {
            if model.canvasMode == .isolated {
                Image(nsImage: fileImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(8)
            } else {
                Image(nsImage: fileImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.shouldShowStreamPreview {
            if model.isPositionedCanvas {
                if let frame = model.positionedImageFrame(in: outputSize) {
                    ZStack(alignment: .topLeading) {
                        DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resize)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.origin.x, y: frame.origin.y)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .clipped()
                } else {
                    DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resizeAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            } else if model.canvasMode == .isolated {
                if model.framing == .dynamic {
                    if let imageSize = model.dynamicImageSize(in: outputSize) {
                        DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resize)
                            .frame(width: imageSize.width, height: imageSize.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resizeAspect)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resize)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            } else {
                DirectStreamView(layer: isPreview ? StreamDisplayLayers.shared.preview : StreamDisplayLayers.shared.output, gravity: .resize)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        } else if !model.isSharing, let image = model.previewSnapshotImage {
            if model.isPositionedCanvas {
                positionedImage(image, outputSize: outputSize)
            } else if model.canvasMode == .isolated {
                if model.framing == .dynamic {
                    if let imageSize = model.dynamicImageSize(in: outputSize) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(isPreview ? .low : .medium)
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(isPreview ? .low : .medium)
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(isPreview ? .low : .medium)
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                canvasImage(image)
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(model.selectedWindowIDs.isEmpty ? "No preview yet. Select a source or show a file." : "Loading preview…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    private func cameraInsets(vertical: CGFloat, horizontal: CGFloat) -> EdgeInsets {
        switch model.cameraPosition {
        case .topLeft: return EdgeInsets(top: vertical, leading: horizontal, bottom: 0, trailing: 0)
        case .topCenter: return EdgeInsets(top: vertical, leading: 0, bottom: 0, trailing: 0)
        case .topRight: return EdgeInsets(top: vertical, leading: 0, bottom: 0, trailing: horizontal)
        case .middleLeft: return EdgeInsets(top: 0, leading: horizontal, bottom: 0, trailing: 0)
        case .middleCenter: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        case .middleRight: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: horizontal)
        case .bottomLeft: return EdgeInsets(top: 0, leading: horizontal, bottom: vertical, trailing: 0)
        case .bottomCenter: return EdgeInsets(top: 0, leading: 0, bottom: vertical, trailing: 0)
        case .bottomRight: return EdgeInsets(top: 0, leading: 0, bottom: vertical, trailing: horizontal)
        }
    }
    @ViewBuilder
    private func cameraOverlay(outputWidth: CGFloat) -> some View {
        let referenceWidth: CGFloat = 960
        let scale = outputWidth > 0 ? outputWidth / referenceWidth : 1
        let relativeSize = model.cameraSize * scale
        let verticalMargin = model.cameraMarginVertical * scale
        let horizontalMargin = model.cameraMarginHorizontal * scale
        let insets = cameraInsets(vertical: verticalMargin, horizontal: horizontalMargin)
        Group {
            if model.cameraShape == .circle {
                CameraOverlayView(mirrored: model.cameraMirrored, deviceID: model.cameraDeviceID)
                    .frame(width: relativeSize, height: relativeSize)
                    .clipShape(Circle())
            } else if model.cameraShape == .square {
                CameraOverlayView(mirrored: model.cameraMirrored, deviceID: model.cameraDeviceID)
                    .frame(width: relativeSize, height: relativeSize)
                    .clipShape(Rectangle())
            } else {
                CameraOverlayView(mirrored: model.cameraMirrored, deviceID: model.cameraDeviceID)
                    .frame(width: relativeSize, height: relativeSize)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
        .padding(insets)
    }
}
