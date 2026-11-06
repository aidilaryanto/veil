import AppKit
import AVFoundation
import SwiftUI
final class CameraLayerView: NSView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    var mirrored = false {
        didSet { applyMirroring() }
    }
    var deviceID: String? = nil {
        didSet {
            if oldValue != deviceID { startSession() }
        }
    }
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        startSession()
    }
    required init?(coder: NSCoder) { return nil }
    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
    private func startSession() {
        let selectedDevice = deviceID.flatMap { AVCaptureDevice(uniqueID: $0) }
        let device = selectedDevice
            ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device) else { return }
        session.stopRunning()
        session.beginConfiguration()
        for existing in session.inputs {
            session.removeInput(existing)
        }
        if session.canAddInput(input) {
            session.addInput(input)
        }
        session.commitConfiguration()
        previewLayer.session = session
        applyMirroring()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    private func applyMirroring() {
        guard let connection = previewLayer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}
struct CameraOverlayView: NSViewRepresentable {
    var mirrored: Bool
    var deviceID: String? = nil
    func makeNSView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.mirrored = mirrored
        view.deviceID = deviceID
        return view
    }
    func updateNSView(_ nsView: CameraLayerView, context: Context) {
        nsView.mirrored = mirrored
        nsView.deviceID = deviceID
    }
}
