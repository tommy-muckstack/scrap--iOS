import SwiftUI
import Foundation
import Combine
import NaturalLanguage
import UIKit
import Speech
import AVFoundation

// MARK: - Gentle Lightning Design System
struct GentleLightning {
    struct Colors {
        // MARK: - Theme-Aware Colors
        static func background(isDark: Bool) -> Color {
            isDark ? Color(red: 0.08, green: 0.08, blue: 0.09) : Color.white
        }
        
        static func backgroundWarm(isDark: Bool) -> Color {
            isDark ? Color(red: 0.09, green: 0.09, blue: 0.10) : Color.white
        }
        
        static func surface(isDark: Bool) -> Color {
            isDark ? Color(red: 0.12, green: 0.12, blue: 0.14) : Color.white
        }
        
        static func surfaceSecondary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color(red: 0.98, green: 0.98, blue: 0.99)
        }
        
        static func textPrimary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.95, green: 0.95, blue: 0.97) : Color(red: 0.12, green: 0.12, blue: 0.15)
        }
        
        static func textSecondary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.65, green: 0.65, blue: 0.70) : Color(red: 0.45, green: 0.45, blue: 0.5)
        }
        
        static func textTertiary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.50, green: 0.50, blue: 0.55) : Color(red: 0.60, green: 0.60, blue: 0.65)
        }
        
        static func border(isDark: Bool) -> Color {
            isDark ? Color(red: 0.25, green: 0.25, blue: 0.28) : Color(red: 0.90, green: 0.90, blue: 0.92)
        }
        
        static func shadow(isDark: Bool) -> Color {
            isDark ? Color.black.opacity(0.15) : Color.black.opacity(0.03)
        }
        
        // MARK: - Static Colors (Theme Independent)
        static let textBlack = Color.black
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let error = Color(red: 0.95, green: 0.26, blue: 0.21)
        static let success = Color(red: 0.29, green: 0.76, blue: 0.49)
        
        // MARK: - Legacy Static Colors (for backward compatibility)
        static let background = Color.white
        static let backgroundWarm = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)
        static let shadowLight = Color.black.opacity(0.03)
    }
    
    struct Typography {
        // HEADINGS / TITLES → SharpGrotesk-Medium (sometimes SemiBold for emphasis)
        static let hero = Font.custom("SharpGrotesk-SemiBold", size: 34)           // Large hero titles
        static let title = Font.custom("SharpGrotesk-Medium", size: 20)            // Standard titles/headings
        static let titleEmphasis = Font.custom("SharpGrotesk-SemiBold", size: 20)  // Emphasized titles
        static let subtitle = Font.custom("SharpGrotesk-Medium", size: 18)         // Subtitles
        static let heading = Font.custom("SharpGrotesk-Medium", size: 16)          // Section headings
        
        // BODY TEXT → SharpGrotesk-Book (regular reading weight)
        static let body = Font.custom("SharpGrotesk-Book", size: 16)               // Primary body text
        static let bodyInput = Font.custom("SharpGrotesk-Book", size: 19)          // Input fields
        static let bodyLarge = Font.custom("SharpGrotesk-Book", size: 18)          // Larger body text
        
        // SECONDARY / SUBTLE TEXT → SharpGrotesk-Light
        static let caption = Font.custom("SharpGrotesk-Light", size: 13)           // Subtle captions
        static let small = Font.custom("SharpGrotesk-Light", size: 11)             // Small subtle text
        static let secondary = Font.custom("SharpGrotesk-Light", size: 14)         // Secondary information
        static let metadata = Font.custom("SharpGrotesk-Light", size: 12)          // Timestamps, metadata
        
        // LEGACY / SPECIAL USE
        static let ultraLight = Font.custom("SharpGrotesk-Thin", size: 14)         // Ultra-light accent
        static let medium = Font.custom("SharpGrotesk-Medium", size: 16)           // Medium weight utility
        
        // ITALIC VARIANTS for emphasis
        static let bodyItalic = Font.custom("SharpGrotesk-BookItalic", size: 16)
        static let titleItalic = Font.custom("SharpGrotesk-MediumItalic", size: 20)
        static let secondaryItalic = Font.custom("SharpGrotesk-LightItalic", size: 14)
    }
    
    struct Layout {
        struct Padding {
            static let lg: CGFloat = 16
            static let xl: CGFloat = 20
        }
        struct Radius {
            static let medium: CGFloat = 12
            static let large: CGFloat = 16
        }
        struct Spacing {
            static let comfortable: CGFloat = 12
        }
    }
    
    struct Animation {
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let elastic = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6)
        static let swoosh = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
    }
    
    struct Sound {
        enum Haptic {
            case swoosh
            
            func trigger() {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
    
    struct Context {
        static func accentColor(isTask: Bool) -> Color {
            return isTask ? Colors.accentTask : Colors.accentIdea
        }
        
        static func backgroundWarmth(isActive: Bool) -> Color {
            return isActive ? Colors.backgroundWarm : Colors.background
        }
    }
}

// MARK: - Simple Item Model (Compatible with Firebase)
// SparkItem is now defined in SparkModels.swift

// MARK: - Firebase Data Manager
class FirebaseDataManager: ObservableObject {
    @Published var items: [SparkItem] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    
    init() {
        // Start listening for data when manager is created
        Task {
            await startListening()
        }
    }
    
    private func startListening() async {
        firebaseManager.startListening { [weak self] firebaseNotes in
            let sparkItems = firebaseNotes.map { SparkItem(from: $0) }
            withAnimation(GentleLightning.Animation.gentle) {
                self?.items = sparkItems
            }
        }
    }
    
    func createItem(from text: String, creationType: String = "text") {
        // Save to Firebase with AI-generated title first, then add to list
        Task {
            do {
                print("📋 DataManager: Starting to save note: '\(text)' type: '\(creationType)'")
                
                // Generate title using OpenAI
                var generatedTitle: String? = nil
                do {
                    generatedTitle = try await OpenAIService.shared.generateTitle(for: text)
                    print("🤖 DataManager: Generated title: '\(generatedTitle!)'")
                } catch {
                    print("⚠️ DataManager: Title generation failed: \(error), proceeding without title")
                }
                
                // Get legacy categories for backward compatibility
                let legacyCategories = await categorizeText(text)
                print("🏷️ DataManager: Categorized text with legacy categories: \(legacyCategories)")
                
                // TODO: Add category suggestion and selection logic here
                let categoryIds: [String] = [] // Will be populated when categories are implemented
                
                let finalTitle = generatedTitle
                let firebaseId = try await firebaseManager.createNote(
                    content: text,
                    title: finalTitle,
                    categoryIds: categoryIds,
                    isTask: false, 
                    categories: legacyCategories,
                    creationType: creationType
                )
                
                print("✅ DataManager: Note saved successfully with Firebase ID: \(firebaseId)")
                
                // Now create the item with the title and add to list
                await MainActor.run {
                    let newItem = SparkItem(content: text, isTask: false)
                    newItem.firebaseId = firebaseId
                    if let title = finalTitle {
                        newItem.title = title
                    }
                    
                    withAnimation(GentleLightning.Animation.elastic) {
                        self.items.insert(newItem, at: 0)
                    }
                    print("📲 DataManager: Added item to list with title: '\(newItem.title)'")
                }
                
                // TODO: Save to Pinecone for vector search
                
            } catch {
                print("💥 DataManager: Failed to save note: \(error)")
                await MainActor.run {
                    self.error = "Failed to save note: \(error.localizedDescription)"
                    print("🗑️ DataManager: Note creation failed")
                }
            }
        }
    }
    
    
    func updateItem(_ item: SparkItem, newContent: String) {
        // Update local item immediately (optimistic)
        item.content = newContent
        
        // Update Firebase
        if let firebaseId = item.firebaseId {
            Task {
                do {
                    try await firebaseManager.updateNote(noteId: firebaseId, newContent: newContent)
                } catch {
                    await MainActor.run {
                        self.error = "Failed to update note: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    func deleteItem(_ item: SparkItem) {
        // Track item deletion before removing
        AnalyticsManager.shared.trackItemDeleted(isTask: item.isTask)
        
        // Remove from local array immediately (optimistic)
        items.removeAll { $0.id == item.id }
        
        // Delete from Firebase
        if let firebaseId = item.firebaseId {
            Task {
                do {
                    try await firebaseManager.deleteNote(noteId: firebaseId)
                } catch {
                    await MainActor.run {
                        self.error = "Failed to delete note: \(error.localizedDescription)"
                        // Re-add the item since deletion failed
                        self.items.insert(item, at: 0)
                    }
                }
            }
        }
    }
    
    // Simple categorization (will be enhanced with AI later)
    private func categorizeText(_ text: String) async -> [String] {
        var categories: [String] = []
        
        if text.lowercased().contains("work") || text.lowercased().contains("meeting") {
            categories.append("work")
        }
        if text.lowercased().contains("personal") || text.lowercased().contains("family") {
            categories.append("personal")
        }
        if text.lowercased().contains("todo") || text.lowercased().contains("task") {
            categories.append("task")
        }
        
        return categories.isEmpty ? ["general"] : categories
    }
}

// MARK: - Content View Model
class ContentViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var placeholderText = "Just start typing..."
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    let placeholder: String
    let dataManager: FirebaseDataManager
    let onCommit: () -> Void
    @FocusState var isFieldFocused: Bool
    
    // Voice recording state
    @State private var isRecording = false
    @State private var speechRecognizer: SFSpeechRecognizer? = SFSpeechRecognizer()
    @State private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    @State private var recognitionTask: SFSpeechRecognitionTask?
    @State private var audioEngine = AVAudioEngine()
    @State private var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined
    @State private var showPermissionAlert = false
    @State private var recordingStartTime: Date?
    
    
    // Computed property to check if there's text content
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Dynamic height for text input
    @State private var textHeight: CGFloat = 40
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .topLeading) {
                    // Placeholder text
                    if text.isEmpty {
                        Text(placeholder)
                            .font(GentleLightning.Typography.bodyInput)
                            .foregroundColor(GentleLightning.Colors.textSecondary.opacity(0.6))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                    }
                    
                    TextEditor(text: $text)
                        .font(GentleLightning.Typography.bodyInput)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                        .focused($isFieldFocused)
                        .disabled(isRecording)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(minHeight: 40, maxHeight: max(40, min(textHeight, 120)), alignment: .topLeading) // Max 3 lines (~120pt), anchored to top
                        .onChange(of: text) { newValue in
                            // Track when user starts typing
                            if newValue.count == 1 && text.count <= 1 {
                                AnalyticsManager.shared.trackNewNoteStarted(method: "text")
                            }
                            
                            // Apply rich text transformations using centralized RichTextTransformer
                            let processedText = RichTextTransformer.transform(newValue, oldText: text)
                            if processedText != newValue {
                                text = processedText
                                if processedText.contains("→") && !newValue.contains("→") {
                                    AnalyticsManager.shared.trackArrowConversion()
                                }
                                if processedText.contains("• ") && !newValue.contains("• ") {
                                    AnalyticsManager.shared.trackBulletPointCreated()
                                }
                                return
                            }
                            
                            // Calculate dynamic height based on content
                            updateTextHeight(for: newValue)
                        }
                        .onAppear {
                            // Check current authorization status
                            authorizationStatus = SFSpeechRecognizer.authorizationStatus()
                            
                            // Only auto-focus on appear, don't request permissions yet
                            Task {
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                await MainActor.run {
                                    if !isRecording {
                                        isFieldFocused = true
                                    }
                                }
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            // Refresh authorization status when app becomes active (user returning from Settings)
                            authorizationStatus = SFSpeechRecognizer.authorizationStatus()
                        }
                }
                
                // Microphone/Save button - transforms based on recording state and text content
                Button(action: {
                    if isRecording {
                        // Stop recording
                        handleVoiceRecording()
                    } else if hasText {
                        // Save the note (only when not recording)
                        if !text.isEmpty {
                            AnalyticsManager.shared.trackNoteSaved(method: "button", contentLength: text.count)
                            dataManager.createItem(from: text, creationType: "text")
                            text = ""
                        }
                    } else {
                        // Start voice recording
                        handleVoiceRecording()
                    }
                }) {
                    ZStack {
                        // Animated background shape with horizontal collapse/expand
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isRecording ? Color.red : Color.black)
                            .frame(height: 40)
                            .frame(width: isRecording ? 40 : (hasText ? 80 : 40))
                            .scaleEffect(x: 1.0, y: 1.0, anchor: .center)
                            .animation(
                                .interpolatingSpring(stiffness: 300, damping: 30)
                                .speed(1.2),
                                value: isRecording || hasText
                            )
                        
                        // Content container with symmetric collapse/expand animations
                        ZStack {
                            // Save text - appears when hasText is true AND not recording
                            if hasText && !isRecording {
                                Text("SAVE")
                                    .font(GentleLightning.Typography.small)
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                                    .scaleEffect(
                                        x: (hasText && !isRecording) ? 1.0 : 0.1, 
                                        y: (hasText && !isRecording) ? 1.0 : 0.1,
                                        anchor: .center
                                    )
                                    .opacity((hasText && !isRecording) ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 280, damping: 22)
                                        .delay((hasText && !isRecording) ? 0.08 : 0.08), // Symmetric timing
                                        value: hasText && !isRecording
                                    )
                            }
                            
                            // Stop icon - appears when recording
                            if isRecording {
                                Image(systemName: "stop.fill")
                                    .font(GentleLightning.Typography.body)
                                    .foregroundColor(.white)
                                    .scaleEffect(
                                        x: isRecording ? 1.0 : 0.1,
                                        y: isRecording ? 1.0 : 0.1,
                                        anchor: .center
                                    )
                                    .opacity(isRecording ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 280, damping: 22)
                                        .delay(0.08), // Consistent symmetric timing
                                        value: isRecording
                                    )
                            }
                            
                            // Microphone icon - default state (when no text and not recording)
                            if !hasText && !isRecording {
                                Image(systemName: "mic.fill")
                                    .font(GentleLightning.Typography.title)
                                    .foregroundColor(.white)
                                    .scaleEffect(
                                        x: (!hasText && !isRecording) ? 1.0 : 0.1,
                                        y: (!hasText && !isRecording) ? 1.0 : 0.1,
                                        anchor: .center
                                    )
                                    .opacity((!hasText && !isRecording) ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 280, damping: 22)
                                        .delay(0.08), // Consistent symmetric timing
                                        value: hasText || isRecording
                                    )
                            }
                        }
                    }
                    .scaleEffect(isRecording ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isRecording)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.vertical, GentleLightning.Layout.Padding.lg)
            .background(Color.white)
            
            // Recording indicator
            if isRecording {
                HStack {
                    Circle()
                        .fill(GentleLightning.Colors.error)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                        .scaleEffect(1.5)
                        .animation(.easeInOut(duration: 0.8).repeatForever(), value: isRecording)
                    
                    Text("Recording...")
                        .font(GentleLightning.Typography.small)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                    
                    Spacer()
                }
                .padding(.horizontal, GentleLightning.Layout.Padding.lg)
                .padding(.top, 4)
                .transition(.opacity)
            }
            
        }
        .alert("Microphone Permission Required", isPresented: $showPermissionAlert) {
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To use voice transcription:\n\n1. Tap 'Open Settings'\n2. Enable 'Microphone' and 'Speech Recognition'\n3. Return to Spark and try again")
        }
    }
    
    private func requestSpeechAuthorization() {
        // First request microphone permission by attempting to start audio engine
        // This will trigger the microphone permission dialog
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // If microphone access works, then request speech recognition
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async {
                    self.authorizationStatus = authStatus
                    // If both permissions granted, start recording immediately
                    if authStatus == .authorized {
                        self.startRecording()
                    }
                }
            }
        } catch {
            print("Failed to set up audio session: \(error)")
            // If microphone access fails, don't request speech recognition
        }
    }
    
    private func handleVoiceRecording() {
        GentleLightning.Sound.Haptic.swoosh.trigger()
        
        if isRecording {
            stopRecording()
        } else {
            // Check permissions before starting recording
            if authorizationStatus == .notDetermined {
                requestSpeechAuthorization()
            } else if authorizationStatus == .authorized {
                startRecording()
            } else {
                // Permission denied - show alert to direct user to Settings
                showPermissionAlert = true
            }
        }
    }
    
    private func startRecording() {
        guard authorizationStatus == .authorized else {
            AnalyticsManager.shared.trackVoicePermissionDenied()
            return
        }
        
        AnalyticsManager.shared.trackVoiceRecordingStarted()
        recordingStartTime = Date()
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("Speech recognizer not available")
            return
        }
        
        do {
            // Cancel previous task if any
            recognitionTask?.cancel()
            recognitionTask = nil
            
            // Configure audio session
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Create recognition request
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                return
            }
            
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            
            // Voice recording creates a new note, doesn't append to existing text
            var voiceNoteContent = ""
            
            // Start recognition task
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                var isFinal = false
                
                if let result = result {
                    DispatchQueue.main.async {
                        let transcription = result.bestTranscription.formattedString
                        
                        // Update the temporary voice note content for visual feedback
                        // Only update visual text if we're still recording
                        voiceNoteContent = transcription
                        if self.isRecording {
                            self.text = transcription
                        }
                    }
                    isFinal = result.isFinal
                }
                
                if error != nil || isFinal {
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    DispatchQueue.main.async {
                        self.recognitionRequest = nil
                        self.recognitionTask = nil
                        self.isRecording = false
                        
                        // Clear the text field immediately to reset button state
                        self.text = ""
                        
                        // Auto-save voice note if we have content
                        if !voiceNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.dataManager.createItem(from: voiceNoteContent, creationType: "voice")
                        }
                    }
                }
            }
            
            // Configure microphone input
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isRecording = true
            AnalyticsManager.shared.trackEvent("voice_recording_started")
            
        } catch {
            print("Error starting recording: \(error)")
            AnalyticsManager.shared.trackEvent("voice_recording_failed", properties: [
                "error": error.localizedDescription
            ])
        }
    }
    
    private func stopRecording() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        isRecording = false
        
        // Track voice recording analytics
        if let startTime = recordingStartTime {
            let duration = Date().timeIntervalSince(startTime)
            AnalyticsManager.shared.trackVoiceRecordingStopped(duration: duration, textLength: text.count)
        }
        recordingStartTime = nil
        
        // Clear text field to reset button state
        text = ""
        
        // Provide haptic feedback to indicate recording stopped
        GentleLightning.Sound.Haptic.swoosh.trigger()
    }
    
    // Calculate text height dynamically
    private func updateTextHeight(for text: String) {
        let font = UIFont(name: "SharpGrotesk-Book", size: 17) ?? UIFont.systemFont(ofSize: 17) // Match bodyInput font size
        let screenWidth = UIScreen.main.bounds.width
        let maxWidth = max(200, screenWidth.isFinite ? screenWidth - 120 : 200) // Ensure minimum width, account for padding and mic button
        
        if !maxWidth.isFinite {
            print("⚠️ updateTextHeight: maxWidth is not finite, using fallback")
            textHeight = 40
            return
        }
        
        // Use empty string calculation for empty text to avoid NaN
        let textToMeasure = text.isEmpty ? " " : text
        
        let boundingRect = textToMeasure.boundingRect(
            with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        
        // Ensure we don't get NaN values
        let rectHeight = boundingRect.height.isFinite ? boundingRect.height : 40
        
        // Calculate height with padding, minimum 40pt, maximum 120pt (3 lines)
        let calculatedHeight = max(40, rectHeight + 16) // 16pt for padding
        
        // Ensure final value is finite and within bounds
        let finalHeight = min(max(40, calculatedHeight.isFinite ? calculatedHeight : 40), 120)
        
        // Temporarily disable animation to prevent NaN issues
        textHeight = finalHeight
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        // Completely empty state - no visual elements
        EmptyView()
    }
}

