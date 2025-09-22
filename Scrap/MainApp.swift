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
        // Static colors (unchanged for existing code compatibility)
        static let background = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let shadowLight = Color.black.opacity(0.03)
        
        // Dynamic theme-aware colors
        static func background(isDark: Bool) -> Color {
            isDark ? Color(red: 0.1, green: 0.1, blue: 0.1) : Color.white
        }
        
        static func surface(isDark: Bool) -> Color {
            isDark ? Color(red: 0.15, green: 0.15, blue: 0.15) : Color.white
        }
        
        static func textPrimary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.95, green: 0.95, blue: 0.95) : Color(red: 0.12, green: 0.12, blue: 0.15)
        }
        
        static func textSecondary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.7, green: 0.7, blue: 0.75) : Color(red: 0.45, green: 0.45, blue: 0.5)
        }
        
        static func shadow(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.05) : Color.black.opacity(0.03)
        }
        
        static func border(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
        }
        
        static func searchInputBackground(isDark: Bool) -> Color {
            isDark ? Color(red: 0.2, green: 0.2, blue: 0.2) : Color(red: 0.95, green: 0.95, blue: 0.97)
        }
    }
    
    struct Typography {
        // HEADINGS / TITLES → SpaceGrotesk-SemiBold/Bold for emphasis
        static let hero = Font.custom("SpaceGrotesk-Bold", size: 34)               // Large hero titles
        static let title = Font.custom("SpaceGrotesk-Medium", size: 20)            // Standard titles/headings
        static let titleEmphasis = Font.custom("SpaceGrotesk-SemiBold", size: 20)  // Emphasized titles
        static let subtitle = Font.custom("SpaceGrotesk-Medium", size: 18)         // Subtitles
        static let heading = Font.custom("SpaceGrotesk-Medium", size: 16)          // Section headings
        
        // BODY TEXT → SpaceGrotesk-Regular (regular reading weight)
        static let body = Font.custom("SpaceGrotesk-Regular", size: 16)            // Primary body text
        static let bodyInput = Font.custom("SpaceGrotesk-Regular", size: 17)       // Input fields
        static let bodyLarge = Font.custom("SpaceGrotesk-Regular", size: 18)       // Larger body text
        
        // SECONDARY / SUBTLE TEXT → SpaceGrotesk-Light
        static let caption = Font.custom("SpaceGrotesk-Light", size: 13)           // Subtle captions
        static let small = Font.custom("SpaceGrotesk-Light", size: 11)             // Small subtle text
        static let secondary = Font.custom("SpaceGrotesk-Light", size: 14)         // Secondary information
        static let metadata = Font.custom("SpaceGrotesk-Light", size: 12)          // Timestamps, metadata
        
        // ITALIC VARIANTS - Space Grotesk doesn't have italics, use regular weights
        static let bodyItalic = Font.custom("SpaceGrotesk-Regular", size: 16)      // No italic variant
        static let titleItalic = Font.custom("SpaceGrotesk-Medium", size: 20)      // No italic variant
        static let secondaryItalic = Font.custom("SpaceGrotesk-Light", size: 14)   // No italic variant
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
    }
    
    struct Animation {
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let elastic = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6)
        static let swoosh = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)
        static let delightful = SwiftUI.Animation.interpolatingSpring(stiffness: 300, damping: 30, initialVelocity: 0)
        static let silky = SwiftUI.Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.35)
        static let bouncy = SwiftUI.Animation.interpolatingSpring(stiffness: 200, damping: 20, initialVelocity: 5)
    }
}

// MARK: - Shared Note Display Component (Design System)
struct NoteDisplayContent: View {
    let title: String
    let content: String
    let isDarkMode: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(GentleLightning.Typography.heading)
                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: isDarkMode))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            Text(content)
                .font(title.isEmpty ? GentleLightning.Typography.body : GentleLightning.Typography.secondary)
                .foregroundColor(title.isEmpty ? GentleLightning.Colors.textPrimary(isDark: isDarkMode) : GentleLightning.Colors.textSecondary(isDark: isDarkMode))
                .lineLimit(title.isEmpty ? nil : 1)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Main App View
