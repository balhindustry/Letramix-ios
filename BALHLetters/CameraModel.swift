import AVFoundation
import Vision
import ImageIO
import SwiftUI

struct FoundWord: Identifiable, Equatable {
    var id: String { word }
    let word: String
    /// Normalised, origin bottom-left, in the upright camera image.
    let box: CGRect
    let confidence: Float
    let direction: WordDirection
    /// Degrees the word is rotated on the table (0, 90, 180, 270).
    let rotation: Int
    /// How many reads have seen this word. ≥ 2 counts as stable.
    var streak = 1
    var isStable: Bool { streak >= 2 }
    var letterCount: Int { word.count }
}

/// Live rear camera + on-device Apple Vision text recognition. Nothing is recorded or uploaded.
final class CameraModel: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published var words: [FoundWord] = []
    @Published var message = ""
    @Published var permissionDenied = false
    @Published var torchOn = false
    @Published private(set) var torchAvailable = false

    private let queue = DispatchQueue(label: "balhletters.camera")
    private var device: AVCaptureDevice?
    private var configured = false
    private var enabled = false
    private var busy = false
    private var lastRead = 0.0
    private var code = "fi"
    private var epoch = 0
    /// Per word: how many times seen, and in which read cycle last.
    private var seen: [String: (count: Int, cycle: Int, word: FoundWord)] = [:]
    private var cycle = 0
    private var supported: [String]?
    private static let rotatedPasses: [(CGImagePropertyOrientation, Int)] = [(.right, 90), (.left, 270), (.down, 180)]
    /// Main-thread intent: should the camera be on? Guards late permission answers.
    private var wanted = false
    private static let letters = try! NSRegularExpression(pattern: "[A-Za-zÅÄÖåäö◇◊♢0-9]+")

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
            self.epoch += 1; self.code = language; self.enabled = true; self.seen = [:]
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
            self.enabled = false; self.epoch += 1; self.seen = [:]
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
        guard enabled, !busy, now - lastRead > 0.5, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastRead = now; busy = true; defer { busy = false }
        let ticket = epoch, language = code
        cycle += 1

        // Every cycle reads the board upright (horizontal + vertical words). Every cycle also reads it in one
        // rotated orientation, cycling through 90°/270°/180°, so words laid sideways or upside down count too.
        var candidates: [FoundWord] = []
        candidates += recognise(pixel, orientation: .up, rotation: 0, language: language, directions: [.horizontal, .vertical])
        let rotated = Self.rotatedPasses[cycle % Self.rotatedPasses.count]
        candidates += recognise(pixel, orientation: rotated.0, rotation: rotated.1, language: language, directions: [.horizontal])

        // Stability: a word must be seen in at least two reads; it is kept for a few cycles so that
        // rotated words (read every third cycle) survive between their reads.
        for word in candidates {
            let previous = seen[word.word]
            seen[word.word] = (count: (previous?.count ?? 0) + 1, cycle: cycle, word: word)
        }
        seen = seen.filter { cycle - $0.value.cycle <= 3 }
        var result = seen.values.map { entry -> FoundWord in var w = entry.word; w.streak = entry.count; return w }
        result.sort { $0.box.midY != $1.box.midY ? $0.box.midY > $1.box.midY : $0.box.minX < $1.box.minX }

        guard enabled, ticket == epoch else { return }
        DispatchQueue.main.async { if !self.message.isEmpty { self.message = "" }; self.words = result }
    }

    /// Runs one text recognition pass and groups the tiles into words, in the pass's own orientation.
    /// Boxes are mapped back to the upright image so the overlay can draw them.
    private func recognise(_ pixel: CVPixelBuffer, orientation: CGImagePropertyOrientation, rotation: Int,
                           language: String, directions: [WordDirection]) -> [FoundWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.02
        if supported == nil { supported = (try? request.supportedRecognitionLanguages()) ?? [] }
        let wanted = language == "fi" ? ["fi-FI", "en-US"] : ["en-US"]
        let available = wanted.filter { supported?.contains($0) == true }
        if !available.isEmpty { request.recognitionLanguages = available }
        do {
            try VNImageRequestHandler(cvPixelBuffer: pixel, orientation: orientation).perform([request])
        } catch {
            DispatchQueue.main.async { self.message = language == "fi" ? "Tunnistus epäonnistui. Kokeillaan seuraavaa kuvaa." : "Recognition failed. Trying the next frame." }
            return []
        }
        var fragments: [TextFragment] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first, candidate.confidence > 0.3 else { continue }
            let text = candidate.string
            for match in Self.letters.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let range = Range(match.range, in: text) else { continue }
                let rect = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                // "K1A1L2" → "KALA": the small point numbers on the tiles are dropped.
                for piece in TileGrouping.letters(in: String(text[range])) {
                    fragments.append(TextFragment(text: piece, box: rect, confidence: candidate.confidence))
                }
            }
        }
        return TileGrouping.words(from: fragments, directions: directions).map { word in
            FoundWord(word: word.text, box: Self.upright(word.box, from: orientation), confidence: word.confidence,
                      direction: word.direction, rotation: rotation)
        }
    }

    /// Maps a normalised rect from the oriented image back to the upright image.
    static func upright(_ r: CGRect, from orientation: CGImagePropertyOrientation) -> CGRect {
        func map(_ p: CGPoint) -> CGPoint {
            switch orientation {
            case .right: return CGPoint(x: 1 - p.y, y: p.x)
            case .left: return CGPoint(x: p.y, y: 1 - p.x)
            case .down: return CGPoint(x: 1 - p.x, y: 1 - p.y)
            default: return p
            }
        }
        let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].map(map)
        let xs = corners.map(\.x), ys = corners.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
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
