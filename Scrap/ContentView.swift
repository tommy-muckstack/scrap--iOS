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
        static let background = Color.white
        static let backgroundWarm = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)
        static let textBlack = Color.black // New option for stronger contrast
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let shadowLight = Color.black.opacity(0.03)
        static let error = Color(red: 0.95, green: 0.26, blue: 0.21)
        static let success = Color(red: 0.29, green: 0.76, blue: 0.49)
    }
    
    struct Typography {
        // Primary hierarchy (most commonly used)
        static let hero = Font.custom("SharpGrotesk-SemiBold", size: 34)
        static let body = Font.custom("SharpGrotesk-Book", size: 16)
        static let bodyInput = Font.custom("SharpGrotesk-Book", size: 17)
        static let title = Font.custom("SharpGrotesk-Medium", size: 20)
        static let caption = Font.custom("SharpGrotesk-Book", size: 13)
        static let small = Font.custom("SharpGrotesk-Book", size: 11)
        
        // Extended weight options
        static let ultraLight = Font.custom("SharpGrotesk-Thin", size: 14)
        static let light = Font.custom("SharpGrotesk-Light", size: 16)
        static let medium = Font.custom("SharpGrotesk-Medium", size: 16)
        
        // Italic variants for emphasis and style
        static let bodyItalic = Font.custom("SharpGrotesk-BookItalic", size: 16)
        static let titleItalic = Font.custom("SharpGrotesk-MediumItalic", size: 20)
        static let lightItalic = Font.custom("SharpGrotesk-LightItalic", size: 16)
        static let ultraLightItalic = Font.custom("SharpGrotesk-ThinItalic", size: 14)
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
class SparkItem: ObservableObject, Identifiable {
    let id: String
    @Published var content: String
    @Published var isTask: Bool
    @Published var isCompleted: Bool
    let createdAt: Date
    var firebaseId: String?
    
    var wrappedContent: String { content }
    
    init(content: String, isTask: Bool = false, id: String = UUID().uuidString) {
        self.id = id
        self.content = content
        self.isTask = isTask
        self.isCompleted = false
        self.createdAt = Date()
    }
    
    // Initialize from Firebase note
    init(from firebaseNote: FirebaseNote) {
        self.id = firebaseNote.id ?? UUID().uuidString
        self.content = firebaseNote.content
        self.isTask = firebaseNote.isTask
        self.isCompleted = false // Firebase notes don't have completion status yet
        self.createdAt = firebaseNote.createdAt
        self.firebaseId = firebaseNote.id
    }
}

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
        // Create optimistic local item - always a note, never a task
        let newItem = SparkItem(content: text, isTask: false)
        withAnimation(GentleLightning.Animation.elastic) {
            items.insert(newItem, at: 0)
        }
        
        // Save to Firebase
        Task {
            do {
                print("📋 DataManager: Starting to save note: '\(text)' type: '\(creationType)'")
                let categories = await categorizeText(text)
                print("🏷️ DataManager: Categorized text with categories: \(categories)")
                
                let firebaseId = try await firebaseManager.createNote(
                    content: text, 
                    isTask: false, 
                    categories: categories,
                    creationType: creationType
                )
                
                print("✅ DataManager: Note saved successfully with Firebase ID: \(firebaseId)")
                
                await MainActor.run {
                    newItem.firebaseId = firebaseId
                    print("📲 DataManager: Updated local item with Firebase ID")
                }
                
                // TODO: Save to Pinecone for vector search
                
            } catch {
                print("💥 DataManager: Failed to save note: \(error)")
                await MainActor.run {
                    // Remove optimistic item on error
                    self.items.removeAll { $0.id == newItem.id }
                    self.error = "Failed to save note: \(error.localizedDescription)"
                    print("🗑️ DataManager: Removed failed item from local storage")
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
                            
                            // Process arrow replacement: -> becomes →
                            let processedText = newValue.replacingOccurrences(of: "->", with: "→")
                            if processedText != newValue {
                                text = processedText
                                AnalyticsManager.shared.trackArrowConversion()
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
                
                // Microphone/Save button - transforms based on text content
                Button(action: {
                    if hasText {
                        // Save the note
                        if !text.isEmpty {
                            AnalyticsManager.shared.trackNoteSaved(method: "button", contentLength: text.count)
                            dataManager.createItem(from: text, creationType: "text")
                            text = ""
                        }
                    } else {
                        // Voice recording
                        handleVoiceRecording()
                    }
                }) {
                    ZStack {
                        // Animated background shape with horizontal collapse/expand
                        RoundedRectangle(cornerRadius: 20)
                            .fill(isRecording ? Color.red : Color.black)
                            .frame(height: 40)
                            .frame(width: hasText ? 80 : 40)
                            .scaleEffect(x: 1.0, y: 1.0, anchor: .center)
                            .animation(
                                .interpolatingSpring(stiffness: 300, damping: 30)
                                .speed(1.2),
                                value: hasText
                            )
                        
                        // Content container with staggered collapse/expand animations
                        ZStack {
                            // Save text - appears when hasText is true
                            if hasText {
                                Text("SAVE")
                                    .font(GentleLightning.Typography.small)
                                    .foregroundColor(.white)
                                    .fontWeight(.semibold)
                                    .scaleEffect(
                                        x: hasText ? 1.0 : 0.01, 
                                        y: hasText ? 1.0 : 0.01,
                                        anchor: .center
                                    )
                                    .opacity(hasText ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 250, damping: 20)
                                        .delay(hasText ? 0.15 : 0), // Delay entrance, immediate exit
                                        value: hasText
                                    )
                            }
                            
                            // Stop icon - appears when recording
                            if isRecording {
                                Image(systemName: "stop.fill")
                                    .font(GentleLightning.Typography.body)
                                    .foregroundColor(.white)
                                    .scaleEffect(
                                        x: isRecording ? 1.0 : 0.01,
                                        y: isRecording ? 1.0 : 0.01,
                                        anchor: .center
                                    )
                                    .opacity(isRecording ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 250, damping: 20)
                                        .delay(isRecording ? 0.1 : 0),
                                        value: isRecording
                                    )
                            }
                            
                            // Microphone icon - default state
                            if !hasText && !isRecording {
                                Image(systemName: "mic.fill")
                                    .font(GentleLightning.Typography.title)
                                    .foregroundColor(.white)
                                    .scaleEffect(
                                        x: (!hasText && !isRecording) ? 1.0 : 0.01,
                                        y: (!hasText && !isRecording) ? 1.0 : 0.01,
                                        anchor: .center
                                    )
                                    .opacity((!hasText && !isRecording) ? 1.0 : 0.0)
                                    .animation(
                                        .interpolatingSpring(stiffness: 250, damping: 20)
                                        .delay((!hasText && !isRecording) ? 0.15 : 0),
                                        value: hasText
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
                        voiceNoteContent = transcription
                        self.text = transcription
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
                        
                        // Auto-save voice note if we have content
                        if !voiceNoteContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            self.dataManager.createItem(from: voiceNoteContent, creationType: "voice")
                            
                            // Clear the text field with animation
                            withAnimation(.easeOut(duration: 0.3)) {
                                self.text = ""
                            }
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
        
        // Don't auto-save when appending to existing text - let user decide when to save
        // Just provide haptic feedback to indicate recording stopped
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
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(item.wrappedContent)
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
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

// MARK: - Note Edit View
struct NoteEditView: View {
    @Binding var isPresented: Bool
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    
    @State private var editedText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    @State private var showingActionSheet = false
    @State private var showingDeleteAlert = false
    @State private var isContentReady = false
    @State private var hasValidGeometry = false
    
    init(isPresented: Binding<Bool>, item: SparkItem, dataManager: FirebaseDataManager) {
        self._isPresented = isPresented
        self.item = item
        self.dataManager = dataManager
        
        let initialContent = item.content.isEmpty ? " " : item.content
        print("🔧 NoteEditView init: item.content = '\(item.content)' -> initialContent = '\(initialContent)'")
        
        // Validate the content doesn't contain problematic characters that could cause NaN
        let safeContent = sanitizeTextContent(initialContent)
        print("🔧 NoteEditView init: sanitized content = '\(safeContent)'")
        
        self._editedText = State(initialValue: safeContent)
    }
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if isContentReady && hasValidGeometry {
                        // Text Editor with safe bounds
                        ScrollView {
                            TextEditor(text: $editedText)
                                .font(GentleLightning.Typography.bodyInput)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                                .padding(GentleLightning.Layout.Padding.lg)
                                .frame(
                                    minWidth: max(200, validWidth(from: geometry.size.width)),
                                    maxWidth: .infinity,
                                    minHeight: max(120, validHeight(from: geometry.size.height)),
                                    maxHeight: .infinity,
                                    alignment: .topLeading
                                )
                                .background(Color.white)
                                .focused($isTextFieldFocused)
                                .onAppear {
                                    print("📝 NoteEditView: TextEditor appeared - focusing field")
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        isTextFieldFocused = true
                                    }
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
                    print("📝 NoteEditView: onAppear - geometry: \(geometry.size), item.content: '\(item.content)', editedText: '\(editedText)'")
                    
                    // Validate geometry
                    validateGeometry(geometry.size)
                    
                    // Double-check our content is safe
                    let safeContent = sanitizeTextContent(item.content)
                    if editedText != safeContent {
                        print("📝 NoteEditView: Updating to safe content: '\(safeContent)'")
                        editedText = safeContent
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
                        
                        // Auto-convert bullet markers to bullet points
                        guard !safeValue.isEmpty else { return }
                        
                        let processedText = processMarkdownBullets(safeValue, oldValue: editedText)
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
                }
                
                Spacer()
            }
            .background(Color.white)
            .navigationTitle("Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
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
            .actionSheet(isPresented: $showingActionSheet) {
                ActionSheet(
                    title: Text("Note Options"),
                    buttons: [
                        .default(Text("Share")) {
                            shareNote()
                        },
                        .destructive(Text("Delete")) {
                            showingDeleteAlert = true
                        },
                        .cancel()
                    ]
                )
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
    
    // MARK: - Helper Methods
    
    // Share note using iOS share sheet
    private func shareNote() {
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
    private func sanitizeTextContent(_ text: String) -> String {
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
    
    // Process markdown-style bullets and smart bullet continuation
    private func processMarkdownBullets(_ text: String, oldValue: String) -> String {
        // Handle Enter key - continue bullet lists
        if text.count > oldValue.count && text.hasSuffix("\n") {
            return processBulletContinuation(text)
        }
        
        // Handle backspace - remove bullets when appropriate
        if text.count < oldValue.count {
            return processBackspaceBulletRemoval(text, oldValue: oldValue)
        }
        
        // Handle space after * or - (original markdown conversion)
        if text.count > oldValue.count && text.hasSuffix(" ") {
            let processed = processMarkdownConversion(text)
            if processed != text {
                AnalyticsManager.shared.trackBulletPointCreated()
            }
            return processArrowReplacement(processed)
        }
        
        // Handle arrow replacement when typing -> followed by space or any character
        if text.count > oldValue.count {
            return processArrowReplacement(text)
        }
        
        return text
    }
    
    private func processMarkdownConversion(_ text: String) -> String {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var modified = false
        
        for (index, line) in lines.enumerated() {
            // Check if line starts with "* " or "- "
            if line.hasPrefix("* ") || line.hasPrefix("- ") {
                // Replace with bullet point
                lines[index] = "• " + line.dropFirst(2)
                modified = true
            }
        }
        
        return modified ? lines.joined(separator: "\n") : text
    }
    
    private func processBulletContinuation(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        guard lines.count >= 2 else { return text }
        
        let previousLine = lines[lines.count - 2] // Line before the new empty line
        let currentLine = lines.last ?? ""
        
        // If previous line starts with bullet and current line is empty, add bullet to current line
        if previousLine.hasPrefix("• ") && currentLine.isEmpty {
            var newLines = lines
            newLines[newLines.count - 1] = "• "
            return newLines.joined(separator: "\n")
        }
        
        return text
    }
    
    private func processBackspaceBulletRemoval(_ text: String, oldValue: String) -> String {
        let newLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let oldLines = oldValue.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        
        // Find which line was modified (text was removed)
        for (index, line) in newLines.enumerated() {
            if index < oldLines.count {
                let oldLine = oldLines[index]
                
                // If we had "• " and now we have just "•" (user backspaced the space after bullet)
                if oldLine.hasPrefix("• ") && line == "•" {
                    var modifiedLines = newLines
                    modifiedLines[index] = "" // Remove the bullet entirely
                    return modifiedLines.joined(separator: "\n")
                }
                
                // If we had "• " and now we have nothing (user backspaced everything)
                if oldLine.hasPrefix("• ") && line.isEmpty && oldLine.count > line.count {
                    // Keep the empty line as-is (normal behavior)
                    return text
                }
            }
        }
        
        return text
    }
    
    // Process arrow replacement: -> becomes →
    private func processArrowReplacement(_ text: String) -> String {
        // Replace all instances of -> with →
        let result = text.replacingOccurrences(of: "->", with: "→")
        return result
    }
    
    // MARK: - Geometry Validation
    
    private func validateGeometry(_ size: CGSize) {
        let isValid = size.width > 0 && size.height > 0 && 
                     size.width.isFinite && size.height.isFinite &&
                     !size.width.isNaN && !size.height.isNaN
        
        print("📏 NoteEditView: Geometry validation - size: \(size), isValid: \(isValid)")
        
        if isValid {
            hasValidGeometry = true
            // Mark content as ready after a brief delay to ensure everything is stable
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isContentReady = true
            }
        }
    }
    
    private func validWidth(from width: CGFloat) -> CGFloat {
        guard width.isFinite && !width.isNaN && width > 0 else {
            print("⚠️ NoteEditView: Invalid width \(width), using fallback")
            return 300 // Fallback width
        }
        return max(200, width - 32)
    }
    
    private func validHeight(from height: CGFloat) -> CGFloat {
        guard height.isFinite && !height.isNaN && height > 0 else {
            print("⚠️ NoteEditView: Invalid height \(height), using fallback")
            return 400 // Fallback height
        }
        return max(120, height * 0.6)
    }
}

// MARK: - Account Drawer View
struct AccountDrawerView: View {
    @Binding var isPresented: Bool
    @State private var showDeleteConfirmation = false
    
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
                Task {
                    do {
                        try await FirebaseManager.shared.deleteAccount()
                    } catch {
                        print("Delete account error: \(error)")
                    }
                }
                isPresented = false
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all your notes. This action cannot be undone.")
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var viewModel = ContentViewModel()
    @State private var editingItem: SparkItem?
    @State private var showingEditView = false
    @State private var showingAccountDrawer = false
    @FocusState private var isInputFieldFocused: Bool
    
    var body: some View {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with Spark title
                HStack {
                    Spacer()
                    
                    Text("Scrap")
                        .font(GentleLightning.Typography.hero)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    Spacer()
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
                                    print("📝 Opening edit view for item: '\(item.content)' with ID: \(item.id)")
                                    AnalyticsManager.shared.trackNoteEditOpened(noteId: item.id)
                                    editingItem = item
                                    showingEditView = true
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
                .gesture(
                    DragGesture()
                        .onEnded { gesture in
                            // Dismiss keyboard when swiping down in scroll area
                            if gesture.translation.height > 50 {
                                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            }
                        }
                )
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
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .padding(.vertical, 16)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(Color.white)
                }
                .background(Color.white)
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
        }
        .background(Color.white)
        .contentShape(Rectangle()) // Make the entire area tappable for keyboard dismissal
        .onTapGesture {
            // Dismiss keyboard when tapping outside input area
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .gesture(
            DragGesture()
                .onEnded { gesture in
                    // Dismiss keyboard when swiping down
                    if gesture.translation.height > 50 {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    }
                }
        )
        .sheet(isPresented: $showingEditView) {
            if let editingItem = editingItem {
                NoteEditView(isPresented: $showingEditView, item: editingItem, dataManager: dataManager)
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
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}