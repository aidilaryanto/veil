import AppKit
import CoreImage
import PDFKit
import QuickLookThumbnailing
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Tipe data

struct SourceItem: Identifiable, Hashable {
    let id: CGWindowID
    let appName: String
    let title: String
}

enum ShareMode: String, CaseIterable, Codable {
    case allow = "Allow"
    case block = "Block"
}

enum Framing: String, CaseIterable, Codable {
    case full = "Full"
    case dynamic = "Dynamic"
}

enum CanvasMode: String, CaseIterable, Codable {
    case fullDisplay = "Full Display"
    case isolated = "Isolated"
}

enum CanvasBackground: String, CaseIterable, Codable {
    case gray = "gray"
    case white = "white"
    case black = "black"
    case custom = "custom"

    var color: Color {
        switch self {
        case .gray: return Color(nsColor: .darkGray)
        case .white: return .white
        case .black, .custom: return .black
        }
    }
}

enum CameraPosition: String, CaseIterable, Codable {
    case topLeft, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var alignment: Alignment {
        switch self {
        case .topLeft: return .topLeading
        case .topCenter: return .top
        case .topRight: return .topTrailing
        case .middleLeft: return .leading
        case .middleCenter: return .center
        case .middleRight: return .trailing
        case .bottomLeft: return .bottomLeading
        case .bottomCenter: return .bottom
        case .bottomRight: return .bottomTrailing
        }
    }

    var label: String {
        switch self {
        case .topLeft: return "Kiri atas"
        case .topCenter: return "Atas"
        case .topRight: return "Kanan atas"
        case .middleLeft: return "Kiri"
        case .middleCenter: return "Tengah"
        case .middleRight: return "Kanan"
        case .bottomLeft: return "Kiri bawah"
        case .bottomCenter: return "Bawah"
        case .bottomRight: return "Kanan bawah"
        }
    }
}

enum CameraShape: String, CaseIterable, Codable {
    case circle = "Lingkaran"
    case square = "Kotak"
    case rounded = "Membulat"
}

enum FileKind: String, Codable {
    case pdf = "PDF"
    case ppt = "PPT"
}

struct FileSource: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: URL
    let kind: FileKind
    let pageCount: Int

    static func == (lhs: FileSource, rhs: FileSource) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct Preset: Identifiable, Codable {
    var id = UUID()
    var name: String
    var mode: ShareMode
    var framing: Framing
    var canvasMode: CanvasMode
    var canvasBackground: CanvasBackground
    var selectedWindowIDs: [CGWindowID]
    var displayID: UInt32?
    var cameraEnabled: Bool
    var cameraPosition: CameraPosition
    var cameraShape: CameraShape
    var cameraSize: Double
    var cameraMirrored: Bool
    var isBuiltIn: Bool = false
    var fileURL: String? = nil
    var fileName: String? = nil
    var fileKind: FileKind? = nil
    var filePageIndex: Int = 0
}

// MARK: - Model utama

@MainActor
final class PilihLayarModel: NSObject, ObservableObject {
    @Published var sources: [SourceItem] = []
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplayID: UInt32?
    @Published var selectedWindowIDs: Set<CGWindowID> = []
    @Published var searchText = ""
    @Published var mode: ShareMode = .allow
    @Published var framing: Framing = .full
    @Published var canvasMode: CanvasMode = .fullDisplay
    @Published var canvasBackground: CanvasBackground = .gray
    @Published var canvasImage: NSImage?
    @Published var alwaysOnTop = true
    @Published var cameraEnabled = true
    @Published var cameraPosition: CameraPosition = .bottomRight
    @Published var cameraShape: CameraShape = .rounded
    @Published var cameraSize: Double = 110
    @Published var cameraMirrored = false
    @Published var isSharing = false
    @Published var isPanic = false
    @Published var isPaused = false
    @Published var previewImage: NSImage?
    @Published var status = "Siap. Tekan Refresh, pilih jendela, lalu Mulai Stream."
    @Published var presets: [Preset] = []
    @Published var activePresetID: UUID?
    @Published var isPreviewVisible = false
    @Published var isOutputVisible = false
    @Published var fileSources: [FileSource] = []
    @Published var activeFileID: UUID?
    @Published var filePageIndex = 0
    @Published var filePreviewImage: NSImage?

    private var capturedWindows: [SCWindow] = []
    private var stream: SCStream?
    private var pdfDocument: PDFDocument?
    private var captureWatchdog: Timer?
    private var lastCaptureSignature = ""
    private let presetsKey = "PilihLayar.v2.presets"

    override init() {
        super.init()
        loadPresets()
    }

    var activeFile: FileSource? {
        guard let id = activeFileID else { return nil }
        return fileSources.first { $0.id == id }
    }

