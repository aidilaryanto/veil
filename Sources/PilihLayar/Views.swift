import AppKit
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

enum PopupKind: String, Identifiable {
    case sources, display, canvas, presets, camera, files
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
            mainActions
            popupGrid
            Text(model.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(16)
        .onChange(of: model.alwaysOnTop) { _, _ in
            model.applyAlwaysOnTop()
        }
        .sheet(item: $popup) { kind in
            switch kind {
            case .sources: sourcesPopup
            case .display: displayPopup
            case .canvas: canvasPopup
            case .presets: presetsPopup
            case .camera: cameraPopup
            case .files: filesPopup
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.isSharing ? Color.green : Color.gray)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.isSharing ? "Stream Running" : "Stream Berhenti")
                    .font(.headline)
                Text("\(model.selectedWindowIDs.count) jendela • \(model.displays.count) layar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Always on Top", isOn: $model.alwaysOnTop)
                .toggleStyle(.checkbox)
                .font(.caption)
            Button("Refresh") { model.refreshSources() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
    }

    private var mainActions: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(model.isSharing ? "Berhenti" : "Mulai Stream") {
                    model.toggleSharing()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                Button {
                    model.togglePanic()
                } label: {
                    VStack(spacing: 2) {
                        Text("Panik")
                        Text(model.isPanic ? "Aktif" : "Blank now")
                            .font(.caption2)
                    }
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .foregroundStyle(.red)
            }
            HStack(spacing: 8) {
                Button("Preview") { model.openOutputWindow() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button(model.isPaused ? "Lanjutkan" : "Pause") {
                    model.togglePause()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var popupGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            popupButton(title: "Sources", icon: "list.bullet") { popup = .sources }
            popupButton(title: "Display", icon: "display") { popup = .display }
            popupButton(title: "Canvas", icon: "rectangle.dashed") { popup = .canvas }
            popupButton(title: "Presets", icon: "bookmark") { popup = .presets }
            popupButton(title: "Camera", icon: "video") { popup = .camera }
            popupButton(title: "Files", icon: "doc") { popup = .files }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "power")
                    Text("Quit").font(.caption)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }

    private func popupButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
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

    private var canvasPopup: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Framing & Canvas").font(.headline)
            Text("Framing").font(.subheadline).bold()
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
                    ForEach(model.presets) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).bold()
                                Text("\(preset.mode == .allow ? "Allow" : "Block") • \(preset.framing.rawValue) • \(preset.canvasMode.rawValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Terapkan") { model.applyPreset(preset) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            if !preset.isBuiltIn {
                                Button("Hapus") { model.deletePreset(preset) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
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
