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

// MARK: - Shared Note Display Component (Design System)
struct NoteDisplayContent: View {
    let title: String
    let content: String
    let isDarkMode: Bool
    
    // Helper to create theme-aware text with visible ellipsis
    private var styledContent: Text {
        if content.hasSuffix("...") {
            // Split content and ellipsis for better visibility
            let mainContent = String(content.dropLast(3))
            let mainText = Text(mainContent)
                .foregroundColor(title.isEmpty ? GentleLightning.Colors.textPrimary(isDark: isDarkMode) : GentleLightning.Colors.textSecondary(isDark: isDarkMode))
            
            // Make ellipsis more visible in dark mode with primary text color
            let ellipsisText = Text("…") // Using Unicode ellipsis character
                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: isDarkMode))
            
            return mainText + ellipsisText
        } else {
            return Text(content)
                .foregroundColor(title.isEmpty ? GentleLightning.Colors.textPrimary(isDark: isDarkMode) : GentleLightning.Colors.textSecondary(isDark: isDarkMode))
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !title.isEmpty {
                Text(title)
                    .font(GentleLightning.Typography.heading)
                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: isDarkMode))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            
            styledContent
                .font(title.isEmpty ? GentleLightning.Typography.body : GentleLightning.Typography.secondary)
                .lineLimit(title.isEmpty ? nil : 1)
                .multilineTextAlignment(.leading)
        }
    }
}

// MARK: - Search Result Model (Shared)
struct SearchResult: Identifiable {
    let id = UUID()
    let firebaseId: String
    let title: String
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
            isDark ? Color.white : Color(red: 0.12, green: 0.12, blue: 0.15) // White for dark mode, original dark color for light mode
        }
        
        static func textSecondary(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.7) : Color(red: 0.45, green: 0.45, blue: 0.5) // Dimmed white for dark mode
        }
        
        static func textTertiary(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.5) : Color(red: 0.60, green: 0.60, blue: 0.65) // More dimmed white for dark mode
        }
        
        static func border(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.3) : Color(red: 0.90, green: 0.90, blue: 0.92) // Subtle white border for dark mode
        }
        
        static func shadow(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.03) // Subtle white glow for dark mode
        }
        
        static func drawerHandle(isDark: Bool) -> Color {
            isDark ? Color.white : Color(red: 0.45, green: 0.45, blue: 0.5) // White in dark mode, gray in light mode
        }
        
        static func placeholder(isDark: Bool) -> Color {
            isDark ? Color.white.opacity(0.6) : Color(red: 0.45, green: 0.45, blue: 0.5).opacity(0.6) // White for dark mode, gray for light mode
        }
        
        static func searchInputBackground(isDark: Bool) -> Color {
            isDark ? Color.black : Color.white // Black background in dark mode, white in light mode
        }
        
        // MARK: - Static Colors (Theme Independent)
        static let textBlack = Color.black
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let error = Color(red: 0.95, green: 0.26, blue: 0.21)
        static let success = Color(red: 0.29, green: 0.76, blue: 0.49)
        static let textGreyStatic = Color(red: 0.45, green: 0.45, blue: 0.5) // Static grey for app info in settings
        static let buttonBrightBackground = Color.white // Bright white button for dark mode visibility
        static let buttonBrightText = Color.black // Black text for bright white buttons
        
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
        
        /// Critical alignment specifications to maintain consistent UI layout
        struct Alignment {
            /// Search icon to microphone icon vertical alignment
            /// 
            /// **Context:** The search magnifying glass in notesSectionHeader must align with 
            /// the microphone button in inputFieldSection for visual consistency.
            ///
            /// **Calculation:**
            /// - Microphone center position: xl(20) + lg(16) + buttonRadius(20) = 56pt from right edge
            /// - Search icon trailing padding: micCenter(56) - searchRadius(22) = 34pt
            ///
            /// **Dependencies:**
            /// - InputField container: `.padding(.horizontal, xl)` = 20pt
            /// - InputField internal: `.padding(.horizontal, lg)` = 16pt  
            /// - Microphone button width: 40pt (radius: 20pt)
            /// - Search icon width: 44pt (radius: 22pt)
            ///
            /// **⚠️ Critical:** If any padding values change, this must be recalculated
            static let searchToMicrophoneTrailing: CGFloat = 34
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
        static let swoosh = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8, blendDuration: 0.1)
        static let delightful = SwiftUI.Animation.interpolatingSpring(stiffness: 300, damping: 30, initialVelocity: 0)
        static let silky = SwiftUI.Animation.timingCurve(0.4, 0.0, 0.2, 1.0, duration: 0.35)
        static let bouncy = SwiftUI.Animation.interpolatingSpring(stiffness: 200, damping: 20, initialVelocity: 5)
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


// MARK: - Content View Model
class ContentViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var placeholderText = "Just type or speak..."
}