    var visibleSources: [SourceItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return sources }
        return sources.filter {
            $0.appName.lowercased().contains(query) || $0.title.lowercased().contains(query)
        }
    }

    var appCount: Int {
        Set(sources.map { $0.appName }).count
    }

    var activePreset: Preset? {
        guard let id = activePresetID else { return nil }
        return presets.first { $0.id == id }
    }

    var displaySubtitle: String {
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) {
            return "\(display.width)x\(display.height)"
        }
        return displays.isEmpty ? "Pilih layar" : "Layar \(selectedDisplayID ?? 0)"
    }

    var groupedSources: [(app: String, items: [SourceItem])] {
        let grouped = Dictionary(grouping: visibleSources, by: { $0.appName })
        return grouped.keys.sorted().map { (app: $0, items: grouped[$0] ?? []) }
    }

    func applyAlwaysOnTop() {
        for window in NSApp.windows {
            if window.title.contains("Output") {
                window.level = .normal
            } else if window.title.contains("Kontrol File") || window.title.contains("Preview") {
                window.level = .floating
            } else {
                window.level = alwaysOnTop ? .floating : .normal
            }
        }
    }

    // MARK: - Sumber (ScreenCaptureKit)

    func refreshSources() {
        Task {
            do {
                // Label argumen di bawah ini adalah yang cocok dengan
                // SDK terbaru; label lama sudah tidak diterima compiler.
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true
                )
                displays = content.displays
                if selectedDisplayID == nil {
                    selectedDisplayID = content.displays.first?.displayID
                }
                capturedWindows = content.windows
                sources = content.windows
                    .filter { $0.owningApplication != nil && !($0.title ?? "").isEmpty }
                    .map { window in
                        SourceItem(
                            id: window.windowID,
                            appName: window.owningApplication?.applicationName ?? "Aplikasi",
                            title: window.title ?? ""
                        )
                    }
                    .sorted { $0.appName < $1.appName }
                status = "\(sources.count) jendela di \(content.displays.count) layar."
            } catch {
                status = "Gagal membaca jendela: \(error.localizedDescription). Periksa izin Screen Recording."
            }
        }
    }

    func toggleSource(_ id: CGWindowID) {
        if selectedWindowIDs.contains(id) {
            selectedWindowIDs.remove(id)
        } else {
            selectedWindowIDs.insert(id)
        }
        if isSharing { restartCapture() }
    }

    func clearSelection() {
        selectedWindowIDs.removeAll()
        if isSharing { restartCapture() }
    }

    // MARK: - Capture

    func toggleSharing() {
        if isSharing { stopCapture() } else { startCapture() }
    }

    func restartCapture() {
        stopCapture(keepSharing: true)
        startCapture()
    }

    func startCapture() {
        guard !isPanic else {
            status = "Mode Panik aktif, output disembunyikan."
            isSharing = false
            return
        }
        guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first else {
            status = "Tidak ada layar. Tekan Refresh dulu."
            isSharing = false
            return
        }
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.showsCursor = true
        let filter: SCContentFilter
        if mode == .allow, selectedWindowIDs.count == 1,
           let onlyID = selectedWindowIDs.first,
           let onlyWindow = capturedWindows.first(where: { $0.windowID == onlyID }) {
            filter = SCContentFilter(desktopIndependentWindow: onlyWindow)
            let frame = onlyWindow.frame
            config.width = max(2, Int(frame.width))
            config.height = max(2, Int(frame.height))
            lastCaptureSignature = captureSignature()
        } else {
            let excluded: [SCWindow]
            if mode == .allow {
                excluded = capturedWindows.filter { !selectedWindowIDs.contains($0.windowID) }
            } else {
                excluded = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }
            }
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            lastCaptureSignature = captureSignature()
        }
        if mode == .allow, selectedWindowIDs.count == 1 {
        } else if framing == .dynamic, !selectedWindowIDs.isEmpty {
            let frames = capturedWindows
                .filter { selectedWindowIDs.contains($0.windowID) }
                .map { $0.frame }
            if let union = frames.reduce(nil as CGRect?, { current, rect in
                current == nil ? rect : current!.union(rect)
            }) {
                config.sourceRect = union
                config.width = max(2, Int(union.width))
                config.height = max(2, Int(union.height))
            } else {
                config.width = display.width
                config.height = display.height
            }
        } else {
            config.width = display.width
            config.height = display.height
        }
        do {
            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(
                self, type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "pilihlayar.capture")
            )
            stream = newStream
            Task {
                do {
                    try await newStream.startCapture()
                    await MainActor.run {
                        isSharing = true
                        status = "Berbagi aktif (\(selectedWindowIDs.count) jendela). Bagikan jendela Output di Zoom/Meet/Teams."
                        startCaptureWatchdog()
                    }
                } catch {
                    await MainActor.run {
                        status = "Gagal mulai capture: \(error.localizedDescription)"
                        isSharing = false
                    }
                }
            }
        } catch {
            status = "Gagal membuat stream: \(error.localizedDescription)"
            isSharing = false
        }
    }

    func stopCapture(keepSharing: Bool = false) {
        stopCaptureWatchdog()
        let oldStream = stream
        stream = nil
        if !keepSharing {
            isSharing = false
        }
        Task { try? await oldStream?.stopCapture() }
    }

    private func captureSignature() -> String {
        let ids = capturedWindows.map { String($0.windowID) }.sorted().joined(separator: ",")
        let frames = capturedWindows
            .filter { selectedWindowIDs.contains($0.windowID) }
            .sorted { $0.windowID < $1.windowID }
            .map { "\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)),\(Int($0.frame.width)),\(Int($0.frame.height))" }
            .joined(separator: "|")
        return "\(mode.rawValue)|\(ids)|\(frames)"
    }

    private func startCaptureWatchdog() {
        stopCaptureWatchdog()
        guard !(mode == .allow && selectedWindowIDs.count == 1) else { return }
        captureWatchdog = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkCaptureStability()
            }
        }
    }

    private func stopCaptureWatchdog() {
        captureWatchdog?.invalidate()
        captureWatchdog = nil
    }

    private func checkCaptureStability() async {
        guard isSharing, stream != nil else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            capturedWindows = content.windows
            displays = content.displays
            sources = content.windows
                .filter { $0.owningApplication != nil && !($0.title ?? "").isEmpty }
                .map { SourceItem(id: $0.windowID, appName: $0.owningApplication?.applicationName ?? "Aplikasi", title: $0.title ?? "") }
                .sorted { $0.appName < $1.appName }
            let signature = captureSignature()
            if signature != lastCaptureSignature {
                lastCaptureSignature = signature
                restartCapture()
            }
        } catch {
        }
    }

    func togglePause() {
        isPaused.toggle()
    }

    func togglePanic() {
        isPanic.toggle()
        if isPanic {
            stopCapture()
            previewImage = nil
            status = "Panik: output langsung dihitamkan."
        } else {
            status = "Panik nonaktif. Tekan Mulai Stream untuk berbagi lagi."
        }
    }

    // MARK: - File PDF / PPT

    func openFilePicker() {
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
            addFile(url: url)
        }
    }

    func addFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else {
                status = "Gagal membuka PDF: \(name)"
                return
            }
            let item = FileSource(name: name, url: url, kind: .pdf, pageCount: max(1, document.pageCount))
            fileSources.append(item)
            activateFile(item)
            status = "PDF ditambahkan: \(name) (\(document.pageCount) halaman)."
        } else if ext == "ppt" || ext == "pptx" {
            // macOS tidak punya renderer slide-per-slide bawaan untuk PPT.
            // Pratinjau yang dipakai adalah thumbnail QuickLook, biasanya
            // slide pertama. Untuk navigasi slide penuh, konversi ke PDF.
            let item = FileSource(name: name, url: url, kind: .ppt, pageCount: 1)
            fileSources.append(item)
            activateFile(item)
            status = "PPT ditambahkan: \(name). Pratinjau slide pertama (QuickLook)."
        } else {
            status = "Format tidak didukung: hanya PDF, PPT, dan PPTX."
        }
    }

    func activateFile(_ item: FileSource) {
        activeFileID = item.id
        filePageIndex = 0
        openFileControlWindow()
        if item.kind == .pdf {
            pdfDocument = PDFDocument(url: item.url)
            renderFilePage()
        } else {
            pdfDocument = nil
            // SDK terbaru: QLThumbnailGenerator.Request dengan label fileAt:.
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: CGSize(width: 1280, height: 720),
                scale: 1,
                representationTypes: QLThumbnailGenerator.Request.RepresentationTypes.thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let self, let image = representation?.nsImage else { return }
                Task { @MainActor in self.filePreviewImage = image }
            }
        }
    }

    func closeFile() {
        activeFileID = nil
        pdfDocument = nil
        filePreviewImage = nil
        filePageIndex = 0
        closeFileControlWindow()
    }

    func removeFile(_ item: FileSource) {
        fileSources.removeAll { $0.id == item.id }
        if activeFileID == item.id { closeFile() }
    }

    func nextFilePage() {
        guard let item = activeFile, filePageIndex + 1 < item.pageCount else { return }
        filePageIndex += 1
        renderFilePage()
    }

    func previousFilePage() {
        guard filePageIndex > 0 else { return }
        filePageIndex -= 1
        renderFilePage()
    }

    private func renderFilePage() {
        guard let document = pdfDocument,
              let page = document.page(at: filePageIndex) else { return }
        filePreviewImage = page.thumbnail(of: NSSize(width: 1280, height: 720), for: .mediaBox)
    }

    // MARK: - Preset

    func replacePreset(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.mode = mode
        updated.framing = framing
        updated.canvasMode = canvasMode
        updated.canvasBackground = canvasBackground
        updated.selectedWindowIDs = Array(selectedWindowIDs)
        updated.displayID = selectedDisplayID
        updated.cameraEnabled = cameraEnabled
        updated.cameraPosition = cameraPosition
        updated.cameraShape = cameraShape
        updated.cameraSize = cameraSize
        updated.cameraMirrored = cameraMirrored
        updated.fileURL = activeFile?.url.path
        updated.fileName = activeFile?.name
        updated.fileKind = activeFile?.kind
        updated.filePageIndex = filePageIndex
        presets[index] = updated
        activePresetID = updated.id
        persistPresets()
        status = "Preset '\(updated.name)' diganti dengan setup saat ini."
    }

    func saveCurrentAsPreset(named name: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanName.isEmpty,
           let existing = presets.first(where: { $0.name.lowercased() == cleanName.lowercased() }) {
            replacePreset(existing)
            return
        }
        var generatedName = cleanName
        if generatedName.isEmpty {
            var number = presets.count + 1
            generatedName = "Preset \(number)"
            while presets.contains(where: { $0.name == generatedName }) {
                number += 1
                generatedName = "Preset \(number)"
            }
        }
        let preset = Preset(
            name: generatedName,
            mode: mode,
            framing: framing,
            canvasMode: canvasMode,
            canvasBackground: canvasBackground,
            selectedWindowIDs: Array(selectedWindowIDs),
            displayID: selectedDisplayID,
            cameraEnabled: cameraEnabled,
            cameraPosition: cameraPosition,
            cameraShape: cameraShape,
            cameraSize: cameraSize,
            cameraMirrored: cameraMirrored,
            fileURL: activeFile?.url.path,
            fileName: activeFile?.name,
            fileKind: activeFile?.kind,
            filePageIndex: filePageIndex
        )
        presets.append(preset)
        activePresetID = preset.id
        persistPresets()
        status = "Preset '\(preset.name)' tersimpan."
    }

    func applyPreset(_ preset: Preset) {
        activePresetID = preset.id
        mode = preset.mode
        framing = preset.framing
        canvasMode = preset.canvasMode
        canvasBackground = preset.canvasBackground
        if preset.canvasBackground != .custom { canvasImage = nil }
        selectedWindowIDs = Set(preset.selectedWindowIDs)
        selectedDisplayID = preset.displayID
        cameraEnabled = preset.cameraEnabled
        cameraPosition = preset.cameraPosition
        cameraShape = preset.cameraShape
        cameraSize = preset.cameraSize
        cameraMirrored = preset.cameraMirrored
        if let path = preset.fileURL, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if let existing = fileSources.first(where: { $0.url.path == path }) {
                closeFile()
                activateFile(existing)
                if existing.kind == .pdf, preset.filePageIndex < existing.pageCount {
                    filePageIndex = preset.filePageIndex
                    renderFilePage()
                }
            } else if FileManager.default.fileExists(atPath: path) {
                closeFile()
                addFile(url: url)
                if preset.filePageIndex > 0, let current = activeFile,
                   current.kind == .pdf, preset.filePageIndex < current.pageCount {
                    filePageIndex = preset.filePageIndex
                    renderFilePage()
                }
            } else {
                closeFile()
                status = "Preset '\(preset.name)' diterapkan, tapi file tidak ditemukan."
                if isSharing { restartCapture() }
                return
            }
        } else {
            closeFile()
        }
        if isSharing { restartCapture() }
        status = "Preset '\(preset.name)' diterapkan."
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id { activePresetID = nil }
        persistPresets()
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: presetsKey)
        }
    }

    private func loadPresets() {
        if let data = UserDefaults.standard.data(forKey: presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            let userPresets = decoded.filter { !$0.isBuiltIn }
            presets = userPresets
            if userPresets.count != decoded.count { persistPresets() }
            return
        }
        presets = []
        persistPresets()
    }
}

// MARK: - SCStreamOutput

extension PilihLayarModel: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        let image = NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
        Task { @MainActor in
            // Saat dijeda, frame terakhir dibekukan: preview tidak diperbarui.
            if !self.isPaused {
                self.previewImage = image
            }
        }
    }
}
