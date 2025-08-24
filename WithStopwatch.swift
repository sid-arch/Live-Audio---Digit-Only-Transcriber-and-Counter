import SwiftUI
import Speech
import AVFoundation
import AVFAudio

// MARK: - Speech recognizer for digits
class DigitRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var digitCount = 0
    @Published var isRecording = false

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func startRecording() {
        // Permissions
        SFSpeechRecognizer.requestAuthorization { _ in }
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .undetermined:
                AVAudioApplication.requestRecordPermission { _ in }
            default: break
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }

        if audioEngine.isRunning { stopRecording() }

        transcript = ""
        digitCount = 0
        isRecording = true

        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request = request else { return }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let result = result else { return }
            let lastWord = result.bestTranscription.segments.last?.substring.lowercased() ?? ""

            let mapped: String?
            switch lastWord {
            case "zero", "0": mapped = "0"
            case "one", "1": mapped = "1"
            case "two", "2": mapped = "2"
            case "three", "3": mapped = "3"
            case "four", "4": mapped = "4"
            case "five", "5": mapped = "5"
            case "six", "6": mapped = "6"
            case "seven", "7": mapped = "7"
            case "eight", "8": mapped = "8"
            case "nine", "9": mapped = "9"
            default: mapped = nil
            }

            if let d = mapped {
                DispatchQueue.main.async {
                    self?.transcript.append(d)
                    self?.digitCount = self?.transcript.count ?? 0
                }
            }
        }
    }

    func stopRecording() {
        isRecording = false
        audioEngine.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func reset() {
        stopRecording()
        transcript = ""
        digitCount = 0
    }
}

// MARK: - Stopwatch
class Stopwatch: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    private var timer: Timer?
    private var startDate: Date?

    func start() {
        elapsed = 0
        startDate = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.001, repeats: true) { [weak self] _ in
            guard let s = self, let start = s.startDate else { return }
            s.elapsed = Date().timeIntervalSince(start)
        }
        RunLoop.current.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func reset() {
        stop()
        elapsed = 0
    }

    func formatted() -> String {
        let ms  = Int((elapsed * 1000).truncatingRemainder(dividingBy: 1000))
        let s   = Int(elapsed) % 60
        let m   = (Int(elapsed) / 60) % 60
        let h   = Int(elapsed) / 3600
        return String(format: "%02d:%02d:%02d.%03d", h, m, s, ms)
    }
}

// MARK: - Main UI
struct ContentView: View {
    @StateObject private var recognizer = DigitRecognizer()
    @StateObject private var stopwatch  = Stopwatch()
    @State private var now = Date()

    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // Two balanced columns
                HStack(alignment: .center) {
                    // LEFT
                    VStack(spacing: 28) {
                        Text("Digits Recited")
                            .font(.title)
                            .foregroundColor(.white)

                        Text("\(recognizer.digitCount)")
                            .font(.system(size: 220, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.yellow)

                        ScrollView {
                            Text(recognizer.transcript)
                                .font(.title3)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2)
                        .padding(.vertical, 30)

                    // RIGHT
                    VStack(spacing: 36) {
                        VStack(spacing: 6) {
                            Text("Live time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(time12h(now))
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .monospacedDigit()
                        }

                        VStack(spacing: 8) {
                            Text("Today's Date")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(dateLong(now))
                                .font(.title2)
                                .foregroundColor(.cyan)
                        }

                        VStack(spacing: 6) {
                            Text("Stopwatch")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(stopwatch.formatted())
                                .font(.system(size: 48, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)
                                .monospacedDigit()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                Spacer(minLength: 16)

                // Bottom buttons
                HStack {
                    Spacer()

                    // Reset Button (bottom-right)
                    Button {
                        recognizer.reset()
                        stopwatch.reset()
                    } label: {
                        Text("Reset")
                            .font(.title3)
                            .frame(width: 120, height: 50)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)

                // Start/Stop centered
                Button {
                    if recognizer.isRecording {
                        recognizer.stopRecording()
                        stopwatch.stop()
                    } else {
                        recognizer.startRecording()
                        stopwatch.start()
                    }
                } label: {
                    Text(recognizer.isRecording ? "Stop" : "Start")
                        .font(.title2)
                        .frame(width: 220, height: 60)
                        .background(recognizer.isRecording ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(18)
                }
                .padding(.bottom, 28)
            }
        }
        .onReceive(clock) { now = $0 }
    }

    private func time12h(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "hh:mm:ss a"
        return f.string(from: date)
    }

    private func dateLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "MMMM dd, yyyy – EEEE"
        return f.string(from: date)
    }
}
