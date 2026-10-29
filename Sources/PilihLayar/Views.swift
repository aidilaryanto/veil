import AppKit
import ScreenCaptureKit
import SwiftUI

enum PopupKind: String, Identifiable {
    case sources, display, frame, mode, canvas, presets, camera
    var id: String { rawValue }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .ultraDark

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
    override func mouseDown(with event: NSEvent) {
        window?.performWindowDrag(with: event)
    }
}

struct WindowDragView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Jendela kontrol utama (control bar, grid 5x2)

struct ContentView: View {
    @EnvironmentObject var model: PilihLayarModel
    @State private var popup: PopupKind?
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WindowDragView()
                .frame(height: 14)
                .overlay(
                    Capsule()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 40, height: 4)
                )
            header
            presetStrip
            popupGrid
            footerRow
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(width: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            ZStack {
                VisualEffectView(material: .ultraDark)
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
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isSharing ? "Stream Running" : "Stream Berhenti")
                    .font(.headline)
                Text("\(model.appCount) apps • \(model.sources.count) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.toggleOutputWindow()
            } label: {
                Label(model.isOutputVisible ? "Visible" : "Hidden",
                      systemImage: model.isOutputVisible ? "eye.fill" : "eye.slash")
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
            )
            Button {
                model.toggleSharing()
            } label: {
                Image(systemName: model.isSharing ? "stop.fill" : "play.fill")
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isSharing ? Color.red : Color.green)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
            )
            .help(model.isSharing ? "Berhenti Stream" : "Mulai Stream")
            Button {
                model.togglePause()
            } label: {
                Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                    .padding(8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.isPaused ? Color.orange : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.45))
            )
            .help(model.isPaused ? "Lanjutkan" : "Pause")
            .disabled(!model.isSharing)
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .toggleStyle(.checkbox)
                .font(.caption)
            Image(systemName: "info.circle")
        }
        .background(WindowDragView())
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Text("File PDF / PPT ada di menu Sources.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") { model.refreshSources() }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.45))
                )
        }
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
                            Button(preset.name) {
                                model.applyPreset(preset)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(model.activePresetID == preset.id ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.black.opacity(0.45))
                            )
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
            gridButton(title: "Panic", subtitle: model.isPanic ? "Aktif" : "Blank now", icon: "hand.raised", tint: .red) {
                model.togglePanic()
            }
            gridButton(title: "Mode", subtitle: model.mode == .allow ? "Allow List" : "Block List", icon: "switch.2") { popup = .mode }
            gridButton(title: "Canvas", subtitle: model.canvasBackground == .custom ? "Image" : model.canvasBackground.rawValue.capitalized, icon: "photo") { popup = .canvas }
            gridButton(title: "Presets", subtitle: model.activePreset?.name ?? "Pilih", icon: "bookmark") { popup = .presets }
            gridButton(title: "Camera", subtitle: model.cameraEnabled ? "On" : "Off", icon: "video") { popup = .camera }
            gridButton(title: "Quit", subtitle: "Exit app", icon: "power", tint: .red) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func gridButton(title: String, subtitle: String, icon: String, tint: Color? = nil, action: @escaping () -> Void) -> some View {
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
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
            }
            .buttonStyle(.plain)
            .help("Tutup")
        }
    }

    // MARK: - Popup Sources

    private var sourcesPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Sources")
            TextField("Cari aplikasi / jendela…", text: $model.searchText)
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
            if model.visibleSources.isEmpty {
                Text("No Matching Sources")
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
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }
            Divider()
            FileTwoPartControl()
            HStack {
                Button("Clear") { model.clearSelection() }
                Spacer()
                Button("Refresh") { model.refreshSources() }
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    // MARK: - Popup Display

    private var displayPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Display")
            Picker("Layar", selection: $model.selectedDisplayID) {
                ForEach(model.displays, id: \.displayID) { display in
                    Text("Layar \(display.displayID) (\(display.width)x\(display.height))")
                        .tag(Optional(display.displayID))
                }
            }
            .onChange(of: model.selectedDisplayID) { _, _ in
                if model.isSharing { model.restartCapture() }
            }
            Text("Canvas — penjelasan singkat")
                .font(.subheadline).bold()
            Text("Full Display: kanvas mengisi seluruh layar yang dipilih, jadi output selalu memenuhi jendela Output.")
            Text("Isolated: hanya jendela yang dipilih yang ditampilkan di atas latar kanvas, dengan ruang kosong di sekelilingnya.")
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
            Text("Full: seluruh layar ditangkap. Dynamic: area tangkapan mengikuti gabungan bingkai jendela yang dipilih.")
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
            Text("Allow List: hanya jendela yang dipilih yang dibagikan. Block List: semua dibagikan kecuali jendela yang dipilih.")
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
            Text("Latar").font(.subheadline).bold()
            Picker("Latar", selection: $model.canvasBackground) {
                Text("Gray").tag(CanvasBackground.gray)
                Text("White").tag(CanvasBackground.white)
                Text("Black").tag(CanvasBackground.black)
                Text("Custom").tag(CanvasBackground.custom)
            }
            .pickerStyle(.segmented)
            if model.canvasBackground == .custom {
                Button(model.canvasImage == nil ? "Pilih Gambar…" : "Ganti Gambar…") {
                    pickCanvasImage()
                }
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
                        Text("Belum ada preset. Buat preset dari setup saat ini lewat Save Current di bawah.")
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
                            Button("Terapkan") { model.applyPreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(model.activePresetID == preset.id ? Color.accentColor : Color.secondary)
                            Button("Replace") { model.replacePreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Timpa preset ini dengan setup saat ini")
                            Button("Hapus") { model.deletePreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            Divider()
            Text("Tips: ketik nama preset yang sudah ada lalu Save Current untuk me-replace-nya, atau pakai tombol Replace di baris preset.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField("Nama preset baru", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
                Button("Save Current") {
                    model.saveCurrentAsPreset(named: newPresetName)
                    newPresetName = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    // MARK: - Popup Camera

    private var cameraPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            popupHeader("Camera")
            Toggle("Aktifkan kamera", isOn: $model.cameraEnabled)
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
    @EnvironmentObject var model: PilihLayarModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("File PDF / PPT").font(.subheadline).bold()
                Text("PDF: halaman penuh. PPT/PPTX: slide pertama (QuickLook).")
                    .font(.caption).foregroundStyle(.secondary)
                if model.fileSources.isEmpty {
                    Text("Belum ada file.")
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
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(model.activeFileID == file.id ? Color.accentColor : Color.primary)
                        .help("Tampilkan file ini")
                        Spacer()
                        Button {
                            model.removeFile(file)
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Hapus file")
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
                    .help("Halaman sebelumnya")
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
                    .help("Halaman berikutnya")
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
                    .help("Tutup file")
                } else {
                    Text("—")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(width: 110)
        }
    }
}

struct FileControlView: View {
    @EnvironmentObject var model: PilihLayarModel

    var body: some View {
        FileTwoPartControl()
            .padding(14)
            .frame(width: 460)
    }
}

struct PreviewContentView: View {
    @EnvironmentObject var model: PilihLayarModel

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
    }
}

// MARK: - Jendela Output

struct OutputContentView: View {
    @EnvironmentObject var model: PilihLayarModel

    var body: some View {
        ZStack {
            if model.isPanic {
                Color.black
                Text("Output Disembunyikan")
                    .foregroundStyle(.white)
                    .font(.title2)
            } else {
                backgroundView
                mainImageView
                if let file = model.activeFile {
                    VStack {
                        Spacer()
                        Text(file.name)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                            .padding(12)
                    }
                }
                cameraOverlay
            }
        }
    }

    private var backgroundView: some View {
        Group {
            if model.canvasBackground == .custom, let image = model.canvasImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                model.canvasBackground.color
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var mainImageView: some View {
        if let image = model.filePreviewImage ?? model.previewImage {
            if model.canvasMode == .isolated {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
                    .padding(20)
            } else {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .clipped()
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("Belum ada pratinjau. Mulai Stream atau tampilkan file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var cameraOverlay: some View {
        if model.cameraEnabled {
            ZStack(alignment: model.cameraPosition.alignment) {
                Color.clear
                Group {
                    if model.cameraShape == .circle {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: model.cameraSize, height: model.cameraSize)
                            .clipShape(Circle())
                    } else if model.cameraShape == .square {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: model.cameraSize, height: model.cameraSize)
                            .clipShape(Rectangle())
                    } else {
                        CameraOverlayView(mirrored: model.cameraMirrored)
                            .frame(width: model.cameraSize, height: model.cameraSize)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding(16)
            }
        }
    }
}
