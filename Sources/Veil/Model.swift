import AppKit
import CoreImage
import PDFKit
import QuickLookThumbnailing
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
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
        case .topLeft: return "Top left"
        case .topCenter: return "Top"
        case .topRight: return "Top right"
        case .middleLeft: return "Left"
        case .middleCenter: return "Center"
        case .middleRight: return "Right"
        case .bottomLeft: return "Bottom left"
        case .bottomCenter: return "Bottom"
        case .bottomRight: return "Bottom right"
        }
    }
}
enum CameraShape: String, CaseIterable, Codable {
    case circle = "Circle"
    case square = "Square"
    case rounded = "Rounded"
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
struct PresetFile: Codable, Hashable {
    var url: String
    var name: String
    var kind: FileKind
    var pageCount: Int
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
    var files: [PresetFile] = []
    var activeFileURL: String? = nil
}
@MainActor
final class VeilModel: NSObject, ObservableObject {
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
    @Published var status = "Ready. Press Refresh, choose a window, then Start Stream."
    @Published var presets: [Preset] = []
    @Published var activePresetID: UUID?
    @Published var isPreviewVisible = false
    @Published var isOutputVisible = false
    @Published var sourceAspectRatio: CGFloat = 16.0 / 9.0
    @Published var fileSources: [FileSource] = []
    @Published var activeFileID: UUID?
    @Published var filePageIndex = 0
    @Published var filePreviewImage: NSImage?
    var shouldShowStreamPreview: Bool {
        isSharing && previewImage != nil
            && !(mode == .allow && selectedWindowIDs.isEmpty)
    }
    private var capturedWindows: [SCWindow] = []
    private var stream: SCStream?
    private var pdfDocument: PDFDocument?
    private var captureWatchdog: Timer?
    private var lastCaptureSignature = ""
    private let presetsKey = "Veil.v2.presets"
    private let legacyPresetsKey = "PilihLayar.v2.presets"
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
        return displays.isEmpty ? "Choose a display" : "Display \(selectedDisplayID ?? 0)"
    }
    var groupedSources: [(app: String, items: [SourceItem])] {
        let grouped = Dictionary(grouping: visibleSources, by: { $0.appName })
        return grouped.keys.sorted().map { (app: $0, items: grouped[$0] ?? []) }
    }
    func updateSourceAspectRatio() {
        var size: CGSize?
        if let image = filePreviewImage {
            size = image.size
        } else if isSharing, let image = previewImage {
            size = image.size
        } else if selectedWindowIDs.count == 1,
                  let onlyID = selectedWindowIDs.first,
                  let frame = capturedWindows.first(where: { $0.windowID == onlyID })?.frame {
            size = frame.size
        } else if framing == .dynamic, !selectedWindowIDs.isEmpty {
            let frames = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }.map { $0.frame }
            if let union = frames.reduce(nil as CGRect?, { $0 == nil ? $1 : $0!.union($1) }) {
                size = union.size
            }
        } else if let image = previewImage {
            size = image.size
        }
        if size == nil,
           let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first {
            size = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
        }
        guard let size = size, size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if abs(ratio - sourceAspectRatio) > 0.01 {
            sourceAspectRatio = ratio
        }
    }
    func applyAlwaysOnTop() {
        for window in NSApp.windows {
            if window.title.contains("Output") {
                window.level = .normal
            } else if window.title.contains("File Control") || window.title.contains("Preview") {
                window.level = .floating
            } else {
                window.level = alwaysOnTop ? .floating : .normal
            }
        }
    }
    private static func sourceItems(from windows: [SCWindow]) -> [SourceItem] {
        var seen = Set<String>()
        return windows
            .filter { $0.owningApplication != nil }
            .sorted {
                if $0.isActive != $1.isActive { return $0.isActive }
                if $0.isOnScreen != $1.isOnScreen { return $0.isOnScreen }
                let app0 = $0.owningApplication?.applicationName ?? "App"
                let app1 = $1.owningApplication?.applicationName ?? "App"
                if app0 != app1 { return app0 < app1 }
                let title0 = ($0.title?.isEmpty == false ? $0.title! : app0)
                let title1 = ($1.title?.isEmpty == false ? $1.title! : app1)
                if title0 != title1 { return title0 < title1 }
                return $0.windowID < $1.windowID
            }
            .compactMap { window -> SourceItem? in
                let appName = window.owningApplication?.applicationName ?? "App"
                let title = (window.title?.isEmpty == false ? window.title! : appName)
                let key = "\(appName)\u{1F}\(title)"
                guard seen.insert(key).inserted else { return nil }
                return SourceItem(id: window.windowID, appName: appName, title: title)
            }
            .sorted {
                if $0.appName != $1.appName { return $0.appName < $1.appName }
                return $0.title < $1.title
            }
    }
    func refreshSources() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: false
                )
                displays = content.displays
                if selectedDisplayID == nil {
                    selectedDisplayID = content.displays.first?.displayID
                }
                capturedWindows = content.windows
                sources = Self.sourceItems(from: content.windows)
                updateSourceAspectRatio()
                status = "\(sources.count) windows on \(content.displays.count) displays."
            } catch {
                status = "Failed to read windows: \(error.localizedDescription). Check Screen Recording permission."
            }
        }
    }
    func toggleSource(_ id: CGWindowID) {
        if selectedWindowIDs.contains(id) {
            selectedWindowIDs.remove(id)
        } else {
            selectedWindowIDs.insert(id)
        }
        updateSourceAspectRatio()
        if isSharing { restartCapture() }
    }
    func clearSelection() {
        selectedWindowIDs.removeAll()
        updateSourceAspectRatio()
        if isSharing { restartCapture() }
    }
    func toggleSharing() {
        if isSharing {
            stopCapture()
        } else {
            previewImage = nil
            startCapture()
        }
    }
    func restartCapture() {
        stopCapture(keepSharing: true)
        startCapture()
    }
    func startCapture() {
        guard !isPanic else {
            status = "Panic mode is on, output is hidden."
            isSharing = false
            return
        }
        guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first else {
            status = "No display found. Press Refresh first."
            isSharing = false
            return
        }
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 5
        config.showsCursor = true
        let scaleFactor: (CGRect) -> CGFloat = { rect in
            NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 1
        }
        let filter: SCContentFilter
        if mode == .allow, selectedWindowIDs.count == 1,
           let onlyID = selectedWindowIDs.first,
           let onlyWindow = capturedWindows.first(where: { $0.windowID == onlyID }) {
            filter = SCContentFilter(desktopIndependentWindow: onlyWindow)
            let frame = onlyWindow.frame
            let scale = scaleFactor(frame)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
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
                let scale = scaleFactor(union)
                config.width = max(2, Int(union.width * scale))
                config.height = max(2, Int(union.height * scale))
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
                sampleHandlerQueue: DispatchQueue(label: "veil.capture")
            )
            stream = newStream
            Task {
                do {
                    try await newStream.startCapture()
                    await MainActor.run {
                        isSharing = true
                        status = "Sharing is live (\(selectedWindowIDs.count) windows). Share the Output window in Zoom/Meet/Teams."
                        startCaptureWatchdog()
                        if !isOutputVisible {
                            openOutputWindow()
                        }
                        reopenFileControlIfNeeded()
                    }
                } catch {
                    await MainActor.run {
                        status = "Failed to start capture: \(error.localizedDescription)"
                        isSharing = false
                    }
                }
            }
        } catch {
            status = "Failed to create stream: \(error.localizedDescription)"
            isSharing = false
        }
    }
    func stopCapture(keepSharing: Bool = false) {
        stopCaptureWatchdog()
        let oldStream = stream
        stream = nil
        if !keepSharing {
            isSharing = false
            previewImage = nil
            closeFile()
            closeOutputWindow()
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
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            capturedWindows = content.windows
            displays = content.displays
            sources = Self.sourceItems(from: content.windows)
            updateSourceAspectRatio()
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
            status = "Panic: output blacked out immediately."
        } else {
            status = "Panic off. Press Start Stream to share again."
        }
    }
    func openFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = "Select PDF or PPT files, or a folder containing them."
        panel.allowedContentTypes = [
            .pdf,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data,
            .folder
        ]
        guard panel.runModal() == .OK else { return }
        var urls: [URL] = []
        for url in panel.urls {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               let enumerator = FileManager.default.enumerator(
                   at: url, includingPropertiesForKeys: nil,
                   options: [.skipsHiddenFiles, .skipsPackageDescendants]
               ) {
                for case let fileURL as URL in enumerator {
                    urls.append(fileURL)
                }
            } else {
                urls.append(url)
            }
        }
        let added = urls.sorted { $0.path < $1.path }.compactMap { addFile(url: $0) }.count
        if added > 0 { syncActivePresetFiles() }
        if added == 0 {
            status = "No new PDF or PPT files added."
        } else if added == 1 {
            status = "1 file added. Click a file name to show it."
        } else {
            status = "\(added) files added. Click a file name to show it."
        }
    }
    func choosePresentationFile() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a PDF or PPT file to present."
        panel.allowedContentTypes = [
            .pdf,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data
        ]
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        if let existing = fileSources.first(where: { $0.url.path == url.path }) {
            activateFile(existing)
            syncActivePresetFiles()
            return true
        }
        guard let added = addFile(url: url) else { return false }
        activateFile(added)
        syncActivePresetFiles()
        return true
    }
    func syncActivePresetFiles() {
        guard let id = activePresetID,
              let index = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[index].files = fileSources.map {
            PresetFile(url: $0.url.path, name: $0.name, kind: $0.kind, pageCount: $0.pageCount)
        }
        presets[index].activeFileURL = activeFile?.url.path
        presets[index].fileURL = activeFile?.url.path
        presets[index].fileName = activeFile?.name
        presets[index].fileKind = activeFile?.kind
        presets[index].filePageIndex = filePageIndex
        persistPresets()
    }
    func fileSource(from presetFile: PresetFile) -> FileSource? {
        let url = URL(fileURLWithPath: presetFile.url)
        guard FileManager.default.fileExists(atPath: presetFile.url) else { return nil }
        if presetFile.kind == .pdf {
            let pageCount = PDFDocument(url: url)?.pageCount ?? presetFile.pageCount
            return FileSource(name: presetFile.name, url: url, kind: .pdf, pageCount: max(1, pageCount))
        } else {
            return FileSource(name: presetFile.name, url: url, kind: .ppt, pageCount: 1)
        }
    }
    func addFile(url: URL) -> FileSource? {
        if fileSources.contains(where: { $0.url.path == url.path }) { return nil }
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return nil }
            let item = FileSource(name: name, url: url, kind: .pdf, pageCount: max(1, document.pageCount))
            fileSources.append(item)
            return item
        } else if ext == "ppt" || ext == "pptx" {
            let item = FileSource(name: name, url: url, kind: .ppt, pageCount: 1)
            fileSources.append(item)
            return item
        } else {
            return nil
        }
    }
    func activateFile(_ item: FileSource) {
        activeFileID = item.id
        filePageIndex = 0
        if isSharing { openFileControlWindow() }
        if item.kind == .pdf {
            pdfDocument = PDFDocument(url: item.url)
            renderFilePage()
        } else {
            pdfDocument = nil
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: CGSize(width: 1280, height: 720),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: QLThumbnailGenerator.Request.RepresentationTypes.thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let self, let image = representation?.nsImage else { return }
                Task { @MainActor in
                    self.filePreviewImage = image
                    self.updateSourceAspectRatio()
                    self.applySourceRatioToWindows()
                }
            }
        }
    }
    func closeFile() {
        activeFileID = nil
        pdfDocument = nil
        filePreviewImage = nil
        filePageIndex = 0
        closeFileControlWindow()
        updateSourceAspectRatio()
        applySourceRatioToWindows()
    }
    func removeFile(_ item: FileSource) {
        guard let index = fileSources.firstIndex(where: { $0.id == item.id }) else { return }
        let wasActive = activeFileID == item.id
        fileSources.remove(at: index)
        if wasActive {
            if fileSources.isEmpty {
                closeFile()
            } else if index > 0 {
                activateFile(fileSources[index - 1])
            } else {
                activateFile(fileSources[0])
            }
        }
        syncActivePresetFiles()
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
        filePreviewImage = page.thumbnail(of: NSSize(width: 3000, height: 3000), for: .mediaBox)
        updateSourceAspectRatio()
        applySourceRatioToWindows()
    }
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
        updated.files = fileSources.map {
            PresetFile(url: $0.url.path, name: $0.name, kind: $0.kind, pageCount: $0.pageCount)
        }
        updated.activeFileURL = activeFile?.url.path
        presets[index] = updated
        activePresetID = updated.id
        persistPresets()
        status = "Preset '\(updated.name)' replaced with the current setup."
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
            filePageIndex: filePageIndex,
            files: fileSources.map {
                PresetFile(url: $0.url.path, name: $0.name, kind: $0.kind, pageCount: $0.pageCount)
            },
            activeFileURL: activeFile?.url.path
        )
        presets.append(preset)
        activePresetID = preset.id
        persistPresets()
        status = "Preset '\(preset.name)' saved."
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
        updateSourceAspectRatio()
        cameraEnabled = preset.cameraEnabled
        cameraPosition = preset.cameraPosition
        cameraShape = preset.cameraShape
        cameraSize = preset.cameraSize
        cameraMirrored = preset.cameraMirrored
        var presetFiles = preset.files
        if presetFiles.isEmpty,
           let path = preset.fileURL, !path.isEmpty,
           let name = preset.fileName, let kind = preset.fileKind {
            presetFiles = [PresetFile(url: path, name: name, kind: kind, pageCount: preset.filePageIndex + 1)]
        }
        fileSources = presetFiles.compactMap { fileSource(from: $0) }
        let activePath = preset.activeFileURL ?? preset.fileURL
        if let path = activePath,
           let active = fileSources.first(where: { $0.url.path == path }) {
            activateFile(active)
            if active.kind == .pdf, preset.filePageIndex < active.pageCount {
                filePageIndex = preset.filePageIndex
                renderFilePage()
            }
        } else {
            activeFileID = nil
            pdfDocument = nil
            filePreviewImage = nil
            filePageIndex = 0
            updateSourceAspectRatio()
            applySourceRatioToWindows()
            if isSharing, !fileSources.isEmpty { openFileControlWindow() }
        }
        if isSharing { restartCapture() }
        status = "Preset '\(preset.name)' applied."
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
        let key = UserDefaults.standard.data(forKey: presetsKey) != nil ? presetsKey : legacyPresetsKey
        if let data = UserDefaults.standard.data(forKey: key),
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
extension VeilModel: SCStreamOutput {
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
            if !self.isPaused {
                self.previewImage = image
                self.updateSourceAspectRatio()
            }
        }
    }
}
