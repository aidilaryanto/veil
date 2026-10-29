import AppKit
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
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
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

// MARK: - Jendela kontrol utama (control bar, grid 5x2)

struct ContentView: View {
    @EnvironmentObject var model: VeilModel
    @State private var popup: PopupKind?
    @State private var newPresetName = ""
    // Konfirmasi Quit: bukan NSAlert / sheet sistem (yang
    // tampilannya tidak dark transparent), melainkan overlay
    // kartu di dalam panel utama — jadi gaya persis panel:
    // blur hudWindow + hitam 0.25, rounded 20, stroke putih.
    @State private var showQuitConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowDragView()
                .frame(height: 28)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 40, height: 4)
                        .allowsHitTesting(false)
                )
            header
            presetStrip
            popupGrid
        }
        .padding(16)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                VisualEffectView(material: .hudWindow)
                Color.black.opacity(0.25)
            }
        )
        // Overlay ini dipasang SEBELUM clipShape, supaya backdrop
        // dan kartu konfirmasi ikut terpotong rounded 20 seperti
        // panel, bukan menonjol kotak di sudut panel.
        .overlay {
            if showQuitConfirmation {
                quitConfirmationView
            }
        }
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 8)
        .background(WindowAccessor { window in
            configureFramelessWindow(window)
        })
        .onChange(of: model.alwaysOnTop) { _, _ in
            model.applyAlwaysOnTop()
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
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.title3)
                Circle()
                    .fill(model.isSharing ? Color.green : Color.gray)
                    .frame(width: 10, height: 10)
            }
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isSharing ? "Stream Running" : "Stream Stopped")
                    .font(.headline)
                Text("\(model.appCount) apps • \(model.sources.count) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .allowsHitTesting(false)
            Spacer()
            // Pola yang sama seperti gridButton: background kotak
            // ada DI DALAM label, jadi frame Button = kotak itu
            // sendiri — klik di mana saja di dalam pill (bukan
            // hanya di ikon mata / teks) menjalankan action.
            Button {
                model.toggleOutputWindow()
            } label: {
                Label(model.isOutputVisible ? "Visible" : "Hidden",
                      systemImage: model.isOutputVisible ? "eye.fill" : "eye.slash")
                    .font(.caption)
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
                model.toggleSharing()
            } label: {
                Image(systemName: model.isSharing ? "stop.fill" : "play.fill")
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isSharing ? Color.red : Color.green)
            .help(model.isSharing ? "Stop Stream" : "Start Stream")
            .pointingHandOnHover()
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.45))
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPaused ? Color.orange : Color.primary)
            .help(model.isPaused ? "Resume" : "Pause")
            .pointingHandOnHover()
            .disabled(!model.isSharing)
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .toggleStyle(.checkbox)
                .font(.caption)
            Image(systemName: "info.circle")
                .allowsHitTesting(false)
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

    private var popupGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
            gridButton(title: "Preview", subtitle: model.isPreviewVisible ? "Visible" : "Hidden", icon: "eye", tint: model.isPreviewVisible ? Color.accentColor : nil) {
                model.togglePreviewWindow()
            }
            gridButton(title: "Sources", subtitle: "\(model.selectedWindowIDs.count) rules", icon: "list.bullet") { popup = .sources }
            gridButton(title: "Display", subtitle: model.displaySubtitle, icon: "display") { popup = .display }
            gridButton(title: "Frame", subtitle: model.framing.rawValue, icon: "rectangle") { popup = .frame }
            gridButton(title: "Panic", subtitle: model.isPanic ? "Active" : "Blank now", icon: "hand.raised", tint: .red) {
                model.togglePanic()
            }
            gridButton(title: "Mode", subtitle: model.mode == .allow ? "Allow List" : "Block List", icon: "switch.2") { popup = .mode }
            gridButton(title: "Canvas", subtitle: model.canvasBackground == .custom ? "Image" : model.canvasBackground.rawValue.capitalized, icon: "photo") { popup = .canvas }
            gridButton(title: "Presets", subtitle: model.activePreset?.name ?? "Choose", icon: "bookmark") { popup = .presets }
            gridButton(title: "Camera", subtitle: model.cameraEnabled ? "On" : "Off", icon: "video") { popup = .camera }
            gridButton(title: "Quit", subtitle: "Exit app", icon: "power", tint: .red) {
                // Dulu langsung terminate — satu klik tidak sengaja
                // di kotak Quit langsung menutup aplikasi (dan
                // menghentikan stream). Sekarang hanya membuka
                // konfirmasi; keluar hanya terjadi lewat tombol
                // Quit di dalam dialog itu.
                showQuitConfirmation = true
            }
        }
    }

    // Dialog konfirmasi Quit, gaya persis panel utama / File
    // Control: blur hudWindow + hitam 0.25, rounded 20, stroke
    // putih 0.12, shadow — bukan NSAlert / sheet sistem.
    // Backdrop-nya adalah tombol yang membatalkan, jadi klik di
    // luar kartu = batal, dan klik di belakang kartu tidak
    // sampai ke tombol grid di bawahnya. Esc juga membatalkan;
    // sengaja tidak ada shortcut Enter untuk Quit, supaya
    // keluar tidak terjadi karena satu ketukan tidak sengaja.
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
            .frame(width: 340)
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

    private func gridButton(title: String, subtitle: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        // PENTING — kenapa cara lama gagal: sebelumnya background
        // kotak dipasang DI LUAR Button, lalu ditambah
        // .contentShape(Rectangle()). Di macOS, area klik NSButton
        // mengikuti LABEL-nya, bukan wrapper di luar Button, jadi
        // contentShape di luar itu tidak cukup: klik di area kosong
        // box (di luar ikon/teks) tetap tidak sampai ke action.
        // Perbaikannya: background kotak dipindah KE DALAM label,
        // dan label dibuat mengisi penuh box (lebar penuh sel grid,
        // tinggi 68). Dengan begitu frame Button = frame box itu
        // sendiri, jadi klik di mana saja di dalam box — ikon,
        // teks, sudut, maupun area kosong di antara keduanya —
        // mengenai Button dan menjalankan action.
        Button(action: action) {
            VStack(spacing: 3) {
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
            .frame(height: 68)
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

    // MARK: - Popup Sources

    private var sourcesPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Sources")
            TextField("Search apps / windows…", text: $model.searchText)
                .textFieldStyle(.roundedBorder)
            Picker("Mode", selection: $model.mode) {
                ForEach(ShareMode.allCases, id: \.self) { mode in
                    Text(mode == .allow ? "Allow List" : "Block List").tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: model.mode) { _, _ in
                if model.isSharing { model.restartCapture() }
            }
            Text(model.visibleSources.isEmpty
                 ? (model.sources.isEmpty ? model.status : "No matching windows for this search.")
                 : "\(model.visibleSources.count) windows in \(Set(model.visibleSources.map { $0.appName }).count) apps")
                .font(.caption)
                .foregroundStyle(.secondary)
            if model.visibleSources.isEmpty {
                Text(model.sources.isEmpty ? "No windows found. Press Refresh, and check Screen Recording permission if the list stays empty." : "No Matching Sources")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(model.groupedSources, id: \.app) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.app).font(.subheadline).bold()
                                ForEach(group.items) { item in
                                    Button {
                                        model.toggleSource(item.id)
                                    } label: {
                                        HStack {
                                            Image(systemName: model.selectedWindowIDs.contains(item.id)
                                                  ? "checkmark.square.fill" : "square")
                                            Text(item.title).lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.vertical, 2)
                                    }
                                    .buttonStyle(.plain)
                                    .contentShape(Rectangle())
                                    .pointingHandOnHover()
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: .infinity)
            }
            Divider()
            FileTwoPartControl(showPageControls: false)
            HStack {
                Button("Clear") { model.clearSelection() }
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
                Spacer()
                Button("Refresh") { model.refreshSources() }
                    .contentShape(Rectangle())
                    .pointingHandOnHover()
            }
        }
        .padding(16)
        .frame(width: 430, height: 640)
        .onAppear { model.refreshSources() }
    }

    // MARK: - Popup Display

    private var displayPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Display")
            Picker("Display", selection: $model.selectedDisplayID) {
                ForEach(model.displays, id: \.displayID) { display in
                    Text("Display \(display.displayID) (\(display.width)x\(display.height))")
                        .tag(Optional(display.displayID))
                }
            }
            .onChange(of: model.selectedDisplayID) { _, _ in
                if model.isSharing { model.restartCapture() }
            }
            Text("Canvas — a quick explanation")
                .font(.subheadline).bold()
            Text("Full Display: the canvas fills the selected display, so the output always fills the Output window.") 
            Text("Isolated: only the selected windows are shown on top of the canvas background, with empty space around them.") 
            Spacer()
        }
        .padding(16)
        .frame(width: 430, height: 300)
    }

    // MARK: - Popup Canvas / Framing

    private var framingPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Frame")
            Picker("Framing", selection: $model.framing) {
                Text("Full").tag(Framing.full)
                Text("Dynamic").tag(Framing.dynamic)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.framing) { _, _ in
                if model.isSharing { model.restartCapture() }
            }
            Text("Full: the entire display is captured. Dynamic: the capture area follows the combined frames of the selected windows.") 
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(width: 430, height: 200)
    }

    private var modePopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Mode")
            Picker("Mode", selection: $model.mode) {
                Text("Allow List").tag(ShareMode.allow)
                Text("Block List").tag(ShareMode.block)
            }
            .pickerStyle(.segmented)
            .onChange(of: model.mode) { _, _ in
                if model.isSharing { model.restartCapture() }
            }
            Text("Allow List: only the selected windows are shared. Block List: everything is shared except the selected windows.") 
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .frame(width: 430, height: 200)
    }

    private var canvasPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Canvas")
            Text("Canvas").font(.subheadline).bold()
            Picker("Canvas", selection: $model.canvasMode) {
                Text("Full Display").tag(CanvasMode.fullDisplay)
                Text("Isolated").tag(CanvasMode.isolated)
            }
            .pickerStyle(.segmented)
            Text("Background").font(.subheadline).bold()
            Picker("Background", selection: $model.canvasBackground) {
                Text("Gray").tag(CanvasBackground.gray)
                Text("White").tag(CanvasBackground.white)
                Text("Black").tag(CanvasBackground.black)
                Text("Custom").tag(CanvasBackground.custom)
            }
            .pickerStyle(.segmented)
            if model.canvasBackground == .custom {
                Button(model.canvasImage == nil ? "Choose Image…" : "Change Image…") {
                    pickCanvasImage()
                }
                .pointingHandOnHover()
            }
            Spacer()
        }
        .padding(16)
        .frame(width: 430, height: 340)
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

    // MARK: - Popup Presets

    private var presetsPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Presets")
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.presets.isEmpty {
                        Text("No presets yet. Create one from the current setup with Save Current below.") 
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 12)
                    }
                    ForEach(model.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).bold()
                                Text("\(preset.mode == .allow ? "Allow" : "Block") • \(preset.framing.rawValue) • \(preset.canvasMode.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let fileName = preset.fileName {
                                    Text("File: \(fileName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Apply") { model.applyPreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(model.activePresetID == preset.id ? Color.accentColor : Color.secondary)
                                .pointingHandOnHover()
                            Button("Replace") { model.replacePreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Replace this preset with the current setup")
                                .pointingHandOnHover()
                            Button("Delete") { model.deletePreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .pointingHandOnHover()
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            Divider()
            Text("Tip: type the name of an existing preset and press Save Current to replace it, or use the Replace button on a preset row.") 
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("New preset name", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save Current") {
                    model.saveCurrentAsPreset(named: newPresetName)
                    newPresetName = ""
                }
                .buttonStyle(.borderedProminent)
                .pointingHandOnHover()
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    // MARK: - Popup Camera

    private var cameraPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Camera")
            Toggle("Enable camera", isOn: $model.cameraEnabled)
            Toggle("Mirror", isOn: $model.cameraMirrored)
            HStack {
                Text("Ukuran")
                Slider(value: $model.cameraSize, in: 100...320, step: 10)
                Text("\(Int(model.cameraSize))").font(.caption).frame(width: 32)
            }
            Text("Posisi").font(.subheadline).bold()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                ForEach(CameraPosition.allCases, id: \.self) { position in
                    Button(position.label) {
                        model.cameraPosition = position
                    }
                    .buttonStyle(.bordered)
                    .tint(model.cameraPosition == position ? Color.accentColor : Color.secondary)
                    .controlSize(.small)
                    .pointingHandOnHover()
                }
            }
            Text("Bentuk").font(.subheadline).bold()
            Picker("Bentuk", selection: $model.cameraShape) {
                ForEach(CameraShape.allCases, id: \.self) { shape in
                    Text(shape.rawValue).tag(shape)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
        }
        .padding(16)
        .frame(width: 430, height: 340)
    }

}

struct FileTwoPartControl: View {
    @EnvironmentObject var model: VeilModel
    var showPageControls: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("File PDF / PPT").font(.subheadline).bold()
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
            .frame(maxWidth: .infinity, alignment: .leading)
            if showPageControls {
                Divider()
                VStack(spacing: 12) {
                if let active = model.activeFile {
                    Text("\(model.filePageIndex + 1)/\(active.pageCount)")
                        .font(.subheadline).bold()
                    Button {
                        model.previousFilePage()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.45))
                    )
                    .disabled(model.filePageIndex == 0)
                    .help("Previous page")
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .pointingHandOnHover()
                    Button {
                        model.nextFilePage()
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.45))
                    )
                    .disabled(model.filePageIndex + 1 >= active.pageCount)
                    .help("Next page")
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .pointingHandOnHover()
                    Button {
                        model.closeFile()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.45))
                    )
                    .help("Close file")
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .pointingHandOnHover()
                } else {
                    Text("—")
                        .font(.caption).foregroundStyle(.secondary)
                }
                }
                .frame(width: 110)
            }
        }
    }
}