struct MainApp: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var navigationPath = NavigationPath()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 20) {
                // Header
                Text("Scrap")
                    .font(.custom("SpaceGrotesk-Bold", size: 48))
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                
                // Input field
                InputField(
                    text: $inputText,
                    voiceRecorder: voiceRecorder,
                    isFocused: $isInputFocused,
                    onSave: { text in
                        // Track new note started with text method
                        AnalyticsManager.shared.trackNewNoteStarted(method: "text")
                        dataManager.createItem(from: text, creationType: "text")
                        inputText = ""
                    },
                    onVoiceNote: { text in
                        // Track new note started with voice method
                        AnalyticsManager.shared.trackNewNoteStarted(method: "voice")
                        dataManager.createItem(from: text, creationType: "voice")
                        inputText = "" // Clear input after creating voice note
                    }
                )
                
                // Notes list
                if dataManager.items.isEmpty {
                    EmptyState()
                } else {
                    ScrollView {
                        NoteList(dataManager: dataManager, navigationPath: $navigationPath)
                            .padding(.horizontal, 16)
                    }
                }
                
                Spacer()
            }
            .gesture(
                DragGesture()
                    .onEnded { value in
                        // Dismiss keyboard when user drags down
                        if value.translation.height > 50 && value.velocity.height > 0 {
                            // Track keyboard dismissal
                            AnalyticsManager.shared.trackKeyboardDismissed(method: "drag")
                            
                            isInputFocused = false
                            print("🔽 MainApp: Dismissed keyboard via pull-down gesture")
                        }
                    }
            )
            .padding(.top, 20)
            .background(GentleLightning.Colors.background)
            .navigationDestination(for: SparkItem.self) { item in
                NoteEditor(item: item, dataManager: dataManager)
            }
        }
    }
}

// MARK: - Empty State
struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No notes yet")
                .font(GentleLightning.Typography.title)
                .foregroundColor(GentleLightning.Colors.textSecondary)
            
            Text("Start by typing a note or recording a voice memo")
                .font(GentleLightning.Typography.secondary)
                .foregroundColor(GentleLightning.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    @ObservedObject var voiceRecorder: VoiceRecorder
    @Binding var isFocused: Bool
    let onSave: (String) -> Void
    let onVoiceNote: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Add a note...", text: $text)
                .font(GentleLightning.Typography.bodyInput)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
                .focused($isFocused)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Track note saved via keyboard submission
                        AnalyticsManager.shared.trackNoteSaved(method: "keyboard", contentLength: text.count)
                        onSave(text)
                    }
                }
                .onChange(of: isFocused) { oldValue, newValue in
                    if newValue {
                        // Track when user starts typing a new note
                        AnalyticsManager.shared.trackEvent("input_field_focused")
                    }
                }
            
            // Voice/Save button
            Button(action: handleButtonTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(buttonColor)
                        .frame(width: buttonWidth, height: 44)
                    
                    if voiceRecorder.isRecording {
                        HStack(spacing: 6) {
                            AnimatedWaveform()
                            Text("REC")
                                .font(GentleLightning.Typography.small)
                                .foregroundColor(.white)
                        }
                    } else if hasText {
                        Text("SAVE")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 18))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: voiceRecorder.transcribedText) { oldValue, newValue in
            if voiceRecorder.isRecording && !newValue.isEmpty {
                // Update text field in real-time during recording
                print("🎤 Live transcription update: '\(newValue)' (was: '\(oldValue)')")
                print("🎤 Current text field value: '\(text)'")
                print("🎤 TextField is focused: \(isFocused)")
                
                // Update text immediately without unfocusing
                text = newValue
            }
        }
        .onChange(of: voiceRecorder.isRecording) { oldValue, newValue in
            if oldValue == true && newValue == false && !voiceRecorder.transcribedText.isEmpty {
                // Recording just stopped and we have text
                print("🎤 Voice recording stopped, creating note: '\(voiceRecorder.transcribedText)'")
                let transcribedText = voiceRecorder.transcribedText
                voiceRecorder.transcribedText = "" // Clear immediately
                text = "" // Clear text field
                onVoiceNote(transcribedText)
            }
        }
    }
    
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var buttonWidth: CGFloat {
        hasText && !voiceRecorder.isRecording ? 80 : 44
    }
    
    private var buttonColor: Color {
        voiceRecorder.isRecording ? Color.red : GentleLightning.Colors.accentNeutral
    }
    
    private func handleButtonTap() {
        if hasText && !voiceRecorder.isRecording {
            // Track note saved via button tap
            AnalyticsManager.shared.trackNoteSaved(method: "button", contentLength: text.count)
            onSave(text)
        } else {
            // Track voice recording toggle
            if !voiceRecorder.isRecording {
                AnalyticsManager.shared.trackVoiceRecordingStarted()
                // Clear text field but keep it focused so user can see transcription
                text = ""
                isFocused = true  // Keep focused to show real-time transcription
                print("🎤 Starting voice recording - cleared text field and kept focused for transcription")
            }
            voiceRecorder.toggleRecording()
        }
    }
}

