import Foundation
import SwiftUI
import FirebaseFirestore

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
                let loadedAttributedString = try NSAttributedString(
                    data: rtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                
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
                .font: UIFont(name: "SpaceGrotesk-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17),
                .foregroundColor: UIColor.black
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
    
    // Prepare attributed string for RTF saving by ensuring system fonts with proper traits
    static func prepareForRTFSave(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let range = NSRange(location: 0, length: mutableString.length)
        
        // Since we're now using Unicode checkboxes, no conversion needed for RTF persistence
        
        // Then convert fonts to system fonts for RTF compatibility
        let newRange = NSRange(location: 0, length: mutableString.length)
        mutableString.enumerateAttribute(.font, in: newRange, options: []) { value, _, _ in
            guard let font = value as? UIFont else { return }
            
            let size = font.pointSize
            let isBold = font.fontName.contains("Bold") || font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            
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
                // Italic only
                if let descriptor = UIFont.systemFont(ofSize: size).fontDescriptor.withSymbolicTraits([.traitItalic]) {
                    systemFont = UIFont(descriptor: descriptor, size: size)
                } else {
                    systemFont = UIFont.italicSystemFont(ofSize: size) // Fallback
                }
            } else {
                // Regular
                systemFont = UIFont.systemFont(ofSize: size)
            }
            
            mutableString.addAttribute(.font, value: systemFont, range: range)
        }
        
        return mutableString
    }
    
    // Convert system fonts back to SpaceGrotesk fonts while preserving formatting traits
    static func prepareForDisplay(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        // Keep Unicode checkboxes as-is - no conversion to attachments needed
        
        // Then get the range after potential length changes from checkbox conversion
        let updatedRange = NSRange(location: 0, length: mutableString.length)
        
        mutableString.enumerateAttribute(.font, in: updatedRange, options: []) { value, range, _ in
            guard let font = value as? UIFont else { return }
            
            let size = font.pointSize
            let isBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let isItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            
            // Convert system fonts back to SpaceGrotesk fonts
            var spaceGroteskFont: UIFont
            
            if isBold && isItalic {
                // Bold + Italic (if available, fallback to just bold)
                if let boldItalicFont = UIFont(name: "SpaceGrotesk-Bold", size: size) {
                    // Apply italic trait to the bold font
                    if let descriptor = boldItalicFont.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                        spaceGroteskFont = UIFont(descriptor: descriptor, size: size)
                    } else {
                        spaceGroteskFont = boldItalicFont // Fallback to just bold
                    }
                } else {
                    spaceGroteskFont = UIFont.boldSystemFont(ofSize: size) // System fallback
                }
            } else if isBold {
                // Bold only
                if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: size) {
                    spaceGroteskFont = boldFont
                } else {
                    spaceGroteskFont = UIFont.boldSystemFont(ofSize: size) // System fallback
                }
            } else if isItalic {
                // Italic only
                if let regularFont = UIFont(name: "SpaceGrotesk-Regular", size: size) {
                    // Apply italic trait to regular font
                    if let descriptor = regularFont.fontDescriptor.withSymbolicTraits([.traitItalic]) {
                        spaceGroteskFont = UIFont(descriptor: descriptor, size: size)
                    } else {
                        spaceGroteskFont = regularFont // Fallback to regular
                    }
                } else {
                    spaceGroteskFont = UIFont.italicSystemFont(ofSize: size) // System fallback
                }
            } else {
                // Regular
                if let regularFont = UIFont(name: "SpaceGrotesk-Regular", size: size) {
                    spaceGroteskFont = regularFont
                } else {
                    spaceGroteskFont = UIFont.systemFont(ofSize: size) // System fallback
                }
            }
            
            mutableString.addAttribute(.font, value: spaceGroteskFont, range: range)
        }
        
        return mutableString
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