/// Jendela kecil yang muncul otomatis saat sebuah file ditampilkan,
/// supaya pengguna bisa membalik halaman / menutup file tanpa harus
/// kembali ke panel kontrol utama. Jendela ini dibuat di
/// OutputWindow.swift (openFileControlWindow), selalu level .floating,
/// dan ditempelkan di sebelah kanan jendela Output (lihat
/// dockFileControlToOutput) — bukan lagi panel lebar 460 pt yang
/// menutupi Output seperti di screenshot.
/// Daftar file tidak lagi memenuhi flyer: di bawah tombol tutup (x)
/// ada ikon folder yang membuka popup daftar file untuk memilih file.
struct FileControlView: View {
    @EnvironmentObject var model: VeilModel

    var body: some View {
        // Controller kini tanpa bar sama sekali (lihat
        // openFileControlWindow: titled + fullSizeContentView,
        // title bar transparan + hidden, traffic light hidden,
        // background jendela clear) dan tampilannya dark
        // transparent persis seperti panel utama: blur hudWindow
        // + lapisan hitam 0.25, sudut rounded 20, stroke putih
        // tipis. Tanpa title bar, flyer tetap bisa digeser lewat
        // WindowDragView di belakang tombol-tombolnya (klik di
        // area kosong flyer = drag, klik di tombol = action tombol).
        // Tutup flyer tetap lewat tombol tutup (x) di kolomnya,
        // bukan lagi lewat traffic light yang sudah dihapus.
        ZStack {
            VisualEffectView(material: .hudWindow)
            Color.black.opacity(0.25)
            WindowDragView()
            FilePageControl()
                .environmentObject(model)
                .padding(14)
        }
        .frame(width: 140)
        .preferredColorScheme(.dark)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 24, x: 0, y: 8)
    }
}

