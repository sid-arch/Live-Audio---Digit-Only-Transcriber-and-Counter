import SwiftUI
import Speech
import AVFoundation
import AVFAudio

// MARK: - Speech recognizer for digits (faster-feel tweaks baked in)
class DigitRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var digitCount = 0
    @Published var isRecording = false

    private let recognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        if #available(iOS 16.0, *) { r?.defaultTaskHint = .dictation } // hint for short words
        return r
    }()

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // To avoid duplicate appends when partial results repeat the same last segment
    private var lastAppendedTimestamp: TimeInterval = -1

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

        if audioEngine.isRunning { stopRecording() } // clean restart

        transcript = ""
        digitCount = 0
        isRecording = true
        lastAppendedTimestamp = -1

        // Audio session tuned for low latency
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        // These preferred settings help reduce end-to-end lag a bit
        try? session.setPreferredSampleRate(44_100)
        try? session.setPreferredIOBufferDuration(0.005) // ~5ms target
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        // Request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true                  // explicit partials
        if #available(iOS 13.0, *) { req.requiresOnDeviceRecognition = false } // allow server if it helps
        request = req

        guard let request = request else { return }

        // Stream mic → request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        // Smaller buffer → more frequent callbacks (tradeoff: a touch more CPU)
        input.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self = self, let result = result else { return }

            guard let lastSeg = result.bestTranscription.segments.last else { return }
            // Skip if we already appended this exact segment (partial results often repeat it)
            if lastSeg.timestamp == self.lastAppendedTimestamp { return }

            let token = lastSeg.substring.lowercased()
            let mapped: String?
            switch token {
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
                self.lastAppendedTimestamp = lastSeg.timestamp
                DispatchQueue.main.async {
                    self.transcript.append(d)
                    self.digitCount = self.transcript.count
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
        lastAppendedTimestamp = -1
    }
}

// MARK: - Main UI (no stopwatch)
struct ContentView: View {
    @StateObject private var recognizer = DigitRecognizer()
    @State private var now = Date()
    private let clock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack {
                // Two balanced columns
                HStack(alignment: .center) {
                    // LEFT: Digits
                    VStack(spacing: 28) {
                        Text("Digits Recited")
                            .font(.title)
                            .foregroundColor(.white)

                        Text("\(recognizer.digitCount)")
                            .font(.system(size: 220, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.yellow)
                            .lineLimit(1)
                            .minimumScaleFactor(0.3)

                        ScrollView {
                            Text(recognizer.transcript)
                                .font(.title)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 120)
                    }
                    .frame(maxWidth: .infinity)

                    // Center divider
                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 2)
                        .padding(.vertical, 30)

                    // RIGHT: Time + Date
                    VStack(spacing: 36) {
                        VStack(spacing: 6) {
                            Text("Live time")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(time12h(now))
                                .font(.system(size: 54, weight: .bold, design: .monospaced))
                                .foregroundColor(.green)
                                .monospacedDigit()
                        }

                        VStack(spacing: 8) {
                            Text("Today's Date")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(dateLong(now))
                                .font(.title)
                                .foregroundColor(.cyan)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)

                Spacer(minLength: 16)

                // Bottom row: Reset (right) + Start/Stop (center)
                HStack {
                    Spacer()
                    Button {
                        recognizer.reset()
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

                Button {
                    if recognizer.isRecording {
                        recognizer.stopRecording()
                    } else {
                        recognizer.startRecording()
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

    // MARK: - Formatters (Dublin, OH = America/New_York)
    private func time12h(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "hh:mm:ss a"   // 12-hour + AM/PM
        return f.string(from: date)
    }

    private func dateLong(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "America/New_York")
        f.dateFormat = "MMMM dd, yyyy – EEEE"
        return f.string(from: date)
    }
}

