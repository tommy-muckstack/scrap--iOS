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
                // Handle authorization status if needed
            }
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                // Handle permission result if needed
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
                        self?.transcribedText = result.bestTranscription.formattedString
                    }
                    
                    if error != nil || result?.isFinal == true {
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
            
        } catch {
            print("Failed to start recording: \(error)")
            stopRecording()
        }
    }
    
    private func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isRecording = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}