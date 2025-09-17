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
        context.setStrokeColor(UIColor.label.cgColor) // Use label color (black in light mode, white in dark mode)
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
        
        // First, find formal checkbox markers (ASCII and Unicode)
        // Support both new ASCII markers and legacy Unicode markers
        // Updated to use RTF-safe markers with parentheses instead of square brackets
        let checkboxPattern = "\\(CHECKED\\)|\\(UNCHECKED\\)|\\[CHECKED\\]|\\[UNCHECKED\\]|\\[\\s*[✓✔︎☑︎]\\s*\\]|\\[\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: checkboxPattern, options: [.caseInsensitive]) else {
            print("❌ CheckboxManager: Failed to create regex for checkbox conversion")
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        print("🔍 CheckboxManager: Found \(matches.count) formal checkbox markers to convert")
        
        // If no formal markers found, look for plain text checkbox descriptions
        if matches.count == 0 {
            print("🔍 CheckboxManager: No formal markers found, checking for plain text checkbox descriptions...")
            
            // Look for patterns like "check box #1 unchecked", "checkbox 2 checked", etc.
            let plainTextPattern = "\\b(?:check\\s*box|checkbox)\\s*[#\\d]*\\s*(unchecked|checked|\\buncheck|\\bcheck(?!\\w))\\b"
            guard let plainTextRegex = try? NSRegularExpression(pattern: plainTextPattern, options: [.caseInsensitive]) else {
                print("❌ CheckboxManager: Failed to create plain text regex")
                return attributedString
            }
            
            let plainTextMatches = plainTextRegex.matches(in: text, range: NSRange(location: 0, length: text.count))
            print("🔍 CheckboxManager: Found \(plainTextMatches.count) plain text checkbox descriptions")
            
            // Convert plain text descriptions to proper checkbox attachments
            for match in plainTextMatches.reversed() {
                let matchText = (text as NSString).substring(with: match.range)
                print("📝 CheckboxManager: Converting plain text description: '\(matchText)'")
                
                // Determine if checked based on the description
                let isChecked = matchText.lowercased().contains("checked") && !matchText.lowercased().contains("unchecked")
                
                // Create checkbox attachment
                let attachment = CheckboxTextAttachment(isChecked: isChecked)
                
                // Set up state change callback for proper synchronization
                attachment.onStateChange = { newState in
                    print("🔄 CheckboxManager: Plain text converted checkbox state changed to \(newState)")
                    // The actual text view delegate notification will be set up by toggleCheckbox when first toggled
                }
                
                let attachmentString = NSAttributedString(attachment: attachment)
                
                // Replace the plain text description with the attachment
                mutableString.replaceCharacters(in: match.range, with: attachmentString)
                print("✅ CheckboxManager: Converted '\(matchText)' to checkbox attachment (checked: \(isChecked))")
            }
            
            return mutableString
        }
        
        if matches.count == 0 {
            print("⚠️ CheckboxManager: No formal checkbox markers found after checking both formal and plain text patterns")
            return mutableString
        }
        
        // Process matches in reverse order to maintain indices
        for match in matches.reversed() {
            let character = (text as NSString).substring(with: match.range)
            
            // Determine if checkbox is checked based on the marker type
            let isChecked: Bool
            if character == "(CHECKED)" || character == "[CHECKED]" {
                isChecked = true
            } else if character == "(UNCHECKED)" || character == "[UNCHECKED]" {
                isChecked = false
            } else {
                // Legacy Unicode pattern - check if it contains any checkmark character
                let checkedPattern = "[✓✔︎☑︎]"
                isChecked = character.range(of: checkedPattern, options: .regularExpression) != nil
            }
            
            print("📝 CheckboxManager: Converting '\(character)' to attachment (checked: \(isChecked))")
            
            // Create checkbox attachment
            let attachment = CheckboxTextAttachment(isChecked: isChecked)
            
            // CRITICAL: Set up state change callback for proper synchronization
            // This ensures the checkbox state changes are properly synchronized with the text view
            // Note: The textView reference will be set up later by the RichTextCoordinator when toggled
            attachment.onStateChange = { newState in
                print("🔄 CheckboxManager: Restored checkbox state changed to \(newState)")
                // The actual text view delegate notification will be set up by toggleCheckbox when first toggled
            }
            
            let attachmentString = NSAttributedString(attachment: attachment)
            
            // Replace marker with attachment
            mutableString.replaceCharacters(in: match.range, with: attachmentString)
        }
        
        print("✅ CheckboxManager: Converted \(matches.count) Unicode checkboxes to attachments")
        return mutableString
    }
    
    /// Convert checkbox attachments to ASCII markers for RTF persistence
    static func convertAttachmentsToUnicodeCheckboxes(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        print("🔄 CheckboxManager: Starting conversion of attachments to ASCII markers")
        print("🔍 CheckboxManager: Input string length: \(attributedString.length)")
        
        var checkboxCount = 0
        var totalAttachments = 0
        
        // Find checkbox attachments and replace with ASCII markers
        attributedString.enumerateAttribute(.attachment, 
                                          in: NSRange(location: 0, length: attributedString.length),
                                          options: [.reverse]) { value, range, _ in
            if value != nil {
                totalAttachments += 1
            }
            
            if let checkboxAttachment = value as? CheckboxTextAttachment {
                checkboxCount += 1
                let checkboxText = checkboxAttachment.isChecked ? "(CHECKED)" : "(UNCHECKED)"
                print("📝 CheckboxManager: Converting attachment #\(checkboxCount) at range \(range) to '\(checkboxText)' (checked: \(checkboxAttachment.isChecked))")
                
                let replacement = NSAttributedString(string: checkboxText)
                mutableString.replaceCharacters(in: range, with: replacement)
                print("✅ CheckboxManager: Converted attachment to ASCII marker '\(checkboxText)'")
            } else if value != nil {
                print("🔍 CheckboxManager: Found non-checkbox attachment at range \(range): \(type(of: value!))")
            }
        }
        
        print("🔍 CheckboxManager: Total attachments found: \(totalAttachments)")
        print("✅ CheckboxManager: Conversion complete - converted \(checkboxCount) checkbox attachments to ASCII markers")
        
        // Verify the conversion worked by checking the final string
        let finalString = mutableString.string
        let checkedCount = finalString.components(separatedBy: "(CHECKED)").count - 1
        let uncheckedCount = finalString.components(separatedBy: "(UNCHECKED)").count - 1
        print("🔍 CheckboxManager: Final string contains \(checkedCount) (CHECKED) and \(uncheckedCount) (UNCHECKED) markers")
        
        return mutableString
    }
    
    /// Insert a new checkbox at the specified location
    static func insertCheckbox(in textView: UITextView, at range: NSRange, isChecked: Bool = false) {
        guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            return
        }
        
        print("📝 CheckboxManager: Inserting new checkbox at range \(range) (checked: \(isChecked))")
        
        let attachment = CheckboxTextAttachment(isChecked: isChecked)
        
        // Set up immediate state change callback for future toggles
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            print("🔄 CheckboxManager: New checkbox state changed to \(newState), updating text view")
            
            // Notify delegate immediately for binding synchronization
            textView.delegate?.textViewDidChange?(textView)
            
            print("✅ CheckboxManager: New checkbox binding synchronized for state: \(newState)")
        }
        
        let attachmentString = NSAttributedString(attachment: attachment)
        mutableText.insert(attachmentString, at: range.location)
        
        textView.attributedText = mutableText
        textView.selectedRange = NSRange(location: range.location + 1, length: 0)
        
        // Immediately notify delegate that content has changed
        textView.delegate?.textViewDidChange?(textView)
        
        print("✅ CheckboxManager: New checkbox inserted and binding updated")
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
        print("📝 CheckboxManager: Starting checkbox toggle at range \(range)")
        
        // Set up the state change callback to ensure immediate synchronization
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            print("🔄 CheckboxManager: Checkbox state changed to \(newState), updating text view")
            
            // Force immediate visual update
            let layoutManager = textView.layoutManager
            layoutManager.invalidateDisplay(forCharacterRange: range)
            textView.setNeedsDisplay()
            
            // CRITICAL: Immediately notify delegate of text changes for binding synchronization
            textView.delegate?.textViewDidChange?(textView)
            
            // Ensure layout is committed immediately
            layoutManager.ensureLayout(for: textView.textContainer)
            
            print("✅ CheckboxManager: Text view updated and binding synchronized for state: \(newState)")
        }
        
        // Toggle the checkbox state (this will trigger the onStateChange callback)
        attachment.isChecked.toggle()
        
        print("✅ CheckboxManager: Checkbox toggle complete - new state: \(attachment.isChecked ? "checked" : "unchecked")")
    }
}

// MARK: - RTF Persistence Extension
extension CheckboxTextAttachment {
    
    /// Custom encoding for RTF persistence using ASCII-safe markers
    func encodeForRTF() -> String {
        return isChecked ? "(CHECKED)" : "(UNCHECKED)"
    }
    
    /// Decode from RTF representation
    static func decodeFromRTF(_ character: String) -> CheckboxTextAttachment? {
        switch character {
        case "(UNCHECKED)", "[UNCHECKED]":
            return CheckboxTextAttachment(isChecked: false)
        case "(CHECKED)", "[CHECKED]":
            return CheckboxTextAttachment(isChecked: true)
        // Keep backward compatibility with old format
        case "[ ]":
            return CheckboxTextAttachment(isChecked: false)
        case "[✓]":
            return CheckboxTextAttachment(isChecked: true)
        default:
            return nil
        }
    }
}