import UIKit
import Foundation

// MARK: - Checkbox Text Attachment
/// A native iOS NSTextAttachment implementation for checkboxes that replaces Unicode characters
/// This provides reliable tap targets, consistent appearance, and proper RTF persistence
class CheckboxTextAttachment: NSTextAttachment {
    
    // MARK: - Properties
    
    /// Whether the checkbox is currently checked
    var isChecked: Bool = false {
        didSet {
            if isChecked != oldValue {
                // Clear cached image to force redraw
                contents = nil
                image = nil
                onStateChange?(isChecked)
            }
        }
    }
    
    /// Callback for when checkbox state changes
    var onStateChange: ((Bool) -> Void)?
    
    /// Size of the checkbox (optimized for touch targets)
    private let checkboxSize = CGSize(width: 22, height: 22) // Apple Notes standard
    
    /// Unique identifier for this checkbox
    let checkboxId = UUID().uuidString
    
    // MARK: - Initialization
    
    init(isChecked: Bool = false) {
        super.init(data: nil, ofType: nil)
        self.isChecked = isChecked
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }
    
    // MARK: - NSTextAttachment Overrides
    
    override func attachmentBounds(for textContainer: NSTextContainer?, 
                                 proposedLineFragment lineFrag: CGRect, 
                                 glyphPosition position: CGPoint, 
                                 characterIndex charIndex: Int) -> CGRect {
        // Position checkbox slightly below baseline for better text alignment
        return CGRect(origin: CGPoint(x: 0, y: -2), size: checkboxSize)
    }
    
    override func image(forBounds imageBounds: CGRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> UIImage? {
        return generateCheckboxImage(bounds: imageBounds)
    }
    
    // MARK: - Image Generation
    
    /// Generate a checkbox image with the current state
    private func generateCheckboxImage(bounds: CGRect) -> UIImage {
        let renderer = UIGraphicsImageRenderer(bounds: bounds)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Set up drawing context
            cgContext.setShouldAntialias(true)
            cgContext.setAllowsAntialiasing(true)
            
            // Draw checkbox background and border
            let checkboxRect = bounds.insetBy(dx: 2, dy: 2)
            let cornerRadius: CGFloat = 3.0
            
            // Background color
            cgContext.setFillColor(UIColor.systemBackground.cgColor)
            
            // Border color - use system colors for proper light/dark mode support
            cgContext.setStrokeColor(UIColor.systemGray3.cgColor)
            cgContext.setLineWidth(1.5)
            
            // Draw rounded rectangle
            let path = UIBezierPath(roundedRect: checkboxRect, cornerRadius: cornerRadius)
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: .fillStroke)
            
            // Draw checkmark if checked
            if isChecked {
                drawCheckmark(in: cgContext, bounds: checkboxRect)
            }
        }
    }
    
    /// Draw the checkmark for checked state
    private func drawCheckmark(in context: CGContext, bounds: CGRect) {
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(2.0)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Create checkmark path (similar to Apple's design)
        let checkPath = UIBezierPath()
        let startX = bounds.minX + bounds.width * 0.28
        let startY = bounds.minY + bounds.height * 0.53
        let midX = bounds.minX + bounds.width * 0.42
        let midY = bounds.minY + bounds.height * 0.66
        let endX = bounds.minX + bounds.width * 0.72
        let endY = bounds.minY + bounds.height * 0.36
        
        checkPath.move(to: CGPoint(x: startX, y: startY))
        checkPath.addLine(to: CGPoint(x: midX, y: midY))
        checkPath.addLine(to: CGPoint(x: endX, y: endY))
        
        context.addPath(checkPath.cgPath)
        context.strokePath()
    }
}

// MARK: - Checkbox Manager
/// Manages checkbox operations within NSAttributedString
class CheckboxManager {
    