/// Kolom kontrol halaman yang ringkas untuk flyer: indikator X/Y,
/// halaman sebelumnya, berikutnya, tutup file, lalu — di bawah
/// tombol tutup — ikon folder yang membuka popup daftar file.
struct FilePageControl: View {
    @EnvironmentObject var model: VeilModel
    @State private var showFilePopup = false

    private func pageButton(systemName: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        // Pola yang sama seperti gridButton: background kotak di
        // dalam label, jadi seluruh kotak 48 tinggi itu bisa diklik,
        // bukan hanya ikon di tengahnya.
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.45))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .disabled(disabled)
        .help(help)
        .pointingHandOnHover()
    }

    var body: some View {
        VStack(spacing: 12) {
            if let active = model.activeFile {
                Text("\(model.filePageIndex + 1)/\(active.pageCount)")
                    .font(.subheadline).bold()
                pageButton(systemName: "chevron.left", help: "Previous page", disabled: model.filePageIndex == 0) {
                    model.previousFilePage()
                }
                pageButton(systemName: "chevron.right", help: "Next page", disabled: model.filePageIndex + 1 >= active.pageCount) {
                    model.nextFilePage()
                }
                pageButton(systemName: "xmark", help: "Close file") {
                    model.closeFile()
                }
            } else {
                Text("—")
                    .font(.caption).foregroundStyle(.secondary)
            }
            // Ikon baru di bawah tombol tutup: membuka popup
            // daftar file, supaya pengguna bisa memilih file lain
            // tanpa daftar file memenuhi flyer.
            pageButton(systemName: "folder", help: "Choose file") {
                showFilePopup = true
            }
            .popover(isPresented: $showFilePopup) {
                FileListPopupView(showFilePopup: $showFilePopup)
                    .environmentObject(model)
            }
        }
        .frame(width: 110)
    }
}

