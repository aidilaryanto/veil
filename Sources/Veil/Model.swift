import AppKit
import AVFoundation
import CoreGraphics
import Foundation
import CoreImage
import CoreVideo
import PDFKit
import QuickLookThumbnailing
import ScreenCaptureKit
import SwiftUI
import UniformTypeIdentifiers
enum DebugLog {
    private static let queue = DispatchQueue(label: "veil.debuglog")
    private static let launchDate = Date()
    private static var handle: FileHandle?
    static var path: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        return base?.appendingPathComponent("Veil/veil-debug.log").path ?? "?"
    }
    static func start() {
        queue.sync {
            openFresh()
            append("LAUNCH Veil \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
        }
    }
    static func log(_ message: String) {
        queue.async {
            if handle == nil {
                openFresh()
            }
            append(message)
        }
    }
    private static func openFresh() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        guard let url = base?.appendingPathComponent("Veil/veil-debug.log") else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "".write(to: url, atomically: true, encoding: .utf8)
        handle = try? FileHandle(forWritingTo: url)
    }
    private static func append(_ message: String) {
        let elapsed = Date().timeIntervalSince(launchDate)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let stamp = formatter.string(from: Date())
        let line = "[\(stamp)] [T+\(String(format: "%.2f", elapsed))s] \(message)\n"
        if let data = line.data(using: .utf8) {
            handle?.write(data)
        }
    }
}
struct SourceItem: Identifiable, Hashable {
    let id: CGWindowID
    let appName: String
    let title: String
    let isOnScreen: Bool
    let isActive: Bool
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
        case .topLeft: return "Top Left"
        case .topCenter: return "Top"
        case .topRight: return "Top Right"
        case .middleLeft: return "Left"
        case .middleCenter: return "Center"
        case .middleRight: return "Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomCenter: return "Bottom"
        case .bottomRight: return "Bottom Right"
        }
    }
    var icon: String {
        switch self {
        case .topLeft: return "arrow.up.left"
        case .topCenter: return "arrow.up"
        case .topRight: return "arrow.up.right"
        case .middleLeft: return "arrow.left"
        case .middleCenter: return "circle.fill"
        case .middleRight: return "arrow.right"
        case .bottomLeft: return "arrow.down.left"
        case .bottomCenter: return "arrow.down"
        case .bottomRight: return "arrow.down.right"
        }
    }
}
enum CameraShape: String, CaseIterable, Codable {
    case circle = "Circle"
    case square = "Square"
    case rounded = "Rounded"
}
enum AnnotationTool: String, CaseIterable {
    case pen
    case laser
}
enum AnnotationColor: String, CaseIterable {
    case red
    case yellow
    case green
    case blue
    case white
    var color: Color {
        switch self {
        case .red: return Color(red: 0.95, green: 0.30, blue: 0.25)
        case .yellow: return Color(red: 1.0, green: 0.85, blue: 0.20)
        case .green: return Color(red: 0.30, green: 0.85, blue: 0.40)
        case .blue: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .white: return Color.white
        }
    }
}
struct AnnotationStroke: Identifiable {
    var id = UUID()
    var points: [CGPoint]
    var color: AnnotationColor
    var widthFraction: CGFloat
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
    var cameraMarginVertical: Double = 16
    var cameraMarginHorizontal: Double = 16
    var cameraDeviceID: String? = nil
    var isBuiltIn: Bool = false
    var fileURL: String? = nil
    var fileName: String? = nil
    var fileKind: FileKind? = nil
    var filePageIndex: Int = 0
    var files: [PresetFile] = []
    var activeFileURL: String? = nil
    var sourceAppNames: [String] = []
}
struct LastSession: Codable {
    var mode: ShareMode = .allow
    var framing: Framing = .full
    var canvasMode: CanvasMode = .isolated
    var canvasBackground: CanvasBackground = .gray
    var selectedWindowIDs: [CGWindowID] = []
    var displayID: UInt32? = nil
    var activePresetID: UUID? = nil
    var cameraEnabled: Bool = true
    var cameraPosition: CameraPosition = .bottomRight
    var cameraShape: CameraShape = .rounded
    var cameraSize: Double = 110
    var cameraMirrored: Bool = false
    var cameraMarginVertical: Double = 16
    var cameraMarginHorizontal: Double = 16
    var cameraDeviceID: String? = nil
    var wasSharing: Bool = false
}
enum PresentationTimerMode: String {
    case countUp
    case countDown
}
@MainActor
final class VeilModel: NSObject, ObservableObject {
    @Published var sources: [SourceItem] = []
    @Published var displays: [SCDisplay] = []
    @Published var selectedDisplayID: UInt32? { didSet { saveLastSession() } }
    @Published var selectedWindowIDs: Set<CGWindowID> = [] { didSet { saveLastSession() } }
    @Published var searchText = ""
    @Published var mode: ShareMode = .allow { didSet { saveLastSession() } }
    @Published var framing: Framing = .full { didSet { saveLastSession() } }
    @Published var canvasMode: CanvasMode = .isolated { didSet { saveLastSession() } }
    @Published var canvasBackground: CanvasBackground = .gray { didSet { saveLastSession() } }
    @Published var canvasImage: NSImage? { didSet { saveLastCanvasImage(canvasImage) } }
    @Published var alwaysOnTop = true
    @Published var cameraEnabled = true { didSet { DebugLog.log("camera: \(cameraEnabled ? "on" : "off")"); saveLastSession() } }
    @Published var cameraPosition: CameraPosition = .bottomRight { didSet { saveLastSession() } }
    @Published var cameraShape: CameraShape = .rounded { didSet { saveLastSession() } }
    @Published var cameraSize: Double = 110 { didSet { saveLastSession() } }
    @Published var cameraMirrored = false { didSet { saveLastSession() } }
    @Published var cameraMarginVertical: Double = 16 { didSet { saveLastSession() } }
    @Published var cameraMarginHorizontal: Double = 16 { didSet { saveLastSession() } }
    @Published var cameraDeviceID: String? = nil { didSet { saveLastSession() } }
    @Published var isSharing = false { didSet { saveLastSession() } }
    @Published var isPanic = false
    @Published var isPaused = false
    @Published var presentationElapsed: TimeInterval = 0
    @Published var presentationTimerActive = false
    @Published var presentationTimerExpanded = false
    @Published var presentationTimerMode: PresentationTimerMode = {
        UserDefaults.standard.string(forKey: "Veil.timerMode") == "countDown" ? .countDown : .countUp
    }() { didSet { UserDefaults.standard.set(presentationTimerMode.rawValue, forKey: "Veil.timerMode") } }
    @Published var countdownDuration: TimeInterval = {
        let saved = UserDefaults.standard.double(forKey: "Veil.countdownDuration")
        return saved > 0 ? saved : 1800
    }() { didSet { UserDefaults.standard.set(countdownDuration, forKey: "Veil.countdownDuration") } }
    @Published var annotationExpanded = false
    @Published var previewImage: NSImage?
    @Published var streamHasFrame = false
    @Published var previewLiveImage: NSImage?
    @Published var previewSnapshotImage: NSImage?
    @Published var livePositionedFrame: CGRect?
    var livePositionedWindowID: CGWindowID?
    @Published var status = "Ready. Stream will start automatically."
    @Published var presets: [Preset] = []
    @Published var activePresetID: UUID? { didSet { saveLastSession() } }
    @Published var isPreviewVisible = true
    @Published var isCaptureAreaVisible = false
    @Published var previewRenderedRatio: CGFloat = 0
    @Published var sourceAspectRatio: CGFloat = 0
    @Published var fileSources: [FileSource] = []
    @Published var activeFileID: UUID?
    @Published var filePageIndex = 0
    @Published var filePreviewImage: NSImage?
    @Published var annotationEnabled = false
    @Published var annotationTool: AnnotationTool = .pen
    @Published var annotationColor: AnnotationColor = .red
    @Published var annotationStrokes: [AnnotationStroke] = []
    @Published var laserPosition: CGPoint? = nil
    static let annotationPenWidthFraction: CGFloat = 0.004
    var shouldShowStreamPreview: Bool {
        isSharing && !(mode == .allow && canvasMode == .isolated && selectedWindowIDs.isEmpty)
    }
    var isNothingSelected: Bool {
        mode == .allow && canvasMode == .isolated && selectedWindowIDs.isEmpty && activeFile == nil
    }
    var capturedWindows: [SCWindow] = []
    var capturedApplications: [SCRunningApplication] = []
    var dynamicCaptureUnion: CGRect?
    var pendingDynamicUnion: CGRect?
    var lastControlFrame: CGRect?
    private var previewSnapshotTimer: Timer?
    private var presentationTimer: Timer?
    private var presentationAccumulated: TimeInterval = 0
    private var presentationCountingSince: Date?
    private var positionPollTimer: Timer?
    private var stream: SCStream?
    private var snapshotStream: SCStream?
    private var pdfDocument: PDFDocument?
    private var filePageCache: [Int: NSImage] = [:]
    private var fileOverviewCache: [Int: NSImage] = [:]
    private var filePageKeyMonitor: Any?
    private var captureWatchdog: Timer?
    private var lastCaptureSignature = ""
    private var lastPositionSignature = ""
    private var watchdogFailureCount = 0
    private var sharingActivity: NSObjectProtocol?
    private let presetsKey = "Veil.presets"
    private let lastSessionKey = "Veil.v2.lastSession"
    private var launchAutoStart = true
    private var launchRetryPending = false
    private var lastStripRetry = Date.distantPast
    private var lastWindowRatio: CGFloat = 0
    private var isFirstRefresh = true
    private var initialRefreshStarted = false
    override init() {
        super.init()
        DebugLog.start()
        loadPresets()
        addBuiltInPresetsIfNeeded()
        restoreLastSession()
        installFilePageKeyMonitor()
        startPresentationTimer()
        refreshSources()
        DebugLog.log("init done: sources=\(sources.count) windows, selected=\(selectedWindowIDs.count) display=\(selectedDisplayID ?? 0)")
    }
    deinit {
        presentationTimer?.invalidate()
        if let monitor = filePageKeyMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
    private func installFilePageKeyMonitor() {
        filePageKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.activeFile != nil else { return event }
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView || responder is NSTextField {
                return event
            }
            switch event.keyCode {
            case 124, 125, 121, 49:
                if self.nextFilePage() { return nil }
            case 123, 126, 116:
                if self.previousFilePage() { return nil }
            default:
                break
            }
            return event
        }
    }
    func saveLastSession() {
        let session = LastSession(mode: mode, framing: framing, canvasMode: canvasMode, canvasBackground: canvasBackground, selectedWindowIDs: Array(selectedWindowIDs), displayID: selectedDisplayID, activePresetID: activePresetID, cameraEnabled: cameraEnabled, cameraPosition: cameraPosition, cameraShape: cameraShape, cameraSize: cameraSize, cameraMirrored: cameraMirrored, cameraMarginVertical: cameraMarginVertical, cameraMarginHorizontal: cameraMarginHorizontal, cameraDeviceID: cameraDeviceID, wasSharing: isSharing)
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: lastSessionKey)
        }
    }
    private func loadLastSession() -> LastSession? {
        guard let data = UserDefaults.standard.data(forKey: lastSessionKey),
              let session = try? JSONDecoder().decode(LastSession.self, from: data) else { return nil }
        return session
    }
    private func restoreLastSession() {
        guard let session = loadLastSession() else { return }
        mode = session.mode
        framing = session.framing
        canvasMode = session.canvasMode
        canvasBackground = session.canvasBackground
        selectedWindowIDs = Set(session.selectedWindowIDs)
        selectedDisplayID = session.displayID
        if let id = session.activePresetID, let preset = presets.first(where: { $0.id == id }) {
            activePresetID = id
            if !preset.files.isEmpty || preset.fileURL != nil {
                applyPresetFiles(preset)
            }
        }
        cameraEnabled = session.cameraEnabled
        cameraPosition = session.cameraPosition
        cameraShape = session.cameraShape
        cameraSize = session.cameraSize
        cameraMirrored = session.cameraMirrored
        cameraMarginVertical = session.cameraMarginVertical
        cameraMarginHorizontal = session.cameraMarginHorizontal
        cameraDeviceID = session.cameraDeviceID
        if session.canvasBackground == .custom {
            if let image = loadLastCanvasImage() {
                canvasImage = image
            } else {
                canvasBackground = .gray
            }
        }
        DebugLog.log("session: restored mode=\(session.mode) canvas=\(session.canvasMode) windows=\(session.selectedWindowIDs.count) display=\(session.displayID ?? 0) preset=\(session.activePresetID != nil) sharing=\(session.wasSharing)")
        launchAutoStart = true
    }
    private func lastCanvasImageURL() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        return base.appendingPathComponent("Veil/last-canvas-image.tiff")
    }
    private func saveLastCanvasImage(_ image: NSImage?) {
        guard let url = lastCanvasImageURL() else { return }
        if let image, let data = image.tiffRepresentation {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url)
        } else {
            try? FileManager.default.removeItem(at: url)
        }
    }
    private func loadLastCanvasImage() -> NSImage? {
        guard let url = lastCanvasImageURL(), let image = NSImage(contentsOf: url) else { return nil }
        return image
    }
    private func addBuiltInPresetsIfNeeded() {
        let builtIns = [
            Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!, name: "Presentation", mode: .allow, framing: .full, canvasMode: .isolated, canvasBackground: .black, selectedWindowIDs: [], displayID: nil, cameraEnabled: true, cameraPosition: .bottomRight, cameraShape: .rounded, cameraSize: 110, cameraMirrored: false, isBuiltIn: true),
            Preset(id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!, name: "Meeting", mode: .allow, framing: .full, canvasMode: .isolated, canvasBackground: .black, selectedWindowIDs: [], displayID: nil, cameraEnabled: true, cameraPosition: .bottomRight, cameraShape: .rounded, cameraSize: 110, cameraMirrored: false, isBuiltIn: true)
        ]
        for preset in builtIns where !presets.contains(where: { $0.name.lowercased() == preset.name.lowercased() }) {
            presets.append(preset)
        }
    }
    func isDefaultPreset(_ preset: Preset) -> Bool {
        preset.selectedWindowIDs.isEmpty && preset.framing == .full && preset.canvasBackground == .black && preset.canvasMode == .isolated && preset.mode == .allow
    }
    func resetPreset(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.mode = .allow
        updated.framing = .full
        updated.canvasMode = .isolated
        updated.canvasBackground = .black
        updated.selectedWindowIDs = []
        updated.displayID = nil
        updated.cameraEnabled = true
        updated.cameraPosition = .bottomRight
        updated.cameraShape = .rounded
        updated.cameraSize = 110
        updated.cameraMirrored = false
        updated.cameraMarginVertical = 16
        updated.cameraMarginHorizontal = 16
        updated.cameraDeviceID = nil
        updated.fileURL = nil
        updated.fileName = nil
        updated.fileKind = nil
        updated.filePageIndex = 0
        updated.files = []
        updated.activeFileURL = nil
        updated.sourceAppNames = []
        presets[index] = updated
        persistPresets()
        if activePresetID == preset.id {
            applyPreset(updated)
        }
        status = "Preset '\(updated.name)' reset to default."
    }
    func movePreset(_ preset: Preset, up: Bool) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }), !preset.isBuiltIn else { return }
        let target = up ? index - 1 : index + 1
        guard target >= 0, target < presets.count, !presets[target].isBuiltIn else { return }
        var updated = presets
        let element = updated.remove(at: index)
        updated.insert(element, at: target)
        presets = updated
        persistPresets()
    }
    var selectedAppCount: Int {
        Set(sources.filter { selectedWindowIDs.contains($0.id) }.map { $0.appName }).count
    }
    var sourceRuleCount: Int {
        selectedAppCount + (activeFile != nil ? 1 : 0)
    }
    var isSelectionOffScreen: Bool {
        guard !selectedWindowIDs.isEmpty, canvasMode != .fullDisplay, mode == .allow, framing == .dynamic else { return false }
        guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first else { return false }
        guard let union = dynamicUnionFrame() else { return false }
        return sourceRect(for: union, on: display) == nil
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
        if selectedDisplayID == nil {
            return "No Display"
        }
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) {
            return "\(display.width)x\(display.height)"
        }
        return displays.isEmpty ? "Choose a display" : "Display \(selectedDisplayID ?? 0)"
    }
    var groupedSources: [(app: String, items: [SourceItem])] {
        let grouped = Dictionary(grouping: visibleSources, by: { $0.appName })
        return grouped.keys.sorted().map { (app: $0, items: grouped[$0] ?? []) }
    }
    func updateRatioFromImage(_ image: NSImage) {
        guard filePreviewImage == nil, image.size.width > 0, image.size.height > 0 else { return }
        if image.size.width < 400, image.size.height < 400 {
            let imageRatio = image.size.width / image.size.height
            if imageRatio > 0.8, imageRatio < 1.25 { return }
        }
        let ratio = image.size.width / image.size.height
        if abs(ratio - sourceAspectRatio) > 0.0005 {
            sourceAspectRatio = ratio
            resizeCaptureAreaWindow()
        }
    }
    func fullDisplayFrameSize() -> CGSize? {
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == selectedDisplayID
        } ?? NSScreen.main
        if let screen, screen.frame.width > 0, screen.frame.height > 0 {
            return screen.frame.size
        }
        if let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first, display.height > 0 {
            let scale = NSScreen.main?.backingScaleFactor ?? 1
            return CGSize(width: CGFloat(display.width) / scale, height: CGFloat(display.height) / scale)
        }
        return nil
    }
    func dynamicUnionWindows() -> [SCWindow] {
        let selected = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }
        let onScreen = selected.filter { $0.isOnScreen }
        return onScreen.isEmpty ? selected : onScreen
    }
    private func isStripThumbnail(_ window: SCWindow) -> Bool {
        let frame = window.frame
        return frame.width <= 200 && frame.height <= 200 && frame.origin.x < 100
    }
    func stripThumbnailWindow() -> SCWindow? {
        if selectedWindowIDs.count == 1, let onlyID = selectedWindowIDs.first,
           let onlyWindow = capturedWindows.first(where: { $0.windowID == onlyID }),
           isStripThumbnail(onlyWindow) {
            return onlyWindow
        }
        let union = dynamicUnionWindows()
        if union.count == 1, let singleWindow = union.first, isStripThumbnail(singleWindow) {
            return singleWindow
        }
        return nil
    }
    func bringSelectedAppToFront() {
        guard let id = selectedWindowIDs.first,
              let window = capturedWindows.first(where: { $0.windowID == id }),
              let pid = window.owningApplication?.processID,
              let app = NSRunningApplication(processIdentifier: pid) else { return }
        app.activate()
        DebugLog.log("bringToFront: activated pid=\(pid) window=\(window.windowID)")
    }
    var effectiveSingleWindowID: CGWindowID? {
        if selectedWindowIDs.count == 1 {
            return selectedWindowIDs.first
        }
        let union = dynamicUnionWindows()
        if union.count == 1 {
            return union.first?.windowID
        }
        return nil
    }
    func dynamicUnionFrame() -> CGRect? {
        dynamicUnionWindows().map { $0.frame }.reduce(nil as CGRect?, { $0 == nil ? $1 : $0!.union($1) })
    }
    func updateSourceAspectRatio() {
        if canvasMode == .fullDisplay, filePreviewImage == nil, let size = fullDisplayFrameSize(), size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            if abs(ratio - sourceAspectRatio) > 0.0005 {
                sourceAspectRatio = ratio
                resizeCaptureAreaWindow()
            }
            return
        }
        var size: CGSize?
        if let image = filePreviewImage {
            size = image.size
        } else if let image = previewImage, !CaptureRouting.shared.isStripCapture() {
            size = image.size
        } else if !isSharing, let image = previewSnapshotImage, !CaptureRouting.shared.isStripCapture() {
            size = image.size
        } else if selectedWindowIDs.count == 1,
                  let onlyID = selectedWindowIDs.first,
                  let window = capturedWindows.first(where: { $0.windowID == onlyID }) {
            if isStripThumbnail(window),
               let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first {
                size = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            } else {
                size = window.frame.size
                if window.frame.height > 0 {
                    lastWindowRatio = window.frame.width / window.frame.height
                }
            }
        } else if mode == .allow, framing == .dynamic, !selectedWindowIDs.isEmpty {
            if let union = dynamicUnionFrame() {
                size = union.size
            }
        }
        if size == nil, selectedWindowIDs.isEmpty,
           let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first {
            size = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
        }
        guard let size = size, size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if abs(ratio - sourceAspectRatio) > 0.0005 {
            sourceAspectRatio = ratio
            resizeCaptureAreaWindow()
        }
    }
    func updateSourceAspectRatioFromSelection() {
        guard filePreviewImage == nil else { return }
        if canvasMode == .fullDisplay, let size = fullDisplayFrameSize(), size.width > 0, size.height > 0 {
            let ratio = size.width / size.height
            if abs(ratio - sourceAspectRatio) > 0.0005 {
                sourceAspectRatio = ratio
                resizeCaptureAreaWindow()
            }
            return
        }
        var size: CGSize?
        if let image = previewImage, !CaptureRouting.shared.isStripCapture() {
            size = image.size
        } else if !isSharing, let image = previewSnapshotImage, !CaptureRouting.shared.isStripCapture() {
            size = image.size
        } else if selectedWindowIDs.count == 1,
           let onlyID = selectedWindowIDs.first,
           let window = capturedWindows.first(where: { $0.windowID == onlyID }) {
            if isStripThumbnail(window),
               let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first {
                size = CGSize(width: CGFloat(display.width), height: CGFloat(display.height))
            } else {
                size = window.frame.size
                if window.frame.height > 0 {
                    lastWindowRatio = window.frame.width / window.frame.height
                }
            }
        } else if mode == .allow, framing == .dynamic, !selectedWindowIDs.isEmpty {
            if let union = dynamicUnionFrame() {
                size = union.size
            }
        }
        guard let size = size, size.width > 0, size.height > 0 else { return }
        let ratio = size.width / size.height
        if abs(ratio - sourceAspectRatio) > 0.0005 {
            sourceAspectRatio = ratio
            resizeCaptureAreaWindow()
        }
    }
    func refreshPreviewSnapshot() {
        guard !isSharing, !isPanic, filePreviewImage == nil,
              mode == .allow, !selectedWindowIDs.isEmpty, !isSelectionOffScreen else {
            previewSnapshotImage = nil
            return
        }
        let selectedWindows = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }
        guard !selectedWindows.isEmpty else {
            previewSnapshotImage = nil
            return
        }
        guard snapshotStream == nil else { return }
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        let filter: SCContentFilter
        if canvasMode == .fullDisplay {
            guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first else {
                previewSnapshotImage = nil
                return
            }
            let veilApps = capturedApplications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            if veilApps.isEmpty {
                let excluded = capturedWindows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingWindows: excluded)
            } else {
                filter = SCContentFilter(display: display, excludingApplications: veilApps, exceptingWindows: [])
            }
            config.width = display.width
            config.height = display.height
        } else if selectedWindows.count == 1, let onlyWindow = selectedWindows.first {
            let frame = onlyWindow.frame
            let scale = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 1
            filter = SCContentFilter(desktopIndependentWindow: onlyWindow)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
        } else if let singleWindow = dynamicUnionWindows().first, dynamicUnionWindows().count == 1 {
            let frame = singleWindow.frame
            let scale = NSScreen.screens.first(where: { $0.frame.intersects(frame) })?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 1
            filter = SCContentFilter(desktopIndependentWindow: singleWindow)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
        } else {
            guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first,
                  let union = dynamicUnionFrame(), union.width > 0, union.height > 0 else {
                previewSnapshotImage = nil
                return
            }
            let excluded = capturedWindows.filter { !selectedWindowIDs.contains($0.windowID) || $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            if framing == .dynamic {
                if let rect = sourceRect(for: union, on: display) {
                    config.sourceRect = rect
                    let scale = NSScreen.screens.first(where: { $0.frame.intersects(union) })?.backingScaleFactor
                        ?? NSScreen.main?.backingScaleFactor ?? 1
                    config.width = max(2, Int(rect.width * scale))
                    config.height = max(2, Int(rect.height * scale))
                } else {
                    previewSnapshotImage = nil
                    return
                }
            } else if let (rect, scale) = displayWithoutMenuBar(for: display) {
                config.sourceRect = rect
                config.width = max(2, Int(rect.width * scale))
                config.height = max(2, Int(rect.height * scale))
            } else {
                config.width = display.width
                config.height = display.height
            }
        }
        do {
            let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
            try newStream.addStreamOutput(
                self, type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "veil.snapshot", qos: .userInteractive)
            )
            snapshotStream = newStream
            CaptureRouting.shared.setSnapshotStreamID(ObjectIdentifier(newStream))
            Task {
                do {
                    try await newStream.startCapture()
                } catch {
                    await MainActor.run {
                        if self.snapshotStream === newStream {
                            self.stopSnapshotStream()
                            self.previewSnapshotImage = nil
                        }
                    }
                }
            }
        } catch {
            previewSnapshotImage = nil
        }
    }
    func stopSnapshotStream() {
        let oldStream = snapshotStream
        snapshotStream = nil
        CaptureRouting.shared.setSnapshotStreamID(nil)
        Task { try? await oldStream?.stopCapture() }
    }
    private func startPresentationTimer() {
        guard presentationTimer == nil else { return }
        presentationTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let counting = self.presentationTimerActive && !self.isPaused && !self.isPanic
                if counting {
                    let since = self.presentationCountingSince ?? Date()
                    self.presentationCountingSince = since
                    self.presentationElapsed = self.presentationAccumulated + Date().timeIntervalSince(since)
                    if self.presentationTimerMode == .countDown && self.presentationElapsed >= self.countdownDuration {
                        self.presentationElapsed = self.countdownDuration
                        self.presentationAccumulated = self.countdownDuration
                        self.presentationCountingSince = nil
                        self.presentationTimerActive = false
                    }
                } else if let since = self.presentationCountingSince {
                    self.presentationAccumulated += Date().timeIntervalSince(since)
                    self.presentationCountingSince = nil
                    self.presentationElapsed = self.presentationAccumulated
                }
            }
        }
    }
    func resetPresentationTimer() {
        DebugLog.log("timer: reset")
        presentationTimerActive = false
        presentationAccumulated = 0
        presentationCountingSince = nil
        presentationElapsed = 0
    }
    func togglePresentationTimer() {
        if presentationTimerActive {
            if let since = presentationCountingSince {
                presentationAccumulated += Date().timeIntervalSince(since)
                presentationCountingSince = nil
            }
            presentationElapsed = presentationAccumulated
            presentationTimerActive = false
            DebugLog.log("timer: pause \(presentationTimerText)")
        } else {
            presentationCountingSince = Date()
            presentationTimerActive = true
            DebugLog.log("timer: start \(presentationTimerMode)")
        }
    }
    var presentationTimerRunning: Bool {
        presentationTimerActive && !isPaused && !isPanic
    }
    var countdownRemaining: TimeInterval {
        max(0, countdownDuration - presentationElapsed)
    }
    func toggleTimerMode() {
        presentationTimerMode = presentationTimerMode == .countUp ? .countDown : .countUp
        DebugLog.log("timer: mode \(presentationTimerMode)")
        presentationAccumulated = 0
        presentationCountingSince = presentationTimerActive ? Date() : nil
        presentationElapsed = 0
        if presentationTimerExpanded {
            setTimerControlExpanded(true)
        }
    }
    func setCountdownDuration(_ duration: TimeInterval) {
        countdownDuration = max(60, min(duration, 36000))
        DebugLog.log("timer: countdown \(Int(countdownDuration))s")
        presentationAccumulated = 0
        presentationCountingSince = presentationTimerActive ? Date() : nil
        presentationElapsed = 0
    }
    var presentationTimerText: String {
        let total = Int(presentationTimerMode == .countDown ? countdownRemaining : presentationElapsed)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        let showHours = presentationTimerMode == .countDown ? countdownDuration >= 3600 : hours > 0
        if showHours {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
    func startPreviewSnapshotTimer() {
        guard !isSharing, previewSnapshotTimer == nil else { return }
        previewSnapshotTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if self?.launchRetryPending == true {
                    self?.refreshSources()
                } else {
                    self?.refreshPreviewSnapshot()
                }
            }
        }
    }
    func stopPreviewSnapshotTimer() {
        previewSnapshotTimer?.invalidate()
        previewSnapshotTimer = nil
        stopSnapshotStream()
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
    func lowerWindowsForPicker() {
        for window in NSApp.windows {
            window.level = .normal
        }
    }
    func showPickerSheet(_ panel: NSOpenPanel, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let parent = PanelWindowStore.shared.window {
            panel.beginSheetModal(for: parent, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    private static func normalLayerWindowIDs() -> Set<CGWindowID>? {
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[CFString: Any]] else { return nil }
        var ids = Set<CGWindowID>()
        for entry in info {
            guard let number = entry[kCGWindowNumber] as? NSNumber,
                  let layer = entry[kCGWindowLayer] as? NSNumber, layer.intValue == 0 else { continue }
            ids.insert(number.uint32Value)
        }
        return ids.isEmpty ? nil : ids
    }
    private static func isFullscreenWindow(_ window: SCWindow) -> Bool {
        let frame = window.frame
        return NSScreen.screens.contains { screen in
            abs(frame.origin.x - screen.frame.origin.x) < 2 &&
            abs(frame.origin.y - screen.frame.origin.y) < 2 &&
            abs(frame.width - screen.frame.width) < 2 &&
            abs(frame.height - screen.frame.height) < 2
        }
    }
    private static func sourceItems(from windows: [SCWindow]) -> [SourceItem] {
        let regularProcessIDs = Set(NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .map { $0.processIdentifier })
        let withoutLayer = windows.filter { window in
            guard let app = window.owningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier,
                  regularProcessIDs.contains(app.processID) else { return false }
            return window.frame.width >= 20 && window.frame.height >= 20
        }
        let normalLayers = normalLayerWindowIDs().flatMap { normal in
            withoutLayer.contains(where: { normal.contains($0.windowID) }) ? normal : nil
        }
        let base = withoutLayer.filter { window in
            if let normal = normalLayers, !normal.contains(window.windowID) { return false }
            return true
        }
        var kept: [SCWindow] = []
        for (_, appWindows) in Dictionary(grouping: base, by: { $0.owningApplication?.applicationName ?? "App" }) {
            let titled = appWindows.filter { $0.title?.isEmpty == false }
            if titled.isEmpty {
                if let largest = appWindows.max(by: { ($0.frame.width * $0.frame.height) < ($1.frame.width * $1.frame.height) }) {
                    kept.append(largest)
                }
            } else {
                kept.append(contentsOf: titled)
            }
        }
        var seen = Set<CGWindowID>()
        return kept
            .sorted {
                if $0.isActive != $1.isActive { return $0.isActive }
                if $0.isOnScreen != $1.isOnScreen { return $0.isOnScreen }
                let app0 = $0.owningApplication?.applicationName ?? "App"
                let app1 = $1.owningApplication?.applicationName ?? "App"
                if app0 != app1 { return app0 < app1 }
                let title0 = ($0.title?.isEmpty == false ? $0.title! : "Untitled window")
                let title1 = ($1.title?.isEmpty == false ? $1.title! : "Untitled window")
                if title0 != title1 { return title0 < title1 }
                return $0.windowID < $1.windowID
            }
            .compactMap { window -> SourceItem? in
                guard seen.insert(window.windowID).inserted else { return nil }
                let appName = window.owningApplication?.applicationName ?? "App"
                let title = (window.title?.isEmpty == false ? window.title! : "Untitled window")
                return SourceItem(id: window.windowID, appName: appName, title: title, isOnScreen: window.isOnScreen, isActive: window.isActive)
            }
            .sorted {
                if $0.appName != $1.appName { return $0.appName < $1.appName }
                return $0.title < $1.title
            }
    }
    private func defaultDisplayID(from displays: [SCDisplay]) -> UInt32? {
        displays.first(where: { CGDisplayIsBuiltin($0.displayID) != 0 })?.displayID ?? displays.first?.displayID
    }
    func refreshSources() {
        if isFirstRefresh {
            guard !initialRefreshStarted else { return }
            initialRefreshStarted = true
        }
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false
                )
                let wasEmpty = displays.isEmpty
                displays = content.displays
                if selectedDisplayID == nil, wasEmpty {
                    selectedDisplayID = defaultDisplayID(from: content.displays)
                }
                capturedWindows = content.windows
                capturedApplications = content.applications
                sources = Self.sourceItems(from: content.windows)
                updateSourceAspectRatio()
                resizeCaptureAreaWindow()
                if isFirstRefresh {
                    isFirstRefresh = false
                    if let id = selectedDisplayID, !displays.contains(where: { $0.displayID == id }) {
                        selectedDisplayID = defaultDisplayID(from: displays)
                    }
                    if launchAutoStart, !isSharing, !isPanic, filePreviewImage == nil, selectedDisplayID != nil {
                        launchAutoStart = false
                        bringSelectedAppToFront()
                        Task {
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            await MainActor.run {
                                if !self.isSharing, !self.isPanic, self.filePreviewImage == nil, self.selectedDisplayID != nil {
                                    self.startCaptureWithFreshSources()
                                }
                            }
                        }
                        return
                    }
                    launchAutoStart = false
                }
                if launchRetryPending, !isSharing, !isPanic, filePreviewImage == nil, selectedDisplayID != nil {
                    launchRetryPending = false
                    startCapture()
                    return
                }
                status = "\(sources.count) windows on \(content.displays.count) displays."
                let selectedLive = content.windows.filter { selectedWindowIDs.contains($0.windowID) }.map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))" }.joined(separator: ",")
                DebugLog.log("refreshSources: \(content.windows.count) windows, \(content.applications.count) apps, selectedLive=[\(selectedLive)]")
            } catch {
                if isFirstRefresh {
                    initialRefreshStarted = false
                }
                status = "Failed to read windows: \(error.localizedDescription). Check Screen Recording permission."
                DebugLog.log("refreshSources ERROR: \(error.localizedDescription)")
            }
        }
    }
    func refreshSourceFramesAndApply() {
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true, onScreenWindowsOnly: false
                )
                capturedWindows = content.windows
                capturedApplications = content.applications
                displays = content.displays
                sources = Self.sourceItems(from: content.windows)
                updateSourceAspectRatio()
                resizeCaptureAreaWindow()
            } catch {
            }
        }
    }
    func isWindowShown(_ id: CGWindowID) -> Bool {
        mode == .allow ? selectedWindowIDs.contains(id) : !selectedWindowIDs.contains(id)
    }
    func toggleApp(_ app: String) {
        let ids = sources.filter { $0.appName == app }.map { $0.id }
        guard !ids.isEmpty else { return }
        let wasAdding = !ids.allSatisfy({ selectedWindowIDs.contains($0) })
        if wasAdding {
            ids.forEach { selectedWindowIDs.insert($0) }
        } else {
            ids.forEach { selectedWindowIDs.remove($0) }
        }
        DebugLog.log("toggleApp \(app): wasAdding=\(wasAdding) ids=\(ids) selected=\(selectedWindowIDs.sorted())")
        if isSharing {
            previewSnapshotImage = nil
        } else {
            previewImage = nil
            previewSnapshotImage = nil
            stopSnapshotStream()
        }
        updateSourceAspectRatio()
        updateSourceAspectRatioFromSelection()
        if isSharing {
            stopPreviewSnapshotTimer()
            if wasAdding {
                bringSelectedAppToFront()
            }
            updateCapture()
        } else if wasAdding, !selectedWindowIDs.isEmpty {
            bringSelectedAppToFront()
            startCaptureWithFreshSources()
        } else {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
    }
    func resetAllSources() {
        DebugLog.log("sources: reset all")
        clearSelection()
        closeFile()
    }
    func toggleSource(_ id: CGWindowID) {
        let wasAdded = !selectedWindowIDs.contains(id)
        if wasAdded {
            selectedWindowIDs.insert(id)
        } else {
            selectedWindowIDs.remove(id)
        }
        DebugLog.log("toggleSource id=\(id): wasAdded=\(wasAdded) selected=\(selectedWindowIDs.sorted())")
        if isSharing {
            previewSnapshotImage = nil
        } else {
            previewImage = nil
            previewSnapshotImage = nil
            stopSnapshotStream()
        }
        updateSourceAspectRatio()
        updateSourceAspectRatioFromSelection()
        if isSharing {
            stopPreviewSnapshotTimer()
            if wasAdded {
                bringSelectedAppToFront()
            }
            updateCapture()
        } else if wasAdded, !selectedWindowIDs.isEmpty {
            bringSelectedAppToFront()
            startCaptureWithFreshSources()
        } else {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
    }
    func clearSelection() {
        selectedWindowIDs.removeAll()
        previewSnapshotImage = nil
        stopPreviewSnapshotTimer()
        updateSourceAspectRatio()
        if isSharing {
            updateCapture()
        }
    }
    func restartCapture() {
        DebugLog.log("restartCapture: called, isSharing=\(isSharing)")
        stopCapture(keepSharing: true)
        startCapture()
    }
    func displayWithoutMenuBar(for display: SCDisplay) -> (CGRect, CGFloat)? {
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == display.displayID
        } ?? NSScreen.main
        guard let screen else { return nil }
        let visible = screen.visibleFrame
        guard visible.width > 0, visible.height > 0 else {
            return (CGRect(x: 0, y: 0, width: screen.frame.width, height: screen.frame.height), screen.backingScaleFactor)
        }
        let rect = CGRect(x: visible.minX - screen.frame.minX, y: screen.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
        return (rect, screen.backingScaleFactor)
    }
    func sourceRect(for frame: CGRect, on display: SCDisplay) -> CGRect? {
        let screen = NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
            return number.uint32Value == display.displayID
        } ?? NSScreen.main
        guard let screen else { return nil }
        let mainHeight = NSScreen.main?.frame.height ?? screen.frame.height
        let screenQuartzTop = mainHeight - screen.frame.maxY
        let localX = frame.minX - screen.frame.minX
        let localY = frame.minY - screenQuartzTop
        let rect = CGRect(x: localX, y: localY, width: frame.width, height: frame.height)
        let visible = screen.visibleFrame
        let bounds = CGRect(x: visible.minX - screen.frame.minX, y: screen.frame.maxY - visible.maxY, width: visible.width, height: visible.height)
        let clipped = rect.intersection(bounds)
        guard clipped.width > 0, clipped.height > 0 else { return nil }
        return clipped
    }
    func captureFilterAndConfig() -> (SCContentFilter, SCStreamConfiguration)? {
        pendingDynamicUnion = nil
        CaptureRouting.shared.setStripCapture(false)
        guard selectedDisplayID != nil else { return nil }
        guard !isNothingSelected else { return nil }
        guard !isSelectionOffScreen else { return nil }
        guard let display = displays.first(where: { $0.displayID == selectedDisplayID }) ?? displays.first else { return nil }
        let config = SCStreamConfiguration()
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.queueDepth = 5
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true
        let scaleFactor: (CGRect) -> CGFloat = { rect in
            NSScreen.screens.first(where: { $0.frame.intersects(rect) })?.backingScaleFactor
                ?? NSScreen.main?.backingScaleFactor ?? 1
        }
        let filter: SCContentFilter
        if canvasMode == .fullDisplay {
            let veilApps = capturedApplications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
            if veilApps.isEmpty {
                let excluded = capturedWindows.filter { $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
                filter = SCContentFilter(display: display, excludingWindows: excluded)
            } else {
                filter = SCContentFilter(display: display, excludingApplications: veilApps, exceptingWindows: [])
            }
            config.width = display.width
            config.height = display.height
        } else if mode == .allow, let stripWindow = stripThumbnailWindow() {
            let frame = stripWindow.frame
            let scale = scaleFactor(frame)
            filter = SCContentFilter(desktopIndependentWindow: stripWindow)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
            CaptureRouting.shared.setStripCapture(true)
            DebugLog.log("strip: branch window \(stripWindow.windowID) frame \(stripWindow.frame) config \(config.width)x\(config.height) positioned=\(isPositionedCanvas) canvas=\(canvasMode)")
        } else if mode == .allow, selectedWindowIDs.count == 1,
                  let onlyID = selectedWindowIDs.first,
                  let onlyWindow = capturedWindows.first(where: { $0.windowID == onlyID }) {
            let frame = onlyWindow.frame
            let scale = scaleFactor(frame)
            filter = SCContentFilter(desktopIndependentWindow: onlyWindow)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
        } else if mode == .allow,
                  let singleWindow = dynamicUnionWindows().first, dynamicUnionWindows().count == 1 {
            let frame = singleWindow.frame
            let scale = scaleFactor(frame)
            filter = SCContentFilter(desktopIndependentWindow: singleWindow)
            config.width = max(2, Int(frame.width * scale))
            config.height = max(2, Int(frame.height * scale))
        } else {
            if mode == .allow, !selectedWindowIDs.isEmpty, capturedWindows.filter({ selectedWindowIDs.contains($0.windowID) }).isEmpty {
                return nil
            }
            let excluded: [SCWindow]
            if mode == .allow {
                excluded = capturedWindows.filter { !selectedWindowIDs.contains($0.windowID) || $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
            } else {
                excluded = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) || $0.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier }
            }
            filter = SCContentFilter(display: display, excludingWindows: excluded)
            if mode == .allow, framing == .dynamic, !selectedWindowIDs.isEmpty {
                if let union = dynamicUnionFrame() {
                    pendingDynamicUnion = union
                    if let rect = sourceRect(for: union, on: display) {
                        config.sourceRect = rect
                        let scale = scaleFactor(union)
                        config.width = max(2, Int(rect.width * scale))
                        config.height = max(2, Int(rect.height * scale))
                    } else {
                        return nil
                    }
                } else if let (rect, scale) = displayWithoutMenuBar(for: display) {
                    config.sourceRect = rect
                    config.width = max(2, Int(rect.width * scale))
                    config.height = max(2, Int(rect.height * scale))
                } else {
                    config.width = display.width
                    config.height = display.height
                }
            } else if let (rect, scale) = displayWithoutMenuBar(for: display) {
                config.sourceRect = rect
                config.width = max(2, Int(rect.width * scale))
                config.height = max(2, Int(rect.height * scale))
            } else {
                config.width = display.width
                config.height = display.height
            }
        }
        return (filter, config)
    }
    func updateCapture() {
        DebugLog.log("updateCapture: called, isSharing=\(isSharing) streamNil=\(stream == nil)")
        guard let current = stream, isSharing else {
            restartCapture()
            return
        }
        guard let (filter, config) = captureFilterAndConfig() else {
            if isNothingSelected {
                stopStreamOnly()
            } else if isSelectionOffScreen {
                stopStreamOnly()
                status = "Selected window is off screen."
            } else if stripThumbnailWindow() != nil, Date().timeIntervalSince(lastStripRetry) > 1 {
                DebugLog.log("updateCapture: filter nil, strip thumbnail, retrying refresh")
                lastStripRetry = Date()
                refreshCaptureFilter()
            }
            DebugLog.log("updateCapture: filter nil, nothingSelected=\(isNothingSelected) offScreen=\(isSelectionOffScreen) strip=\(stripThumbnailWindow() != nil)")
            return
        }
        CaptureRouting.shared.setExpectedMainFrameSize(CGSize(width: config.width, height: config.height))
        DebugLog.log("updateCapture: expected size \(config.width)x\(config.height)")
        let target = current
        Task {
            do {
                try await target.updateContentFilter(filter)
                try await target.updateConfiguration(config)
                await MainActor.run {
                    if self.stream === target {
                        self.dynamicCaptureUnion = self.pendingDynamicUnion
                        self.lastCaptureSignature = self.captureSignature()
                        self.lastPositionSignature = self.positionSignature()
                        self.updateSourceAspectRatioFromSelection()
                        self.resizeCaptureAreaWindow()
                    }
                }
                DebugLog.log("updateCapture: reconfigure ok, config=\(config.width)x\(config.height)")
            } catch {
                DebugLog.log("updateCapture ERROR: \(error.localizedDescription), restarting")
                await MainActor.run { self.restartCapture() }
            }
        }
    }
    func refreshCaptureFilter() {
        guard isSharing else { return }
        DebugLog.log("refreshCaptureFilter: refetching shareable content...")
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                capturedWindows = content.windows
                capturedApplications = content.applications
                displays = content.displays
                sources = Self.sourceItems(from: content.windows)
                guard isSharing, stream != nil else { return }
                let selectedLive = content.windows.filter { selectedWindowIDs.contains($0.windowID) }.map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))" }.joined(separator: ",")
                DebugLog.log("refreshCaptureFilter: fetch ok, \(content.windows.count) windows, selectedLive=[\(selectedLive)]")
                updateCapture()
            } catch {
                DebugLog.log("refreshCaptureFilter ERROR: \(error.localizedDescription)")
            }
        }
    }
    func startCaptureWithFreshSources() {
        DebugLog.log("startCaptureWithFreshSources: fetching, selected=\(selectedWindowIDs.sorted())")
        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                await MainActor.run {
                    displays = content.displays
                    capturedWindows = content.windows
                    capturedApplications = content.applications
                    sources = Self.sourceItems(from: content.windows)
                    updateSourceAspectRatio()
                    resizeCaptureAreaWindow()
                    let selectedLive = content.windows.filter { selectedWindowIDs.contains($0.windowID) }.map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)) onScreen=\($0.isOnScreen)" }.joined(separator: ",")
                    DebugLog.log("startCaptureWithFreshSources: fetch ok, \(content.windows.count) windows, selectedLive=[\(selectedLive)]")
                    if !selectedWindowIDs.isEmpty, !isSharing {
                        startCapture()
                    }
                }
            } catch {
                DebugLog.log("startCaptureWithFreshSources ERROR: \(error.localizedDescription)")
                await MainActor.run {
                    if !selectedWindowIDs.isEmpty, !isSharing {
                        startCapture()
                    }
                }
            }
        }
    }
    func startCapture() {
        stopPreviewSnapshotTimer()
        if stream != nil {
            if isSharing {
                updateCapture()
            } else {
                restartCapture()
            }
            return
        }
        guard !isPanic else {
            status = "Panic mode is on, output is hidden."
            isSharing = false
            return
        }
        guard let (filter, config) = captureFilterAndConfig() else {
            isSharing = false
            if isNothingSelected {
                status = "Nothing is currently selected to share."
                DebugLog.log("startCapture: filter nil, nothing selected")
                return
            }
            if isSelectionOffScreen {
                status = "Selected window is off screen."
                DebugLog.log("startCapture: filter nil, selection off screen")
                return
            }
            status = selectedDisplayID == nil ? "Pause the output until a display is selected." : "No display found. Press Refresh first."
            DebugLog.log("startCapture: filter nil, display=\(selectedDisplayID ?? 0) selected=\(selectedWindowIDs.sorted())")
            if selectedDisplayID != nil {
                launchRetryPending = true
                refreshPreviewSnapshot()
                startPreviewSnapshotTimer()
            }
            return
        }
        let selectedFrames = capturedWindows.filter { selectedWindowIDs.contains($0.windowID) }.map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))@\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y)) onScreen=\($0.isOnScreen)" }.joined(separator: ",")
        DebugLog.log("startCapture: filter ok, config=\(config.width)x\(config.height) showsCursor=\(config.showsCursor) selected=[\(selectedFrames)] mode=\(mode.rawValue) framing=\(framing.rawValue) canvas=\(canvasMode.rawValue)")
        CaptureRouting.shared.setExpectedMainFrameSize(CGSize(width: config.width, height: config.height))
        lastCaptureSignature = captureSignature()
        lastPositionSignature = positionSignature()
        startPositionPoller()
        do {
            let newStream = SCStream(filter: filter, configuration: config, delegate: self)
            try newStream.addStreamOutput(
                self, type: .screen,
                sampleHandlerQueue: DispatchQueue(label: "veil.capture", qos: .userInteractive)
            )
            stream = newStream
            CaptureRouting.shared.setMainStreamID(ObjectIdentifier(newStream))
            streamHasFrame = false
            CaptureRouting.shared.setFirstFrame(false)
            DebugLog.log("startCapture: stream created id=\(ObjectIdentifier(newStream)), starting...")
            Task {
                do {
                    try await newStream.startCapture()
                    await MainActor.run {
                        isSharing = true
                        launchRetryPending = false
                        dynamicCaptureUnion = pendingDynamicUnion
                        beginSharingActivity()
                        stopPreviewSnapshotTimer()
                        status = "Sharing is live (\(selectedAppCount) \(selectedAppCount == 1 ? "app" : "apps")). Share the Output window in Zoom/Meet/Teams."
                        startCaptureWatchdog()
                        resizeCaptureAreaWindow()
                        reopenFileControlIfNeeded()
                        reopenTimerControlIfNeeded()
                    }
                    DebugLog.log("startCapture: stream started, isSharing=true")
                    for attempt in 1...30 {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        let shouldRetry = await MainActor.run {
                            self.isSharing && self.stream === newStream && !self.streamHasFrame
                        }
                        guard shouldRetry else { break }
                        let dropped = CaptureRouting.shared.droppedSummary()
                        DebugLog.log("noFrameRetry attempt=\(attempt): still no frame, dropped=\(dropped.0) lastDropped=\(dropped.1), refetching...")
                        await MainActor.run {
                            self.refreshCaptureFilter()
                        }
                    }
                    let dropped = CaptureRouting.shared.droppedSummary()
                    DebugLog.log("noFrameRetry done: streamHasFrame=\(streamHasFrame) dropped=\(dropped.0) lastDropped=\(dropped.1)")
                } catch {
                    DebugLog.log("startCapture ERROR: \(error.localizedDescription)")
                    await MainActor.run {
                        if self.stream === newStream {
                            self.stream = nil
                            CaptureRouting.shared.setMainStreamID(nil)
                        }
                        status = "Failed to start capture: \(error.localizedDescription)"
                        isSharing = false
                        launchRetryPending = true
                        if !self.isPanic, self.selectedDisplayID != nil {
                            self.refreshPreviewSnapshot()
                            self.startPreviewSnapshotTimer()
                        }
                    }
                }
            }
        } catch {
            status = "Failed to create stream: \(error.localizedDescription)"
            isSharing = false
            if selectedDisplayID != nil {
                launchRetryPending = true
                refreshPreviewSnapshot()
                startPreviewSnapshotTimer()
            }
        }
    }
    func stopCapture(keepSharing: Bool = false) {
        stopCaptureWatchdog()
        stopPositionPoller()
        dynamicCaptureUnion = nil
        pendingDynamicUnion = nil
        let oldStream = stream
        stream = nil
        CaptureRouting.shared.setMainStreamID(nil)
        if !keepSharing {
            isSharing = false
            previewImage = nil
            streamHasFrame = false
            CaptureRouting.shared.setFirstFrame(false)
            previewLiveImage = nil
            closeFile()
            closeCaptureAreaWindow()
            endSharingActivity()
        }
        Task { try? await oldStream?.stopCapture() }
    }
    func stopStreamOnly() {
        stopCaptureWatchdog()
        stopPositionPoller()
        dynamicCaptureUnion = nil
        pendingDynamicUnion = nil
        let oldStream = stream
        stream = nil
        CaptureRouting.shared.setMainStreamID(nil)
        isSharing = false
        previewImage = nil
        previewSnapshotImage = nil
        streamHasFrame = false
        CaptureRouting.shared.setFirstFrame(false)
        previewLiveImage = nil
        endSharingActivity()
        Task { try? await oldStream?.stopCapture() }
    }
    private func captureSignature() -> String {
        let frames = capturedWindows
            .filter { selectedWindowIDs.contains($0.windowID) }
            .sorted { $0.windowID < $1.windowID }
            .map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))" }
            .joined(separator: ",")
        return "\(canvasMode.rawValue)|\(mode.rawValue)|\(framing.rawValue)|\(selectedDisplayID ?? 0)|\(frames)"
    }
    private func positionSignature() -> String {
        capturedWindows
            .filter { selectedWindowIDs.contains($0.windowID) }
            .sorted { $0.windowID < $1.windowID }
            .map { "\($0.windowID):\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))" }
            .joined(separator: ",")
    }
    private func startPositionPoller() {
        stopPositionPoller()
        positionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollPositionedFrame()
            }
        }
    }
    private func stopPositionPoller() {
        positionPollTimer?.invalidate()
        positionPollTimer = nil
    }
    private func pollPositionedFrame() {
        guard isSharing, mode == .allow, positionedCanvasScreen() != nil,
              let windowID = effectiveSingleWindowID,
              let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[CFString: Any]],
              let raw = list.first?[kCGWindowBounds] else { return }
        var bounds: CGRect?
        if let rect = raw as? CGRect {
            bounds = rect
        } else if let dict = raw as? NSDictionary, let rect = CGRect(dictionaryRepresentation: dict) {
            bounds = rect
        }
        guard let bounds, bounds.width > 0, bounds.height > 0 else { return }
        if let old = livePositionedFrame, livePositionedWindowID == windowID,
           abs(old.origin.x - bounds.origin.x) < 0.5, abs(old.origin.y - bounds.origin.y) < 0.5,
           abs(old.width - bounds.width) < 0.5, abs(old.height - bounds.height) < 0.5 {
            resizeCaptureAreaWindow()
            return
        }
        livePositionedWindowID = windowID
        livePositionedFrame = bounds
        resizeCaptureAreaWindow()
    }
    private func startCaptureWatchdog() {
        stopCaptureWatchdog()
        captureWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkCaptureStability()
            }
        }
    }
    private func beginSharingActivity() {
        guard sharingActivity == nil else { return }
        sharingActivity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Live window capture")
    }
    private func endSharingActivity() {
        if let activity = sharingActivity {
            ProcessInfo.processInfo.endActivity(activity)
            sharingActivity = nil
        }
    }
    private func stopCaptureWatchdog() {
        captureWatchdog?.invalidate()
        captureWatchdog = nil
    }
    private func checkCaptureStability() async {
        guard isSharing, stream != nil else { return }
        resizeCaptureAreaWindow()
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            if watchdogFailureCount >= 3 {
                status = "Sharing is live."
            }
            watchdogFailureCount = 0
            let selected = content.windows
                .filter { selectedWindowIDs.contains($0.windowID) }
                .sorted { $0.windowID < $1.windowID }
            let newContentSignature = "\(canvasMode.rawValue)|\(mode.rawValue)|\(framing.rawValue)|\(selectedDisplayID ?? 0)|" + selected.map { "\($0.windowID):\(Int($0.frame.width))x\(Int($0.frame.height))" }.joined(separator: ",")
            let newPositionSignature = selected.map { "\($0.windowID):\(Int($0.frame.origin.x)),\(Int($0.frame.origin.y))" }.joined(separator: ",")
            guard newContentSignature != lastCaptureSignature || newPositionSignature != lastPositionSignature else { return }
            DebugLog.log("watchdog: signature changed, oldContent=\(lastCaptureSignature) newContent=\(newContentSignature) oldPos=\(lastPositionSignature) newPos=\(newPositionSignature)")
            capturedWindows = content.windows
            if displays.map({ $0.displayID }) != content.displays.map({ $0.displayID }) {
                displays = content.displays
            }
            if newContentSignature != lastCaptureSignature {
                sources = Self.sourceItems(from: content.windows)
                lastCaptureSignature = newContentSignature
                lastPositionSignature = newPositionSignature
                updateCapture()
            } else {
                lastPositionSignature = newPositionSignature
                if mode == .allow, framing == .dynamic, canvasMode != .fullDisplay, !selectedWindowIDs.isEmpty {
                    updateCapture()
                }
            }
        } catch {
            watchdogFailureCount += 1
            if watchdogFailureCount == 3 {
                status = "Cannot read windows. Preview may be stuck. Quit and reopen Veil to start again."
            }
        }
    }
    func togglePause() {
        isPaused.toggle()
        CaptureRouting.shared.setPaused(isPaused)
        status = isPaused ? "Paused. Preview and Output are frozen. Press Resume to continue." : "Sharing is live."
    }
    func togglePanic() {
        isPanic.toggle()
        DebugLog.log("panic: \(isPanic ? "on" : "off")")
        if isPanic {
            stopCapture()
            previewImage = nil
            previewSnapshotImage = nil
            stopPreviewSnapshotTimer()
            status = "Panic: output blacked out immediately."
        } else {
            status = "Panic off. Stream resumed."
            startCapture()
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
        DebugLog.log("filePicker: showing")
        showPickerSheet(panel) { [weak self] result in
            guard result == .OK else {
                Task { @MainActor in
                    self?.applyAlwaysOnTop()
                    DebugLog.log("filePicker: cancelled")
                }
                return
            }
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
            Task { @MainActor in
                guard let self else { return }
                self.applyAlwaysOnTop()
                let added = urls.sorted { $0.path < $1.path }.compactMap { self.addFile(url: $0) }.count
                DebugLog.log("filePicker: added=\(added)")
                if added > 0 { self.syncActivePresetFiles() }
                if added == 0 {
                    self.status = "No new PDF or PPT files added."
                } else if added == 1 {
                    self.status = "1 file added. Click a file name to show it."
                } else {
                    self.status = "\(added) files added. Click a file name to show it."
                }
            }
        }
    }
    func choosePresentationFile(completion: @escaping (Bool) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select PDF or PPT files to present."
        panel.allowedContentTypes = [
            .pdf,
            UTType(filenameExtension: "ppt") ?? .data,
            UTType(filenameExtension: "pptx") ?? .data
        ]
        DebugLog.log("chooseFile: showing")
        showPickerSheet(panel) { [weak self] result in
            Task { @MainActor in
                guard let self else { completion(false); return }
                self.applyAlwaysOnTop()
                guard result == .OK, !panel.urls.isEmpty else {
                    DebugLog.log("chooseFile: cancelled")
                    completion(false)
                    return
                }
                self.clearActivePreset()
                self.fileSources.removeAll()
                var first: FileSource?
                for url in panel.urls.sorted(by: { $0.path < $1.path }) {
                    if let existing = self.fileSources.first(where: { $0.url.path == url.path }) {
                        if first == nil { first = existing }
                    } else if let added = self.addFile(url: url), first == nil {
                        first = added
                    }
                }
                guard let active = first else { completion(false); return }
                self.activateFile(active)
                self.syncActivePresetFiles()
                completion(true)
            }
        }
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
            DebugLog.log("file: added \(name) pdf pages=\(item.pageCount)")
            return item
        } else if ext == "ppt" || ext == "pptx" {
            let item = FileSource(name: name, url: url, kind: .ppt, pageCount: 1)
            fileSources.append(item)
            DebugLog.log("file: added \(name) ppt")
            return item
        } else {
            return nil
        }
    }
    func activateFile(_ item: FileSource) {
        DebugLog.log("file: activate \(item.name) \(item.kind) pages=\(item.pageCount)")
        activeFileID = item.id
        filePageIndex = 0
        filePageCache.removeAll()
        fileOverviewCache.removeAll()
        previewSnapshotImage = nil
        stopPreviewSnapshotTimer()
        if isCaptureAreaVisible { openFileControlWindow() }
        if item.kind == .pdf {
            pdfDocument = PDFDocument(url: item.url)
            renderFilePage()
        } else {
            pdfDocument = nil
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: CGSize(width: 2000, height: 2000),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: QLThumbnailGenerator.Request.RepresentationTypes.thumbnail
            )
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
                guard let self, let image = representation?.nsImage else { return }
                Task { @MainActor in
                    self.filePreviewImage = image
                    self.updateSourceAspectRatio()
                    self.resizeCaptureAreaWindow()
                }
            }
        }
    }
    func closeFile() {
        DebugLog.log("file: close")
        activeFileID = nil
        pdfDocument = nil
        filePageCache.removeAll()
        fileOverviewCache.removeAll()
        filePreviewImage = nil
        filePageIndex = 0
        fileSources.removeAll()
        closeFileControlWindow()
        updateSourceAspectRatio()
        resizeCaptureAreaWindow()
        if !isSharing {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
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
    @discardableResult
    func nextFilePage() -> Bool {
        guard let item = activeFile, filePageIndex + 1 < item.pageCount else { return false }
        filePageIndex += 1
        DebugLog.log("file: page \(filePageIndex + 1)/\(item.pageCount)")
        renderFilePage()
        return true
    }
    @discardableResult
    func previousFilePage() -> Bool {
        guard filePageIndex > 0 else { return false }
        filePageIndex -= 1
        DebugLog.log("file: page \(filePageIndex + 1)/\(activeFile?.pageCount ?? 0)")
        renderFilePage()
        return true
    }
    func goToFilePage(_ index: Int) {
        guard let item = activeFile, index >= 0, index < item.pageCount else { return }
        filePageIndex = index
        DebugLog.log("file: page \(filePageIndex + 1)/\(item.pageCount)")
        renderFilePage()
    }
    func filePageThumbnail(at index: Int) -> NSImage? {
        guard let item = activeFile, index >= 0, index < item.pageCount else { return nil }
        if let cached = fileOverviewCache[index] {
            return cached
        }
        guard let document = pdfDocument, let page = document.page(at: index) else { return nil }
        let image = page.thumbnail(of: NSSize(width: 320, height: 320), for: .mediaBox)
        fileOverviewCache[index] = image
        return image
    }
    private func renderFilePage() {
        guard let document = pdfDocument else { return }
        if let cached = filePageCache[filePageIndex] {
            filePreviewImage = cached
        } else if let page = document.page(at: filePageIndex) {
            let image = page.thumbnail(of: NSSize(width: 3000, height: 3000), for: .mediaBox)
            filePageCache[filePageIndex] = image
            filePreviewImage = image
        } else {
            return
        }
        updateSourceAspectRatio()
        resizeCaptureAreaWindow()
        preRenderFileNeighbors()
    }
    private func preRenderFileNeighbors() {
        guard let document = pdfDocument, let item = activeFile else { return }
        filePageCache = filePageCache.filter { abs($0.key - filePageIndex) <= 1 }
        for index in [filePageIndex - 1, filePageIndex + 1] {
            guard index >= 0, index < item.pageCount, filePageCache[index] == nil else { continue }
            Task.detached { [weak self, document] in
                guard let page = document.page(at: index) else { return }
                let image = page.thumbnail(of: NSSize(width: 3000, height: 3000), for: .mediaBox)
                await MainActor.run { [weak self] in
                    guard let self, self.pdfDocument === document else { return }
                    self.filePageCache[index] = image
                }
            }
        }
    }
    func replacePreset(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var updated = preset
        updated.mode = mode
        updated.framing = framing
        updated.canvasMode = canvasMode
        updated.canvasBackground = canvasBackground
        updated.selectedWindowIDs = Array(selectedWindowIDs)
        updated.displayID = nil
        updated.cameraEnabled = cameraEnabled
        updated.cameraPosition = cameraPosition
        updated.cameraShape = cameraShape
        updated.cameraSize = cameraSize
        updated.cameraMirrored = cameraMirrored
        updated.cameraMarginVertical = cameraMarginVertical
        updated.cameraMarginHorizontal = cameraMarginHorizontal
        updated.cameraDeviceID = cameraDeviceID
        updated.fileURL = activeFile?.url.path
        updated.fileName = activeFile?.name
        updated.fileKind = activeFile?.kind
        updated.filePageIndex = filePageIndex
        updated.files = fileSources.map {
            PresetFile(url: $0.url.path, name: $0.name, kind: $0.kind, pageCount: $0.pageCount)
        }
        updated.activeFileURL = activeFile?.url.path
        updated.sourceAppNames = currentSourceAppNames()
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
            displayID: nil,
            cameraEnabled: cameraEnabled,
            cameraPosition: cameraPosition,
            cameraShape: cameraShape,
            cameraSize: cameraSize,
            cameraMirrored: cameraMirrored,
            cameraMarginVertical: cameraMarginVertical,
            cameraMarginHorizontal: cameraMarginHorizontal,
            cameraDeviceID: cameraDeviceID,
            fileURL: activeFile?.url.path,
            fileName: activeFile?.name,
            fileKind: activeFile?.kind,
            filePageIndex: filePageIndex,
            files: fileSources.map {
                PresetFile(url: $0.url.path, name: $0.name, kind: $0.kind, pageCount: $0.pageCount)
            },
            activeFileURL: activeFile?.url.path,
            sourceAppNames: currentSourceAppNames()
        )
        presets.append(preset)
        activePresetID = preset.id
        persistPresets()
        status = "Preset '\(preset.name)' saved."
    }
    var hotkeyPresets: [Preset] {
        Array((presets.filter { !$0.isBuiltIn } + presets.filter { $0.isBuiltIn }).prefix(9))
    }
    func hotkeyNumber(for preset: Preset) -> Int? {
        hotkeyPresets.firstIndex(where: { $0.id == preset.id }).map { $0 + 1 }
    }
    func startAnnotationStroke(at point: CGPoint) {
        annotationStrokes.append(AnnotationStroke(points: [point], color: annotationColor, widthFraction: Self.annotationPenWidthFraction))
    }
    func addAnnotationPoint(_ point: CGPoint) {
        guard !annotationStrokes.isEmpty else { return }
        annotationStrokes[annotationStrokes.count - 1].points.append(point)
    }
    func endAnnotationStroke() {
        if let last = annotationStrokes.last, last.points.count < 2 {
            annotationStrokes.removeLast()
        }
    }
    func clearAnnotations() {
        DebugLog.log("annotation: clear")
        annotationStrokes.removeAll()
        laserPosition = nil
    }
    func applyPresetFiles(_ preset: Preset) {
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
            resizeCaptureAreaWindow()
            closeFileControlWindow()
        }
    }
    func applyPreset(_ preset: Preset) {
        DebugLog.log("preset: apply \(preset.name)")
        activePresetID = preset.id
        mode = preset.mode
        framing = preset.framing
        canvasMode = preset.canvasMode
        canvasBackground = preset.canvasBackground
        if preset.canvasBackground != .custom { canvasImage = nil }
        selectedWindowIDs = Set(preset.selectedWindowIDs)
        previewImage = nil
        previewSnapshotImage = nil
        updateSourceAspectRatio()
        updateSourceAspectRatioFromSelection()
        cameraEnabled = preset.cameraEnabled
        cameraPosition = preset.cameraPosition
        cameraShape = preset.cameraShape
        cameraSize = preset.cameraSize
        cameraMirrored = preset.cameraMirrored
        cameraMarginVertical = preset.cameraMarginVertical
        cameraMarginHorizontal = preset.cameraMarginHorizontal
        cameraDeviceID = preset.cameraDeviceID
        applyPresetFiles(preset)
        if isSharing {
            stopPreviewSnapshotTimer()
            previewSnapshotImage = nil
            updateCapture()
        } else if !selectedWindowIDs.isEmpty, filePreviewImage == nil {
            startCapture()
        } else {
            stopSnapshotStream()
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
        refreshSourceFramesAndApply()
        status = "Preset '\(preset.name)' applied."
    }
    func clearActivePreset() {
        guard let id = activePresetID, let preset = presets.first(where: { $0.id == id }) else {
            activePresetID = nil
            return
        }
        DebugLog.log("preset: clear \(preset.name)")
        let keptWindows = selectedWindowIDs
        let presetHasFile = !preset.files.isEmpty || preset.fileURL != nil
        activePresetID = nil
        selectedWindowIDs = keptWindows
        status = "Preset '\(preset.name)' cleared. No preset selected."
        if presetHasFile {
            closeFile()
        }
        if isSharing {
            updateCapture()
        } else if mode == .allow, !keptWindows.isEmpty, filePreviewImage == nil {
            refreshPreviewSnapshot()
            startPreviewSnapshotTimer()
        }
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        if activePresetID == preset.id { activePresetID = nil }
        persistPresets()
    }
    func currentSourceAppNames() -> [String] {
        Array(Set(sources.filter { selectedWindowIDs.contains($0.id) }.map { $0.appName })).sorted()
    }
    func fileSourceLabel(for preset: Preset) -> String? {
        if let name = preset.fileName, !name.isEmpty {
            if let kind = preset.fileKind {
                return "Source: \(kind.rawValue) — \(name)"
            }
            return "Source: \(name)"
        }
        if !preset.files.isEmpty {
            let kinds = Array(Set(preset.files.map { $0.kind.rawValue })).sorted().joined(separator: " / ")
            if preset.files.count == 1 {
                return "Source: \(kinds) — \(preset.files[0].name)"
            }
            return "Source: \(kinds) — \(preset.files.count) files"
        }
        return nil
    }
    func sourceLabel(for preset: Preset) -> String? {
        if let fileLabel = fileSourceLabel(for: preset) {
            return fileLabel
        }
        if !preset.sourceAppNames.isEmpty {
            return "Source: \(preset.sourceAppNames.joined(separator: ", "))"
        }
        let live = Array(Set(sources.filter { preset.selectedWindowIDs.contains($0.id) }.map { $0.appName })).sorted()
        if !live.isEmpty {
            return "Source: \(live.joined(separator: ", "))"
        }
        if !preset.selectedWindowIDs.isEmpty {
            return "Source: App window"
        }
        if preset.mode == .block {
            return "Source: Display"
        }
        return nil
    }
    func renamePreset(_ preset: Preset, to name: String) -> Bool {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return false }
        if cleanName.isEmpty { return false }
        if cleanName == presets[index].name { return true }
        if presets.contains(where: { $0.id != preset.id && $0.name.lowercased() == cleanName.lowercased() }) {
            status = "A preset named '\(cleanName)' already exists."
            return false
        }
        presets[index].name = cleanName
        persistPresets()
        status = "Preset renamed to '\(cleanName)'."
        return true
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
            if userPresets.count != decoded.count {
                persistPresets()
            }
            return
        }
        presets = []
        persistPresets()
    }
}
extension VeilModel: SCStreamOutput {
    nonisolated private static let sharedFrameContext = CIContext()
    nonisolated private static func isBlackPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> Bool {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return false }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard width > 0, height > 0, bytesPerRow >= width * 4 else { return false }
        let samples = 4
        for gy in 0..<samples {
            for gx in 0..<samples {
                let x = min(max((gx * width) / samples + width / (samples * 2), 0), width - 1)
                let y = min(max((gy * height) / samples + height / (samples * 2), 0), height - 1)
                let pixel = base.advanced(by: y * bytesPerRow + x * 4)
                let b = pixel.load(as: UInt8.self)
                let g = pixel.advanced(by: 1).load(as: UInt8.self)
                let r = pixel.advanced(by: 2).load(as: UInt8.self)
                if r > 4 || g > 4 || b > 4 {
                    return false
                }
            }
        }
        return true
    }
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let statusValue = attachments.first?[.status] as? Int,
           let frameStatus = SCFrameStatus(rawValue: statusValue),
           frameStatus != .complete {
            let statusName: String
            switch frameStatus {
            case .started: statusName = "started"
            case .suspended: statusName = "suspended"
            case .idle: statusName = "idle"
            case .blank: statusName = "blank"
            case .stopped: statusName = "stopped"
            case .complete: statusName = "complete"
            @unknown default: statusName = "unknown(\(statusValue))"
            }
            CaptureRouting.shared.recordDroppedFrame(status: statusName)
            let dropped = CaptureRouting.shared.droppedSummary()
            if dropped.0 <= 5 {
                DebugLog.log("delegate: DROPPED frame status=\(statusName) totalDropped=\(dropped.0)")
            }
            return
        }
        let streamID = ObjectIdentifier(stream)
        if CaptureRouting.shared.isSnapshotStreamID(streamID) {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            guard let cgImage = Self.sharedFrameContext.createCGImage(ciImage, from: ciImage.extent) else { return }
            let image = NSImage(
                cgImage: cgImage,
                size: NSSize(width: cgImage.width, height: cgImage.height)
            )
            DebugLog.log("delegate: snapshot frame \(cgImage.width)x\(cgImage.height)")
            Task { @MainActor in
                self.previewSnapshotImage = image
                self.updateRatioFromImage(image)
                self.stopSnapshotStream()
            }
        } else if CaptureRouting.shared.isMainStreamID(streamID), !CaptureRouting.shared.isPaused() {
            let frameWidth = CVPixelBufferGetWidth(pixelBuffer)
            let frameHeight = CVPixelBufferGetHeight(pixelBuffer)
            let frameIndex = CaptureRouting.shared.nextMainFrameIndex()
            let isBlack = Self.isBlackPixelBuffer(pixelBuffer)
            if frameIndex <= 5 {
                DebugLog.log("delegate: main frame #\(frameIndex) \(frameWidth)x\(frameHeight) black=\(isBlack)")
            }
            if frameIndex % 120 == 0 {
                DebugLog.log("delegate: frame #\(frameIndex) \(frameWidth)x\(frameHeight) black=\(isBlack)")
            }
            if isBlack {
                if CaptureRouting.shared.recordBlackFrame() {
                    DebugLog.log("delegate: 15 black frames in a row, restarting capture")
                    Task { @MainActor in
                        self.restartCapture()
                    }
                }
            } else {
                CaptureRouting.shared.resetBlackFrames()
                if CaptureRouting.shared.takeFirstFrame() {
                    DebugLog.log("delegate: first non-black frame #\(frameIndex) \(frameWidth)x\(frameHeight), streamHasFrame=true")
                    Task { @MainActor in
                        self.streamHasFrame = true
                        self.previewSnapshotImage = nil
                        self.stopPreviewSnapshotTimer()
                    }
                }
                if frameIndex % 2 == 0 {
                    let expected = CaptureRouting.shared.expectedMainFrameSize()
                    let sizeMismatch = expected.width > 0 && expected.height > 0
                        && (abs(CGFloat(frameWidth) - expected.width) / expected.width > 0.1
                            || abs(CGFloat(frameHeight) - expected.height) / expected.height > 0.1)
                    if sizeMismatch, CaptureRouting.shared.recordSkippedFrame() <= 5 {
                        DebugLog.log("delegate: skipped frame #\(frameIndex) \(frameWidth)x\(frameHeight), expected \(Int(expected.width))x\(Int(expected.height))")
                    }
                    if !sizeMismatch {
                        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                        if let cgImage = Self.sharedFrameContext.createCGImage(ciImage, from: ciImage.extent) {
                            let liveImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                            Task { @MainActor in
                                self.previewLiveImage = liveImage
                            }
                        }
                    }
                }
            }
            if frameWidth > 0, frameHeight > 0 {
                let ratio = CGFloat(frameWidth) / CGFloat(frameHeight)
                if !CaptureRouting.shared.isStripCapture(), CaptureRouting.shared.checkRatio(ratio) {
                    Task { @MainActor in
                        self.sourceAspectRatio = ratio
                        self.resizeCaptureAreaWindow()
                    }
                }
            }
        }
    }
}

extension VeilModel: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        DebugLog.log("stream didStopWithError: \(error.localizedDescription)")
        Task { @MainActor in
            guard self.isSharing, self.stream === stream else { return }
            self.stopCaptureWatchdog()
            self.stopPositionPoller()
            self.stopPreviewSnapshotTimer()
            self.stream = nil
            self.isSharing = false
            self.previewImage = nil
            self.streamHasFrame = false
            CaptureRouting.shared.setFirstFrame(false)
            self.previewLiveImage = nil
            self.closeCaptureAreaWindow()
            self.endSharingActivity()
            self.status = "Stream stopped: \(error.localizedDescription). Select a source or quit and reopen Veil to start again."
        }
    }
}
