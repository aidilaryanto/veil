import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum PopupKind: String, Identifiable {
    case sources, display, frame, mode, canvas, presets, camera, files
    var id: String { rawValue }
}

// MARK: - Jendela kontrol utama (box kecil lebar 430)

struct ContentView: View {
    @EnvironmentObject var model: PilihLayarModel
    @State private var popup: PopupKind?
    @State private var newPresetName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            streamRow
            presetStrip
            popupGrid
            footerRow
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .frame(minWidth: 600)
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
            case .files: filesPopup
            }
        }
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
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .toggleStyle(.checkbox)
                .font(.caption)
            Image(systemName: "info.circle")
        }
    }

    private var streamRow: some View {
        HStack(spacing: 8) {
            Button(model.isSharing ? "Berhenti" : "Mulai Stream") {
                model.toggleSharing()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            Button(model.isPaused ? "Lanjutkan" : "Pause") {
                model.togglePause()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
        }
    }

    private var footerRow: some View {
        HStack(spacing: 8) {
            Button("Files PDF / PPT") { popup = .files }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
            Button("Refresh") { model.refreshSources() }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(model.activePresetID == preset.id ? Color.accentColor : Color.secondary)
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
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 68)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    // MARK: - Popup Sources

    private var sourcesPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sources").font(.headline)
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
            Text("Display").font(.headline)
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
            Text("Frame").font(.headline)
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
            Text("Mode").font(.headline)
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
            Text("Canvas").font(.headline)
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
            Text("Presets").font(.headline)
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
                            Button("Hapus") { model.deletePreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
            Divider()
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
            Text("Camera").font(.headline)
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

    // MARK: - Popup Files

    private var filesPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Files PDF / PPT").font(.headline)
            Text("PDF: navigasi halaman penuh. PPT/PPTX: pratinjau slide pertama saja (QuickLook).")
                .font(.caption).foregroundStyle(.secondary)
            Button("Tambah File PDF / PPT") { pickFile() }
                .buttonStyle(.borderedProminent)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.fileSources) { file in
                        HStack {
                            Text(file.name).lineLimit(1)
                            Spacer()
                            Button("Tampilkan") { model.activateFile(file) }
                                .buttonStyle(.bordered).controlSize(.small)
                            Button("Hapus") { model.removeFile(file) }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                }
            }
            .frame(maxHeight: 180)
            if let active = model.activeFile {
                Divider()
                Text(active.name).font(.subheadline).bold().lineLimit(1)
                HStack {
                    Button("Sebelumnya") { model.previousFilePage() }
                        .disabled(model.filePageIndex == 0)
                    Spacer()
                    Text("Hal. \(model.filePageIndex + 1) / \(active.pageCount)")
                        .font(.caption)
                    Spacer()
                    Button("Berikutnya") { model.nextFilePage() }
                        .disabled(model.filePageIndex + 1 >= active.pageCount)
                }
                Button("Tutup File") { model.closeFile() }
            }
        }
        .padding(16)
        .frame(width: 430)
    }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            .pdf,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data
        ]
        if panel.runModal() == .OK, let url = panel.url {
            model.addFile(url: url)
        }
    }
}

struct FileControlView: View {
    @EnvironmentObject var model: PilihLayarModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let file = model.activeFile {
                Text(file.name)
                    .font(.subheadline)
                    .bold()
                    .lineLimit(1)
                Text("\(file.kind.rawValue) • Hal. \(model.filePageIndex + 1) / \(file.pageCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Sebelumnya") { model.previousFilePage() }
                        .disabled(model.filePageIndex == 0)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Spacer()
                    Button("Berikutnya") { model.nextFilePage() }
                        .disabled(model.filePageIndex + 1 >= file.pageCount)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Button("Tutup File") { model.closeFile() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Tidak ada file yang ditampilkan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 340)
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