// MARK: - Simple Firebase Data Manager
class FirebaseDataManager: ObservableObject {
    @Published var items: [SparkItem] = []
    @Published var isLoading = false
    @Published var categories: [Category] = []
    @Published var selectedCategoryFilter: String? = nil
    
    let firebaseManager = FirebaseManager.shared
    
    init() {
        startListening()
        loadCategories()
    }
    
    func createItem(from text: String, creationType: String = "text") {
        // Create RTF document from the start
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // Convert to RTF data using trait preservation
        var rtfData: Data? = nil
        do {
            let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedText)
            rtfData = try rtfCompatibleString.data(
                from: NSRange(location: 0, length: rtfCompatibleString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("✅ Created RTF data for voice note: \(rtfData?.count ?? 0) bytes")
        } catch {
            print("❌ Failed to create RTF data: \(error)")
        }
        
        let newItem = SparkItem(content: text, isTask: false)
        newItem.rtfData = rtfData
        
        items.insert(newItem, at: 0)
        
        Task {
            do {
                // Generate title
                var title: String? = nil
                do {
                    title = try await OpenAIService.shared.generateTitle(for: text)
                } catch {
                    print("Title generation failed: \(error)")
                }
                
                // Create note with RTF content from the start
                let firebaseId = try await firebaseManager.createNote(
                    content: text,
                    title: title,
                    categoryIds: [],
                    isTask: false,
                    categories: [],
                    creationType: creationType,
                    rtfData: rtfData
                )
                
                await MainActor.run {
                    newItem.firebaseId = firebaseId
                    newItem.title = title ?? ""
                    print("✅ DataManager: Successfully synced note to Firebase with ID: \(firebaseId)")
                }
            } catch {
                await MainActor.run {
                    // Even if Firebase sync fails, keep the note locally with the generated title
                    if let title = title {
                        newItem.title = title
                    }
                    print("⚠️ DataManager: Firebase sync failed but note preserved locally: \(error)")
                }
            }
        }
    }
    
    func createItemFromAttributedText(_ attributedText: NSAttributedString, creationType: String = "rich_text") {
        print("📝 Creating item from NSAttributedString with \(attributedText.length) characters")
        
        // Convert attributed text to RTF data for storage using proper trait preservation
        var rtfData: Data? = nil
        do {
            // Convert custom fonts to system fonts before RTF generation to preserve traits
            let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedText)
            rtfData = try rtfCompatibleString.data(
                from: NSRange(location: 0, length: rtfCompatibleString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("✅ Successfully created RTF data (\(rtfData?.count ?? 0) bytes) with trait preservation")
        } catch {
            print("❌ Failed to create RTF data: \(error)")
        }
        
        // Extract plain text for display and search
        let plainText = attributedText.string
        
        // Create new item with plain text content and RTF data
        let newItem = SparkItem(content: plainText, isTask: false)
        newItem.rtfData = rtfData
        
        items.insert(newItem, at: 0)
        
        Task {
            do {
                // Generate title from plain text
                var title: String? = nil
                do {
                    title = try await OpenAIService.shared.generateTitle(for: plainText)
                    print("📝 Generated title: '\(title ?? "nil")'")
                } catch {
                    print("Title generation failed: \(error)")
                }
                
                // Create note with RTF content
                let firebaseId = try await firebaseManager.createNote(
                    content: plainText,
                    title: title,
                    categoryIds: [],
                    isTask: false,
                    categories: [],
                    creationType: creationType,
                    rtfData: rtfData
                )
                
                await MainActor.run {
                    newItem.firebaseId = firebaseId
                    newItem.title = title ?? ""
                }
                
                print("✅ Successfully saved formatted note to Firebase")
            } catch {
                await MainActor.run {
                    // Even if Firebase sync fails, keep the note locally with the generated title
                    if let title = title {
                        newItem.title = title
                    }
                }
                print("⚠️ DataManager: Firebase sync failed but formatted note preserved locally: \(error)")
            }
        }
    }
    
    func updateItem(_ item: SparkItem, newContent: String) {
        item.content = newContent
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.updateNote(noteId: firebaseId, newContent: newContent)
            }
        }
    }
    
