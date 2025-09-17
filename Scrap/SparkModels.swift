import Foundation
import SwiftUI
import FirebaseFirestore
import UIKit

// MARK: - Spark Item (Main Note Model)
class SparkItem: ObservableObject, Identifiable, Hashable {
    let id: String
    @Published var content: String
    @Published var title: String
    @Published var categoryIds: [String]
    @Published var isTask: Bool
    @Published var isCompleted: Bool
    let createdAt: Date
    var firebaseId: String?
    var rtfData: Data? // Stored RTF data for rich text formatting
    
    init(content: String, title: String = "", categoryIds: [String] = [], isTask: Bool = false, id: String = UUID().uuidString) {
        self.id = id
        self.content = content
        self.title = title
        self.categoryIds = categoryIds
        self.isTask = isTask
        self.isCompleted = false
        self.createdAt = Date()
    }
    
    init(from firebaseNote: FirebaseNote) {
        self.id = firebaseNote.id ?? UUID().uuidString
        self.title = firebaseNote.title ?? ""
        self.categoryIds = firebaseNote.categoryIds ?? []
        self.isTask = firebaseNote.isTask
        self.isCompleted = false
        self.createdAt = firebaseNote.createdAt
        self.firebaseId = firebaseNote.id
        
        // Always preserve RTF data - content should maintain formatting
        if let base64RTF = firebaseNote.rtfContent,
           let rtfData = Data(base64Encoded: base64RTF) {
            
            // For content display, extract plain text only for title bar purposes
            // The actual rich content will be handled by the RTF editor
            do {
                // Debug: First decode the RTF data to see what we're actually storing
                print("🔍 SparkItem.init: Loading RTF data from Firebase, size: \(rtfData.count) bytes")
                if let rtfString = String(data: rtfData, encoding: .utf8) {
                    print("🔍 SparkItem.init: Raw RTF data contains: \(rtfString.prefix(500))")
                } else {
                    print("🔍 SparkItem.init: RTF data is not UTF-8 encoded")
                }
                
                let loadedAttributedString = try NSAttributedString(
                    data: rtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                
                // Debug: Print what was actually loaded from RTF
                print("🔍 SparkItem.init: Loaded from RTF - content: '\(loadedAttributedString.string)'")
                print("🔍 SparkItem.init: Loaded from RTF - length: \(loadedAttributedString.length)")
                
                // Debug: Check for specific checkbox patterns in the loaded content
                let content = loadedAttributedString.string
                if content.contains("<CHECKED>") {
                    print("🔍 SparkItem.init: Found checked ASCII marker <CHECKED> in loaded content")
                }
                if content.contains("<UNCHECKED>") {
                    print("🔍 SparkItem.init: Found unchecked ASCII marker <UNCHECKED> in loaded content")
                }
                if content.contains("(CHECKED)") {
                    print("🔍 SparkItem.init: Found checked ASCII marker (CHECKED) in loaded content")
                }
                if content.contains("(UNCHECKED)") {
                    print("🔍 SparkItem.init: Found unchecked ASCII marker (UNCHECKED) in loaded content")
                }
                if content.contains("[CHECKED]") {
                    print("🔍 SparkItem.init: Found checked ASCII marker [CHECKED] in loaded content")
                }
                if content.contains("[UNCHECKED]") {
                    print("🔍 SparkItem.init: Found unchecked ASCII marker [UNCHECKED] in loaded content")
                }
                if content.contains("✓") {
                    print("🔍 SparkItem.init: Found checkmark character ✓ in loaded content")
                }
                if content.contains("[ ]") {
                    print("🔍 SparkItem.init: Found unchecked pattern [ ] in loaded content")
                }
                if content.contains("[✓]") {
                    print("🔍 SparkItem.init: Found checked pattern [✓] in loaded content")
                }
                
                // Convert system fonts back to SpaceGrotesk fonts while preserving formatting
                let convertedAttributedString = SparkItem.prepareForDisplay(loadedAttributedString)
                
                // Re-generate RTF data with SpaceGrotesk fonts for proper display
                let convertedRTFData = try convertedAttributedString.data(
                    from: NSRange(location: 0, length: convertedAttributedString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                self.rtfData = convertedRTFData
                
                self.content = loadedAttributedString.string // Plain text for title bar only
            } catch {
                print("❌ SparkItem init: Failed to load RTF, using Firebase content: \(error)")
                // Fallback to Firebase content if RTF extraction fails
                self.content = firebaseNote.content
                self.rtfData = nil
            }
        } else {
            // No RTF data available - create RTF from plain content
            self.content = firebaseNote.content
            
            // Convert plain content to RTF format with default styling
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16),
                .foregroundColor: UIColor.label
            ]
            let attributedString = NSAttributedString(string: firebaseNote.content, attributes: attributes)
            
            do {
                // Use trait preservation method for RTF generation
                let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedString)
                let rtfData = try rtfCompatibleString.data(
                    from: NSRange(location: 0, length: rtfCompatibleString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                self.rtfData = rtfData
            } catch {
                print("❌ SparkItem init: Failed to create RTF from plain content: \(error)")
                self.rtfData = nil
            }
        }
    }
    
    var displayTitle: String {
        title.isEmpty ? (content.isEmpty ? "Untitled Note" : String(content.prefix(30))) : title
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SparkItem, rhs: SparkItem) -> Bool {
        lhs.id == rhs.id
    }
    
    // MARK: - RTF Font Trait Preservation
    
    /// Ensure font size is safe (not NaN, infinite, or too small/large)
    private static func safeFontSize(_ size: CGFloat) -> CGFloat {
        // Check for NaN, infinity, or invalid values
        guard size.isFinite && size > 0 else {
            print("⚠️ SparkItem: Invalid font size \(size), using default 17")
            return 17.0 // Default font size
        }
        
        // Clamp to reasonable bounds
        let minSize: CGFloat = 8.0
        let maxSize: CGFloat = 72.0
        return max(minSize, min(maxSize, size))
    }
    
    // Prepare attributed string for RTF saving by ensuring system fonts with proper traits
    static func prepareForRTFSave(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        // First, convert NSTextAttachment checkboxes to Unicode characters for RTF persistence
        print("🔧 SparkItem.prepareForRTFSave: Converting checkboxes to Unicode before RTF save")
        let processedString = CheckboxManager.convertAttachmentsToUnicodeCheckboxes(mutableString)
        let finalMutableString = NSMutableAttributedString(attributedString: processedString)
        print("🔧 SparkItem.prepareForRTFSave: Checkbox conversion complete")
        
        // Debug: Print what we're about to save
        print("🔍 SparkItem.prepareForRTFSave: Final string content: '\(finalMutableString.string)'")
        let checkboxChars = ["<UNCHECKED>", "<CHECKED>", "(UNCHECKED)", "(CHECKED)", "[UNCHECKED]", "[CHECKED]", "[ ]", "[✓]"]
        for char in checkboxChars {
            let count = finalMutableString.string.components(separatedBy: char).count - 1
            if count > 0 {
                print("🔍 SparkItem.prepareForRTFSave: Converted string contains \(count) instances of '\(char)'")
            }
        }
        
        // Debug: Check for any NSTextAttachment objects that might still be present
        finalMutableString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: finalMutableString.length), options: []) { value, range, _ in
            if let attachment = value {
                print("⚠️ SparkItem.prepareForRTFSave: Still found attachment at range \(range): \(type(of: attachment))")
                if let checkboxAttachment = attachment as? CheckboxTextAttachment {
                    print("⚠️ SparkItem.prepareForRTFSave: Attachment is CheckboxTextAttachment (checked: \(checkboxAttachment.isChecked))")
                }
            }
        }
        
        // Debug: Test RTF round-trip conversion to see what gets preserved
        if finalMutableString.string.contains("<CHECKED>") || finalMutableString.string.contains("<UNCHECKED>") || finalMutableString.string.contains("(CHECKED)") || finalMutableString.string.contains("(UNCHECKED)") || finalMutableString.string.contains("[CHECKED]") || finalMutableString.string.contains("[UNCHECKED]") {
            do {
                let testRTFData = try finalMutableString.data(
                    from: NSRange(location: 0, length: finalMutableString.length),
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
                )
                
                // Now try to read it back
                let restoredAttributedString = try NSAttributedString(
                    data: testRTFData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                
                print("🔍 SparkItem.prepareForRTFSave: RTF round-trip test - original: '\(finalMutableString.string)'")
                print("🔍 SparkItem.prepareForRTFSave: RTF round-trip test - restored: '\(restoredAttributedString.string)'")
                
                // Check if markers survived
                if restoredAttributedString.string.contains("<CHECKED>") || restoredAttributedString.string.contains("<UNCHECKED>") {
                    print("✅ SparkItem.prepareForRTFSave: Angle bracket markers survived RTF conversion")
                } else if restoredAttributedString.string.contains("(CHECKED)") || restoredAttributedString.string.contains("(UNCHECKED)") {
                    print("✅ SparkItem.prepareForRTFSave: Parentheses markers survived RTF conversion")
                } else if restoredAttributedString.string.contains("[CHECKED]") || restoredAttributedString.string.contains("[UNCHECKED]") {
                    print("✅ SparkItem.prepareForRTFSave: Square bracket markers survived RTF conversion")
                } else {
                    print("❌ SparkItem.prepareForRTFSave: All checkbox markers were lost in RTF conversion")
                }
                
            } catch {
                print("❌ SparkItem.prepareForRTFSave: RTF round-trip test failed: \(error)")
            }
        }
        
        // Debug: Check Unicode values of checkbox characters
        let content = finalMutableString.string
        for (index, char) in content.enumerated() {
            if char == "✓" || char == "[" || char == "]" {
                if let scalar = char.unicodeScalars.first {
                    print("🔍 SparkItem.prepareForRTFSave: Character '\(char)' at index \(index) has Unicode: \\u{\(String(scalar.value, radix: 16))}")
                }
            }
        }
        
        // Then convert fonts to system fonts for RTF compatibility and preserve paragraph styles
        let range = NSRange(location: 0, length: finalMutableString.length)
        
        // First pass: Convert fonts for RTF compatibility
        finalMutableString.enumerateAttribute(.font, in: range, options: []) { value, fontRange, _ in
            guard let font = value as? UIFont else { return }
            
            let size = safeFontSize(font.pointSize)
            let isBold = font.fontName.contains("Bold") || font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let isItalic = font.fontName.contains("Italic") || font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            
            // Create system font with proper traits for RTF compatibility
            var systemFont: UIFont
            
            if isBold && isItalic {
                // Bold + Italic
                if let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits([.traitBold, .traitItalic]) {
                    systemFont = UIFont(descriptor: descriptor, size: size)
                } else {
                    systemFont = UIFont.boldSystemFont(ofSize: size) // Fallback to just bold
                }
            } else if isBold {
                // Bold only
                systemFont = UIFont.boldSystemFont(ofSize: size)
            } else if isItalic {
                // Italic only - ensure we properly create system italic font
                let baseDescriptor = UIFont.systemFont(ofSize: size).fontDescriptor
                if let italicDescriptor = baseDescriptor.withSymbolicTraits([.traitItalic]) {
                    systemFont = UIFont(descriptor: italicDescriptor, size: size)
                    print("✅ SparkItem: Created system italic font for RTF save")
                } else {
                    // Alternative approach using UIFont.italicSystemFont if symbolic traits fail
                    systemFont = UIFont.italicSystemFont(ofSize: size)
                    print("⚠️ SparkItem: Used UIFont.italicSystemFont fallback for RTF save")
                }
            } else {
                // Regular
                systemFont = UIFont.systemFont(ofSize: size)
            }
            
            finalMutableString.addAttribute(.font, value: systemFont, range: fontRange)
        }
        
        // Second pass: Ensure paragraph styles are properly set for RTF compatibility
        finalMutableString.enumerateAttribute(.paragraphStyle, in: range, options: []) { value, styleRange, _ in
            if let paragraphStyle = value as? NSParagraphStyle {
                // Create a mutable copy to ensure RTF compatibility
                let mutableParagraphStyle = NSMutableParagraphStyle()
                mutableParagraphStyle.setParagraphStyle(paragraphStyle)
                
                // Ensure RTF-compatible values (clamp to reasonable ranges)
                mutableParagraphStyle.firstLineHeadIndent = max(0, min(paragraphStyle.firstLineHeadIndent, 200))
                mutableParagraphStyle.headIndent = max(0, min(paragraphStyle.headIndent, 200))
                mutableParagraphStyle.lineSpacing = max(0, min(paragraphStyle.lineSpacing, 50))
                
                print("🔧 SparkItem: Preserving paragraph style - firstLineIndent: \(mutableParagraphStyle.firstLineHeadIndent), headIndent: \(mutableParagraphStyle.headIndent)")
                
                finalMutableString.addAttribute(.paragraphStyle, value: mutableParagraphStyle, range: styleRange)
            }
        }
        
        return finalMutableString
    }
    
    // Convert system fonts back to SpaceGrotesk fonts while preserving formatting traits
    static func prepareForDisplay(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        // Debug: Print the actual string content to see what we're working with
        print("🔍 SparkItem.prepareForDisplay: Input string content: '\(attributedString.string)'")
        print("🔍 SparkItem.prepareForDisplay: String length: \(attributedString.length)")
        
        // Check for checkbox text markers (both new and legacy)
        let checkboxChars = ["<UNCHECKED>", "<CHECKED>", "(UNCHECKED)", "(CHECKED)", "[UNCHECKED]", "[CHECKED]", "[ ]", "[✓]"]
        for char in checkboxChars {
            let count = attributedString.string.components(separatedBy: char).count - 1
            if count > 0 {
                print("🔍 SparkItem.prepareForDisplay: Found \(count) instances of '\(char)'")
            }
        }
        
        // First, convert Unicode checkboxes to NSTextAttachment for better display
        print("🔧 SparkItem.prepareForDisplay: Converting Unicode checkboxes to attachments for display")
        
        // Debug: Check what we're sending to the conversion function
        mutableString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutableString.length), options: []) { value, range, _ in
            if let attachment = value {
                print("🔍 SparkItem.prepareForDisplay: Input has attachment at range \(range): \(type(of: attachment))")
            }
        }
        