// MARK: - Item Row
struct ItemRowSimple: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    let onTap: () -> Void
    // @ObservedObject private var categoryService = CategoryService.shared
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Title and content
                VStack(alignment: .leading, spacing: 4) {
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    Text(item.content)
                        .font(item.title.isEmpty ? GentleLightning.Typography.body : GentleLightning.Typography.secondary)
                        .foregroundColor(item.title.isEmpty ? GentleLightning.Colors.textPrimary : GentleLightning.Colors.textSecondary)
                        .lineLimit(item.title.isEmpty ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Category pills
                if !item.categoryIds.isEmpty {
                    HStack(spacing: 6) {
                        // TODO: Uncomment when CategoryService is added to project
                        /*
                        ForEach(categoryService.getCategoriesByIds(item.categoryIds), id: \.id) { category in
                            CategoryPillSimple(category: category)
                        }
                        */
                        Spacer()
                    }
                }
                
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.vertical, GentleLightning.Layout.Padding.lg)
            .background(
                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                    .fill(GentleLightning.Colors.surface)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") {
                withAnimation(GentleLightning.Animation.gentle) {
                    dataManager.deleteItem(item)
                }
            }
            .tint(.red)
        }
    }
}

// MARK: - Simple Category Pill for List View
// TODO: Uncomment when Category model is added to project
/*
struct CategoryPillSimple: View {
    let category: Category
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(category.uiColor)
                .frame(width: 6, height: 6)
            
            Text(category.name)
                .font(GentleLightning.Typography.metadata)
                .foregroundColor(GentleLightning.Colors.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(category.uiColor.opacity(0.1))
        )
    }
}
*/

