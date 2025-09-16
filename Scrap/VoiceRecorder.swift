import Foundation
import Speech
import AVFoundation

// MARK: - Simple Voice Recorder
class VoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recordingStartTime: Date?
    
    init() {
        requestPermissions()
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                if status == .denied {
                    AnalyticsManager.shared.trackVoicePermissionDenied()
                }
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                if !granted {
                    AnalyticsManager.shared.trackVoicePermissionDenied()
                }
            }
        }
    }
    
    private func startRecording() {
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else { return }
        
        do {
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Set up audio engine
            audioEngine = AVAudioEngine()
            guard let audioEngine = audioEngine else { return }
            
            let inputNode = audioEngine.inputNode
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else { return }
            
            recognitionRequest.shouldReportPartialResults = true
            
            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                DispatchQueue.main.async {
                    if let result = result {
                        let newText = result.bestTranscription.formattedString
                        print("🎙️ VoiceRecorder: Updating transcribedText to: '\(newText)' (isFinal: \(result.isFinal))")
                        self?.transcribedText = newText
                    }
                    
                    if error != nil || result?.isFinal == true {
                        if let error = error {
                            print("🎙️ VoiceRecorder: Recognition error: \(error)")
                        }
                        self?.stopRecording()
                    }
                }
            }
            
            // Configure microphone input
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                recognitionRequest.append(buffer)
            }
            
            // Start audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            transcribedText = ""
            recordingStartTime = Date()
            
        } catch {
            print("Failed to start recording: \(error)")
            stopRecording()
        }
    }
    
    private func stopRecording() {
        // Track voice recording completion
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            AnalyticsManager.shared.trackVoiceRecordingStopped(duration: duration, textLength: transcribedText.count)
        }
        
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        recordingStartTime = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}