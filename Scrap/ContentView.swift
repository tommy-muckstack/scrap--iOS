import SwiftUI
import WidgetKit
import Foundation
import Combine
import NaturalLanguage
import UIKit
import Speech
import AVFoundation
import FirebaseAuth

// MARK: - Search Result Model (Shared)
struct SearchResult: Identifiable {
    let id = UUID()
    let firebaseId: String
    let content: String
    let similarity: Double
    let isTask: Bool
    let categories: [String]
    let createdAt: Date
    
    var confidencePercentage: Int {
        Int(similarity * 100)
    }
    
    var previewContent: String {
        String(content.prefix(150)) + (content.count > 150 ? "..." : "")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let applyFormatting = Notification.Name("applyFormatting")
    static let applyTextFormatting = Notification.Name("applyTextFormatting")
    static let applyBlockFormatting = Notification.Name("applyBlockFormatting")
    static let performUndo = Notification.Name("performUndo")
    static let performRedo = Notification.Name("performRedo")
    static let updateUndoRedoState = Notification.Name("updateUndoRedoState")
    static let updateToolbarState = Notification.Name("updateToolbarState")
}

// MARK: - Formatting Enums
enum TextFormat {
    case bold, italic, underline, strikethrough
    
    var description: String {
        switch self {
        case .bold: return "Bold"
        case .italic: return "Italic"
        case .underline: return "Underline"
        case .strikethrough: return "Strikethrough"
        }
    }
}

enum BlockFormat {
    case bulletList, checkbox
    
    var description: String {
        switch self {
        case .bulletList: return "Bullet List"
        case .checkbox: return "Checkbox"
        }
    }
}

// MARK: - Formatting State Management
struct FormattingState {
    var activeTextFormats: Set<TextFormat> = []
    var activeBlockFormat: BlockFormat? = nil
    
    // Computed properties for individual format checks
    var isBoldActive: Bool {
        get { activeTextFormats.contains(.bold) }
        set { 
            if newValue {
                activeTextFormats.insert(.bold)
            } else {
                activeTextFormats.remove(.bold)
            }
        }
    }
    
    var isItalicActive: Bool {
        get { activeTextFormats.contains(.italic) }
        set { 
            if newValue {
                activeTextFormats.insert(.italic)
            } else {
                activeTextFormats.remove(.italic)
            }
        }
    }
    
    var isUnderlineActive: Bool {
        get { activeTextFormats.contains(.underline) }
        set { 
            if newValue {
                activeTextFormats.insert(.underline)
            } else {
                activeTextFormats.remove(.underline)
            }
        }
    }
    
    var isStrikethroughActive: Bool {
        get { activeTextFormats.contains(.strikethrough) }
        set { 
            if newValue {
                activeTextFormats.insert(.strikethrough)
            } else {
                activeTextFormats.remove(.strikethrough)
            }
        }
    }
    
    var isListModeActive: Bool {
        get { activeBlockFormat == .bulletList }
        set { 
            if newValue {
                activeBlockFormat = .bulletList
            } else if activeBlockFormat == .bulletList {
                activeBlockFormat = nil
            }
        }
    }
    
    var isCheckboxModeActive: Bool {
        get { activeBlockFormat == .checkbox }
        set { 
            if newValue {
                activeBlockFormat = .checkbox
            } else if activeBlockFormat == .checkbox {
                activeBlockFormat = nil
            }
        }
    }
    
    // Computed properties for bullet and check list
    var isBulletListActive: Bool {
        activeBlockFormat == .bulletList
    }
    
    var isCheckListActive: Bool {
        activeBlockFormat == .checkbox
    }
    
    // Utility methods
    mutating func toggleTextFormat(_ format: TextFormat) {
        if activeTextFormats.contains(format) {
            activeTextFormats.remove(format)
            print("🎨 FormattingState: Removed \(format) format. Active formats: \(activeFormatsDescription)")
        } else {
            activeTextFormats.insert(format)
            print("🎨 FormattingState: Added \(format) format. Active formats: \(activeFormatsDescription)")
        }
    }
    
    mutating func setBlockFormat(_ format: BlockFormat?) {
        let oldFormat = activeBlockFormat
        activeBlockFormat = format
        print("🎨 FormattingState: Block format changed from \(oldFormat?.description ?? "none") to \(format?.description ?? "none")")
    }
    
    mutating func toggleBlockFormat(_ format: BlockFormat) {
        if activeBlockFormat == format {
            activeBlockFormat = nil
            print("🎨 FormattingState: Toggled off \(format.description)")
        } else {
            activeBlockFormat = format
            print("🎨 FormattingState: Toggled on \(format.description)")
        }
    }
    
    mutating func clearAllFormatting() {
        activeTextFormats.removeAll()
        activeBlockFormat = nil
        print("🎨 FormattingState: Cleared all formatting")
    }
    
    // Additional utility methods
    func hasAnyTextFormatting() -> Bool {
        return !activeTextFormats.isEmpty
    }
    
    func hasBlockFormatting() -> Bool {
        return activeBlockFormat != nil
    }
    
    func hasAnyFormatting() -> Bool {
        return hasAnyTextFormatting() || hasBlockFormatting()
    }
    
    // Sync formatting state from text attributes (useful when cursor moves)
    mutating func syncFromTextAttributes(bold: Bool, italic: Bool, underline: Bool, strikethrough: Bool) {
        activeTextFormats.removeAll()
        if bold { activeTextFormats.insert(.bold) }
        if italic { activeTextFormats.insert(.italic) }
        if underline { activeTextFormats.insert(.underline) }
        if strikethrough { activeTextFormats.insert(.strikethrough) }
    }
    
    // Get all active formats as a readable description
    var activeFormatsDescription: String {
        var formats: [String] = []
        if isBoldActive { formats.append("Bold") }
        if isItalicActive { formats.append("Italic") }
        if isUnderlineActive { formats.append("Underline") }
        if isStrikethroughActive { formats.append("Strikethrough") }
        if isListModeActive { formats.append("List") }
        if isCheckboxModeActive { formats.append("Checkbox") }
        return formats.isEmpty ? "None" : formats.joined(separator: ", ")
    }
}

// MARK: - Widget Helper Functions
func updateWidgetData(noteCount: Int) {
    // Use App Group to share data with widget extension
    if let sharedDefaults = UserDefaults(suiteName: "group.scrap.app") {
        sharedDefaults.set(noteCount, forKey: "ScrapNoteCount")
    }
    // Also update standard UserDefaults as fallback
    UserDefaults.standard.set(noteCount, forKey: "ScrapNoteCount")
    WidgetCenter.shared.reloadAllTimelines()
}

// MARK: - Gentle Lightning Design System
struct GentleLightning {
    struct Colors {
        // MARK: - Theme-Aware Colors
        static func background(isDark: Bool) -> Color {
            isDark ? Color.black : Color.white
        }
        
