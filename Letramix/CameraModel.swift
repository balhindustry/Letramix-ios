import AVFoundation
import Vision
import SwiftUI

struct FoundWord: Identifiable { var id: String { word }; let word: String; let box: CGRect; let confidence: Float }
final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var words: [FoundWord] = []
    @Published var message = ""
    @Published var permissionDenied = false
    private let queue = DispatchQueue(label: "letramix.camera")
    private var configured = false
    private var enabled = false
    private var lastRead = 0.0
    private var code = "fi"
    private var epoch = 0
    func start(language: String) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined { AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in if allowed { self?.start(language: language) } else { self?.denied() } }; return }
        guard status == .authorized else { denied(); return }
        queue.async { [weak self] in
            guard let self else { return }
            self.epoch += 1; self.code = language; self.enabled = true
            do {
                if !self.configured { try self.configure(); self.configured = true }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.permissionDenied = false; self.message = "" }
            } catch { DispatchQueue.main.async { self.message = language == "fi" ? "Kameraa ei voitu avata tällä laitteella." : "Camera could not be opened on this device." } }
        }
    }
    private func denied() { DispatchQueue.main.async { self.permissionDenied = true } }
    private func configure() throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }; session.sessionPreset = .hd1280x720
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw NSError(domain: "Camera", code: 1) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw NSError(domain: "Camera", code: 2) }; session.addInput(input)
        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { throw NSError(domain: "Camera", code: 3) }; session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
    func stop() {
        queue.async { [weak self] in guard let self else { return }; self.enabled = false; self.epoch += 1; if self.session.isRunning { self.session.stopRunning() } }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, now-lastRead > 0.7, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }; lastRead = now
        let ticket = epoch, language = code
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = false
        let supported = (try? request.supportedRecognitionLanguages()) ?? []
        let wanted = language == "fi" ? ["fi-FI", "en-US"] : ["en-US"]
        let available = wanted.filter { supported.contains($0) }
        if !available.isEmpty { request.recognitionLanguages = available }
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up).perform([request])
            var found: [String: FoundWord] = [:]
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                let regex = try NSRegularExpression(pattern: "[A-Za-zÅÄÖåäö]{2,}")
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text) else { continue }
                    let word = String(text[range]).uppercased()
                    let rect = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                    if found[word] == nil { found[word] = FoundWord(word: word, box: rect, confidence: candidate.confidence) }
                }
            }
            guard enabled, ticket == epoch else { return }
            let result = found.values.sorted { $0.word < $1.word }
            DispatchQueue.main.async { self.words = result }
        } catch { DispatchQueue.main.async { self.message = language == "fi" ? "Tunnistus epäonnistui. Kokeillaan seuraavaa kuvaa." : "Recognition failed. Trying the next frame." } }
    }
}
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() { super.layoutSubviews(); if let c = preview.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 } }
}
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView { let v = PreviewView(); v.preview.session = session; v.preview.videoGravity = .resizeAspect; return v }
    func updateUIView(_ uiView: PreviewView, context: Context) { }
}