/// Isi popup daftar file: klik nama file untuk menampilkannya
/// (dan menutup popup), x kecil untuk menghapus, tombol Add File
/// untuk menambah file baru. Dipakai dari ikon folder di flyer;
/// popup Sources tetap memakai daftar file langsung seperti semula.
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
            OutputContentView()
                .environmentObject(model)
            Text("PREVIEW")
                .font(.caption2).bold()
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(10)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Text(model.isSharing && !model.isPanic ? "Visible" : "Hidden")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.6))
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .padding(10)
                }
            }
        }
        // Kalau rasio sumber berubah (jendela dipilih lain, atau
        // sumber di-resize saat streaming), sesuaikan ukuran
        // jendela Preview (dan Output) ke rasio baru itu.
        .onChange(of: model.sourceAspectRatio) { _, _ in
            model.applySourceRatioToWindows()
        }
    }
}

// MARK: - Jendela Output

/// Pembungkus Output khusus untuk jendela Output (bukan Preview):
/// seluruh isi Output dilapisi WindowDragView transparan, jadi
/// Output tetap bisa digeser dengan drag sistem macOS dari mana
/// saja di atas gambar — tidak lagi bergantung pada title bar
/// yang kini sudah dihapus total (fullSizeContentView). Output
/// tidak punya tombol yang bisa diklik, jadi lapisan drag ini
/// tidak menghalangi interaksi apa pun.
struct OutputWindowRootView: View {
    @EnvironmentObject var model: VeilModel