    /// Convert Unicode checkbox characters to NSTextAttachment checkboxes
    static func convertUnicodeCheckboxesToAttachments(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let text = attributedString.string
        
        // Find Unicode checkbox characters and replace with attachments
        // Note: ☑️ is two Unicode scalars (☑ + variation selector), so we need separate patterns
        let checkboxPattern = "☑️|☑|☐"
        guard let regex = try? NSRegularExpression(pattern: checkboxPattern) else {
            print("❌ CheckboxManager: Failed to create regex for checkbox conversion")
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        print("🔍 CheckboxManager: Found \(matches.count) checkbox Unicode characters to convert")
        
        if matches.count == 0 {
            print("⚠️ CheckboxManager: No checkbox characters found in text: '\(text.prefix(100))...'")
        }
        
        // Process matches in reverse order to maintain indices
        for match in matches.reversed() {
            let character = (text as NSString).substring(with: match.range)
            let isChecked = character == "☑️" || character == "☑"
            
            print("📝 CheckboxManager: Converting '\(character)' to attachment (checked: \(isChecked))")
            
            // Create checkbox attachment
            let attachment = CheckboxTextAttachment(isChecked: isChecked)
            let attachmentString = NSAttributedString(attachment: attachment)
            
            // Replace Unicode character with attachment
            mutableString.replaceCharacters(in: match.range, with: attachmentString)
        }
        
        print("✅ CheckboxManager: Converted \(matches.count) Unicode checkboxes to attachments")
        return mutableString
    }
    
    /// Convert checkbox attachments to Unicode characters for RTF persistence
    static func convertAttachmentsToUnicodeCheckboxes(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        print("🔄 CheckboxManager: Starting conversion of attachments to Unicode")
        print("🔍 CheckboxManager: Input string length: \(attributedString.length)")
        
        var checkboxCount = 0
        
        // Find checkbox attachments and replace with Unicode
        attributedString.enumerateAttribute(.attachment, 
                                          in: NSRange(location: 0, length: attributedString.length),
                                          options: [.reverse]) { value, range, _ in
            if let checkboxAttachment = value as? CheckboxTextAttachment {
                checkboxCount += 1
                let checkboxText = checkboxAttachment.isChecked ? "☑" : "☐"
                print("📝 CheckboxManager: Converting attachment #\(checkboxCount) at range \(range) to '\(checkboxText)' (checked: \(checkboxAttachment.isChecked))")
                
                let replacement = NSAttributedString(string: checkboxText)
                mutableString.replaceCharacters(in: range, with: replacement)
                print("✅ CheckboxManager: Converted attachment to Unicode '\(checkboxText)'")
            } else if value != nil {
                print("🔍 CheckboxManager: Found non-checkbox attachment at range \(range): \(type(of: value!))")
            }
        }
        
        print("✅ CheckboxManager: Conversion complete - converted \(checkboxCount) checkbox attachments to Unicode")
        return mutableString
    }
    
    /// Insert a new checkbox at the specified location
    static func insertCheckbox(in textView: UITextView, at range: NSRange, isChecked: Bool = false) {
        guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            return
        }
        
        let attachment = CheckboxTextAttachment(isChecked: isChecked)
        let attachmentString = NSAttributedString(attachment: attachment)
        
        mutableText.insert(attachmentString, at: range.location)
        
        textView.attributedText = mutableText
        textView.selectedRange = NSRange(location: range.location + 1, length: 0)
    }
    
    /// Find checkbox attachment at a given tap location
    static func findCheckboxAtLocation(_ location: CGPoint, in textView: UITextView) -> (attachment: CheckboxTextAttachment, range: NSRange)? {
        guard let textPosition = textView.closestPosition(to: location) else { return nil }
        
        let tapIndex = textView.offset(from: textView.beginningOfDocument, to: textPosition)
        guard let attributedText = textView.attributedText else { return nil }
        
        // Check for attachment at tap position
        if tapIndex < attributedText.length {
            if let attachment = attributedText.attribute(.attachment, at: tapIndex, effectiveRange: nil) as? CheckboxTextAttachment {
                return (attachment, NSRange(location: tapIndex, length: 1))
            }
        }
        
        // Check previous character (in case tap was on the edge)
        if tapIndex > 0 && tapIndex - 1 < attributedText.length {
            if let attachment = attributedText.attribute(.attachment, at: tapIndex - 1, effectiveRange: nil) as? CheckboxTextAttachment {
                return (attachment, NSRange(location: tapIndex - 1, length: 1))
            }
        }
        
        return nil
    }
    
    /// Toggle checkbox state and update the text view
    static func toggleCheckbox(_ attachment: CheckboxTextAttachment, in textView: UITextView, at range: NSRange) {
        // Toggle the checkbox state
        attachment.isChecked.toggle()
        
        // Force the text view to refresh the attachment display
        let layoutManager = textView.layoutManager
        layoutManager.invalidateDisplay(forCharacterRange: range)
        textView.setNeedsDisplay()
        
        // Notify text view of content changes
        textView.delegate?.textViewDidChange?(textView)
    }
}

// MARK: - RTF Persistence Extension
extension CheckboxTextAttachment {
    
    /// Custom encoding for RTF persistence
    func encodeForRTF() -> String {
        return isChecked ? "☑" : "☐"
    }
    
    /// Decode from RTF representation
    static func decodeFromRTF(_ character: String) -> CheckboxTextAttachment? {
        switch character {
        case "☐":
            return CheckboxTextAttachment(isChecked: false)
        case "☑", "☑️":
            return CheckboxTextAttachment(isChecked: true)
        default:
            return nil
        }
    }
}