// MARK: - Firebase Data Manager
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
        
        withAnimation(GentleLightning.Animation.elastic) {
            items.insert(newItem, at: 0)
        }
        
        Task {
            // Generate title
            let title: String? = await {
                do {
                    return try await OpenAIService.shared.generateTitle(for: text)
                } catch {
                    print("Title generation failed: \(error)")
                    return nil
                }
            }()
            
            do {
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
        
        withAnimation(GentleLightning.Animation.elastic) {
            items.insert(newItem, at: 0)
        }
        
        Task {
            // Generate title from plain text
            let title: String? = await {
                do {
                    let generatedTitle = try await OpenAIService.shared.generateTitle(for: plainText)
                    print("📝 Generated title: '\(generatedTitle)'")
                    return generatedTitle
                } catch {
                    print("Title generation failed: \(error)")
                    return nil
                }
            }()
            
            do {
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
        // Ensure UI updates happen on main thread
        DispatchQueue.main.async {
            item.content = newContent
        }
        
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
            
            // Ensure UI updates happen on main thread
            DispatchQueue.main.async {
                item.content = plainText
            }
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
        withAnimation(GentleLightning.Animation.gentle) {
            items.removeAll { $0.id == item.id }
        }
        
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

// MARK: - Animated Placeholder Text
struct AnimatedPlaceholderText: View {
    let text: String
    let themeManager: ThemeManager
    
    @State private var animatingDotIndex = -1
    @State private var animationTimer: Timer?
    
    private var textWithoutDots: String {
        String(text.dropLast(3)) // Remove the "..."
    }
    
    var body: some View {
        // Don't render anything if text is empty
        if !text.isEmpty {
            HStack(spacing: 0) {
                // Static text part
                Text(textWithoutDots)
                    .font(GentleLightning.Typography.bodyInput)
                    .foregroundColor(GentleLightning.Colors.placeholder(isDark: themeManager.isDarkMode))
                
                // Animated dots
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { index in
                        Text(".")
                            .font(GentleLightning.Typography.bodyInput)
                            .foregroundColor(GentleLightning.Colors.placeholder(isDark: themeManager.isDarkMode))
                            .scaleEffect(animatingDotIndex == index ? 1.8 : 1.0)
                            .offset(y: animatingDotIndex == index ? -6 : 0)
                    }
                }
            }
            .onAppear {
                startAnimation()
            }
            .onDisappear {
                stopAnimation()
            }
        }
    }
    
    private func startAnimation() {
        // Initial delay before first animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            performAnimation()
        }
        
        // Set up repeating timer - full sequence takes ~0.9s (3 dots * 0.3s), then wait 5s
        animationTimer = Timer.scheduledTimer(withTimeInterval: 6.0, repeats: true) { _ in
            performAnimation()
        }
    }
    
    private func stopAnimation() {
        animationTimer?.invalidate()
        animationTimer = nil
    }
    
    private func performAnimation() {
        // Reset to ensure clean state
        animatingDotIndex = -1
        
        // Animate each dot in sequence with proper timing
        for index in 0..<3 {
            let delay = Double(index) * 0.3 // Increased delay for clearer effect
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    animatingDotIndex = index
                }
                
                // Reset this specific dot after animation
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.25) {
                    withAnimation(.easeInOut(duration: 0.1)) {
                        if animatingDotIndex == index {
                            animatingDotIndex = -1
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    let placeholder: String
    let dataManager: FirebaseDataManager
    let onCommit: () -> Void
    var isFieldFocused: FocusState<Bool>.Binding
    var hideMicrophone: Bool = false
    var isSearchExpanded: Bool = false
    
    // Theme management
    @ObservedObject private var themeManager = ThemeManager.shared
    
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
            .animation(GentleLightning.Animation.bouncy, value: isRecording)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    // Rich Text Editor
                    ZStack(alignment: .topLeading) {
                        // Animated placeholder text
                        if attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearchExpanded {
                            AnimatedPlaceholderText(text: placeholder, themeManager: themeManager)
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
                if !hideMicrophone {
                    actionButton
                }
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
                    
                    WaveformView(
                        isRecording: isRecording,
                        barCount: 5,
                        barWidth: 3,
                        barSpacing: 2,
                        maxHeight: 16,
                        color: GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode)
                    )
                    
                    Spacer()
                }
                .padding(.horizontal, GentleLightning.Layout.Padding.lg)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95)).combined(with: .move(edge: .top)))
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
    
    @EnvironmentObject var themeManager: ThemeManager
    
    // Cache expensive computations
    private var displayTitle: String {
        item.title.isEmpty ? String(item.content.prefix(50)) : item.title
    }
    
    private var previewText: String {
        item.title.isEmpty ? "" : String(item.content.prefix(100))
    }
    
    var body: some View {
        Button(action: {
            // Simple haptic feedback for button press
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            // Navigate immediately without animation
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 2) {
                // Title - use content as title if no title exists
                Text(displayTitle)
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                // Preview text - only show if title exists
                if !previewText.isEmpty {
                    Text(previewText)
                        .font(GentleLightning.Typography.secondary)
                        .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, GentleLightning.Layout.Padding.lg)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                    .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                    .shadow(
                        color: GentleLightning.Colors.shadow(isDark: themeManager.isDarkMode),
                        radius: 2,
                        x: 0,
                        y: 1
                    )
            )
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
                // Haptic feedback for destructive action
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
                
                dataManager.deleteItem(item)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") {
                // Haptic feedback for swipe delete
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
                
                dataManager.deleteItem(item)
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

// MARK: - Manage Tags View
struct ManageTagsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var themeManager = ThemeManager.shared
    @State private var userCategories: [Category] = []
    @State private var selectedCategories: [String] = [] // Not used but required for CategoryManagerView
    @State private var isLoadingCategories = false
    @State private var showingCreateForm = false
    @State private var newCategoryName = ""
    @State private var selectedColorKey = ""
    @State private var availableColors: [(key: String, hex: String, name: String)] = []
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
            ZStack {
                GentleLightning.Colors.background(isDark: themeManager.isDarkMode)
                    .ignoresSafeArea()
                
                if isLoadingCategories {
                    VStack {
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(GentleLightning.Colors.accentNeutral)
                        Text("Loading Tags...")
                            .font(GentleLightning.Typography.caption)
                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                            .padding(.top, 8)
                    }
                } else {
                    VStack(spacing: 0) {
                        if showingCreateForm {
                            // Create Tag Form
                            CreateTagInlineView(
                                categoryName: $newCategoryName,
                                selectedColorKey: $selectedColorKey,
                                availableColors: availableColors,
                                onCancel: {
                                    showingCreateForm = false
                                    newCategoryName = ""
                                    selectedColorKey = ""
                                },
                                onCreate: { name, colorKey in
                                    createCategory(name: name, colorKey: colorKey)
                                }
                            )
                        } else {
                            // Header section with create button
                            VStack(spacing: 16) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Manage Tags")
                                            .font(GentleLightning.Typography.heading)
                                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                        
                                        Text("View and organize your tags")
                                            .font(GentleLightning.Typography.caption)
                                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    }
                                    
                                    Spacer()
                                    
                                    Button(action: {
                                        showingCreateForm = true
                                        loadAvailableColors()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: "plus")
                                                .font(.system(size: 12, weight: .medium))
                                            Text("New Tag")
                                                .font(GentleLightning.Typography.caption)
                                        }
                                        .foregroundColor(themeManager.isDarkMode ? GentleLightning.Colors.buttonBrightText : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(themeManager.isDarkMode ? GentleLightning.Colors.buttonBrightBackground : GentleLightning.Colors.accentNeutral)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(themeManager.isDarkMode ? Color.clear : Color.clear, lineWidth: 1)
                                        )
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                                
                                Divider()
                                    .background(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode).opacity(0.2))
                                    .padding(.horizontal, 24)
                            }
                            
                            // Tags grid
                            ScrollView {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                    ForEach(userCategories) { category in
                                        TagDisplayCard(category: category)
                                    }
                                }
                                .padding(.horizontal, 24)
                                .padding(.top, 20)
                            }
                            
                            if userCategories.isEmpty {
                                VStack(spacing: 16) {
                                    Spacer()
                                    
                                    Image(systemName: "tag")
                                        .font(.system(size: 48))
                                        .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode).opacity(0.6))
                                    
                                    VStack(spacing: 8) {
                                        Text("No tags yet")
                                            .font(GentleLightning.Typography.title)
                                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                        
                                        Text("Create your first tag to organize your notes")
                                            .font(GentleLightning.Typography.body)
                                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                            .multilineTextAlignment(.center)
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
        .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
        .onAppear {
            loadCategories()
        }
    }
    
    private func loadCategories() {
        isLoadingCategories = true
        Task {
            do {
                // Load categories without cleanup to preserve standalone tags
                let categories = try await CategoryService.shared.getUserCategories()
                await MainActor.run {
                    userCategories = categories
                    isLoadingCategories = false
                }
            } catch {
                await MainActor.run {
                    userCategories = []
                    isLoadingCategories = false
                }
            }
        }
    }
    
    private func loadAvailableColors() {
        Task {
            do {
                let colors = try await CategoryService.shared.getAvailableColors()
                await MainActor.run {
                    availableColors = colors.isEmpty ? CategoryService.availableColors : colors
                    selectedColorKey = availableColors.first?.key ?? ""
                }
            } catch {
                await MainActor.run {
                    availableColors = CategoryService.availableColors
                    selectedColorKey = availableColors.first?.key ?? ""
                }
            }
        }
    }
    
    private func createCategory(name: String, colorKey: String) {
        isLoading = true
        Task {
            do {
                let newCategory = try await CategoryService.shared.createCustomCategory(name: name, colorKey: colorKey)
                
                // Track category creation
                AnalyticsManager.shared.trackCategoryCreated(categoryName: name, colorKey: colorKey)
                
                await MainActor.run {
                    userCategories.append(newCategory)
                    
                    // Notify other views that categories have been updated
                    NotificationCenter.default.post(name: .categoriesUpdated, object: nil)
                    
                    // Reset form but stay in tags view
                    showingCreateForm = false
                    newCategoryName = ""
                    selectedColorKey = ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Tag Display Card (Read-only version for manage tags)
struct TagDisplayCard: View {
    let category: Category
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(category.uiColor)
                .frame(width: 12, height: 12)
                .overlay(
                    Circle()
                        .stroke(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode).opacity(0.2), lineWidth: 1)
                )
            
            // Category name
            Text(category.name)
                .font(GentleLightning.Typography.body)
                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                .lineLimit(1)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(GentleLightning.Colors.surfaceSecondary(isDark: themeManager.isDarkMode))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode).opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Account Drawer View
struct AccountDrawerView: View {
    @Binding var isPresented: Bool
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteError: String?
    @State private var showDeleteResult = false
    @State private var showManageTags = false
    @State private var showMoreActions = false
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
                VStack(spacing: 12) {
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
                        )
                        
                        // Group Notes by Tag Toggle
                        HStack {
                            Text("Group Notes by Tag")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            
                            Spacer()
                            
                            Toggle("", isOn: Binding(
                                get: { themeManager.groupNotesByTag },
                                set: { _ in themeManager.toggleGroupNotesByTag() }
                            ))
                            .tint(GentleLightning.Colors.accentNeutral)
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                        )
                        
                        // Manage Tags option
                        Button(action: {
                            showManageTags = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Manage Tags")
                                        .font(GentleLightning.Typography.body)
                                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                                }
                                
                                Spacer()
                                
                                Text("OPEN")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(themeManager.isDarkMode ? GentleLightning.Colors.textBlack : Color.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(themeManager.isDarkMode ? Color.white : Color.black)
                                    )
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                        )
                    }
                    
                    // Account actions
                    VStack(spacing: 16) {
                    // More Actions button
                    Button(action: {
                        showMoreActions = true
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("More Actions")
                                    .font(GentleLightning.Typography.body)
                                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(themeManager.isDarkMode ? Color.black : GentleLightning.Colors.surface)
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
                    .padding(.bottom, 60)
                }
                .padding(.horizontal, 20)
            }
        }
        .background(
            GentleLightning.Colors.background(isDark: themeManager.isDarkMode)
                .ignoresSafeArea(.all)
        )
        .overlay(
            // Add shadow only in dark mode
            Group {
                if themeManager.isDarkMode {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                        .shadow(
                            color: Color.white.opacity(0.1),
                            radius: 12,
                            x: 0,
                            y: -4
                        )
                        .allowsHitTesting(false)
                }
            }
        )
        .sheet(isPresented: $showManageTags) {
            ManageTagsView()
        }
        .actionSheet(isPresented: $showMoreActions) {
            ActionSheet(
                title: Text("More Actions"),
                buttons: [
                    .default(Text("Logout")) {
                        do {
                            try FirebaseManager.shared.signOut()
                        } catch {
                            print("Sign out error: \(error)")
                        }
                        isPresented = false
                    },
                    .destructive(Text("Delete Account")) {
                        showDeleteConfirmation = true
                    },
                    .cancel()
                ]
            )
        }
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
    @ObservedObject private var themeManager = ThemeManager.shared
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
        .opacity(isSearchExpanded ? 0 : 1) // Hide when search is expanded
        .scaleEffect(isSearchExpanded ? 0.95 : 1.0) // Subtle scale effect
        .animation(GentleLightning.Animation.silky, value: isSearchExpanded)
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
            itemsListContent
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
        } else if searchResults.isEmpty && hasSearched {
            // No search results found (either from search or category filter)
            VStack(spacing: 12) {
                Text("No results found")
                    .font(GentleLightning.Typography.subtitle)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                
                Text(searchText.isEmpty ? "No notes match the selected category" : "Try a different search term")
                    .font(GentleLightning.Typography.secondary)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .padding(.top, 20)
        } else {
            // Search results list - use different styling based on whether it's actual search vs showing all notes
            let hasSearchText = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            
            ScrollView {
                LazyVStack(spacing: hasSearchText ? 8 : 12) {
                    ForEach(searchResults, id: \.firebaseId) { result in
                        if hasSearchText {
                            // When there's search text, show SearchResultRow with relevance scores
                            SearchResultRow(
                                result: result,
                                searchText: searchText,
                                onTap: {
                                    handleSearchResultTap(result)
                                }
                            )
                            .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                        } else {
                            // When showing all notes (category filter or no filter), use main app styling
                            if let item = dataManager.items.first(where: { $0.firebaseId == result.firebaseId || $0.id == result.firebaseId }) {
                                ItemRowSimple(item: item, dataManager: dataManager) {
                                    handleSearchResultTap(result)
                                }
                                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                            }
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }
    
    @ViewBuilder
    private var mainNotesListView: some View {
        let _ = print("📋 MainNotesListView: Evaluating with groupNotesByTag = \(themeManager.groupNotesByTag)")
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
            // Conditional notes list - grouped or regular based on setting
            let _ = print("🔄 ContentView: Evaluating conditional view with groupNotesByTag = \(themeManager.groupNotesByTag)")
            ScrollView {
                if themeManager.groupNotesByTag {
                    // Show grouped notes view
                    let _ = print("📋 ContentView: Showing grouped notes view (groupNotesByTag = \(themeManager.groupNotesByTag))")
                    GroupedNotesView(
                        items: Array(dataManager.items.prefix(displayedItemsCount)),
                        categories: dataManager.categories,
                        dataManager: dataManager,
                        onItemTap: { item in
                            // Navigate without animation to prevent list wobbling
                            navigationPath.append(item)
                        },
                        themeManager: themeManager
                    )
                    .padding(.top, 8)
                } else {
                    // Show regular notes list
                    let _ = print("📋 ContentView: Showing regular notes list (groupNotesByTag = \(themeManager.groupNotesByTag))")
                    LazyVStack(spacing: 12) {
                        ForEach(Array(dataManager.items.prefix(displayedItemsCount).enumerated()), id: \.element.id) { index, item in
                            ItemRowSimple(item: item, dataManager: dataManager) {
                                // Navigate without animation to prevent list wobbling
                                navigationPath.append(item)
                            }
                            .padding(.horizontal, GentleLightning.Layout.Padding.xl)
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
            }
            .onTapGesture {
                // Also dismiss keyboard when tapping in scroll area
                if isInputFieldFocused {
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
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
            .opacity(isSearchExpanded ? 0.0 : 1.0) // Completely hide main content when search is expanded
            .scaleEffect(isSearchExpanded ? 0.92 : 1.0) // Subtle scale down effect
            .offset(y: isSearchExpanded ? -120 : 0) // Slide content up when search is expanded
            .blur(radius: isSearchExpanded ? 2 : 0) // Subtle blur effect when hidden
            .animation(GentleLightning.Animation.swoosh, value: isSearchExpanded)
            
            // UNIFIED Search System - single SearchBarView with results below in proper VStack
            VStack(spacing: 0) {
                if isSearchExpanded {
                    // Search bar at top
                    HStack {
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
                            onReindex: triggerReindexing,
                            categories: dataManager.categories,
                            selectedCategoryId: $dataManager.selectedCategoryFilter
                        )
                        .id("unique-search-bar") // Unique ID since this is the only SearchBarView instance
                        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                        .padding(.top, 16)
                        .onAppear {
                            print("🔍 ContentView: ONLY SearchBarView instance shown in EXPANDED mode")
                        }
                    }
                    .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
                    
                    // Search results content BELOW the search bar
                    ScrollView {
                        searchResultsView
                            .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                    }
                    .background(
                        // Solid background to prevent transparency issues
                        Rectangle()
                            .fill(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
                            .ignoresSafeArea(.all)
                    )
                }
                
                Spacer()
            }
            .animation(GentleLightning.Animation.swoosh, value: isSearchExpanded)
            
            // Floating options button overlay - anchored to bottom like original
            VStack {
                Spacer()
                
                Button(action: {
                    AnalyticsManager.shared.trackAccountDrawerOpened()
                    showingAccountDrawer = true
                }) {
                    Text("...")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                        .frame(width: 120, height: 100) // Increased from 100x80 to 120x100
                        .multilineTextAlignment(.center)
                        .contentShape(Rectangle()) // Ensure entire frame area is tappable
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.horizontal, 20) // Add extra padding for larger tap area
                .padding(.bottom, 10) // Add bottom padding for easier thumb reach
            }
            .opacity(isSearchExpanded ? 0 : 1) // Hide when search is expanded
            .scaleEffect(isSearchExpanded ? 0.9 : 1.0) // Subtle scale effect
            .offset(y: isSearchExpanded ? 20 : 0) // Slide down when hiding
            .animation(GentleLightning.Animation.silky, value: isSearchExpanded)
            #if os(iOS)
            .ignoresSafeArea(.keyboard, edges: .bottom) // Hide when keyboard appears - iOS only
            #endif
            .dismissKeyboardOnDrag()
        }
    }
    
    @ViewBuilder
    private var inputFieldSection: some View {
        // Input Field - positioned lower on screen
        InputField(text: $viewModel.inputText, 
                  placeholder: isSearchExpanded ? "" : viewModel.placeholderText, // Hide placeholder when search is expanded
                  dataManager: dataManager,
                  onCommit: {
            // No automatic saving - users must use the SAVE button
            // Just dismiss keyboard when pressing return
            #if os(iOS)
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            #endif
        },
                  isFieldFocused: $isInputFieldFocused,
                  hideMicrophone: isSearchExpanded, // Hide microphone when search is expanded
                  isSearchExpanded: isSearchExpanded) // Pass search state to InputField
        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
    }
    
    @ViewBuilder
    private var notesSectionHeader: some View {
        // My Notes header with search button aligned on same line
        HStack {
            Text("My Notes")
                .font(GentleLightning.Typography.caption)
                .foregroundColor(GentleLightning.Colors.textBlack)
                .padding(.leading, GentleLightning.Layout.Padding.xl + GentleLightning.Layout.Padding.lg)
            
            Spacer()
            
            // Simple search magnifying glass button - only show when search is collapsed
            if !isSearchExpanded {
                Button(action: {
                    print("🔍 ContentView: Search button tapped - expanding search")
                    AnalyticsManager.shared.trackSearchInitiated()
                    withAnimation(GentleLightning.Animation.delightful) {
                        isSearchExpanded = true
                    }
                    // Show all notes when search is first opened
                    showAllNotes()
                    // Focus the search field after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isSearchFieldFocused = true
                    }
                }) {
                    Image(systemName: GentleLightning.Icons.search)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                        .frame(width: 44, height: 44)
                        .background(Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.trailing, GentleLightning.Layout.Alignment.searchToMicrophoneTrailing) // Center-align with microphone icon - see design system for calculation
                .onAppear {
                    print("🔍 ContentView: Showing simple search button inline with 'My Notes' header")
                }
            }
        }
        .opacity(isSearchExpanded ? 0 : 1) // Hide when search is expanded
        .scaleEffect(isSearchExpanded ? 0.95 : 1.0) // Subtle scale effect
        .offset(y: isSearchExpanded ? -10 : 0) // Slide up when hiding
        .animation(GentleLightning.Animation.silky, value: isSearchExpanded)
        .padding(.top, 16)
        .padding(.bottom, 8)
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
        
        ZStack {
            ScrollView {
                itemsListContent
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            .simultaneousGesture(
                DragGesture()
                    .onChanged { gesture in
                        // Dismiss keyboard immediately when scrolling starts (iOS only)
                        if abs(gesture.translation.height) > 10 && isInputFieldFocused {
                            #if os(iOS)
                            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                            #endif
                        }
                    }
            )
            .onTapGesture {
                // Also dismiss keyboard when tapping in scroll area (iOS only)
                if isInputFieldFocused {
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
                }
            }
            .buttonStyle(PlainButtonStyle())
            .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
            
            // Gradient overlay for floating button area
            VStack {
                Spacer()
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        GentleLightning.Colors.background(isDark: themeManager.isDarkMode).opacity(0),
                        GentleLightning.Colors.background(isDark: themeManager.isDarkMode).opacity(0.3),
                        GentleLightning.Colors.background(isDark: themeManager.isDarkMode).opacity(0.7)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                .allowsHitTesting(false)
            }
            .opacity(isSearchExpanded ? 0 : 1)
            .animation(GentleLightning.Animation.silky, value: isSearchExpanded)
        }
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
        .padding(.bottom, 140) // Extra padding for floating button area
        .background(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
    }
    
    @ViewBuilder
    private var mainNotesListContent: some View {
        let _ = print("📋 MainNotesListContent: Evaluating with groupNotesByTag = \(themeManager.groupNotesByTag)")
        
        // Conditional notes list - grouped or regular based on setting
        if themeManager.groupNotesByTag {
            // Show grouped notes view
            let _ = print("📋 ContentView: Showing grouped notes view (groupNotesByTag = \(themeManager.groupNotesByTag))")
            GroupedNotesView(
                items: Array(dataManager.filteredItems.prefix(displayedItemsCount)),
                categories: dataManager.categories,
                dataManager: dataManager,
                onItemTap: { item in
                    AnalyticsManager.shared.trackNoteEditOpened(noteId: item.id)
                    navigationPath.append(item)
                    print("✅ ContentView: Navigation pushed for item.id = '\(item.id)'")
                },
                themeManager: themeManager
            )
        } else {
            // Show regular notes list
            let _ = print("📋 ContentView: Showing regular notes list (groupNotesByTag = \(themeManager.groupNotesByTag))")
            let itemsToDisplay = Array(dataManager.filteredItems.prefix(displayedItemsCount))
            
            ForEach(itemsToDisplay) { item in
                ItemRowSimple(item: item, dataManager: dataManager) {
                    AnalyticsManager.shared.trackNoteEditOpened(noteId: item.id)
                    
                    // Use navigation instead of sheets - bulletproof approach
                    navigationPath.append(item)
                    
                    print("✅ ContentView: Navigation pushed for item.id = '\(item.id)'")
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .top)).combined(with: .scale(scale: 0.95)),
                    removal: .opacity.combined(with: .move(edge: .bottom)).combined(with: .scale(scale: 0.95))
                ))
                .animation(GentleLightning.Animation.delightful, value: item.id)
                .onAppear {
                    // Load more items when reaching the last item
                    if item.id == dataManager.filteredItems.last?.id && displayedItemsCount < dataManager.filteredItems.count {
                        withAnimation(GentleLightning.Animation.gentle) {
                            displayedItemsCount = min(displayedItemsCount + 10, dataManager.filteredItems.count)
                        }
                    }
                }
            }
            
            // Loading indicator
            if displayedItemsCount < dataManager.filteredItems.count {
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

    var body: some View {
        let _ = print("🔄 MAIN ContentView.body: Rendering with groupNotesByTag = \(themeManager.groupNotesByTag)")
        NavigationStack(path: $navigationPath) {
            ZStack {
                mainContent
            }
            .background(GentleLightning.Colors.background(isDark: themeManager.isDarkMode))
            .contentShape(Rectangle()) // Make the entire area tappable for keyboard dismissal
            .onTapGesture {
                // Dismiss keyboard when tapping outside input area
                #if os(iOS)
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
            .onChange(of: isSearchExpanded) { newValue in
                if newValue {
                    // When search expands, clear focus from main input field
                    isInputFieldFocused = false
                } else {
                    // When search collapses, return focus to main input field
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isInputFieldFocused = true
                    }
                }
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
            displayedItemsCount = min(10, dataManager.filteredItems.count)
        }
        .onChange(of: dataManager.selectedCategoryFilter) { _ in
            // Reset pagination when filter changes
            displayedItemsCount = min(10, dataManager.filteredItems.count)
            // Refresh search results if search is expanded
            if isSearchExpanded {
                performSearch()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusInputField)) { _ in
            // Handle widget deep link - focus InputField and collapse search if expanded
            print("📱 ContentView: Widget deep link detected - focusing InputField")
            
            // If search is expanded, collapse it first
            if isSearchExpanded {
                withAnimation(GentleLightning.Animation.delightful) {
                    isSearchExpanded = false
                }
                // Focus InputField after search collapses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    isInputFieldFocused = true
                }
            } else {
                // Focus InputField immediately if search is not expanded
                isInputFieldFocused = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .categoriesUpdated)) { _ in
            // Handle category updates - reload categories for search
            print("📱 ContentView: Categories updated - reloading for search")
            dataManager.loadCategories()
        }
        } // NavigationStack
    
    private func loadMoreItems() {
        // Add a small delay to simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                displayedItemsCount = min(displayedItemsCount + itemsPerPage, dataManager.filteredItems.count)
            }
        }
    }
    
    private func performSearch() {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // If no search text AND no category filter, show all notes by default
        if trimmedSearchText.isEmpty && dataManager.selectedCategoryFilter == nil {
            showAllNotes()
            return
        }
        
        // If no search text but category filter is active, show filtered notes
        if trimmedSearchText.isEmpty {
            showAllNotes()
            return
        }
        
        isSearching = true
        
        Task { @MainActor in
            do {
                let results = try await VectorSearchService.shared.semanticSearch(
                    query: trimmedSearchText,
                    limit: 20
                )
                
                // Apply category filter if one is selected
                let filteredResults: [SearchResult]
                if let selectedCategoryId = dataManager.selectedCategoryFilter {
                    // Filter search results by category
                    filteredResults = results.filter { result in
                        // Find the corresponding item and check its categories
                        if let item = dataManager.items.first(where: { $0.firebaseId == result.firebaseId }) {
                            return item.categoryIds.contains(selectedCategoryId)
                        }
                        return false
                    }
                } else {
                    filteredResults = results
                }
                
                searchResults = filteredResults
                hasSearched = true
                isSearching = false
                
                // Track search analytics (with category filter info)
                AnalyticsManager.shared.trackSearch(query: trimmedSearchText, resultCount: filteredResults.count)
                if dataManager.selectedCategoryFilter != nil {
                    AnalyticsManager.shared.trackEvent("search_with_category_filter")
                }
            } catch {
                print("Search failed: \(error)")
                hasSearched = true
                isSearching = false
                // Could show error state here
            }
        }
    }
    
    private func showAllNotes() {
        // Convert all notes to SearchResult format, sorted by created date
        let allItems = dataManager.items.sorted { (item1: SparkItem, item2: SparkItem) in
            item1.createdAt > item2.createdAt
        }
        
        // Apply category filter if one is selected
        let filteredItems: [SparkItem]
        if let selectedCategoryId = dataManager.selectedCategoryFilter {
            filteredItems = allItems.filter { item in
                item.categoryIds.contains(selectedCategoryId)
            }
        } else {
            filteredItems = allItems
        }
        
        // Convert to SearchResult format
        searchResults = filteredItems.map { item in
            SearchResult(
                firebaseId: item.firebaseId ?? item.id,
                title: item.title,
                content: item.content,
                similarity: 1.0, // Max similarity since we're showing all
                isTask: item.isTask,
                categories: item.categoryIds,
                createdAt: item.createdAt
            )
        }
        
        hasSearched = true
        isSearching = false
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
        if let item = dataManager.items.first(where: { $0.firebaseId == result.firebaseId }) {
            // Clear search state and collapse search to ensure back button returns to main view
            // This provides better UX - users expect to return to main view, not search results
            withAnimation(GentleLightning.Animation.swoosh) {
                isSearchExpanded = false
            }
            
            // Clear search state so back navigation goes to main view
            searchText = ""
            searchResults = []
            hasSearched = false
            searchTask?.cancel()
            searchTask = nil
            
            // Clear navigation path to ensure clean navigation stack
            navigationPath = NavigationPath()
            
            // Small delay to let the search collapse animation complete before navigation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                navigationPath.append(item)
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
                    #if os(iOS)
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    #endif
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

// MARK: - Tag Filter Pills View with Parallax Animations
struct TagFilterPillsView: View {
    let categories: [Category]
    @Binding var selectedCategoryId: String?
    @Binding var isSearchExpanded: Bool
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        if isSearchExpanded && !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Category pills with staggered animations
                    ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                        TagPill(
                            name: category.name,
                            color: category.color,
                            isSelected: selectedCategoryId == category.id,
                            onTap: {
                                withAnimation(GentleLightning.Animation.delightful) {
                                    selectedCategoryId = selectedCategoryId == category.id ? nil : category.id
                                }
                            }
                        )
                        .scaleEffect(isSearchExpanded ? 1.0 : 0.8)
                        .opacity(isSearchExpanded ? 1.0 : 0.0)
                        .offset(y: isSearchExpanded ? 0 : -10)
                        .blur(radius: isSearchExpanded ? 0 : 1)
                        .animation(
                            GentleLightning.Animation.delightful
                                .delay(Double(index) * 0.08), // Staggered parallax entrance
                            value: isSearchExpanded
                        )
                    }
                }
                .padding(.horizontal, 16) // Increased padding to preserve pill borders
                .padding(.vertical, 4) // Add vertical padding to prevent border clipping
            }
            // Enhanced container transition with parallax effects
            .scaleEffect(isSearchExpanded ? 1.0 : 0.95)
            .opacity(isSearchExpanded ? 1.0 : 0.0)
            .offset(y: isSearchExpanded ? 0 : -15)
            .animation(GentleLightning.Animation.delightful.delay(0.1), value: isSearchExpanded)
            // Fade-out mask for smooth edge transitions (preserves pill borders)
            .mask(
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.02),
                        .init(color: .black, location: 0.98),
                        .init(color: .clear, location: 1)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
        }
    }
}

// MARK: - Individual Tag Pill
struct TagPill: View {
    let name: String
    let color: String
    let isSelected: Bool
    let onTap: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    private var pillColor: Color {
        Color(hex: color) ?? GentleLightning.Colors.accentNeutral
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                // Enhanced color dot with delightful animations
                Circle()
                    .fill(pillColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isSelected ? 1.3 : 1.0)
                    .rotationEffect(.degrees(isSelected ? 180 : 0))
                    .brightness(isSelected ? 0.1 : 0)
                    .animation(GentleLightning.Animation.delightful, value: isSelected)
                
                // Enhanced tag name with smooth typography transitions
                Text(name)
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(
                        isSelected 
                            ? GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode)
                            : GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode)
                    )
                    .fontWeight(isSelected ? .medium : .regular)
                    .scaleEffect(isSelected ? 1.02 : 1.0)
                    .animation(GentleLightning.Animation.silky, value: isSelected)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(
                        isSelected
                            ? pillColor.opacity(0.15)
                            : GentleLightning.Colors.surface(isDark: themeManager.isDarkMode)
                    )
                    .overlay(
                        Capsule()
                            .stroke(
                                isSelected
                                    ? pillColor.opacity(0.3)
                                    : GentleLightning.Colors.border(isDark: themeManager.isDarkMode),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                            .scaleEffect(isSelected ? 1.02 : 1.0)
                            .animation(GentleLightning.Animation.delightful.delay(0.05), value: isSelected)
                    )
                    .shadow(
                        color: isSelected ? pillColor.opacity(0.2) : .clear,
                        radius: isSelected ? 8 : 0,
                        x: 0,
                        y: isSelected ? 2 : 0
                    )
            )
            .scaleEffect(isSelected ? 1.08 : 1.0)
            .animation(GentleLightning.Animation.delightful, value: isSelected)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Color Extension for Hex Support
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

extension ContentView {
    // MARK: - Search View Management
    // Note: Using direct SearchBarView instances with .id("main-search-bar") 
    // to ensure SwiftUI treats them as the same view and prevents multiple instances
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
    
    // Category filtering support
    let categories: [Category]
    @Binding var selectedCategoryId: String?
    
    @EnvironmentObject var themeManager: ThemeManager
    
    // Debug identifier to track multiple instances
    private let instanceId = UUID().uuidString.prefix(8)
    
    init(
        isExpanded: Binding<Bool>,
        searchText: Binding<String>,
        searchResults: Binding<[SearchResult]>,
        isSearching: Binding<Bool>,
        searchTask: Binding<Task<Void, Never>?>,
        hasSearched: Binding<Bool>,
        isSearchFieldFocused: FocusState<Bool>.Binding,
        onResultTap: @escaping (SearchResult) -> Void,
        onSearch: @escaping () -> Void,
        onReindex: @escaping () -> Void,
        categories: [Category],
        selectedCategoryId: Binding<String?>
    ) {
        self._isExpanded = isExpanded
        self._searchText = searchText
        self._searchResults = searchResults
        self._isSearching = isSearching
        self._searchTask = searchTask
        self._hasSearched = hasSearched
        self.isSearchFieldFocused = isSearchFieldFocused
        self.onResultTap = onResultTap
        self.onSearch = onSearch
        self.onReindex = onReindex
        self.categories = categories
        self._selectedCategoryId = selectedCategoryId
        
        print("🔍 SearchBarView: CREATED new instance \(instanceId)")
    }
    
    var body: some View {
        let _ = print("🔍 SearchBarView \(instanceId): Rendering body with isExpanded = \(isExpanded)")
        VStack(alignment: .trailing, spacing: 8) {
            // Horizontal search bar with magnifying glass
            HStack(alignment: .center) {
                // Search input field - slides in from the right when expanded
                if isExpanded {
                    HStack {
                        Image(systemName: GentleLightning.Icons.search)
                            .font(.system(size: 16))
                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                        
                        TextField("Search your notes...", text: $searchText)
                            .font(GentleLightning.Typography.body)
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            .accentColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            .focused(isSearchFieldFocused)
                            .onSubmit {
                                print("🔍 SearchBarView \(instanceId): TextField onSubmit triggered")
                                onSearch()
                            }
                            .onChange(of: isSearchFieldFocused.wrappedValue) { isFocused in
                                print("🔍 SearchBarView \(instanceId): Focus changed to \(isFocused)")
                                if !isFocused && isExpanded {
                                    print("⚠️ SearchBarView \(instanceId): Field lost focus while expanded - this might indicate a focus conflict")
                                }
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
                                    // Always show all notes (filtered by tag if one is selected) when search text is empty
                                    onSearch()
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
                    .padding(8)
                    .background(GentleLightning.Colors.searchInputBackground(isDark: themeManager.isDarkMode))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(GentleLightning.Colors.border(isDark: themeManager.isDarkMode), lineWidth: 1)
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
                        print("🔍 SearchBarView: COLLAPSING search - setting isExpanded = false")
                        withAnimation(GentleLightning.Animation.swoosh) {
                            isExpanded = false
                        }
                        // Clear all search parameters when collapsing
                        print("🔍 SearchBarView: Clearing search state and results")
                        searchText = ""
                        searchResults = []
                        hasSearched = false
                        searchTask?.cancel()
                        searchTask = nil
                        print("🔍 SearchBarView \(instanceId): Setting isSearchFieldFocused = false")
                        isSearchFieldFocused.wrappedValue = false
                        // Clear category filter to return to showing all notes
                        selectedCategoryId = nil
                    } else {
                        // Expanding search
                        print("🔍 SearchBarView \(instanceId): EXPANDING search - setting isExpanded = true")
                        withAnimation(GentleLightning.Animation.swoosh) {
                            isExpanded = true
                        }
                        // Focus immediately for better UX - user can start typing right away
                        print("🔍 SearchBarView \(instanceId): Setting isSearchFieldFocused = true")
                        isSearchFieldFocused.wrappedValue = true
                        // Show all notes when search is first opened (default state)
                        print("🔍 SearchBarView \(instanceId): Calling onSearch() to load initial results")
                        onSearch()
                    }
                }) {
                    ZStack {
                        // Magnifying glass icon
                        Image(systemName: GentleLightning.Icons.search)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            .scaleEffect(isExpanded ? 0.0 : 1.0)
                            .opacity(isExpanded ? 0.0 : 1.0)
                            .rotationEffect(.degrees(isExpanded ? -180 : 0)) // Opposite rotation to the X mark
                            .blur(radius: isExpanded ? 2 : 0)
                            .animation(GentleLightning.Animation.swoosh.delay(isExpanded ? 0 : 0.15), value: isExpanded)
                        
                        // X mark icon
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(themeManager.isDarkMode ? Color.black : Color.white)
                            .scaleEffect(isExpanded ? 1.0 : 0.0)
                            .opacity(isExpanded ? 1.0 : 0.0)
                            .rotationEffect(.degrees(isExpanded ? 0 : 180)) // Reverse rotation direction for smoother collapse
                            .blur(radius: isExpanded ? 0 : 2)
                            .animation(GentleLightning.Animation.swoosh.delay(isExpanded ? 0.15 : 0), value: isExpanded)
                    }
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 44, height: 44) // Increase tap target to Apple's recommended 44pt minimum
                .background(
                    Circle()
                        .fill(themeManager.isDarkMode ? Color.white : Color.black)
                        .overlay(
                            Circle()
                                .stroke(themeManager.isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.1), lineWidth: 1)
                        )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 4, x: 0, y: 2)
                .contentShape(Circle()) // Make entire circle tappable
            }
            
            // Tag filter pills shown when search is expanded
            TagFilterPillsView(
                categories: categories,
                selectedCategoryId: $selectedCategoryId,
                isSearchExpanded: $isExpanded
            )
            
        }
        .frame(maxWidth: .infinity, alignment: .trailing) // Ensure consistent positioning and prevent floating
    }
}

// MARK: - Search Result Row
struct SearchResultRow: View {
    let result: SearchResult
    let searchText: String
    let onTap: () -> Void
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    // Title and content using shared design system component
                    NoteDisplayContent(
                        title: result.title,
                        content: result.previewContent,
                        isDarkMode: themeManager.isDarkMode
                    )
                    
                    HStack(spacing: 8) {
                        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(result.confidencePercentage)% match")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                        }
                        
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
                    .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
            }
            .padding(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Grouped Notes View
struct GroupedNotesView: View {
    let items: [SparkItem]
    let categories: [Category]
    let dataManager: FirebaseDataManager
    let onItemTap: (SparkItem) -> Void
    @ObservedObject var themeManager: ThemeManager
    @State private var expandedSections: Set<String> = []
    
    private var groupedItems: [(String, String, [SparkItem])] {
        print("🏷️ GroupedNotesView: Computing groupedItems with \(items.count) items")
        var groups: [String: [SparkItem]] = [:]
        var categoryInfo: [String: (String, String)] = [:] // categoryId -> (name, color)
        
        // Create category lookup
        for category in categories {
            categoryInfo[category.id] = (category.name, category.color)
        }
        
        // Group items by categories
        for item in items {
            if item.categoryIds.isEmpty {
                // No tag group
                groups["no_tag", default: []].append(item)
            } else {
                // Add to each category the item belongs to
                for categoryId in item.categoryIds {
                    groups[categoryId, default: []].append(item)
                }
            }
        }
        
        // Convert to sorted array with category info
        var result: [(String, String, [SparkItem])] = []
        
        // Add "No Tag" section first if it exists
        if let noTagItems = groups["no_tag"] {
            result.append(("no_tag", "No Tag", noTagItems.sorted { $0.createdAt > $1.createdAt }))
        }
        
        // Add category sections sorted by category name
        for categoryId in groups.keys.sorted() {
            guard categoryId != "no_tag", let items = groups[categoryId] else { continue }
            let categoryName = categoryInfo[categoryId]?.0 ?? "Unknown Tag"
            result.append((categoryId, categoryName, items.sorted { $0.createdAt > $1.createdAt }))
        }
        
        return result
    }
    
    var body: some View {
        let _ = print("🏷️ GroupedNotesView: Rendering grouped view with \(groupedItems.count) sections")
        LazyVStack(spacing: 16) {
            ForEach(groupedItems, id: \.0) { categoryId, categoryName, categoryItems in
                VStack(spacing: 8) {
                    // Section header
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            if expandedSections.contains(categoryId) {
                                expandedSections.remove(categoryId)
                            } else {
                                expandedSections.insert(categoryId)
                            }
                        }
                    }) {
                        HStack {
                            // Category indicator
                            if categoryId == "no_tag" {
                                Circle()
                                    .fill(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                    .frame(width: 8, height: 8)
                            } else if let category = categories.first(where: { $0.id == categoryId }) {
                                Circle()
                                    .fill(category.uiColor)
                                    .frame(width: 8, height: 8)
                            }
                            
                            Text(categoryName)
                                .font(GentleLightning.Typography.heading)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
                            
                            Text("(\(categoryItems.count))")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                            
                            Spacer()
                            
                            Image(systemName: expandedSections.contains(categoryId) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textSecondary(isDark: themeManager.isDarkMode))
                                .rotationEffect(.degrees(expandedSections.contains(categoryId) ? 0 : -90))
                                .animation(.easeInOut(duration: 0.2), value: expandedSections.contains(categoryId))
                        }
                        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(GentleLightning.Colors.surface(isDark: themeManager.isDarkMode))
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Section content
                    if expandedSections.contains(categoryId) {
                        VStack(spacing: 12) {
                            ForEach(categoryItems) { item in
                                ItemRowSimple(item: item, dataManager: dataManager) {
                                    onItemTap(item)
                                }
                                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                            }
                        }
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity.combined(with: .move(edge: .top))
                        ))
                    }
                }
            }
        }
        .onAppear {
            // Expand all sections by default
            expandedSections = Set(groupedItems.map { $0.0 })
        }
    }
}


// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}