    var body: some View {
        OutputContentView()
            .environmentObject(model)
            .overlay(WindowDragView())
            // Clean tanpa frame: sudut jendela dibulatkan, tidak
            // ada border / frame macOS di sekeliling gambar.
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Pembungkus Preview yang sama seperti Output: tanpa bar,
/// tanpa frame, sudut rounded, dan bisa digeser dari mana saja
/// di atas gambar (lapisan WindowDragView transparan).
struct PreviewWindowRootView: View {
    @EnvironmentObject var model: VeilModel

    var body: some View {
        PreviewContentView()
            .environmentObject(model)
            .overlay(WindowDragView())
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct OutputContentView: View {
    @EnvironmentObject var model: VeilModel

    var body: some View {
        // GeometryReader: ukuran jendela Output saat ini, supaya
        // isi di dalamnya bisa diskalakan PROPORSIONAL terhadap
        // jendela — bukan ukuran poin absolut yang diam di tempat
        // saat jendela di-resize. Tanpa ini, gambar file yang
        // diraster di ukuran tetap bisa terpotong saat jendela
        // diperkecil, dan kamera yang ukurannya absolut (misal
        // 110 pt) akan tampak mengecil relatif terhadap Output
        // saat jendela diperbesar — tampilan di share screen pun
        // ikut berubah hanya karena jendela lokal di-resize.
        GeometryReader { geometry in
            ZStack {
                if model.isPanic {
                    Color.black
                    Text("Output Disembunyikan")
                        .foregroundStyle(.white)
                        .font(.title2)
                } else {
                    backgroundView
                    mainImageView
                    // Kapsul nama file di bawah tampilan PDF/PPT
                    // sengaja dihapus atas permintaan pengguna:
                    // halaman file tampil bersih tanpa teks nama
                    // file di atasnya. Nama file tetap terlihat di
                    // daftar file di popup Sources dan di flyer
                    // kontrol file, jadi file yang aktif tetap
                    // bisa dikenali dari sana, bukan dari Output.
                    cameraOverlay(outputWidth: geometry.size.width)
                }
            }
        }
        // Sama seperti Preview: rasio sumber berubah => ukuran
        // jendela Output mengikuti rasio baru itu.
        .onChange(of: model.sourceAspectRatio) { _, _ in
            model.applySourceRatioToWindows()
        }
    }

    private var backgroundView: some View {
        Group {
            // Pengaman kedua untuk bar abu-abu: saat file tampil,
            // latar di balik halaman dibuat putih, bukan canvas
            // abu-abu default — jadi kalaupun masih ada selisih
            // rasio sekecil apa pun (misalnya di bawah ambang
            // 0,01 updateSourceAspectRatio), sisa letterbox-nya
            // menyatu dengan halaman PDF yang juga putih dan
            // tidak terlihat sebagai bar abu-abu. Stream tetap
            // memakai warna canvas seperti biasa.
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
    private var mainImageView: some View {
        // File: pakai scaledToFit + frame penuh jendela, bukan
        // scaledToFill. Halaman file harus selalu tampil UTUH,
        // tidak tercrop, apa pun ukuran jendela Output saat ini:
        // gambar menyesuaikan diri ke dalam jendela (sisi canvas
        // yang kosong diisi warna canvas), jadi memperkecil
        // jendela tidak memotong halaman, memperbesar jendela
        // tidak membuat halaman meluber keluar jendela.
        // Stream: tetap scaledToFill (mengisi canvas penuh),
        // tapi dengan frame penuh jendela supaya ikut membesar /
        // mengecil bersama jendela, bukan diam di ukuran raster
        // aslinya lalu terpotong saat jendela diperkecil.
        if let fileImage = model.filePreviewImage {
            if model.canvasMode == .isolated {
                Image(nsImage: fileImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
            } else {
                Image(nsImage: fileImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if model.shouldShowStreamPreview, let image = model.previewImage {
            if model.canvasMode == .isolated {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .padding(20)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("No preview yet. Start the stream or show a file.") 
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cameraOverlay(outputWidth: CGFloat) -> some View {
        if model.cameraEnabled {
            // Kamera proporsional terhadap lebar Output, bukan
            // poin absolut: nilai slider kamera (default 110,
            // rentang 100...320) diartikan sebagai ukuran saat
            // lebar Output 960 (lebar awal Output). Kalau Output
            // di-resize ke 1920, kamera menjadi 2x lipat; kalau
            // diperkecil ke 480, kamera menjadi setengah — jadi
            // proporsi kamera terhadap isi share SELALU sama,
            // apa pun ukuran jendela lokalnya. Margin dari tepi
            // ikut proporsional dengan cara yang sama.
            let referenceWidth: CGFloat = 960
            let scale = outputWidth > 0 ? outputWidth / referenceWidth : 1
            let relativeSize = model.cameraSize * scale
            let relativeMargin = 16 * scale
            ZStack(alignment: model.cameraPosition.alignment) {
                Color.clear
                Group {
                    if model.cameraShape == .circle {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: relativeSize, height: relativeSize)
                            .clipShape(Circle())
                    } else if model.cameraShape == .square {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: relativeSize, height: relativeSize)
                            .clipShape(Rectangle())
                    } else {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: relativeSize, height: relativeSize)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(relativeMargin)
            }
        }
    }
}