// MARK: - Note Edit View
struct NoteEditView: View {
    @Binding var isPresented: Bool
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    
    @State private var editedText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingActionSheet = false
    @State private var showingDeleteAlert = false
    @State private var isContentReady = true
    
    init(isPresented: Binding<Bool>, item: SparkItem, dataManager: FirebaseDataManager) {
        print("🏗️ NoteEditView init: STARTING - item.id = '\(item.id)'")
        print("🏗️ NoteEditView init: item.content = '\(item.content)' (length: \(item.content.count))")
        print("🏗️ NoteEditView init: item.content.isEmpty = \(item.content.isEmpty)")
        
        self._isPresented = isPresented
        self.item = item
        self.dataManager = dataManager
        
        let initialContent = item.content.isEmpty ? " " : item.content
        print("🏗️ NoteEditView init: initialContent = '\(initialContent)' (length: \(initialContent.count))")
        
        self._editedText = State(initialValue: initialContent)
        
        print("🏗️ NoteEditView init: COMPLETED - editedText initialized with '\(initialContent.prefix(50))...'")
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isContentReady {
                    // Simplified Text Editor without ScrollView wrapper
                    TextEditor(text: Binding(
                        get: {
                            print("📖 TextEditor binding GET: returning '\(editedText.prefix(30))...' (length: \(editedText.count))")
                            return editedText
                        },
                        set: { newValue in
                            print("✏️  TextEditor binding SET: received '\(newValue.prefix(30))...' (length: \(newValue.count))")
                            editedText = newValue
                        }
                    ))
                        .font(GentleLightning.Typography.bodyInput)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                        .padding(GentleLightning.Layout.Padding.lg)
                        .background(Color.white)
                        .focused($isTextFieldFocused)
                        .onAppear {
                            print("🎯 NoteEditView: TextEditor onAppear - text = '\(editedText.prefix(30))...'")
                            print("🎯 NoteEditView: TextEditor onAppear - focusing field in 0.1s")
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isTextFieldFocused = true
                                print("🎯 NoteEditView: TextEditor focus applied")
                            }
                        }
                } else {
                    // Loading state
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(GentleLightning.Colors.accentNeutral)
                        
                        Text("Loading note...")
                            .font(GentleLightning.Typography.body)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white)
                }
            }
            .onAppear {
                print("🚀 NoteEditView VStack onAppear: TRIGGERED")
                print("🚀 NoteEditView VStack onAppear: item.content = '\(item.content)' (length: \(item.content.count))")
                print("🚀 NoteEditView VStack onAppear: editedText = '\(editedText)' (length: \(editedText.count))")
                print("🚀 NoteEditView VStack onAppear: isContentReady = \(isContentReady)")
                
                // Double-check our content is safe
                let safeContent = sanitizeTextContent(item.content)
                print("🚀 NoteEditView VStack onAppear: safeContent = '\(safeContent)' (length: \(safeContent.count))")
                
                if editedText != safeContent {
                    print("⚠️  NoteEditView VStack onAppear: Content mismatch - updating editedText")
                    print("⚠️  NoteEditView VStack onAppear: Old: '\(editedText)'")
                    print("⚠️  NoteEditView VStack onAppear: New: '\(safeContent)'")
                    editedText = safeContent
                } else {
                    print("✅ NoteEditView VStack onAppear: Content matches - no update needed")
                }
                
                // Set content ready to show the TextEditor
                print("🚀 NoteEditView VStack onAppear: Setting isContentReady = true")
                DispatchQueue.main.async {
                    isContentReady = true
                    print("✅ NoteEditView VStack onAppear: Content ready - TextEditor should show")
                }
            }
                    .onChange(of: editedText) { newValue in
                        // Sanitize input to prevent NaN errors
                        let safeValue = sanitizeTextContent(newValue)
                        if safeValue != newValue {
                            print("🛡️ NoteEditView: Sanitized input from '\(newValue)' to '\(safeValue)'")
                            editedText = safeValue
                            return
                        }
                        
                        // Apply rich text transformations (bullets, arrows, etc.)
                        guard !safeValue.isEmpty else { return }
                        
                        let processedText = RichTextTransformer.transform(safeValue, oldText: editedText)
                        if processedText != safeValue && processedText != editedText {
                            editedText = processedText
                        }
                        
                        // Auto-save changes
                        let trimmedContent = safeValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmedContent.isEmpty {
                            dataManager.updateItem(item, newContent: trimmedContent)
                            AnalyticsManager.shared.trackNoteEditSaved(noteId: item.id, contentLength: safeValue.count)
                        }
                    }
                    .onChange(of: item.content) { newContent in
                        // Update edited text if the underlying item content changes (with sanitization)
                        let safeNewContent = sanitizeTextContent(newContent)
                        if editedText != safeNewContent {
                            print("📝 NoteEditView: Item content changed, updating to safe content: '\(safeNewContent)'")
                            editedText = safeNewContent
                        }
                    }
            .background(Color.white)
            // .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Back") {
                    isPresented = false
                }
                .font(GentleLightning.Typography.body)
                .foregroundColor(GentleLightning.Colors.textSecondary),
                
                trailing: Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(GentleLightning.Typography.bodyInput)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                }
            )
            .confirmationDialog("Note Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
                Button("Share") {
                    shareNote()
                }
                Button("Delete", role: .destructive) {
                    showingDeleteAlert = true
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert("Delete Note", isPresented: $showingDeleteAlert) {
                Button("Delete", role: .destructive) {
                    dataManager.deleteItem(item)
                    isPresented = false
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This note will be permanently deleted. This action cannot be undone.")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    // Share note using iOS share sheet
    func shareNote() {
        AnalyticsManager.shared.trackNoteShared(noteId: item.id)
        let shareText = editedText.isEmpty ? item.content : editedText
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        // Get the key window and root view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = keyWindow.rootViewController else {
            print("ShareNote: Could not find root view controller")
            return
        }
        
        // Find the topmost view controller that can present
        var presentingViewController = rootViewController
        while let presented = presentingViewController.presentedViewController {
            // Ensure we don't get stuck in a loop and that the view controller is ready
            if presented.isBeingPresented || presented.isBeingDismissed {
                break
            }
            presentingViewController = presented
        }
        
        // Ensure the presenting view controller is loaded and ready
        guard presentingViewController.isViewLoaded,
              presentingViewController.view.window != nil else {
            print("ShareNote: Presenting view controller not ready")
            return
        }
        
        // Configure for iPad popover
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presentingViewController.view
            popover.sourceRect = CGRect(
                x: presentingViewController.view.bounds.midX, 
                y: presentingViewController.view.bounds.midY, 
                width: 0, 
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        
        // Present with error handling
        DispatchQueue.main.async {
            presentingViewController.present(activityViewController, animated: true) { [weak presentingViewController] in
                print("ShareNote: Activity view controller presented successfully from \(String(describing: presentingViewController))")
            }
        }
    }
    
    // Sanitize text content to prevent CoreGraphics NaN errors
    func sanitizeTextContent(_ text: String) -> String {
        guard !text.isEmpty else { return " " }
        
        // Remove any problematic characters that could cause layout issues
        var sanitized = text
        
        // Remove null characters and other control characters that might cause issues
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")
        
        // Replace any zero-width or invisible characters that might cause measurement issues
        sanitized = sanitized.replacingOccurrences(of: "\u{200B}", with: "") // Zero-width space
        sanitized = sanitized.replacingOccurrences(of: "\u{FEFF}", with: "") // Byte order mark
        sanitized = sanitized.replacingOccurrences(of: "\u{202E}", with: "") // Right-to-left override
        
        // Ensure we don't have empty string after sanitization
        if sanitized.isEmpty || sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return " "
        }
        
        // Limit extremely long single lines that might cause layout issues
        let lines = sanitized.components(separatedBy: .newlines)
        let sanitizedLines = lines.map { line in
            line.count > 1000 ? String(line.prefix(1000)) + "..." : line
        }
        
        return sanitizedLines.joined(separator: "\n")
    }
}

// MARK: - Account Drawer View
struct AccountDrawerView: View {
    @Binding var isPresented: Bool
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showDeleteResult = false
    
    // Get app version info
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2)
                .fill(GentleLightning.Colors.textSecondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)
            
            VStack(spacing: 24) {
                // Account actions
                VStack(spacing: 16) {
                    // Logout button
                    Button(action: {
                        do {
                            try FirebaseManager.shared.signOut()
                        } catch {
                            print("Sign out error: \(error)")
                        }
                        isPresented = false
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.square")
                                .font(GentleLightning.Typography.title)
                            Text("Logout")
                                .font(GentleLightning.Typography.body)
                            Spacer()
                        }
                        .foregroundColor(GentleLightning.Colors.textBlack)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(GentleLightning.Colors.surface)
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 4, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Delete Account button
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .font(GentleLightning.Typography.title)
                            Text("Delete Account")
                                .font(GentleLightning.Typography.body)
                            Spacer()
                        }
                        .foregroundColor(GentleLightning.Colors.error)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(GentleLightning.Colors.surface)
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 4, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Spacer()
                
                // App info
                VStack(spacing: 8) {
                    Text("Scrap")
                        .font(GentleLightning.Typography.title)
                        .foregroundColor(GentleLightning.Colors.textBlack)
                    
                    Text("Version \(appVersion) (\(buildNumber))")
                        .font(GentleLightning.Typography.small)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                }
                .padding(.bottom, 40)
            }
            .padding(.horizontal, 20)
        }
        .background(Color.white)
        .alert("Delete Account", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                isDeletingAccount = true
                deleteError = nil
                
                Task {
                    do {
                        try await FirebaseManager.shared.deleteAccount()
                        
                        // Account deleted successfully, user is now logged out
                        await MainActor.run {
                            isDeletingAccount = false
                            deleteError = nil
                            isPresented = false
                        }
                        
                    } catch {
                        await MainActor.run {
                            isDeletingAccount = false
                            deleteError = "Failed to delete account: \(error.localizedDescription)\n\nYour notes have been deleted and you have been logged out, but the account may still exist. Please contact support if needed."
                            showDeleteResult = true
                        }
                    }
                }
            }
            .disabled(isDeletingAccount)
            
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all your notes. This action cannot be undone.")
        }
        .alert("Account Deletion", isPresented: $showDeleteResult) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            Text(deleteError ?? "Account deleted successfully. You have been logged out.")
        }
        .overlay(
            // Loading overlay when deleting account
            Group {
                if isDeletingAccount {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(GentleLightning.Colors.accentNeutral)
                        
                        Text("Deleting account...")
                            .font(GentleLightning.Typography.body)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                        
                        Text("This may take a moment")
                            .font(GentleLightning.Typography.caption)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .padding(32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.white)
                            .shadow(color: GentleLightning.Colors.shadowLight, radius: 20, x: 0, y: 4)
                    )
                }
            }
        )
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @State private var navigationPath = NavigationPath()
    @State private var showingAccountDrawer = false
    @State private var showingSettings = false
    @FocusState private var isInputFieldFocused: Bool
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with Spark title and settings
                HStack {
                    Spacer()
                    
                    Text("Scrap")
                        .font(GentleLightning.Typography.hero)
                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                    
                    Spacer()
                    
                    Button(action: {
                        showingSettings = true
                    }) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20))
                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                    }
                }
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                .padding(.top, GentleLightning.Layout.Padding.xl)
                .padding(.bottom, GentleLightning.Layout.Padding.lg)
                
                // Large spacer to push input field lower
                Spacer()
                Spacer()
                
                // Input Field - positioned lower on screen
                InputField(text: $viewModel.inputText, 
                          placeholder: viewModel.placeholderText,
                          dataManager: dataManager,
                          onCommit: {
                    // No automatic saving - users must use the SAVE button
                    // Just dismiss keyboard when pressing return
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                })
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                
                // Smaller spacer below
                Spacer()
                    .frame(maxHeight: 100)
                
                // Items List - scrollable content
                ScrollView {
                    LazyVStack(spacing: GentleLightning.Layout.Spacing.comfortable) {
                        if dataManager.items.isEmpty {
                            EmptyStateView()
                                .padding(.top, 60)
                        } else {
                            ForEach(dataManager.items) { item in
                                ItemRowSimple(item: item, dataManager: dataManager) {
                                    print("🎯 ContentView: Note tap detected - navigating to item.id = '\(item.id)'")
                                    print("🎯 ContentView: item.content = '\(item.content)' (length: \(item.content.count))")
                                    
                                    AnalyticsManager.shared.trackNoteEditOpened(noteId: item.id)
                                    
                                    // Use navigation instead of sheets - bulletproof approach
                                    navigationPath.append(item)
                                    
                                    print("✅ ContentView: Navigation pushed for item.id = '\(item.id)'")
                                }
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                    removal: .move(edge: .leading).combined(with: .opacity)
                                ))
                                .animation(GentleLightning.Animation.elastic, value: item.id)
                            }
                        }
                    }
                    .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                    .padding(.bottom, 120) // Extra padding for footer
                }
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { gesture in
                            // Dismiss keyboard immediately when scrolling starts  
                            if abs(gesture.translation.height) > 10 && isInputFieldFocused {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                )
                .onTapGesture {
                    // Also dismiss keyboard when tapping in scroll area
                    if isInputFieldFocused {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
            }
            
            // Fixed footer at bottom - will be covered by keyboard
            VStack {
                Spacer()
                
                VStack(spacing: 0) {
                    Divider()
                        .opacity(0.1)
                    
                    Button(action: {
                        AnalyticsManager.shared.trackAccountDrawerOpened()
                        showingAccountDrawer = true
                    }) {
                        Text("My Account")
                            .font(GentleLightning.Typography.body)
                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                }
                .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
        .contentShape(Rectangle()) // Make the entire area tappable for keyboard dismissal
        .onTapGesture {
            // Dismiss keyboard when tapping outside input area
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .navigationDestination(for: SparkItem.self) { item in
            NavigationNoteEditView(item: item, dataManager: dataManager)
                .onAppear {
                    print("✅ Navigation NoteEditView: Successfully opened note with id = '\(item.id)'")
                    print("✅ Navigation NoteEditView: Note content = '\(item.content)' (length: \(item.content.count))")
                }
        }
        .sheet(isPresented: $showingAccountDrawer) {
            AccountDrawerView(isPresented: $showingAccountDrawer)
                .presentationDetents([.fraction(0.4), .medium])
                .presentationDragIndicator(.hidden)
                .onDisappear {
                    AnalyticsManager.shared.trackAccountDrawerClosed()
                }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(themeManager: themeManager)
        }
        } // NavigationStack
    }
}

// MARK: - Navigation Note Edit View
struct NavigationNoteEditView: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    @Environment(\.dismiss) private var dismiss
    // @ObservedObject private var categoryService = CategoryService.shared
    
    @State private var editedText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingActionSheet = false
    @State private var showingDeleteAlert = false
    @State private var isContentReady = true
    @State private var selectedCategoryIds: [String] = []
    @State private var editedTitle: String = ""
    @State private var showingFormattingSheet = false
    
    init(item: SparkItem, dataManager: FirebaseDataManager) {
        print("🏗️ NavigationNoteEditView init: STARTING - item.id = '\(item.id)'")
        print("🏗️ NavigationNoteEditView init: item.content = '\(item.content)' (length: \(item.content.count))")
        
        self.item = item
        self.dataManager = dataManager
        
        let initialContent = item.content.isEmpty ? " " : item.content
        print("🏗️ NavigationNoteEditView init: initialContent = '\(initialContent)' (length: \(initialContent.count))")
        
        self._editedText = State(initialValue: initialContent)
        self._selectedCategoryIds = State(initialValue: item.categoryIds)
        self._editedTitle = State(initialValue: item.title)
        
        print("🏗️ NavigationNoteEditView init: COMPLETED - all properties initialized")
    }
    
    // MARK: - View Components
    private var titleSection: some View {
        TextField("Title", text: $editedTitle)
            .font(.headline)
            .padding(GentleLightning.Layout.Padding.lg)
            .background(Color.white)
            .onChange(of: editedTitle) { newTitle in
                guard !newTitle.isEmpty else { return }
                item.title = newTitle
            }
    }
    
    private var textEditorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inline formatting button at start of content area
            HStack {
                Button(action: { showingFormattingSheet.toggle() }) {
                    HStack(spacing: 2) {
                        Text("B")
                            .font(.system(size: 14, weight: .bold))
                        Text("7")
                            .font(.system(size: 12))
                            .underline()
                        Text("U")
                            .font(.system(size: 14))
                            .underline()
                    }
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(GentleLightning.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                Spacer()
            }
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.bottom, 8)
            
            // Text editor
            TextEditor(text: $editedText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(GentleLightning.Layout.Padding.lg)
                .background(Color.white)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            if isContentReady {
                titleSection
                textEditorSection
            }
                
            // Category picker at bottom
            VStack(spacing: 0) {
                Divider()
                    .background(GentleLightning.Colors.textSecondary.opacity(0.3))
                
                // TODO: Uncomment when CategoryPicker is added to project
                /*
                CategoryPicker(selectedCategoryIds: $selectedCategoryIds, maxSelections: 3)
                    .padding(GentleLightning.Layout.Padding.lg)
                    .onChange(of: selectedCategoryIds) { newCategoryIds in
                        // Update the item's categories
                        Task {
                            if let firebaseId = item.firebaseId {
                                do {
                                    try await FirebaseManager.shared.updateNoteCategories(noteId: firebaseId, categoryIds: newCategoryIds)
                                    await MainActor.run {
                                        item.categoryIds = newCategoryIds
                                    }
                                    
                                    // Update usage count for selected categories
                                    for categoryId in newCategoryIds {
                                        await categoryService.updateCategoryUsage(categoryId)
                                    }
                                } catch {
                                    print("Failed to update categories: \(error)")
                                }
                            }
                        }
                    }
                */
            }
            .background(Color.white)
        }
        .onAppear {
            print("🚀 NavigationNoteEditView VStack onAppear: TRIGGERED")
            
            let safeContent = sanitizeTextContent(item.content)
            print("🚀 NavigationNoteEditView VStack onAppear: safeContent = '\(safeContent)' (length: \(safeContent.count))")
            
            if editedText != safeContent {
                print("⚠️ NavigationNoteEditView VStack onAppear: Content mismatch - updating editedText")
                editedText = safeContent
            } else {
                print("✅ NavigationNoteEditView VStack onAppear: Content matches - no update needed")
            }
            
            isContentReady = true
            print("✅ NavigationNoteEditView VStack onAppear: Content ready - TextEditor should show")
        }
        .onChange(of: editedText) { newValue in
            let safeValue = sanitizeTextContent(newValue)
            if safeValue != newValue {
                print("🛡️ NavigationNoteEditView: Sanitized input")
                editedText = safeValue
                return
            }
            
            guard !safeValue.isEmpty else { return }
            
            let processedText = RichTextTransformer.transform(safeValue, oldText: editedText)
            if processedText != safeValue && processedText != editedText {
                editedText = processedText
            }
            
            let trimmedContent = safeValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedContent.isEmpty {
                dataManager.updateItem(item, newContent: trimmedContent)
                AnalyticsManager.shared.trackNoteEditSaved(noteId: item.id, contentLength: safeValue.count)
            }
        }
        .onChange(of: item.content) { newContent in
            let safeNewContent = sanitizeTextContent(newContent)
            if editedText != safeNewContent {
                print("📝 NavigationNoteEditView: Item content changed, updating to safe content")
                editedText = safeNewContent
            }
        }
        .background(Color.white)
        // .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(GentleLightning.Typography.bodyInput)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                }
            }
        }
        .confirmationDialog("Note Options", isPresented: $showingActionSheet, titleVisibility: .visible) {
            Button("Share") {
                shareNote()
            }
            Button("Delete", role: .destructive) {
                showingDeleteAlert = true
            }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Note", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                dataManager.deleteItem(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This note will be permanently deleted. This action cannot be undone.")
        }
        .sheet(isPresented: $showingFormattingSheet) {
            FormattingSheet(text: $editedText)
        }
    }
    
    private func shareNote() {
        AnalyticsManager.shared.trackNoteShared(noteId: item.id)
        let shareText = editedText.isEmpty ? item.content : editedText
        
        let activityViewController = UIActivityViewController(
            activityItems: [shareText],
            applicationActivities: nil
        )
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let keyWindow = windowScene.windows.first(where: { $0.isKeyWindow }),
              let rootViewController = keyWindow.rootViewController else {
            print("ShareNote: Could not find root view controller")
            return
        }
        
        var presentingViewController = rootViewController
        while let presented = presentingViewController.presentedViewController {
            if presented.isBeingPresented || presented.isBeingDismissed {
                break
            }
            presentingViewController = presented
        }
        
        guard presentingViewController.isViewLoaded,
              presentingViewController.view.window != nil else {
            print("ShareNote: Presenting view controller not ready")
            return
        }
        
        if let popover = activityViewController.popoverPresentationController {
            popover.sourceView = presentingViewController.view
            popover.sourceRect = CGRect(
                x: presentingViewController.view.bounds.midX, 
                y: presentingViewController.view.bounds.midY, 
                width: 0, 
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        
        DispatchQueue.main.async {
            presentingViewController.present(activityViewController, animated: true) { [weak presentingViewController] in
                print("ShareNote: Activity view controller presented successfully from \(String(describing: presentingViewController))")
            }
        }
    }
    
    private func sanitizeTextContent(_ text: String) -> String {
        guard !text.isEmpty else { return " " }
        
        var sanitized = text
        sanitized = sanitized.replacingOccurrences(of: "\0", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\u{200B}", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\u{FEFF}", with: "")
        sanitized = sanitized.replacingOccurrences(of: "\u{202E}", with: "")
        
        if sanitized.isEmpty || sanitized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return " "
        }
        
        let lines = sanitized.components(separatedBy: .newlines)
        let sanitizedLines = lines.map { line in
            line.count > 1000 ? String(line.prefix(1000)) + "..." : line
        }
        
        return sanitizedLines.joined(separator: "\n")
    }
}