        let processedString = CheckboxManager.convertUnicodeCheckboxesToAttachments(mutableString)
        let finalMutableString = NSMutableAttributedString(attributedString: processedString)
        print("🔧 SparkItem.prepareForDisplay: Unicode checkbox conversion complete")
        
        // Debug: Check what we got back from the conversion
        var attachmentCount = 0
        finalMutableString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: finalMutableString.length), options: []) { value, range, _ in
            if let attachment = value {
                attachmentCount += 1
                print("🔍 SparkItem.prepareForDisplay: Output has attachment #\(attachmentCount) at range \(range): \(type(of: attachment))")
                if let checkboxAttachment = attachment as? CheckboxTextAttachment {
                    print("🔍 SparkItem.prepareForDisplay: Attachment is CheckboxTextAttachment (checked: \(checkboxAttachment.isChecked))")
                }
            }
        }
        print("🔍 SparkItem.prepareForDisplay: Total attachments after conversion: \(attachmentCount)")
        
        // Then get the range after potential length changes from checkbox conversion
        let updatedRange = NSRange(location: 0, length: finalMutableString.length)
        
        finalMutableString.enumerateAttribute(.font, in: updatedRange, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            
            let size = safeFontSize(font.pointSize)
            let isBold = font.fontName.contains("Bold") || font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let isItalic = font.fontName.contains("Italic") || font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            
            // Convert system fonts back to SpaceGrotesk fonts
            var spaceGroteskFont: UIFont
            
            if isBold && isItalic {
                // Bold + Italic - Use Space Mono Bold Italic for true italic rendering
                if let boldItalicFont = UIFont(name: "SpaceMono-BoldItalic", size: size) {
                    spaceGroteskFont = boldItalicFont
                    print("✅ SparkItem: Using SpaceMono-BoldItalic for bold italic text")
                } else if let spaceGroteskBold = UIFont(name: "SpaceGrotesk-Bold", size: size) {
                    // Fallback to SpaceGrotesk-Bold if Space Mono not available
                    spaceGroteskFont = spaceGroteskBold
                    print("⚠️ SparkItem: SpaceMono-BoldItalic not available, using SpaceGrotesk-Bold")
                } else {
                    spaceGroteskFont = UIFont.boldSystemFont(ofSize: size) // Ultimate fallback
                    print("⚠️ SparkItem: No custom fonts available, using system bold")
                }
            } else if isBold {
                // Bold only
                if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: size) {
                    spaceGroteskFont = boldFont
                } else {
                    spaceGroteskFont = UIFont.boldSystemFont(ofSize: size) // System fallback
                }
            } else if isItalic {
                // Italic only - Use Space Mono Italic for true italic rendering
                if let italicFont = UIFont(name: "SpaceMono-Italic", size: size) {
                    spaceGroteskFont = italicFont
                    print("✅ SparkItem: Using SpaceMono-Italic for italic text")
                } else if let spaceGroteskRegular = UIFont(name: "SpaceGrotesk-Regular", size: size) {
                    // Fallback to SpaceGrotesk-Regular if Space Mono not available
                    spaceGroteskFont = spaceGroteskRegular
                    print("⚠️ SparkItem: SpaceMono-Italic not available, using SpaceGrotesk-Regular")
                } else {
                    spaceGroteskFont = UIFont.systemFont(ofSize: size) // Ultimate fallback
                    print("⚠️ SparkItem: No custom fonts available, using system font")
                }
            } else {
                // Regular
                if let regularFont = UIFont(name: "SpaceGrotesk-Regular", size: size) {
                    spaceGroteskFont = regularFont
                } else {
                    spaceGroteskFont = UIFont.systemFont(ofSize: size) // System fallback
                }
            }
            
            finalMutableString.addAttribute(.font, value: spaceGroteskFont, range: range)
        }
        
        // Ensure paragraph styles are preserved when converting back from RTF
        let fullRange = NSRange(location: 0, length: finalMutableString.length)
        finalMutableString.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, styleRange, _ in
            if let paragraphStyle = value as? NSParagraphStyle {
                print("📖 SparkItem: Preserving paragraph style for display - firstLineIndent: \(paragraphStyle.firstLineHeadIndent), headIndent: \(paragraphStyle.headIndent)")
                // Paragraph styles should already be compatible, just ensure they're preserved
                finalMutableString.addAttribute(.paragraphStyle, value: paragraphStyle, range: styleRange)
            }
        }
        
        return finalMutableString
    }
    
}

