import AppKit
import AVFoundation
import SwiftUI

/// Lapisan pratinjau kamera berbasis AVCaptureVideoPreviewLayer.
final class CameraLayerView: NSView {
    private let session = AVCaptureSession()
    private let layer = AVCaptureVideoPreviewLayer()

    var mirrored = false {
        didSet { applyMirroring() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer.videoGravity = .resizeAspectFill
        self.layer?.addSublayer(layer)
        startSession()
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        layer.frame = bounds
    }

    private func startSession() {
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)
        guard let device,
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.addInput(input)
        session.commitConfiguration()
        layer.session = session
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    private func applyMirroring() {
        guard let connection = layer.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = mirrored
    }
}

struct CameraOverlayView: NSViewRepresentable {
    var mirrored: Bool

    func makeNSView(context: Context) -> CameraLayerView {
        let view = CameraLayerView()
        view.mirrored = mirrored
        return view
    }

    func updateNSView(_ nsView: CameraLayerView, context: Context) {
        nsView.mirrored = mirrored
    }
}
