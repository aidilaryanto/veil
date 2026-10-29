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
    /// Rasio (lebar / tinggi) dari sumber yang sedang ditampilkan.
    /// Default 16:9, tapi diperbarui setiap kali sumber berubah:
    /// jendela yang dipilih, gabungan jendela (framing Dynamic),
    /// layar (framing Full / Block), atau frame stream yang masuk.
    /// Jendela Output dan Preview memakai rasio ini (bukan 16:9
    /// tetap), supaya sumber yang bukan 16:9 tidak terpotong oleh
    /// scaledToFill di dalam jendela 16:9.
    @Published var sourceAspectRatio: CGFloat = 16.0 / 9.0
    @Published var fileSources: [FileSource] = []
    @Published var activeFileID: UUID?
    @Published var filePageIndex = 0
    @Published var filePreviewImage: NSImage?

    /// Apakah ada frame stream yang LAYAK ditampilkan (bukan
    /// sekadar previewImage != nil). Kasus yang dilaporkan:
    /// pertama kali Start dengan mode Allow tapi belum ada
    /// jendela yang dipilih — SCStream tetap berjalan dan
    /// mengirim frame layar hitam (semua jendela di-exclude)
    /// + kursor, sehingga Output/Preview menampilkan layar
    /// hitam berkursor, bukan placeholder "No preview yet".
    /// Jadi frame stream hanya layak tampil kalau sedang sharing
    /// DAN ada frame-nya DAN bukan kasus Allow tanpa pilihan
    /// (yang memang tidak ada sumber untuk ditampilkan).
    /// Mode Block tanpa pilihan justru valid: itu berarti
    /// share seluruh layar (tidak ada yang di-block).
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

    /// Menghitung ulang sourceAspectRatio dari sumber yang sedang
    /// ditampilkan, dengan prioritas: file yang sedang tampil >
    /// frame stream (kalau sedang sharing) > frame jendela yang
    /// dipilih (supaya ganti pilihan sebelum Start pun langsung
    /// mengubah rasio Preview/Output, bukan tertahan frame lama) >
    /// frame stream lama > gabungan frame (Dynamic) > layar yang
    /// dipilih. Hanya mengubah nilai kalau rasionya benar-benar
    /// berubah (> 0,01), supaya jendela Output/Preview tidak
    /// di-resize setiap frame.
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

    // MARK: - Sumber (ScreenCaptureKit)

    /// Mengubah daftar SCWindow mentah menjadi SourceItem tanpa duplikat.
    /// ScreenCaptureKit dengan onScreenWindowsOnly: false mengembalikan
    /// semua jendela milik sebuah aplikasi, termasuk jendela tersembunyi /
    /// helper tanpa judul. Judul kosong diganti nama aplikasi, sehingga
    /// satu aplikasi bisa tampil berkali-kali dengan baris yang identik
    /// (mis. "Acrobat" tujuh kali di screenshot). Karena itu baris dengan
    /// pasangan (appName, title) yang sama digabung jadi satu.
    /// Urutan sebelum deduplikasi sengaja mendahulukan jendela aktif dan
    /// on-screen, supaya windowID yang dipertahankan adalah jendela yang
    /// benar-benar terlihat, bukan jendela helper tersembunyi. Jendela
    /// minimized / Space lain tetap dipertahankan (hanya duplikatnya
    /// yang dibuang), jadi perbaikan list kosong sebelumnya tidak mundur.
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
                // Label argumen di bawah ini adalah yang cocok dengan
                // SDK terbaru; label lama sudah tidak diterima compiler.
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

    // MARK: - Capture

    func toggleSharing() {
        if isSharing {
            stopCapture()
        } else {
            // Start dari tombol Start/Stop (bukan restart):
            // kosongkan frame lama dulu, supaya saat pertama
            // kali distart — dan setiap start ulang setelah stop
            // — yang tampil di Preview maupun Output adalah
            // placeholder "No preview yet", bukan frame beku
            // dari stream sebelumnya, sampai frame baru pertama
            // dari SCStream benar-benar datang.
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
        // Ketajaman: frame SCWindow dinyatakan dalam poin,
        // sementara config.width/height adalah PIKSEL output. Di layar
        // Retina (scale 2x), memakai ukuran poin apa adanya berarti
        // capture hanya setengah resolusi piksel layar, lalu gambar
        // itu di-upscale ke backing store 2x jendela Output — inilah
        // yang terasa "terkompres" / buram. Jadi ukuran output
        // dikalikan scale layar tempat sumber berada, supaya capture
        // berjalan di resolusi piksel native dan tidak perlu
        // di-upscale lagi. Untuk capture layar penuh, display.width
        // sudah dalam piksel, jadi tidak dikalikan lagi.
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
                        // Stream start => Output langsung muncul,
                        // tanpa perlu menekan tombol mata lagi.
                        // Hanya dibuka kalau belum terlihat, supaya
                        // restart di tengah streaming (ganti preset /
                        // sumber) tidak mengangkat Output ke depan
                        // berulang-ulang dan mengganggu panel kontrol.
                        if !isOutputVisible {
                            openOutputWindow()
                        }
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
            // Stream stop (tombol Stop maupun Panic) => kembali
            // ke "No preview yet": frame terakhir stream dihapus,
            // jadi Preview yang masih terbuka — dan Output kalau
            // dibuka lagi manual lewat tombol mata — tidak lagi
            // menampilkan frame beku terakhir, melainkan placeholder
            // yang sama seperti saat aplikasi pertama kali dibuka
            // (previewImage dan filePreviewImage sama-sama nil).
            // Termasuk file PDF/PPT: Stop juga menutup tampilan
            // file (closeFile — daftar file di Sources tetap ada,
            // hanya yang sedang tampil yang ditutup, beserta
            // flyer-nya), jadi Preview/Output tidak tertahan di
            // halaman PDF/PPT terakhir, melainkan kembali ke
            // placeholder. Restart (keepSharing: true) sengaja
            // TIDAK menutup file, supaya ganti preset/sumber di
            // tengah streaming tidak menghilangkan file yang
            // sedang ditampilkan.
            previewImage = nil
            closeFile()
            // Stream stop (tombol Stop maupun Panic) => Output
            // langsung ditutup. Di Zoom/Meet, yang di-share adalah
            // jendela Output ini, jadi begitu jendelanya hilang,
            // share screen di Zoom/Meet ikut terhenti — Veil tidak
            // punya API langsung ke Zoom/Meet, menutup sumber
            // share-nya inilah caranya. Restart sengaja TIDAK
            // menutup Output (keepSharing: true), supaya Output
            // tidak berkedip hilang-muncul saat ganti preset/sumber.
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
                status = "Failed to open PDF: \(name)"
                return
            }
            let item = FileSource(name: name, url: url, kind: .pdf, pageCount: max(1, document.pageCount))
            fileSources.append(item)
            activateFile(item)
            status = "PDF added: \(name) (\(document.pageCount) pages)."
        } else if ext == "ppt" || ext == "pptx" {
            // macOS tidak punya renderer slide-per-slide bawaan untuk PPT.
            // Pratinjau yang dipakai adalah thumbnail QuickLook, biasanya
            // slide pertama. Untuk navigasi slide penuh, konversi ke PDF.
            let item = FileSource(name: name, url: url, kind: .ppt, pageCount: 1)
            fileSources.append(item)
            activateFile(item)
            status = "PPT added: \(name). First-slide preview (QuickLook)."
        } else {
            status = "Unsupported format: PDF, PPT, and PPTX only."
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
            // scale = scale layar Retina (2x), bukan 1: thumbnail
            // 1280x720 poin diraster jadi 2560x1440 piksel, supaya
            // tidak di-upscale lagi di jendela Output.
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
                    // Thumbnail PPT baru diterima => rasio jendela
                    // ikut rasio slide, supaya tidak ada bar canvas
                    // di kiri/kanan seperti kasus PDF di bawah.
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
        // Kembali ke rasio stream/sumber setelah file ditutup,
        // supaya jendela tidak tertahan di rasio halaman file.
        updateSourceAspectRatio()
        applySourceRatioToWindows()
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
        // Sebelumnya thumbnail dibatasi 1280x720: halaman PDF
        // (misalnya A4 portrait) diraster kecil lalu di-upscale
        // ke jendela Output yang backing store-nya 2x — hasilnya
        // buram / seperti terkompres. Sekarang thumbnail diminta
        // dalam kotak 3000x3000 (sisi panjang sampai 3000 piksel,
        // rasio halaman dipertahankan), jadi Output tidak perlu
        // meng-upscale lagi pada ukuran jendela biasa.
        filePreviewImage = page.thumbnail(of: NSSize(width: 3000, height: 3000), for: .mediaBox)
        // AKAR BAR ABU-ABU di screenshot: fungsi ini sebelumnya
        // tidak pernah memanggil updateSourceAspectRatio, jadi
        // saat PDF dibuka / halaman diganti, jendela Output dan
        // Preview tetap di rasio lama (misalnya 16:9 / rasio
        // stream), sementara halaman PDF di-scaledToFit ke dalam
        // jendela itu — selisih rasionya muncul sebagai bar
        // canvas abu-abu (default canvasBackground .gray) di
        // kiri dan kanan halaman. Sekarang rasio jendela ikut
        // rasio halaman file, jadi halaman mengisi jendela penuh
        // tanpa bar di kiri/kanan, dan tanpa tercrop (masih Fit).
        updateSourceAspectRatio()
        applySourceRatioToWindows()
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
            filePageIndex: filePageIndex
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
                status = "Preset '\(preset.name)' applied, but the file was not found."
                if isSharing { restartCapture() }
                return
            }
        } else {
            closeFile()
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

// MARK: - SCStreamOutput

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
            // Saat dijeda, frame terakhir dibekukan: preview tidak diperbarui.
            if !self.isPaused {
                self.previewImage = image
                // Frame stream inilah "ukuran yang ditampilkan":
                // kalau sumber di-resize, rasio frame ikut berubah
                // dan jendela Output/Preview menyesuaikan lewat
                // onChange sourceAspectRatio di Views.
                self.updateSourceAspectRatio()
            }
        }
    }
}