        static func backgroundWarm(isDark: Bool) -> Color {
            isDark ? Color.black : Color.white
        }
        
        static func surface(isDark: Bool) -> Color {
            isDark ? Color.black : Color.white
        }
        
        static func surfaceSecondary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.05, green: 0.05, blue: 0.05) : Color(red: 0.98, green: 0.98, blue: 0.99)
        }
        
        static func textPrimary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.224, green: 1.0, blue: 0.078) : Color(red: 0.12, green: 0.12, blue: 0.15) // #39FF14 for dark mode
        }
        
        static func textSecondary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.224, green: 1.0, blue: 0.078).opacity(0.7) : Color(red: 0.45, green: 0.45, blue: 0.5) // Dimmed neon green
        }
        
        static func textTertiary(isDark: Bool) -> Color {
            isDark ? Color(red: 0.224, green: 1.0, blue: 0.078).opacity(0.5) : Color(red: 0.60, green: 0.60, blue: 0.65) // More dimmed neon green
        }
        
        static func border(isDark: Bool) -> Color {
            isDark ? Color(red: 0.224, green: 1.0, blue: 0.078).opacity(0.3) : Color(red: 0.90, green: 0.90, blue: 0.92) // Subtle neon green border
        }
        
        static func shadow(isDark: Bool) -> Color {
            isDark ? Color(red: 0.224, green: 1.0, blue: 0.078).opacity(0.1) : Color.black.opacity(0.03) // Subtle neon glow
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
        // HEADINGS / TITLES → SpaceGrotesk-SemiBold/Bold for emphasis
        static let hero = Font.custom("SpaceGrotesk-Bold", size: 34)               // Large hero titles
        static let title = Font.custom("SpaceGrotesk-Medium", size: 20)            // Standard titles/headings
        static let titleEmphasis = Font.custom("SpaceGrotesk-SemiBold", size: 20)  // Emphasized titles
        static let subtitle = Font.custom("SpaceGrotesk-Medium", size: 18)         // Subtitles
        static let heading = Font.custom("SpaceGrotesk-Medium", size: 16)          // Section headings
        
        // BODY TEXT → SpaceGrotesk-Regular (regular reading weight)
        static let body = Font.custom("SpaceGrotesk-Regular", size: 16)            // Primary body text
        static let bodyInput = Font.custom("SpaceGrotesk-Regular", size: 19)       // Input fields
        static let bodyLarge = Font.custom("SpaceGrotesk-Regular", size: 18)       // Larger body text
        
        // SECONDARY / SUBTLE TEXT → SpaceGrotesk-Light
        static let caption = Font.custom("SpaceGrotesk-Light", size: 13)           // Subtle captions
        static let small = Font.custom("SpaceGrotesk-Light", size: 11)             // Small subtle text
        static let secondary = Font.custom("SpaceGrotesk-Light", size: 14)         // Secondary information
        static let metadata = Font.custom("SpaceGrotesk-Light", size: 12)          // Timestamps, metadata
        
        // LEGACY / SPECIAL USE
        static let ultraLight = Font.custom("SpaceGrotesk-Light", size: 14)        // Ultra-light accent (no Thin variant)
        static let medium = Font.custom("SpaceGrotesk-Medium", size: 16)           // Medium weight utility
        
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
    
    // MARK: - Components
    struct Components {
        static func customCheckbox(isChecked: Bool, isDark: Bool = false) -> some View {
            ZStack {
                // Outer circle (always black outline)
                Circle()
                    .strokeBorder(Color.black, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.clear))
                
                // Checkmark (only when checked)
                if isChecked {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Colors.success) // Green checkmark
                }
            }
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
                // Update widget with new note count
                updateWidgetData(noteCount: sparkItems.count)
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
                
                // Track note creation with type
                let noteType = creationType == "voice" ? "voice" : "text"
                AnalyticsManager.shared.trackItemCreated(isTask: false, contentLength: text.count, creationType: noteType)
                
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
                    
                    // Update widget with new count
                    updateWidgetData(noteCount: self.items.count)
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
    
    func createItemFromAttributedText(_ attributedText: NSAttributedString, creationType: String = "rich_text") {
        print("📝 Creating item from NSAttributedString with \(attributedText.length) characters")
        
        // Convert attributed text to RTF data for storage
        let rtfData: Data? = {
            do {
                let data = try attributedText.data(
                    from: NSRange(location: 0, length: attributedText.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                print("✅ Successfully created RTF data (\(data.count) bytes)")
                return data
            } catch {
                print("❌ Failed to create RTF data: \(error)")
                return nil
            }
        }()
        
        // Extract plain text for display and search
        let plainText = attributedText.string
        
        // Save to Firebase with AI-generated title first, then add to list
        Task {
            do {
                print("📋 DataManager: Starting to save formatted note: '\(plainText)' type: '\(creationType)'")
                
                // Generate title using OpenAI
                var generatedTitle: String? = nil
                do {
                    generatedTitle = try await OpenAIService.shared.generateTitle(for: plainText)
                    print("🤖 DataManager: Generated title: '\(generatedTitle!)'")
                } catch {
                    print("⚠️ DataManager: Title generation failed: \(error), proceeding without title")
                }
                
                // Get legacy categories for backward compatibility
                let legacyCategories = await categorizeText(plainText)
                print("🏷️ DataManager: Categorized text with legacy categories: \(legacyCategories)")
                
                // TODO: Add category suggestion and selection logic here
                let categoryIds: [String] = [] // Will be populated when categories are implemented
                
                let finalTitle = generatedTitle
                let firebaseId = try await firebaseManager.createNote(
                    content: plainText,
                    title: finalTitle,
                    categoryIds: categoryIds,
                    isTask: false, 
                    categories: legacyCategories,
                    creationType: creationType,
                    rtfData: rtfData
                )
                
                print("✅ DataManager: Formatted note saved successfully with Firebase ID: \(firebaseId)")
                
                // Track note creation with type
                AnalyticsManager.shared.trackItemCreated(isTask: false, contentLength: plainText.count, creationType: creationType)
                
                // Now create the item with the title and add to list
                await MainActor.run {
                    let newItem = SparkItem(content: plainText, isTask: false)
                    newItem.firebaseId = firebaseId
                    newItem.rtfData = rtfData
                    if let title = finalTitle {
                        newItem.title = title
                    }
                    
                    withAnimation(GentleLightning.Animation.elastic) {
                        self.items.insert(newItem, at: 0)
                    }
                    print("📲 DataManager: Added formatted item to list with title: '\(newItem.title)'")
                    
                    // Update widget with new count
                    updateWidgetData(noteCount: self.items.count)
                }
                
                // TODO: Save to Pinecone for vector search
                
            } catch {
                print("💥 DataManager: Failed to save formatted note: \(error)")
                await MainActor.run {
                    self.error = "Failed to save note: \(error.localizedDescription)"
                    print("🗑️ DataManager: Formatted note creation failed")
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
    
    func updateItemWithRTF(_ item: SparkItem, rtfData: Data) {
        // Extract plain text from RTF for local display/search
        do {
            let attributedString = try NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            item.content = attributedString.string
        } catch {
            print("❌ Failed to extract plain text from RTF: \(error)")
        }
        
        // Update Firebase with RTF data
        if let firebaseId = item.firebaseId {
            Task {
                do {
                    try await firebaseManager.updateNoteWithRTF(noteId: firebaseId, rtfData: rtfData)
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
        
        // Update widget with new count
        updateWidgetData(noteCount: items.count)
        
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
    @Published var placeholderText = "Just type or speak..."
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    let placeholder: String
    let dataManager: FirebaseDataManager
    let onCommit: () -> Void
    var isFieldFocused: FocusState<Bool>.Binding
    
    // Rich text state management
    @State private var attributedText = NSAttributedString()
    @StateObject private var richTextContext = RichTextContext()
    
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
        !attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    // Dynamic height for text input
    @State private var textHeight: CGFloat = 40
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Rich Text Editor
                    ZStack(alignment: .topLeading) {
                        // Placeholder text
                        if attributedText.string.isEmpty {
                            Text(placeholder)
                                .font(GentleLightning.Typography.bodyInput)
                                .foregroundColor(GentleLightning.Colors.textSecondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        RichTextEditor.forNotes(
                            text: $attributedText,
                            context: richTextContext
                        )
                        .disabled(isRecording)
                        .frame(minHeight: 40, maxHeight: max(40, min(textHeight, 120)), alignment: .topLeading)
                        .focused(isFieldFocused)
                        .onChange(of: attributedText) { newValue in
                            // Update plain text binding for compatibility
                            let newPlainText = newValue.string
                            if text != newPlainText {
                                text = newPlainText
                            }
                            
                            // Track when user starts typing
                            if newPlainText.count == 1 && attributedText.string.count <= 1 {
                                AnalyticsManager.shared.trackNewNoteStarted(method: "text")
                            }
                            
                            // Calculate dynamic height based on content
                            updateTextHeight(for: newPlainText)
                        }
                    }
                    
                    // Note: Formatting toolbar removed from main input field
                    // It should only appear in the dedicated note editor
                }
                .onAppear {
                    // Initialize attributed text from plain text
                    if !text.isEmpty && attributedText.string.isEmpty {
                        attributedText = NSAttributedString(string: text)
                    }
                    
                    // Check current authorization status
                    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
                    
                    // Focus the field if it should be focused
                    if isFieldFocused.wrappedValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            richTextContext.isEditingText = true
                        }
                    }
                }
                .onChange(of: isFieldFocused.wrappedValue) { isFocused in
                    // Sync external focus state with rich text context
                    richTextContext.isEditingText = isFocused
                }
                .onChange(of: richTextContext.isEditingText) { isEditing in
                    // Sync rich text context back to external focus state
                    if isFieldFocused.wrappedValue != isEditing {
                        isFieldFocused.wrappedValue = isEditing
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Refresh authorization status when app becomes active (user returning from Settings)
                    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
                }
                
                // Microphone/Save button - transforms based on recording state and text content
                Button(action: {
                    if isRecording {
                        // Stop recording
                        handleVoiceRecording()
                    } else if hasText {
                        // Save the note (only when not recording)
                        if !attributedText.string.isEmpty {
                            AnalyticsManager.shared.trackNoteSaved(method: "button", contentLength: attributedText.string.count)
                            
                            // Create new item with rich text formatting
                            dataManager.createItemFromAttributedText(attributedText, creationType: "rich_text")
                            
                            // Clear both text fields
                            text = ""
                            attributedText = NSAttributedString()
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
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                // Title - use content as title if no title exists
                Text(item.title.isEmpty ? item.content : item.title)
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Preview text - only show if title exists
                if !item.title.isEmpty && !item.content.isEmpty {
                    Text(item.content)
                        .font(GentleLightning.Typography.secondary)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.vertical, 12) // Reduced vertical padding
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
    
    // Computed property to break up complex expression
    private var textEditorBinding: Binding<String> {
        Binding(
            get: {
                print("📖 TextEditor binding GET: returning '\(editedText.prefix(30))...' (length: \(editedText.count))")
                return editedText
            },
            set: { newValue in
                print("✏️  TextEditor binding SET: received '\(newValue.prefix(30))...' (length: \(newValue.count))")
                editedText = newValue
            }
        )
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isContentReady {
                    // Simplified Text Editor without ScrollView wrapper
                    TextEditor(text: textEditorBinding)
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
                        .font(.system(size: 14))
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
    @StateObject private var themeManager = ThemeManager.shared
    
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
            
            ScrollView {
                VStack(spacing: 24) {
                    // Settings Section (from SettingsView)
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("My Account")
                                .font(GentleLightning.Typography.heading)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            Spacer()
                        }
                        
                        // Dark Mode Toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Dark Mode")
                                    .font(GentleLightning.Typography.body)
                                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            }
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { themeManager.isDarkMode },
                                set: { _ in themeManager.toggleDarkMode() }
                            ))
                            .tint(GentleLightning.Colors.accentNeutral)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                                .shadow(
                                    color: GentleLightning.Colors.shadow(isDark: themeManager.isDarkMode),
                                    radius: 8,
                                    x: 0,
                                    y: 2
                                )
                        )
                    }
                    
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
                            .font(.custom("SharpGrotesk-Bold-Regular", size: 24))
                            .foregroundColor(GentleLightning.Colors.textBlack)
                        
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .padding(.bottom, 40)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
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

// MARK: - Note Edit View Wrapper (Prevents Multiple Inits)
struct NoteEditViewWrapper: View {
    let item: SparkItem
    let dataManager: FirebaseDataManager
    
    var body: some View {
        NavigationNoteEditView(item: item, dataManager: dataManager)
            .id(item.id) // Use stable ID to prevent unnecessary reinitializations
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var viewModel = ContentViewModel()
    @StateObject private var themeManager = ThemeManager.shared
    @StateObject private var richTextContext = RichTextContext()
    @State private var attributedText = NSAttributedString()
    @State private var navigationPath = NavigationPath()
    @State private var showingAccountDrawer = false
    @FocusState private var isInputFieldFocused: Bool
    
    // Search functionality
    @State private var isSearchExpanded = false
    @State private var searchText = ""
    @State private var searchResults: [SearchResult] = []
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var hasSearched = false
    @State private var isSearching = false
    @FocusState private var isSearchFieldFocused: Bool
    
    // Pagination
    @State private var displayedItemsCount = 10
    private let itemsPerPage = 10
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
        ZStack {
            // Main content
            VStack(spacing: 0) {
                // Header with Spark title and settings
                HStack {
                    Spacer()
                    
                    Text("Scrap")
                        .font(.custom("SharpGrotesk-Bold-Regular", size: 48))
                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                    
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
                },
                          isFieldFocused: $isInputFieldFocused)
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                
                // Only show My Notes header and search when there are notes to display
                if !dataManager.items.isEmpty {
                    // Smaller spacer below
                    Spacer()
                        .frame(maxHeight: 20)
                    
                    // My Notes header with search functionality overlay
                    ZStack {
                        // Base content: My Notes text and horizontal line
                        HStack {
                            Text("My Notes")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .padding(.leading, GentleLightning.Layout.Padding.xl + GentleLightning.Layout.Padding.lg)
                            
                            Spacer()
                        }
                        .opacity(isSearchExpanded ? 0 : 1) // Hide when search is expanded
                        .animation(GentleLightning.Animation.swoosh, value: isSearchExpanded)
                        
                        // Overlay: Search bar
                        HStack {
                            if isSearchExpanded {
                                Spacer()
                                    .frame(width: 36) // Match the trailing padding when expanded
                            } else {
                                Spacer()
                            }
                            SearchBarView(
                                isExpanded: $isSearchExpanded,
                                searchText: $searchText,
                                searchResults: $searchResults,
                                isSearching: $isSearching,
                                searchTask: $searchTask,
                                hasSearched: $hasSearched,
                                isSearchFieldFocused: $isSearchFieldFocused,
                                onResultTap: { result in
                                    // Find the matching item in dataManager.items and navigate to it
                                    if let item = dataManager.items.first(where: { $0.id == result.firebaseId }) {
                                        navigationPath.append(item)
                                        // Collapse search after navigation
                                        withAnimation {
                                            isSearchExpanded = false
                                            searchText = ""
                                            searchResults = []
                                            hasSearched = false
                                            searchTask?.cancel()
                                            searchTask = nil
                                        }
                                    }
                                },
                                onSearch: performSearch,
                                onReindex: triggerReindexing
                            )
                            .padding(.trailing, 36) // 20pt (outer) + 16pt (inner) to match microphone button center
                        }
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                }
                
                // Items List - scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if dataManager.items.isEmpty {
                            EmptyStateView()
                                .padding(.top, 20)
                        } else if searchResults.isEmpty {
                            // Only show notes list when not displaying search results
                            let itemsToDisplay = Array(dataManager.items.prefix(displayedItemsCount))
                            
                            ForEach(itemsToDisplay) { item in
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
                                .onAppear {
                                    // Load more items when reaching the last item
                                    if item.id == itemsToDisplay.last?.id && displayedItemsCount < dataManager.items.count {
                                        loadMoreItems()
                                    }
                                }
                            }
                            
                            // Loading indicator
                            if displayedItemsCount < dataManager.items.count {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                        .scaleEffect(0.8)
                                    Spacer()
                                }
                                .padding(.vertical, 20)
                                .onAppear {
                                    loadMoreItems()
                                }
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
                        Text("...")
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
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
            NoteEditViewWrapper(item: item, dataManager: dataManager)
                .onAppear {
                    print("✅ Navigation NoteEditView: Successfully opened note with id = '\(item.id)'")
                    print("✅ Navigation NoteEditView: Note content = '\(item.content)' (length: \(item.content.count))")
                }
        }
        .sheet(isPresented: $showingAccountDrawer) {
            AccountDrawerView(isPresented: $showingAccountDrawer)
                .presentationDetents([.fraction(0.6), .large])
                .presentationDragIndicator(.hidden)
                .onDisappear {
                    AnalyticsManager.shared.trackAccountDrawerClosed()
                }
        }
        } // NavigationStack
        .onAppear {
            // Initialize widget with current note count when app starts
            updateWidgetData(noteCount: dataManager.items.count)
            
            // Auto-focus the input field when the app loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFieldFocused = true
                print("🎯 ContentView: Auto-focused input field on app load - setting focus to true")
                
                // Add additional debugging
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    print("🎯 ContentView: Checking focus state after delay - isInputFieldFocused: \(isInputFieldFocused)")
                }
            }
            
            // Auto-index notes for search when app loads
            Task {
                // Wait a moment for the data to load
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Only index if we have notes and user is authenticated
                guard !dataManager.items.isEmpty,
                      Auth.auth().currentUser != nil else {
                    print("🔍 ContentView: Skipping auto-indexing - no items or not authenticated")
                    return
                }
                
                print("🔍 ContentView: Starting auto-indexing of \(dataManager.items.count) notes...")
                triggerReindexing()
            }
        }
        .onChange(of: dataManager.items.count) { _ in
            // Reset pagination when items change (new item added or deleted)
            displayedItemsCount = min(10, dataManager.items.count)
        }
    }
    
    private func loadMoreItems() {
        // Add a small delay to simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                displayedItemsCount = min(displayedItemsCount + itemsPerPage, dataManager.items.count)
            }
        }
    }
    
    private func performSearch() {
        guard !self.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            self.searchResults = []
            self.hasSearched = false
            return
        }
        
        self.isSearching = true
        
        Task { @MainActor in
            do {
                let results = try await VectorSearchService.shared.semanticSearch(
                    query: self.searchText,
                    limit: 10
                )
                
                self.searchResults = results
                self.hasSearched = true
                self.isSearching = false
            } catch {
                print("Search failed: \(error)")
                self.hasSearched = true
                self.isSearching = false
                // Could show error state here
            }
        }
    }
    
    private func triggerReindexing() {
        print("🔄 ContentView: Manual reindexing triggered by long press")
        
        Task {
            // Get all current items and convert to FirebaseNote format for reindexing
            let firebaseNotes = self.dataManager.items.compactMap { item -> FirebaseNote? in
                guard let firebaseId = item.firebaseId else { return nil }
                
                return FirebaseNote(
                    id: firebaseId,
                    userId: Auth.auth().currentUser?.uid ?? "",
                    content: item.content,
                    title: item.title,
                    categoryIds: item.categoryIds,
                    isTask: item.isTask,
                    categories: [], // Legacy field
                    createdAt: item.createdAt,
                    updatedAt: Date(), // Use current date since SparkItem doesn't have updatedAt
                    pineconeId: nil,
                    creationType: "manual_reindex",
                    rtfContent: nil
                )
            }
            
            print("🔄 ContentView: Starting reindex of \(firebaseNotes.count) notes...")
            await VectorSearchService.shared.reindexAllNotes(firebaseNotes)
            print("✅ ContentView: Reindexing completed!")
            
            // Run semantic search debugging test after reindexing
            print("🧪 ContentView: Running semantic search debug test...")
            await VectorSearchService.shared.testSemanticSearchDebug()
            
            // Show success feedback
            await MainActor.run {
                // Could show a toast or alert here
                print("💡 ContentView: Reindexing and debugging finished - check console for results!")
            }
        }
    }
}

// MARK: - Formatting Toolbar View (Extracted Component)
struct FormattingToolbarView: View {
    @ObservedObject var context: RichTextContext
    
    var body: some View {
        VStack(spacing: 0) {
            // Full-width top divider
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            
            // Evenly spaced horizontal layout
            HStack {
                // Core formatting buttons
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleBold()
                    }
                }) {
                    Image(systemName: "bold")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isBoldActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isBoldActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .clipped()
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isBoldActive)
                }
                
                Spacer()
                
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleItalic()
                    }
                }) {
                    Image(systemName: "italic")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isItalicActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isItalicActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isItalicActive)
                }
                
                Spacer()
                
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleStrikethrough()
                    }
                }) {
                    Image(systemName: "strikethrough")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isStrikethroughActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isStrikethroughActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isStrikethroughActive)
                }
                
                Spacer()
                
                // Code block button (moved here between strikethrough and list buttons)
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleCodeBlock()
                    }
                }) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(context.isCodeBlockActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isCodeBlockActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isCodeBlockActive)
                }
                
                Spacer()
                
                // List buttons
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleBulletList()
                    }
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isBulletListActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isBulletListActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isBulletListActive)
                }
                
                Spacer()
                
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0)) {
                        context.toggleCheckbox()
                    }
                }) {
                    Image(systemName: "checklist")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isCheckboxActive ? .white : .black)
                        .frame(width: 32, height: 32)
                        .background(context.isCheckboxActive ? .black : Color.clear)
                        .clipShape(Circle())
                        .animation(.spring(response: 0.2, dampingFraction: 0.7, blendDuration: 0), value: context.isCheckboxActive)
                }
                
                Spacer()
                
                // Keyboard dismiss button
                Button(action: { 
                    context.isEditingText = false
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.black)
                        .frame(width: 32, height: 32)
                        .background(GentleLightning.Colors.accentNeutral.opacity(0.1))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16) // Match content padding for consistency
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .background(Color.white)
    }
}

