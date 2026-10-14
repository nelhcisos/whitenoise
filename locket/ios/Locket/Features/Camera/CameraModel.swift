import AVFoundation
import Observation
import UIKit

/// Owns the capture session. Session work happens on a private queue;
/// observable state is only changed on the main thread.
@Observable
final class CameraModel: NSObject {
    enum Status {
        case unknown, ready, denied, unavailable
    }

    private(set) var status: Status = .unknown
    private(set) var position: AVCaptureDevice.Position = .back
    private(set) var isCapturing = false
    var flashOn = false

    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "locket.camera")
    @ObservationIgnored private var input: AVCaptureDeviceInput?
    @ObservationIgnored private var configured = false
    @ObservationIgnored private var completion: ((UIImage?) -> Void)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.run() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    func flip() {
        let newPosition: AVCaptureDevice.Position = position == .back ? .front : .back
        queue.async {
            guard let newInput = Self.makeInput(newPosition) else { return }
            self.session.beginConfiguration()
            if let old = self.input { self.session.removeInput(old) }
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.input = newInput
            } else if let old = self.input {
                self.session.addInput(old)
            }
            self.session.commitConfiguration()
            DispatchQueue.main.async { self.position = newPosition }
        }
    }

    /// Takes a photo and returns it as a 1080×1080 square, like the preview shows it.
    func capture(_ completion: @escaping (UIImage?) -> Void) {
        guard status == .ready, !isCapturing else { return }
        isCapturing = true
        self.completion = completion
        let flash = flashOn
        let mirrored = position == .front
        queue.async {
            let settings = AVCapturePhotoSettings()
            if self.output.supportedFlashModes.contains(.on) {
                settings.flashMode = flash ? .on : .off
            }
            if let connection = self.output.connection(with: .video) {
                if connection.isVideoRotationAngleSupported(90) {
                    connection.videoRotationAngle = 90 // portrait
                }
                if connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = mirrored // selfies look like the preview
                }
            }
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    private func run() {
        let position = self.position
        queue.async {
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .photo
                guard let input = Self.makeInput(position),
                      self.session.canAddInput(input),
                      self.session.canAddOutput(self.output)
                else {
                    self.session.commitConfiguration()
                    DispatchQueue.main.async { self.status = .unavailable }
                    return
                }
                self.session.addInput(input)
                self.session.addOutput(self.output)
                self.input = input
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.status = .ready }
        }
    }

    private static func makeInput(_ position: AVCaptureDevice.Position) -> AVCaptureDeviceInput? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else {
            return nil
        }
        return try? AVCaptureDeviceInput(device: device)
    }
}

extension CameraModel: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation()
            .flatMap { UIImage(data: $0) }
            .map { $0.squareCropped(side: 1080) }
        DispatchQueue.main.async {
            self.isCapturing = false
            self.completion?(image)
            self.completion = nil
        }
    }
}

extension UIImage {
    /// Center square, drawn upright (EXIF orientation applied), at most `side` pixels.
    func squareCropped(side: CGFloat) -> UIImage {
        let shortest = min(size.width, size.height)
        guard shortest > 0 else { return self }
        let target = min(side, shortest * scale)
        let factor = target / shortest
        let drawSize = CGSize(width: size.width * factor, height: size.height * factor)
        let origin = CGPoint(x: (target - drawSize.width) / 2, y: (target - drawSize.height) / 2)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: target, height: target), format: format).image { _ in
            draw(in: CGRect(origin: origin, size: drawSize))
        }
    }
}
