import SwiftUI
import Speech
import AVFoundation
import AVFAudio

// MARK: - Speech recognizer for digits (fast + robust)
class DigitRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var digitCount = 0
    @Published var isRecording = false

    private let recognizer: SFSpeechRecognizer? = {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        if #available(iOS 16.0, *) { r?.defaultTaskHint = .dictation } // better for short tokens
        return r
    }()

    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // Prevent duplicate appends & post-stop “final” callbacks
    private var lastAppendedTimestamp: TimeInterval = -1

    func startRecording() {
        // Permissions
        SFSpeechRecognizer.requestAuthorization { _ in }
        if #available(iOS 17.0, *) {
            if AVAudioApplication.shared.recordPermission == .undetermined {
                AVAudioApplication.requestRecordPermission { _ in }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        }

        if audioEngine.isRunning { stopRecording() }   // clean restart

        transcript = ""
        digitCount = 0
        lastAppendedTimestamp = -1
        isRecording = true

        // Low-latency audio session
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try? session.setPreferredSampleRate(44_100)
        try? session.setPreferredIOBufferDuration(0.005) // ~5ms
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 13.0, *) { req.requiresOnDeviceRecognition = false } // allow server if faster
        request = req

        guard let request = request else { return }

        // Mic → request
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 256, format: format) { buffer, _ in
            request.append(buffer)
        }

        audioEngine.prepare()
        try? audioEngine.start()

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, _ in
            guard let self = self else { return }
            // 🔒 Ignore any callbacks after Stop was pressed
            guard self.isRecording else { return }
            guard let result = result, let seg = result.bestTranscription.segments.last else { return }

            // ⛔️ Skip duplicates (partials often repeat same last segment)
            if seg.timestamp == self.lastAppendedTimestamp { return }

            let token = seg.substring.lowercased()
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
                self.lastAppendedTimestamp = seg.timestamp
                DispatchQueue.main.async {
                    self.transcript.append(d)
                    self.digitCount = self.transcript.count
                }
            }
        }
    }

    func stopRecording() {
        // Flip this first so late callbacks are ignored
        isRecording = false

        audioEngine.stop()
        request?.endAudio()
        recognitionTask?.cancel()
        audioEngine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        recognitionTask = nil
        request = nil
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
                        
                        // Bigger transcript for camera legibility
                        ScrollView {
                            Text(recognizer.transcript)
                                .font(.title)   // ~50% larger than earlier
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 160)
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
                                .font(.title)   // bigger date text
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