// MARK: - Conditional SafeAreaInset Modifier

// MARK: - Navigation Note Edit View
struct NavigationNoteEditView: View {
    let item: SparkItem // Change from @ObservedObject to let to prevent unnecessary redraws
    let dataManager: FirebaseDataManager
    @Environment(\.dismiss) private var dismiss
    // @ObservedObject private var categoryService = CategoryService.shared
    
    @State private var editedText: String = ""
    @State private var attributedText: NSAttributedString = NSAttributedString()
    @StateObject private var richTextContext = RichTextContext()
    @FocusState private var isTextFieldFocused: Bool
    @FocusState private var isTitleFocused: Bool
    @State private var showingActionSheet = false
    @State private var showingDeleteAlert = false
    @State private var isContentReady = true
    @State private var selectedCategoryIds: [String] = []
    @State private var editedTitle: String = ""
    @State private var showingFormattingSheet = false
    @State private var keyboardHeight: CGFloat = 0
    
    // Consolidated formatting state
    @State private var formattingState = FormattingState()
    @State private var isRichTextFocused = false
    @State private var isBodyTextFocused = false
    @State private var canUndo = false
    @State private var canRedo = false
    @State private var isUpdatingText = false
    @State private var isSavingContent = false
    @State private var saveTimer: Timer?
    
