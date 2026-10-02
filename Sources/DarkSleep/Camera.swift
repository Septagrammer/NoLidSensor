import AVFoundation
import Foundation

// All capture state belongs to one serial queue. Each completion is delivered once.
final class CameraProbe: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "DarkSleep.camera", qos: .utility)
    private var session: AVCaptureSession?
    private var completion: ((Result<[Double], Error>) -> Void)?
    private var started = 0.0
    private var samples: [Double] = []
    private var lastSample = 0.0
    private var token = UUID()
    private var timeout: DispatchWorkItem?
    private var activeOutput: AVCaptureVideoDataOutput?

    func capture(_ callback: @escaping (Result<[Double], Error>) -> Void) {
        queue.async {
            self.finish(.failure(self.error(L("Check cancelled"))))
            self.completion = callback
            self.token = UUID()
            let token = self.token
            // Never select an iPhone/Continuity camera or silently use an external camera.
            let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .unspecified).devices
            guard let device = devices.first(where: { $0.position == .front || $0.localizedName.lowercased().contains("facetime") || $0.localizedName.lowercased().contains("built-in") }) else {
                self.finish(.failure(self.error(L("Built-in camera not found")))); return
            }
            guard !device.isInUseByAnotherApplication else {
                self.finish(.failure(self.error(L("Camera is in use by another app")))); return
            }
            do {
                let session = AVCaptureSession()
                session.sessionPreset = .low
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: self.queue)
                guard session.canAddInput(input), session.canAddOutput(output) else { throw self.error(L("Camera unavailable")) }
                session.addInput(input); session.addOutput(output)
                self.activeOutput = output
                self.session = session
                self.samples = []; self.started = ProcessInfo.processInfo.systemUptime; self.lastSample = 0
                session.startRunning()
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    guard self.token == token, self.completion != nil else { return }
                    self.finish(.failure(self.error(L("The camera did not provide enough frames"))))
                }
                self.timeout = timeout
                self.queue.asyncAfter(deadline: .now() + 10, execute: timeout)
            } catch { self.finish(.failure(error)) }
        }
    }
    func cancel() { queue.async { self.finish(.failure(self.error(L("Check cancelled")))) } }
    private func error(_ text: String) -> NSError { NSError(domain: "DarkSleep", code: 1, userInfo: [NSLocalizedDescriptionKey: text]) }
    private func finish(_ result: Result<[Double], Error>) {
        timeout?.cancel(); timeout = nil
        activeOutput?.setSampleBufferDelegate(nil, queue: nil); activeOutput = nil
        session?.stopRunning(); session = nil
        let callback = completion; completion = nil
        if let callback { DispatchQueue.main.async { callback(result) } }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput buffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        // Discard startup frames and allow automatic exposure to settle.
        guard output === activeOutput, completion != nil, now - started >= 2, now - lastSample >= 0.35,
              let pixels = CMSampleBufferGetImageBuffer(buffer) else { return }
        lastSample = now
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else { return }
        let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels), row = CVPixelBufferGetBytesPerRow(pixels)
        guard width > 0, height > 0 else { return }
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var sum = 0.0
        // Bounded 32 × 24 sample grid; no image decode, storage or UI work.
        for y in 0..<24 { for x in 0..<32 {
            let i = min(height - 1, y * height / 24) * row + min(width - 1, x * width / 32) * 4
            sum += (0.0722 * Double(bytes[i]) + 0.7152 * Double(bytes[i+1]) + 0.2126 * Double(bytes[i+2])) / 255
        } }
        samples.append(sum / 768)
        if samples.count >= 5 { finish(.success(samples)) }
    }
}