// MARK: - Formatting Sheet
struct FormattingSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Text Formatting")
                    .font(GentleLightning.Typography.title)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .padding(.top, 20)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    FormatButton(title: "Bold", symbol: "bold", action: { applyFormat("**", "**") })
                    FormatButton(title: "Italic", symbol: "italic", action: { applyFormat("*", "*") })
                    FormatButton(title: "Underline", symbol: "underline", action: { applyFormat("<u>", "</u>") })
                    FormatButton(title: "Strikethrough", symbol: "strikethrough", action: { applyFormat("~~", "~~") })
                    FormatButton(title: "Code", symbol: "curlybraces", action: { applyFormat("`", "`") })
                    FormatButton(title: "Quote", symbol: "quote.bubble", action: { applyFormat("> ", "") })
                    FormatButton(title: "Bullet", symbol: "list.bullet", action: { applyFormat("• ", "") })
                    FormatButton(title: "Number", symbol: "list.number", action: { applyFormat("1. ", "") })
                    FormatButton(title: "Header 1", symbol: "textformat.size.larger", action: { applyFormat("# ", "") })
                    FormatButton(title: "Header 2", symbol: "textformat.size", action: { applyFormat("## ", "") })
                    FormatButton(title: "Link", symbol: "link", action: { applyFormat("[", "](url)") })
                    FormatButton(title: "Highlight", symbol: "highlighter", action: { applyFormat("==", "==") })
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("Formatting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func applyFormat(_ prefix: String, _ suffix: String) {
        text += prefix + "text" + suffix
        dismiss()
    }
}

// MARK: - Format Button
struct FormatButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                
                Text(title)
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GentleLightning.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}