    func updateItemWithRTF(_ item: SparkItem, rtfData: Data) {
        // Store RTF data in the item for persistence
        item.rtfData = rtfData
        
        // Always extract plain text from RTF for local display/search to prevent showing raw RTF
        do {
            let attributedString = try NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            let plainText = attributedString.string
            item.content = plainText
        } catch {
            print("❌ Failed to extract plain text from RTF: \(error)")
            // Don't update content if RTF extraction fails to preserve existing content
        }
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.updateNoteWithRTF(noteId: firebaseId, rtfData: rtfData)
            }
        }
    }
    
    func deleteItem(_ item: SparkItem) {
        items.removeAll { $0.id == item.id }
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.deleteNote(noteId: firebaseId)
            }
        }
    }
    
    private func startListening() {
        firebaseManager.startListening { [weak self] firebaseNotes in
            guard let self = self else { return }
            
            // Convert Firebase notes to SparkItems
            let firebaseSparkItems = firebaseNotes.map(SparkItem.init)
            
            // Merge with existing local items that haven't been synced yet
            var allItems = firebaseSparkItems
            
            // Add any local items that don't have Firebase IDs (haven't been synced yet)
            for localItem in self.items {
                if localItem.firebaseId == nil {
                    // This is a local-only item that hasn't been synced to Firebase yet
                    allItems.insert(localItem, at: 0) // Add at beginning since it's newest
                    print("📱 DataManager: Preserving local item: '\(localItem.displayTitle)'")
                }
            }
            
            // Sort by creation date to maintain proper order
            allItems.sort { $0.createdAt > $1.createdAt }
            
            self.items = allItems
            
            // Index existing notes for vector search
            Task {
                do {
                    // Test connection first
                    let isConnected = try await VectorSearchService.shared.testConnection()
                    if isConnected {
                        await VectorSearchService.shared.reindexAllNotes(firebaseNotes)
                    } else {
                        print("⚠️ ChromaDB connection failed, vector search will not be available")
                    }
                } catch {
                    print("⚠️ Failed to test ChromaDB connection or index notes: \(error)")
                }
            }
        }
    }
    
    // MARK: - Category Management
    
    func loadCategories() {
        Task {
            do {
                let loadedCategories = try await CategoryService.shared.getUserCategories()
                await MainActor.run {
                    self.categories = loadedCategories
                }
            } catch {
                print("⚠️ Failed to load categories: \(error)")
            }
        }
    }
    
    func setSelectedCategoryFilter(_ categoryId: String?) {
        selectedCategoryFilter = categoryId
    }
    
    func clearCategoryFilter() {
        selectedCategoryFilter = nil
    }
    
    // MARK: - Filtering
    
    var filteredItems: [SparkItem] {
        guard let selectedCategory = selectedCategoryFilter else {
            return items // No filter applied
        }
        
        return items.filter { item in
            item.categoryIds.contains(selectedCategory)
        }
    }
    
}

// MARK: - Animated Waveform Component
struct AnimatedWaveform: View {
    @State private var animationPhase: Double = 0
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white)
                    .frame(width: 2, height: waveHeight(for: index))
                    .animation(
                        Animation.easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animationPhase
                    )
            }
        }
        .frame(width: 16, height: 12)
        .onAppear {
            animationPhase = 1.0
        }
        .onDisappear {
            animationPhase = 0.0
        }
    }
    
    private func waveHeight(for index: Int) -> CGFloat {
        let baseHeight: CGFloat = 3
        let maxHeight: CGFloat = 12
        let animationOffset = sin(animationPhase * .pi * 2 + Double(index) * 0.5) * 0.5 + 0.5
        return baseHeight + (maxHeight - baseHeight) * animationOffset
    }
}