// MARK: - Category Model
class Category: ObservableObject, Identifiable, Hashable {
    let id: String
    @Published var name: String
    @Published var color: String
    let createdAt: Date
    @Published var usageCount: Int
    var firebaseId: String?
    
    init(name: String, color: String = Category.defaultColor(), id: String = UUID().uuidString) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.usageCount = 0
    }
    
    init(from firebaseCategory: FirebaseCategory) {
        self.id = firebaseCategory.id ?? UUID().uuidString
        self.name = firebaseCategory.name
        self.color = firebaseCategory.color
        self.createdAt = firebaseCategory.createdAt
        self.usageCount = firebaseCategory.usageCount
        self.firebaseId = firebaseCategory.id
    }
    
    var uiColor: Color {
        Color(hex: color) ?? Color.gray
    }
    
    static func defaultColor() -> String {
        let colors = [
            "#6B73FF", "#9F7AEA", "#4FD1C7", "#68D391", "#F6AD55",
            "#FC8181", "#63B3ED", "#D69E2E", "#ED64A6", "#A0AEC0"
        ]
        return colors.randomElement() ?? colors[0]
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Category, rhs: Category) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Firebase Models
struct FirebaseNote: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let content: String
    let title: String?
    let categoryIds: [String]?
    let isTask: Bool
    let categories: [String] // Legacy field
    let createdAt: Date
    let updatedAt: Date
    let pineconeId: String?
    let creationType: String
    let rtfContent: String? // RTF data stored as base64 string
    
    var wrappedContent: String { content }
}

struct FirebaseCategory: Codable {
    let id: String?
    let name: String
    let color: String
    let createdAt: Date
    let usageCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, color, usageCount
        case createdAt = "created_at"
    }
}

// MARK: - Color Extension
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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Keyboard Dismissal Extension
extension View {
    /// Adds a drag gesture to dismiss the keyboard when pulling down
    func dismissKeyboardOnDrag() -> some View {
        self.gesture(
            DragGesture()
                .onChanged { value in
                    // Only dismiss keyboard if dragging downward (positive height translation)
                    if value.translation.height > 30 {
                        hideKeyboard()
                    }
                }
        )
    }
    
    /// Hides the keyboard by ending editing
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