    init(item: SparkItem, dataManager: FirebaseDataManager) {
        print("🏗️ NavigationNoteEditView init: STARTING - item.id = '\(item.id)'")
        
        self.item = item
        self.dataManager = dataManager
        
        // RTF is our primary format - always work with NSAttributedString
        let initialAttributedText: NSAttributedString
        if let rtfData = item.rtfData {
            print("📖 Loading RTF formatting data (\(rtfData.count) bytes)")
            initialAttributedText = NavigationNoteEditView.dataToAttributedString(rtfData)
            print("📖 Loaded formatted text: '\(initialAttributedText.string.prefix(50))...'")
        } else {
            // Create new RTF document with default formatting
            print("📝 Creating new RTF document")
            let initialContent = item.content.isEmpty ? " " : item.content
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "SharpGrotesk-Book", size: 17) ?? UIFont.systemFont(ofSize: 17),
                .foregroundColor: UIColor.black
            ]
            initialAttributedText = NSAttributedString(string: initialContent, attributes: attributes)
        }
        
        // Only store the attributed text - no plain text needed
        self._attributedText = State(initialValue: initialAttributedText)
        self._editedText = State(initialValue: initialAttributedText.string) // Keep for compatibility but don't use
        
        self._selectedCategoryIds = State(initialValue: item.categoryIds)
        self._editedTitle = State(initialValue: item.title)
        
        print("🏗️ NavigationNoteEditView init: COMPLETED - RTF document ready")
    }
    
    // MARK: - NSAttributedString Persistence Methods
    
    // Convert NSAttributedString to NSData for storage
    static func attributedStringToData(_ attributedString: NSAttributedString) -> Data? {
        do {
            let data = try attributedString.data(
                from: NSRange(location: 0, length: attributedString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("💾 Converted NSAttributedString to RTF data: \(data.count) bytes")
            return data
        } catch {
            print("❌ Failed to convert NSAttributedString to data: \(error)")
            return nil
        }
    }
    
    // Convert NSData back to NSAttributedString
    static func dataToAttributedString(_ data: Data) -> NSAttributedString {
        do {
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.rtf,
                .characterEncoding: String.Encoding.utf8.rawValue
            ]
            let attributedString = try NSAttributedString(data: data, options: options, documentAttributes: nil)
            print("📖 Loaded NSAttributedString from RTF data: '\(attributedString.string.prefix(50))...'")
            
            // Debug: Log the attributes of the first character to verify formatting is preserved
            if attributedString.length > 0 {
                let firstCharAttributes = attributedString.attributes(at: 0, effectiveRange: nil)
                if let font = firstCharAttributes[.font] as? UIFont {
                    print("📖 DETAILED RTF LOAD DEBUG:")
                    print("   - Font name: '\(font.fontName)'")
                    print("   - Font size: \(font.pointSize)")
                    print("   - Bold trait: \(font.fontDescriptor.symbolicTraits.contains(.traitBold))")
                    print("   - Font descriptor: \(font.fontDescriptor)")
                    
                    // Check if it's a custom font vs system font
                    if font.fontName.contains("SharpGrotesk") {
                        print("   ✅ Custom SharpGrotesk font preserved")
                    } else {
                        print("   ❌ Font fallback occurred - custom font lost during RTF conversion")
                        print("   - Available SharpGrotesk fonts:")
                        let sharpGroteskFonts = UIFont.familyNames.filter { $0.contains("SharpGrotesk") }
                        for family in sharpGroteskFonts {
                            for fontName in UIFont.fontNames(forFamilyName: family) {
                                print("     * \(fontName)")
                            }
                        }
                    }
                }
                
                // Check all attributes to see what's preserved vs lost
                print("📖 All attributes at first character:")
                for (key, value) in firstCharAttributes {
                    print("   - \(key): \(value)")
                }
            }
            
            // Fix custom font issues after RTF loading
            let restoredAttributedString = restoreCustomFonts(in: attributedString)
            return restoredAttributedString
        } catch {
            print("❌ Failed to convert data to NSAttributedString: \(error)")
            
            // Fallback to plain text with default formatting
            if let plainText = String(data: data, encoding: .utf8) {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: UIFont(name: "SharpGrotesk-Book", size: 17) ?? UIFont.systemFont(ofSize: 17),
                    .foregroundColor: UIColor.black
                ]
                return NSAttributedString(string: plainText, attributes: attributes)
            }
            
            return NSAttributedString(string: " ")
        }
    }
    
    // Restore custom fonts after RTF loading (fixes font fallback issues)
    static func restoreCustomFonts(in attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let range = NSRange(location: 0, length: mutableString.length)
        
        // Enumerate through all font attributes
        mutableString.enumerateAttribute(.font, in: range, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            
            var replacementFont: UIFont? = nil
            
            // Check if this is a system font that should be a custom font
            if !font.fontName.contains("SpaceGrotesk") {
                let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold) || font.fontName.contains("Bold")
                let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic) || font.fontName.contains("Italic")
                
                print("📖 Font restoration: Found system font '\(font.fontName)' - bold: \(isBold), italic: \(isItalic)")
                
                // Map to appropriate Space Grotesk variant
                let targetFontName: String
                if isBold && isItalic {
                    targetFontName = "SpaceGrotesk-Bold" // Space Grotesk doesn't have italic variants, use bold
                } else if isBold {
                    targetFontName = "SpaceGrotesk-Bold"
                } else if isItalic {
                    targetFontName = "SpaceGrotesk-Regular" // No italic variant, use regular
                } else {
                    targetFontName = "SpaceGrotesk-Regular"
                }
                
                replacementFont = UIFont(name: targetFontName, size: font.pointSize)
                
                if let replacementFont = replacementFont {
                    print("📖 ✅ Restored font: '\(font.fontName)' -> '\(replacementFont.fontName)'")
                } else {
                    print("📖 ❌ Failed to restore font: '\(targetFontName)' not available")
                    
                    // Debug: List all available fonts containing "SpaceGrotesk"
                    let availableFonts = UIFont.familyNames.flatMap { familyName in
                        UIFont.fontNames(forFamilyName: familyName)
                    }.filter { $0.contains("SpaceGrotesk") }
                    
                    print("📖 🔍 Available SpaceGrotesk fonts at runtime: \(availableFonts)")
                }
            }
            
            // Apply the replacement font if found
            if let replacementFont = replacementFont {
                mutableString.addAttribute(.font, value: replacementFont, range: range)
            }
        }
        
        print("📖 Font restoration complete")
        return mutableString
    }
    
    // MARK: - Helper Methods
    
    // MARK: - View Components
    private var titleSection: some View {
        TextField("Give me a name", text: $editedTitle, axis: .vertical)
            .font(GentleLightning.Typography.hero)
            .foregroundColor(GentleLightning.Colors.textPrimary)
            .padding(.horizontal, 16)
            .padding(.top, 40)
            .padding(.bottom, 8)
            .lineLimit(1...3)
            .multilineTextAlignment(.leading)
            .focused($isTitleFocused)
            .onChange(of: editedTitle) { newTitle in
                guard !newTitle.isEmpty else { return }
                item.title = newTitle
            }
    }
    
    private var textEditorSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Text editor with placeholder-like styling
            ZStack(alignment: .topLeading) {
                if attributedText.string.isEmpty || attributedText.string == " " {
                    Text("Now write something brilliant")
                        .font(GentleLightning.Typography.bodyLarge)
                        .foregroundColor(Color.gray.opacity(0.5))
                        .padding(.horizontal, 16)
                        .padding(.top, 5)
                        .allowsHitTesting(false)
                }
                
                RichTextEditor.forNotes(
                    text: $attributedText,
                    context: richTextContext
                )
                .padding(.horizontal, 16)
                .background(Color.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    // Main content view to break up complex expression
    private var mainContentView: some View {
        VStack(spacing: 0) {
            if isContentReady {
                // Combined title and text editor for seamless flow
                VStack(alignment: .leading, spacing: 0) {
                    titleSection
                    textEditorSection
                }
                .background(Color.white)
                .frame(maxWidth: .infinity) // Ensure consistent width
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
            
        }
        .background(Color.white)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main content area
            mainContentView
            
            // Fixed formatting toolbar area to prevent layout shifts
            // Only show one toolbar when text editing is active
            if isRichTextFocused && isBodyTextFocused && !isTitleFocused && 
               !showingActionSheet && !showingDeleteAlert && !showingFormattingSheet {
                FormattingToolbarView(context: richTextContext)
                    .background(Color.white)
                    .id("main-formatting-toolbar") // Unique identifier to prevent duplication
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity).animation(GentleLightning.Animation.swoosh),
                        removal: .move(edge: .bottom).combined(with: .opacity).animation(GentleLightning.Animation.gentle)
                    ))
            }
        }
        .simultaneousGesture(
                DragGesture()
                    .onChanged { gesture in
                        // Dismiss keyboard when swiping down (like in main app)  
                        if gesture.translation.height > 10 && isRichTextFocused {
                            print("🎯 Dismissing keyboard via swipe down gesture")
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            richTextContext.isEditingText = false
                        }
                    }
            )
        .background(Color.white)
        .contentShape(Rectangle()) // Make the entire area tappable for keyboard dismissal
        .onTapGesture {
            // Only dismiss keyboard when tapping outside both title and text areas
            // Check if we're tapping in empty space by comparing with focused states
            if isRichTextFocused && !isTitleFocused {
                // Give a small delay to allow text editor tap to register first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Only dismiss if neither title nor body got focus
                    if !isTitleFocused && !isBodyTextFocused {
                        print("🎯 Dismissing keyboard via tap gesture on empty area")
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        richTextContext.isEditingText = false  // This will update isRichTextFocused and isBodyTextFocused via onChange
                    }
                }
            }
        }
        .background(
            // Ensure white background extends to all edges, especially bottom safe area
            Color.white.ignoresSafeArea(.container, edges: .bottom)
        )
        .onAppear {
            print("🚀 NavigationNoteEditView onAppear: TRIGGERED")
            print("🚀 NavigationNoteEditView onAppear: Current attributedText = '\(attributedText.string.prefix(100))...'")
            print("🚀 NavigationNoteEditView onAppear: Current editedText = '\(editedText.prefix(100))...'")
            
            // All content is ready - attributedText should already be properly initialized
            // No need to re-convert since init() handles both HTML and plain text properly
            isContentReady = true
            richTextContext.setAttributedString(attributedText)
            
            // Update RichTextContext formatting state based on loaded content
            richTextContext.updateFormattingState()
            
            // Auto-focus the body text editor when entering note editor
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                richTextContext.isEditingText = true
            }
            
            print("✅ NavigationNoteEditView onAppear: Content ready - Rich text editor should show with proper formatting")
        }
        .onDisappear {
            print("🚀 NavigationNoteEditView onDisappear: TRIGGERED - ensuring content is saved")
            // Only save if we're not showing modals to prevent interference with modal presentation
            if !showingActionSheet && !showingDeleteAlert && !showingFormattingSheet {
                // Cancel any pending timer and save immediately to prevent data loss
                saveImmediately()
            } else {
                print("🚀 NavigationNoteEditView onDisappear: Skipping save - modal is showing")
            }
        }
        .onChange(of: isRichTextFocused) { newValue in
            withAnimation(GentleLightning.Animation.swoosh) {
                isTextFieldFocused = newValue
            }
        }
        .onChange(of: isTitleFocused) { newValue in
            withAnimation(GentleLightning.Animation.gentle) {
                if newValue {
                    isBodyTextFocused = false
                    richTextContext.isEditingText = false
                }
            }
        }
        .onChange(of: richTextContext.isEditingText) { newValue in
            withAnimation(GentleLightning.Animation.swoosh) {
                if newValue {
                    isBodyTextFocused = true
                    isRichTextFocused = true  // This was missing!
                    isTitleFocused = false
                } else {
                    isBodyTextFocused = false
                    isRichTextFocused = false
                }
            }
        }
        .onChange(of: attributedText) { newValue in
            // Simple RTF-only save - no plain text sync needed
            saveTimer?.invalidate()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                Task { @MainActor in
                    await saveContentToFirebase()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                let height = keyboardFrame.height
                // Ensure height is finite, positive, and reasonable to prevent CoreGraphics NaN errors
                if height.isFinite && height > 0 && height <= 1000 && !height.isNaN && !height.isInfinite {
                    keyboardHeight = height
                } else {
                    print("⚠️ Invalid keyboard height detected: \(height), using fallback")
                    keyboardHeight = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardHeight = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateUndoRedoState)) { notification in
            if let userInfo = notification.userInfo {
                canUndo = userInfo["canUndo"] as? Bool ?? false
                canRedo = userInfo["canRedo"] as? Bool ?? false
            }
        }
        // Remove global animation that causes sliding effect
        .navigationBarBackButtonHidden(true)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Back arrow on the left
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(GentleLightning.Colors.textBlack)
                }
            }
            
            // More options button (vertical dots)
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingActionSheet = true
                }) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                        .rotationEffect(.degrees(90))
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
    
    // MARK: - Save Functions
    
    @MainActor
    private func saveContentToFirebase() async {
        guard !isSavingContent else {
            print("💾 Save already in progress, skipping")
            return
        }
        
        let trimmedContent = attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            print("💾 Empty content, skipping save")
            return
        }
        
        isSavingContent = true
        print("💾 Starting RTF-only save to Firebase...")
        
        // Always save as RTF - this is now our primary format
        if let rtfData = NavigationNoteEditView.attributedStringToData(attributedText) {
            print("💾 Saving RTF data: '\(attributedText.string.prefix(100))...' (RTF bytes: \(rtfData.count))")
            
            // Save RTF data directly without updating plain text
            item.rtfData = rtfData
            
            if item.firebaseId != nil {
                // Use the data manager's public method instead of accessing private firebaseManager
                dataManager.updateItemWithRTF(item, rtfData: rtfData)
                print("💾 RTF saved via data manager")
            }
            
            AnalyticsManager.shared.trackNoteEditSaved(noteId: item.id, contentLength: attributedText.length)
        } else {
            print("❌ Failed to convert to RTF - this should not happen")
        }
        
        print("💾 Save completed successfully")
        isSavingContent = false
    }
    
    private func saveImmediately() {
        saveTimer?.invalidate()
        Task { @MainActor in
            await saveContentToFirebase()
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
    
    // MARK: - Formatting Actions
    
    private func toggleBold() {
        formattingState.toggleTextFormat(.bold)
        applyFormattingToSelection(format: .bold, isActive: formattingState.isBoldActive)
    }
    
    private func toggleItalic() {
        formattingState.toggleTextFormat(.italic)
        applyFormattingToSelection(format: .italic, isActive: formattingState.isItalicActive)
    }
    
    private func toggleUnderline() {
        formattingState.toggleTextFormat(.underline)
        applyFormattingToSelection(format: .underline, isActive: formattingState.isUnderlineActive)
    }
    
    private func toggleStrikethrough() {
        formattingState.toggleTextFormat(.strikethrough)
        applyFormattingToSelection(format: .strikethrough, isActive: formattingState.isStrikethroughActive)
    }
    
    private func toggleListMode() {
        let newState = !formattingState.isListModeActive
        formattingState.setBlockFormat(newState ? .bulletList : nil)
        applyBlockFormatting(format: .bulletList, isActive: formattingState.isListModeActive)
    }
    
    private func toggleCheckboxMode() {
        let newState = !formattingState.isCheckboxModeActive
        formattingState.setBlockFormat(newState ? .checkbox : nil)
        applyBlockFormatting(format: .checkbox, isActive: formattingState.isCheckboxModeActive)
    }
    
    // MARK: - Formatting Application
    private func applyFormattingToSelection(format: TextFormat, isActive: Bool) {
        // This function will trigger the RichTextEditor to apply formatting to selected text
        // We'll send a notification to the RichTextEditor
        NotificationCenter.default.post(
            name: .applyFormatting,
            object: nil,
            userInfo: ["format": format, "isActive": isActive]
        )
        print("📝 Applying \(format) formatting - active: \(isActive)")
    }
    
    private func applyBlockFormatting(format: BlockFormat, isActive: Bool) {
        // This function will trigger the RichTextEditor to apply block formatting to current line(s)
        // We'll send a notification to the RichTextEditor
        NotificationCenter.default.post(
            name: .applyBlockFormatting,
            object: nil,
            userInfo: ["format": format, "isActive": isActive]
        )
        print("📝 Applying \(format) block formatting - active: \(isActive)")
    }
    
    private func performUndo() {
        // Send undo notification to RichTextEditor
        NotificationCenter.default.post(
            name: .performUndo,
            object: nil
        )
    }
    
    private func performRedo() {
        // Send redo notification to RichTextEditor
        NotificationCenter.default.post(
            name: .performRedo,
            object: nil
        )
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}


// MARK: - Formatting Toggle Button
struct FormattingToggleButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isActive ? Color.white : GentleLightning.Colors.textPrimary(isDark: false))
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? GentleLightning.Colors.accentNeutral : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isActive ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.border(isDark: false),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(PlainButtonStyle())
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
                    FormatButton(title: "Code", symbol: "chevron.left.forwardslash.chevron.right", action: { applyFormat("`", "`") })
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

// MARK: - Search Bar View
struct SearchBarView: View {
    @Binding var isExpanded: Bool
    @Binding var searchText: String
    @Binding var searchResults: [SearchResult]
    @Binding var isSearching: Bool
    @Binding var searchTask: Task<Void, Never>?
    @Binding var hasSearched: Bool
    var isSearchFieldFocused: FocusState<Bool>.Binding
    let onResultTap: (SearchResult) -> Void
    let onSearch: () -> Void
    let onReindex: () -> Void
    
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            // Horizontal search bar with magnifying glass
            HStack(alignment: .center) {
                // Search input field - slides in from the right when expanded
                if isExpanded {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 16))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        TextField("Search your notes...", text: $searchText)
                            .font(GentleLightning.Typography.body)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .focused(isSearchFieldFocused)
                            .onSubmit {
                                onSearch()
                            }
                            .onLongPressGesture {
                                // Debug feature: long press to trigger reindexing
                                onReindex()
                            }
                            .onChange(of: searchText) { newValue in
                                // Cancel any existing search task
                                searchTask?.cancel()
                                
                                let trimmedValue = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                                
                                if trimmedValue.isEmpty {
                                    // Clear search results immediately for empty input
                                    searchResults = []
                                    hasSearched = false
                                    return
                                }
                                
                                // Reset search state when text changes
                                hasSearched = false
                                
                                // Check if input ends with space or has multiple words (trigger immediate search)
                                let shouldSearchImmediately = newValue.hasSuffix(" ") || trimmedValue.contains(" ") || trimmedValue.count >= 3
                                
                                if shouldSearchImmediately {
                                    // Search immediately for space-terminated input or longer queries
                                    onSearch()
                                } else {
                                    // Debounced search for shorter queries - wait for typing to stop
                                    searchTask = Task {
                                        do {
                                            try await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds
                                            if !Task.isCancelled && searchText == newValue {
                                                await MainActor.run {
                                                    onSearch()
                                                }
                                            }
                                        } catch {
                                            // Task was cancelled, ignore
                                        }
                                    }
                                }
                            }
                        
                        if isSearching {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(GentleLightning.Colors.accentNeutral)
                        }
                        
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(GentleLightning.Colors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(GentleLightning.Colors.border(isDark: false), lineWidth: 1)
                            )
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity).animation(GentleLightning.Animation.swoosh),
                        removal: .move(edge: .trailing).combined(with: .opacity).animation(GentleLightning.Animation.swoosh)
                    ))
                }
                
                // Magnifying glass button - stays on the right
                Button(action: {
                    withAnimation(GentleLightning.Animation.swoosh) {
                        isExpanded.toggle()
                        if isExpanded {
                            // Focus the search field when expanding - sync with swoosh animation
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                isSearchFieldFocused.wrappedValue = true
                            }
                        } else {
                            // Clear search when collapsing
                            searchText = ""
                            searchResults = []
                            hasSearched = false
                            searchTask?.cancel()
                            searchTask = nil
                            isSearchFieldFocused.wrappedValue = false
                        }
                    }
                }) {
                    ZStack {
                        // Magnifying glass icon
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .scaleEffect(isExpanded ? 0.1 : 1.0)
                            .opacity(isExpanded ? 0.0 : 1.0)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0), value: isExpanded)
                        
                        // X mark icon
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .scaleEffect(isExpanded ? 1.0 : 0.1)
                            .opacity(isExpanded ? 1.0 : 0.0)
                            .rotationEffect(.degrees(isExpanded ? 0 : -90))
                            .animation(.spring(response: 0.6, dampingFraction: 0.8, blendDuration: 0).delay(isExpanded ? 0.1 : 0), value: isExpanded)
                    }
                    .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(GentleLightning.Colors.surface)
                                .overlay(
                                    Circle()
                                        .stroke(GentleLightning.Colors.border(isDark: false), lineWidth: 1)
                                )
                                .opacity(isExpanded ? 0.0 : 1.0)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8, blendDuration: 0), value: isExpanded)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Search results or empty state shown below when expanded
            if isExpanded {
                VStack(spacing: 4) {
                    if !searchResults.isEmpty {
                        // Show search results
                        ForEach(searchResults.prefix(3)) { result in
                            SearchResultRow(result: result) {
                                onResultTap(result)
                            }
                        }
                        
                        if searchResults.count > 3 {
                            Text("+ \(searchResults.count - 3) more results")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching && hasSearched {
                        // Show empty state only AFTER search has completed with no results
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 24))
                                    .foregroundColor(GentleLightning.Colors.textSecondary)
                                
                                Text("No results found")
                                    .font(GentleLightning.Typography.heading)
                                    .foregroundColor(GentleLightning.Colors.textPrimary)
                                
                                Text("Try different keywords or check your spelling")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(GentleLightning.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                    } else if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isSearching {
                        // Show loading state during search
                        VStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(GentleLightning.Colors.accentNeutral)
                            
                            Text("Searching...")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                        }
                        .padding(.vertical, 16)
                        .padding(.horizontal, 8)
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(GentleLightning.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(GentleLightning.Colors.border(isDark: false), lineWidth: 1)
                        )
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.95).combined(with: .opacity).animation(GentleLightning.Animation.swoosh),
                    removal: .opacity.animation(GentleLightning.Animation.swoosh)
                ))
            }
        }
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: SearchResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.previewContent)
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                    
                    HStack(spacing: 8) {
                        Text("\(result.confidencePercentage)% match")
                            .font(GentleLightning.Typography.caption)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        if result.isTask {
                            Text("Task")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.accentNeutral)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    Capsule()
                                        .fill(GentleLightning.Colors.accentNeutral.opacity(0.1))
                                )
                        }
                        
                        Spacer()
                    }
                }
                
                Spacer()
                
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12))
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .padding(8)
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