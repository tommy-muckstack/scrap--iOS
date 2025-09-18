import SwiftUI
import WidgetKit
import Foundation
import Combine
import NaturalLanguage
import UIKit
import Speech
import AVFoundation
import FirebaseAuth

// Dependencies needed for NoteEditor - ensure proper compilation order
// This file requires: SparkServices.swift, NoteEditor.swift, SparkModels.swift

// Ensure NoteEditor is accessible - workaround for target membership issues

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
        } else {
            activeTextFormats.insert(format)
        }
    }
    
    mutating func setBlockFormat(_ format: BlockFormat?) {
        activeBlockFormat = format
    }
    
    mutating func toggleBlockFormat(_ format: BlockFormat) {
        if activeBlockFormat == format {
            activeBlockFormat = nil
        } else {
            activeBlockFormat = format
        }
    }
    
    mutating func clearAllFormatting() {
        activeTextFormats.removeAll()
        activeBlockFormat = nil
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
        
        static func drawerHandle(isDark: Bool) -> Color {
            isDark ? Color(red: 0.65, green: 0.7, blue: 1.0) : Color(red: 0.45, green: 0.45, blue: 0.5) // Purple in dark mode, gray in light mode
        }
        
        // MARK: - Static Colors (Theme Independent)
        static let textBlack = Color.black
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let error = Color(red: 0.95, green: 0.26, blue: 0.21)
        static let success = Color(red: 0.29, green: 0.76, blue: 0.49)
        static let textGreyStatic = Color(red: 0.45, green: 0.45, blue: 0.5) // Static grey for app info in settings
        
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
        static let title = Font.custom("SpaceGrotesk-Medium", size: 28)            // Standard titles/headings
        static let titleEmphasis = Font.custom("SpaceGrotesk-SemiBold", size: 28)  // Emphasized titles
        static let subtitle = Font.custom("SpaceGrotesk-Medium", size: 18)         // Subtitles
        static let heading = Font.custom("SpaceGrotesk-Medium", size: 16)          // Section headings
        
        // BODY TEXT → SpaceGrotesk-Regular (regular reading weight)
        static let body = Font.custom("SpaceGrotesk-Regular", size: 16)            // Primary body text
        static let bodyInput = Font.custom("SpaceGrotesk-Regular", size: 16)       // Input fields
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
    
    struct Icons {
        // MARK: - Navigation Icons
        static let navigationBack = "chevron.left"
        static let navigationOptions = "ellipsis"
        static let navigationOptionsVertical = "ellipsis"
        static let navigationMore = "ellipsis.circle"
        static let navigationClose = "xmark"
        
        // MARK: - Action Icons
        static let share = "square.and.arrow.up"
        static let delete = "trash"
        static let edit = "pencil"
        static let add = "plus"
        static let search = "magnifyingglass"
        
        // MARK: - Formatting Icons
        static let formatBold = "bold"
        static let formatItalic = "italic"
        static let formatStrikethrough = "strikethrough"
        static let formatCode = "chevron.left.forwardslash.chevron.right"
        static let formatList = "list.bullet"
        static let formatChecklist = "checklist"
        static let formatQuote = "quote.bubble"
        static let formatHeader = "textformat.size.larger"
        static let formatLink = "link"
        static let formatHighlight = "highlighter"
        
        // MARK: - Status Icons
        static let success = "checkmark.circle.fill"
        static let error = "exclamationmark.triangle.fill"
        static let warning = "exclamationmark.circle.fill"
        static let info = "info.circle.fill"
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
    
    let firebaseManager = FirebaseManager.shared
    
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
                
                // Create RTF data with Space Grotesk font for consistent display
                var rtfData: Data? = nil
                do {
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16),
                        .foregroundColor: UIColor.label
                    ]
                    let attributedText = NSAttributedString(string: text, attributes: attributes)
                    let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedText)
                    rtfData = try rtfCompatibleString.data(
                        from: NSRange(location: 0, length: rtfCompatibleString.length),
                        documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf]
                    )
                    print("✅ DataManager: Created RTF data (\(rtfData?.count ?? 0) bytes) for \(creationType) note")
                } catch {
                    print("❌ DataManager: Failed to create RTF data: \(error)")
                }
                
                let finalTitle = generatedTitle
                let firebaseId = try await firebaseManager.createNote(
                    content: text,
                    title: finalTitle,
                    categoryIds: categoryIds,
                    isTask: false, 
                    categories: legacyCategories,
                    creationType: creationType,
                    rtfData: rtfData
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
        
        // Convert attributed text to RTF data for storage using trait preservation
        var rtfData: Data? = nil
        do {
            let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedText)
            rtfData = try rtfCompatibleString.data(
                from: NSRange(location: 0, length: rtfCompatibleString.length),
                documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            print("❌ Failed to create RTF data: \(error)")
        }
        
        // Extract plain text for display and search
        let plainText = attributedText.string
        
        // Save to Firebase with AI-generated title first, then add to list
        Task { [rtfData] in
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
        // Update local item immediately (optimistic) - ensure on main thread
        DispatchQueue.main.async {
            item.content = newContent
        }
        
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
                options: [NSAttributedString.DocumentReadingOptionKey.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            // Ensure UI updates happen on main thread
            DispatchQueue.main.async {
                item.content = attributedString.string
            }
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
    
    // Theme management
    @StateObject private var themeManager = ThemeManager.shared
    
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
    
    // Extract complex button to resolve compiler timeout
    private var actionButton: some View {
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
                    .fill(isRecording ? Color.red : (themeManager.isDarkMode ? GentleLightning.Colors.textPrimary(isDark: true) : Color.black))
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
                            .foregroundColor(themeManager.isDarkMode ? Color.black : .white)
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
                            .foregroundColor(themeManager.isDarkMode ? Color.black : .white)
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
                                .foregroundColor(themeManager.isDarkMode ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.textSecondary.opacity(0.6))
                                .padding(.top, 8)
                                .padding(.leading, 4)
                        }
                        
                        RichTextEditorWithDrawings(
                            text: $attributedText,
                            context: richTextContext,
                            showingFormatting: .constant(false),
                            configuration: { textView in
                            // Apply forNotes configuration
                            textView.autocorrectionType = .yes
                            textView.autocapitalizationType = .sentences
                            textView.smartQuotesType = .yes
                            textView.smartDashesType = .yes
                            textView.spellCheckingType = .yes
                            
                            // Set cursor color to black (matching design system)
                            textView.tintColor = UIColor.label
                            
                            // Improve text alignment and padding to match placeholder
                            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
                            textView.textContainer.lineFragmentPadding = 4
                            
                            // Better line spacing for readability
                            let paragraphStyle = NSMutableParagraphStyle()
                            paragraphStyle.lineSpacing = 4
                            paragraphStyle.paragraphSpacing = 8
                            
                            // Set default Space Grotesk font for all notes
                            let defaultFont = UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
                            
                            textView.typingAttributes = [
                                .paragraphStyle: paragraphStyle,
                                .font: defaultFont,
                                .foregroundColor: UIColor.label
                            ]
                        }
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
                .onChange(of: text) { newPlainText in
                    // Sync plain text changes (from voice transcription) to attributed text for display
                    if attributedText.string != newPlainText {
                        print("🔄 InputField: Syncing text binding to attributedText: '\(newPlainText)'")
                        
                        // Create attributed string with proper SpaceGrotesk font and size
                        let attributes: [NSAttributedString.Key: Any] = [
                            .font: UIFont(name: "SpaceGrotesk-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17),
                            .foregroundColor: UIColor.label
                        ]
                        attributedText = NSAttributedString(string: newPlainText, attributes: attributes)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Refresh authorization status when app becomes active (user returning from Settings)
                    authorizationStatus = SFSpeechRecognizer.authorizationStatus()
                }
                
                // Microphone/Save button - transforms based on recording state and text content
                actionButton
            }
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.vertical, GentleLightning.Layout.Padding.lg)
            .background(themeManager.isDarkMode ? Color.black : Color.white)
            
            // Simple recording indicator that doesn't interfere with transcription
            if isRecording {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)
                    
                    Text("Listening...")
                        .font(GentleLightning.Typography.small)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                    
                    Spacer()
                    
                    Text("Tap red button to stop")
                        .font(GentleLightning.Typography.small)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                        .opacity(0.7)
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
        print("🎙️ ContentView: startRecording() called")
        
        guard authorizationStatus == .authorized else {
            print("❌ ContentView: Speech authorization not granted: \(authorizationStatus)")
            AnalyticsManager.shared.trackVoicePermissionDenied()
            return
        }
        
        print("✅ ContentView: Speech authorization confirmed")
        AnalyticsManager.shared.trackVoiceRecordingStarted()
        recordingStartTime = Date()
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            print("❌ ContentView: Speech recognizer not available")
            return
        }
        
        print("✅ ContentView: Speech recognizer available")
        
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
            print("🎙️ ContentView: Starting speech recognition task...")
            recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
                if let result = result {
                    DispatchQueue.main.async {
                        let transcription = result.bestTranscription.formattedString
                        print("🎙️ ContentView: Transcription update: '\(transcription)' (isFinal: \(result.isFinal), isRecording: \(self.isRecording))")
                        
                        // Update the temporary voice note content for visual feedback
                        voiceNoteContent = transcription
                        
                        // Always update the UI for real-time transcription (including final results)
                        // The isFinal check will handle cleanup after UI is updated
                        print("🎙️ ContentView: Updating text field with transcription: '\(transcription)'")
                        print("🎙️ ContentView: Current isRecording state: \(self.isRecording)")
                        print("🎙️ ContentView: Current text before update: '\(self.text)'")
                        self.text = transcription
                        print("🎙️ ContentView: Text after update: '\(self.text)'")
                        
                        // Handle final result cleanup AFTER updating the UI
                        if result.isFinal {
                            print("🎙️ ContentView: Processing final result - cleaning up after UI update")
                            
                            // Perform cleanup in the same dispatch block to ensure proper sequencing
                            self.audioEngine.stop()
                            inputNode.removeTap(onBus: 0)
                            
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
                
                // Error handling only - cleanup is now handled in the result processing above
                if let error = error {
                    print("🎙️ ContentView: Speech recognition error: \(error)")
                    // Only stop on error, not on isFinal (that's handled above)
                    self.audioEngine.stop()
                    inputNode.removeTap(onBus: 0)
                    
                    DispatchQueue.main.async {
                        self.recognitionRequest = nil
                        self.recognitionTask = nil
                        self.isRecording = false
                        self.text = ""
                    }
                }
            }
            
            // Configure microphone input
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            print("🎙️ ContentView: Setting up audio tap with format: \(recordingFormat)")
            
            var bufferCount = 0
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                bufferCount += 1
                if bufferCount % 100 == 0 { // Log every 100th buffer to avoid spam
                    print("🎙️ ContentView: Audio buffer #\(bufferCount) received (frameLength: \(buffer.frameLength))")
                }
                self.recognitionRequest?.append(buffer)
            }
            
            print("🎙️ ContentView: Preparing audio engine...")
            audioEngine.prepare()
            
            print("🎙️ ContentView: Starting audio engine...")
            try audioEngine.start()
            
            print("✅ ContentView: Audio engine started successfully")
            isRecording = true
            
            // Clear text field but keep it focused so user can see real-time transcription
            text = ""
            isFieldFocused.wrappedValue = true
            print("🎤 Starting voice recording - cleared text field and kept focused for transcription")
            print("🎤 Current isRecording state: \(isRecording)")
            print("🎤 Current text field state: '\(text)'")
            print("🎤 Current focus state: \(isFieldFocused.wrappedValue)")
            
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
    
    @State private var isNavigating = false
    
    // Cache expensive computations
    private var displayTitle: String {
        item.title.isEmpty ? String(item.content.prefix(50)) : item.title
    }
    
    private var previewText: String {
        item.title.isEmpty ? "" : String(item.content.prefix(100))
    }
    
    var body: some View {
        Button(action: {
            // Provide immediate visual feedback
            withAnimation(.easeInOut(duration: 0.1)) {
                isNavigating = true
            }
            
            // Navigate after brief delay for smooth feedback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                onTap()
                isNavigating = false
            }
        }) {
            VStack(alignment: .leading, spacing: 2) {
                // Title - use content as title if no title exists
                Text(displayTitle)
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Preview text - only show if title exists
                if !previewText.isEmpty {
                    Text(previewText)
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
                    .fill(isNavigating ? GentleLightning.Colors.surface.opacity(0.7) : GentleLightning.Colors.surface)
            )
            .scaleEffect(isNavigating ? 0.98 : 1.0)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                // Add scribble/drawing to this note
                Task {
                    await addScribbleToNote()
                }
            }) {
                Label("Add Scribble", systemImage: "scribble")
            }
            
            Divider()
            
            Button("Delete", role: .destructive) {
                withAnimation(GentleLightning.Animation.gentle) {
                    dataManager.deleteItem(item)
                }
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") {
                withAnimation(GentleLightning.Animation.gentle) {
                    dataManager.deleteItem(item)
                }
            }
            .tint(.red)
        }
    }
    
    // MARK: - Single Drawing Support
    
    /// Add a scribble/drawing to this note using single drawing per note architecture
    private func addScribbleToNote() async {
        guard let firebaseId = item.firebaseId else {
            print("❌ ItemRowSimple: Cannot add scribble - note has no Firebase ID")
            return
        }
        
        // Update the item to indicate it has a drawing
        await MainActor.run {
            item.hasDrawing = true
            // Initialize with empty drawing data - will be populated when user first draws
            item.drawingData = nil
            item.drawingHeight = 200 // Default height
            item.drawingColor = "#000000" // Default black color
        }
        
        // Update Firebase to reflect the change using the new Firebase methods
        do {
            // Use the dedicated Firebase methods for single drawing updates
            try await FirebaseManager.shared.updateNoteDrawingData(
                noteId: firebaseId,
                drawingData: nil, // No drawing data initially
                hasDrawing: true
            )
            
            try await FirebaseManager.shared.updateNoteDrawingHeight(
                noteId: firebaseId,
                height: 200
            )
            
            try await FirebaseManager.shared.updateNoteDrawingColor(
                noteId: firebaseId,
                color: "#000000"
            )
            
            print("✅ ItemRowSimple: Successfully added scribble capability to note \(firebaseId)")
            
            // Track analytics for drawing addition
            AnalyticsManager.shared.trackDrawingUpdated(
                noteId: firebaseId,
                hasContent: true
            )
            
        } catch {
            print("❌ ItemRowSimple: Failed to update note with scribble capability: \(error)")
            // Revert local change on error
            await MainActor.run {
                item.hasDrawing = false
            }
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
                .fill(GentleLightning.Colors.drawerHandle(isDark: themeManager.isDarkMode))
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
                        .foregroundColor(themeManager.isDarkMode ? GentleLightning.Colors.textPrimary(isDark: true) : GentleLightning.Colors.textBlack)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(themeManager.isDarkMode ? Color.black : GentleLightning.Colors.surface)
                                .shadow(color: themeManager.isDarkMode ? GentleLightning.Colors.shadow(isDark: true) : GentleLightning.Colors.shadowLight, radius: 4, x: 0, y: 1)
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
                                .fill(themeManager.isDarkMode ? Color.black : GentleLightning.Colors.surface)
                                .shadow(color: themeManager.isDarkMode ? GentleLightning.Colors.shadow(isDark: true) : GentleLightning.Colors.shadowLight, radius: 4, x: 0, y: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                    Spacer()
                    
                    // App info
                    VStack(spacing: 8) {
                        Text("Scrap")
                            .font(.custom("SpaceGrotesk-Bold", size: 24))
                            .foregroundColor(GentleLightning.Colors.textGreyStatic)
                        
                        Text("Version \(appVersion) (\(buildNumber))")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textGreyStatic)
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
    
    private var headerView: some View {
        HStack {
            Spacer()
            
            Text("Scrap")
                .font(.custom("SpaceGrotesk-Bold", size: 48))
                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
            
            Spacer()
        }
        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
        .padding(.top, GentleLightning.Layout.Padding.xl)
        .padding(.bottom, GentleLightning.Layout.Padding.lg)
    }
    
    @ViewBuilder
    private var notesSection: some View {
        if !dataManager.items.isEmpty {
            // Smaller spacer below
            Spacer()
                .frame(maxHeight: 20)
            
            notesSectionHeader
            notesListContent
        }
    }
    
    @ViewBuilder
    private var notesListContent: some View {
        // Notes list or empty state
        if hasSearched {
            searchResultsView
        } else {
            mainNotesListView
        }
    }
    
    @ViewBuilder
    private var searchResultsView: some View {
        // Show search results
        if isSearching {
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Searching...")
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .padding(.top, 20)
        } else if searchResults.isEmpty && !searchText.isEmpty {
            // No search results found
            VStack(spacing: 12) {
                Text("No results found")
                    .font(GentleLightning.Typography.subtitle)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                
                Text("Try a different search term")
                    .font(GentleLightning.Typography.secondary)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .padding(.top, 20)
        } else {
            // Search results list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(searchResults, id: \.firebaseId) { result in
                        SearchResultRow(
                            result: result,
                            onTap: {
                                handleSearchResultTap(result)
                            }
                        )
                        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                    }
                }
                .padding(.top, 8)
            }
            .transition(.asymmetric(
                insertion: .move(edge: .top).combined(with: .opacity),
                removal: .move(edge: .top).combined(with: .opacity)
            ))
            .animation(GentleLightning.Animation.swoosh, value: searchResults.count)
        }
    }
    
    @ViewBuilder
    private var mainNotesListView: some View {
        // Normal notes list or empty state
        if dataManager.items.isEmpty {
            // Empty state
            VStack(spacing: 16) {
                Text("No notes yet")
                    .font(GentleLightning.Typography.title)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                
                Text("Start by typing above or using voice recording")
                    .font(GentleLightning.Typography.secondary)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 40)
        } else {
            // Notes list
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(dataManager.items.prefix(displayedItemsCount).enumerated()), id: \.element.id) { index, item in
                        ItemRowSimple(item: item, dataManager: dataManager) {
                            // Optimize navigation with immediate feedback
                            withAnimation(.easeInOut(duration: 0.15)) {
                                navigationPath.append(item)
                            }
                        }
                        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)
                        ))
                        .onAppear {
                            // Load more items when approaching the end
                            if index == displayedItemsCount - 3 {
                                loadMoreItems()
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
            .onTapGesture {
                // Also dismiss keyboard when tapping in scroll area
                if isInputFieldFocused {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
            }
        }
    }
    
    @ViewBuilder
    private var mainContent: some View {
        ZStack {
            VStack(spacing: 0) {
                headerView
                
                // Large spacer to push input field lower
                Spacer()
                Spacer()
                
                inputFieldSection
                itemsListSection
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
                            .font(.system(size: 44, weight: .medium))
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            .padding(.vertical, 20)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                }
                .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .dismissKeyboardOnDrag()
        }
    }
    
    @ViewBuilder
    private var inputFieldSection: some View {
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
    }
    
    @ViewBuilder
    private var notesSectionHeader: some View {
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
            searchBarOverlay
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }
    
    @ViewBuilder
    private var searchBarOverlay: some View {
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
                onResultTap: handleSearchResultTap,
                onSearch: performSearch,
                onReindex: triggerReindexing
            )
            .padding(.trailing, 36) // 20pt (outer) + 16pt (inner) to match microphone button center
        }
    }
    
    @ViewBuilder 
    private var itemsListSection: some View {
        // Items List - scrollable content with header
        if !dataManager.items.isEmpty {
            // Smaller spacer below
            Spacer()
                .frame(maxHeight: 20)
            
            notesSectionHeader
        }
        
        ScrollView {
            itemsListContent
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
        .buttonStyle(PlainButtonStyle())
        .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
    }
    
    @ViewBuilder
    private var itemsListContent: some View {
        LazyVStack(spacing: 0) {
            if dataManager.items.isEmpty {
                EmptyStateView()
                    .padding(.top, 20)
            } else if hasSearched {
                searchResultsView
            } else {
                mainNotesListContent
            }
        }
        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
        .padding(.bottom, 120) // Extra padding for footer
        .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
    }
    
    @ViewBuilder
    private var mainNotesListContent: some View {
        // Only show notes list when not displaying search results
        let itemsToDisplay = Array(dataManager.items.prefix(displayedItemsCount))
        
        ForEach(itemsToDisplay) { item in
            ItemRowSimple(item: item, dataManager: dataManager) {
                // Prevent rapid multiple navigations
                guard navigationPath.isEmpty || navigationPath.count == 0 else { return }
                
                AnalyticsManager.shared.trackNoteEditOpened(noteId: item.id)
                
                // Use navigation instead of sheets - bulletproof approach
                navigationPath.append(item)
                
                print("✅ ContentView: Navigation pushed for item.id = '\(item.id)'")
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: item.id)
            .onAppear {
                // Load more items when reaching the last item
                if item.id == dataManager.items.last?.id && displayedItemsCount < dataManager.items.count {
                    withAnimation(GentleLightning.Animation.gentle) {
                        displayedItemsCount = min(displayedItemsCount + 10, dataManager.items.count)
                    }
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

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ZStack {
                mainContent
            }
            .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
            .contentShape(Rectangle()) // Make the entire area tappable for keyboard dismissal
            .onTapGesture {
                // Dismiss keyboard when tapping outside input area
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .navigationDestination(for: SparkItem.self) { item in
                NoteEditor(item: item, dataManager: dataManager)
                    .navigationBarHidden(false)
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
        .onAppear {
            // Initialize widget with current note count when app starts
            updateWidgetData(noteCount: dataManager.items.count)
            
            // Auto-focus the input field when the app loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFieldFocused = true
                
                // Add additional debugging
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                }
            }
            
            // Auto-index notes for search when app loads
            Task {
                // Wait a moment for the data to load
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Only index if we have notes and user is authenticated
                guard !dataManager.items.isEmpty,
                      Auth.auth().currentUser != nil else {
                    return
                }
                
                triggerReindexing()
            }
        }
        .onChange(of: dataManager.items.count) { _ in
            // Reset pagination when items change (new item added or deleted)
            displayedItemsCount = min(10, dataManager.items.count)
        }
        } // NavigationStack
    
    private func loadMoreItems() {
        // Add a small delay to simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                displayedItemsCount = min(displayedItemsCount + itemsPerPage, dataManager.items.count)
            }
        }
    }
    
    private func performSearch() {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            hasSearched = false
            return
        }
        
        isSearching = true
        
        Task { @MainActor in
            do {
                let results = try await VectorSearchService.shared.semanticSearch(
                    query: searchText,
                    limit: 10
                )
                
                searchResults = results
                hasSearched = true
                isSearching = false
                
                // Track search analytics
                AnalyticsManager.shared.trackSearch(query: searchText, resultCount: results.count)
            } catch {
                print("Search failed: \(error)")
                hasSearched = true
                isSearching = false
                // Could show error state here
            }
        }
    }
    
    private func triggerReindexing() {
        print("🔄 ContentView: Manual reindexing triggered by long press")
        
        Task {
            // Get all current items and convert to FirebaseNote format for reindexing
            let firebaseNotes = dataManager.items.compactMap { item -> FirebaseNote? in
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
            
            // Show success feedback
            await MainActor.run {
                print("✅ ContentView: Reindexing completed successfully!")
            }
        }
    }
    
    private func handleSearchResultTap(_ result: SearchResult) {
        // Track search result tap
        AnalyticsManager.shared.trackNoteOpened(noteId: result.firebaseId, openMethod: "search_result")
        
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
                    if isExpanded {
                        // Collapsing search
                        withAnimation(GentleLightning.Animation.swoosh) {
                            isExpanded = false
                        }
                        // Clear search when collapsing
                        searchText = ""
                        searchResults = []
                        hasSearched = false
                        searchTask?.cancel()
                        searchTask = nil
                        isSearchFieldFocused.wrappedValue = false
                    } else {
                        // Expanding search
                        withAnimation(GentleLightning.Animation.swoosh) {
                            isExpanded = true
                        }
                        // Focus immediately for better UX - user can start typing right away
                        isSearchFieldFocused.wrappedValue = true
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