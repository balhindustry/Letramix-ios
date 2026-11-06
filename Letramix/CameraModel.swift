import AVFoundation
import Vision
import SwiftUI

struct FoundWord: Identifiable, Equatable {
    var id: String { word }
    let word: String
    /// Vision coordinates: normalised, origin bottom-left.
    let box: CGRect
    let confidence: Float
    /// How many reads in a row this word has been seen. ≥ 2 counts as stable.
    var streak = 1
    var isStable: Bool { streak >= 2 }
}

/// Live rear camera + on-device Apple Vision text recognition. Nothing is recorded or uploaded.
final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var words: [FoundWord] = []
    @Published var message = ""
    @Published var permissionDenied = false
    @Published var torchOn = false
    @Published private(set) var torchAvailable = false

    private let queue = DispatchQueue(label: "letramix.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var enabled = false
    private var busy = false
    private var lastRead = 0.0
    private var code = "fi"
    private var epoch = 0
    private var streaks: [String: Int] = [:]
    private var supported: [String]?
    /// Main-thread intent: should the camera be on? Guards late permission answers.
    private var wanted = false
    private static let letters = try! NSRegularExpression(pattern: "[A-Za-zÅÄÖåäö◇◊♢]+")

    func start(language: String) {
        wanted = true
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if !allowed { self.denied() } else if self.wanted { self.start(language: language) }
                }
            }
            return
        }
        guard status == .authorized else { denied(); return }
        queue.async { [weak self] in
            guard let self else { return }
            self.epoch += 1; self.code = language; self.enabled = true; self.streaks = [:]
            do {
                if !self.configured { try self.configure(); self.configured = true }
                if !self.session.isRunning { self.session.startRunning() }
                let torch = self.device?.hasTorch ?? false
                DispatchQueue.main.async { self.permissionDenied = false; self.message = ""; self.torchAvailable = torch }
            } catch {
                DispatchQueue.main.async { self.message = language == "fi" ? "Kameraa ei voitu avata tällä laitteella." : "Camera could not be opened on this device." }
            }
        }
    }

    func stop() {
        wanted = false
        // Strong capture: the session must really stop even if the view is already gone.
        queue.async {
            self.enabled = false; self.epoch += 1; self.streaks = [:]
            self.setTorch(false)
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.words = []; self.torchOn = false }
        }
    }

    func toggleTorch() {
        let next = !torchOn
        queue.async { [weak self] in self?.setTorch(next) }
    }

    private func setTorch(_ on: Bool) {
        guard let device, device.hasTorch, (try? device.lockForConfiguration()) != nil else { return }
        if on { try? device.setTorchModeOn(level: 0.6) } else { device.torchMode = .off }
        device.unlockForConfiguration()
        DispatchQueue.main.async { self.torchOn = on }
    }

    private func denied() { DispatchQueue.main.async { self.permissionDenied = true } }

    private func configure() throws {
        session.beginConfiguration(); defer { session.commitConfiguration() }
        session.sessionPreset = .hd1920x1080
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw NSError(domain: "Camera", code: 1) }
        self.device = device
        if (try? device.lockForConfiguration()) != nil {
            if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
            if device.isAutoFocusRangeRestrictionSupported { device.autoFocusRangeRestriction = .near }   // tiles on a table
            device.unlockForConfiguration()
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw NSError(domain: "Camera", code: 2) }
        session.addInput(input)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        guard session.canAddOutput(output) else { throw NSError(domain: "Camera", code: 3) }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard enabled, !busy, now - lastRead > 0.45, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRead = now; busy = true; defer { busy = false }
        let ticket = epoch, language = code

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        if supported == nil { supported = (try? request.supportedRecognitionLanguages()) ?? [] }
        let wanted = language == "fi" ? ["fi-FI", "en-US"] : ["en-US"]
        let available = wanted.filter { supported?.contains($0) == true }
        if !available.isEmpty { request.recognitionLanguages = available }

        do {
            try VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up).perform([request])
        } catch {
            DispatchQueue.main.async { self.message = language == "fi" ? "Tunnistus epäonnistui. Kokeillaan seuraavaa kuvaa." : "Recognition failed. Trying the next frame." }
            return
        }

        var fragments: [FoundWord] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { continue }
            let text = candidate.string
            for match in Self.letters.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let word = String(text[range]).uppercased().replacingOccurrences(of: "◊", with: "◇").replacingOccurrences(of: "♢", with: "◇")
                let rect = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                fragments.append(FoundWord(word: word, box: rect, confidence: candidate.confidence))
            }
        }

        // Tiles can be read as separate letters: join fragments on the same baseline when they touch.
        var rows: [[FoundWord]] = []
        for fragment in fragments.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let index = rows.firstIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.box.midY - fragment.box.midY) < min(first.box.height, fragment.box.height) * 0.45
            }) { rows[index].append(fragment) } else { rows.append([fragment]) }
        }
        var found: [String: FoundWord] = [:]
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

        // A word must be read in two reads in a row before it counts: filters one-frame OCR noise.
        var nextStreaks: [String: Int] = [:]
        for key in found.keys { nextStreaks[key] = (streaks[key] ?? 0) + 1; found[key]?.streak = nextStreaks[key]! }
        streaks = nextStreaks

        guard enabled, ticket == epoch else { return }
        let result = found.values.sorted { $0.box.midY != $1.box.midY ? $0.box.midY > $1.box.midY : $0.box.minX < $1.box.minX }
        DispatchQueue.main.async { if !self.message.isEmpty { self.message = "" }; self.words = result }
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let c = preview.connection, c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.preview.session = session
        view.preview.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {}
}
