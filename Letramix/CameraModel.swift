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
            var fragments: [FoundWord] = []
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first else { continue }
                let text = candidate.string
                let regex = try NSRegularExpression(pattern: "[A-Za-zÅÄÖåäö◇◊♢]+")
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range, in: text) else { continue }
                    let word = String(text[range]).uppercased().replacingOccurrences(of: "◊", with: "◇").replacingOccurrences(of: "♢", with: "◇")
                    let rect = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                    fragments.append(FoundWord(word: word, box: rect, confidence: candidate.confidence))
                }
            }
            // No colour filtering: blue and black tiles use the same recognition path.
            // Group nearby OCR fragments on the same baseline; never join scattered tiles.
            var rows: [[FoundWord]] = []
            for fragment in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
                if let index = rows.firstIndex(where: { row in
                    guard let first = row.first else { return false }
                    return abs(first.box.midY - fragment.box.midY) < min(first.box.height, fragment.box.height) * 0.45
                }) { rows[index].append(fragment) } else { rows.append([fragment]) }
            }
            func save(_ run: [FoundWord]) {
                let word = run.map(\.word).joined()
                guard word.count >= 2, let first = run.first else { return }
                let box = run.dropFirst().reduce(first.box) { $0.union($1.box) }
                found[word] = FoundWord(word: word, box: box, confidence: run.map(\.confidence).min() ?? 0)
            }
            for row in rows {
                var run: [FoundWord] = []
                for fragment in row.sorted(by: { $0.box.minX < $1.box.minX }) {
                    if let previous = run.last {
                        let gap = fragment.box.minX - previous.box.maxX
                        if gap > max(previous.box.height, fragment.box.height) * 1.25 || gap < -min(previous.box.width, fragment.box.width) * 0.25 {
                            save(run); run = []
                        }
                    }
                    run.append(fragment)
                }
                save(run)
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
