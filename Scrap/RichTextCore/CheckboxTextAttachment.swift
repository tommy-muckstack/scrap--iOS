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
        
        // First, find formal checkbox markers (RTF-safe ASCII and legacy patterns)
        // Prioritize new RTF-safe markers, but maintain backward compatibility
        let checkboxPattern = "\\[CHECKBOX_CHECKED\\]|\\[CHECKBOX_UNCHECKED\\]|☑CHECKED☑|☐UNCHECKED☐|\\[CHECKED\\]|\\[UNCHECKED\\]|<CHECKED>|<UNCHECKED>|\\(CHECKED\\)|\\(UNCHECKED\\)|\\[\\s*[✓✔︎☑︎]\\s*\\]|\\[\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: checkboxPattern, options: [.caseInsensitive]) else {
            // Failed to create regex for checkbox conversion
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        // Found \(matches.count) formal checkbox markers to convert
        
        // If no formal markers found, look for plain text checkbox descriptions
        if matches.count == 0 {
            // No formal markers found, checking for plain text checkbox descriptions...
            
            // Look for patterns like "check box #1 unchecked", "checkbox 2 checked", etc.
            let plainTextPattern = "\\b(?:check\\s*box|checkbox)\\s*[#\\d]*\\s*(unchecked|checked|\\buncheck|\\bcheck(?!\\w))\\b"
            guard let plainTextRegex = try? NSRegularExpression(pattern: plainTextPattern, options: [.caseInsensitive]) else {
                // Failed to create plain text regex
                return attributedString
            }
            
            let plainTextMatches = plainTextRegex.matches(in: text, range: NSRange(location: 0, length: text.count))
            // Found \(plainTextMatches.count) plain text checkbox descriptions
            
            // Convert plain text descriptions to proper checkbox attachments
            for match in plainTextMatches.reversed() {
                let matchText = (text as NSString).substring(with: match.range)
                // Converting plain text description
                
                // Determine if checked based on the description
                let isChecked = matchText.lowercased().contains("checked") && !matchText.lowercased().contains("unchecked")
                
                // Create checkbox attachment
                let attachment = CheckboxTextAttachment(isChecked: isChecked)
                
                // Set up state change callback for proper synchronization
                attachment.onStateChange = { newState in
                    // Plain text converted checkbox state changed
                    // The actual text view delegate notification will be set up by toggleCheckbox when first toggled
                }
                
                // Create attachment string with proper font context to ensure rendering compatibility
                let attachmentString = NSMutableAttributedString(attachment: attachment)
                // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
                let systemFont = UIFont.systemFont(ofSize: 16)
                attachmentString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: attachmentString.length))
                
                // Replace the plain text description with the attachment
                mutableString.replaceCharacters(in: match.range, with: attachmentString)
                // Converted to checkbox attachment
            }
            
            return mutableString
        }
        
        if matches.count == 0 {
            // No formal checkbox markers found
            return mutableString
        }
        
        // Process matches in reverse order to maintain indices
        for match in matches.reversed() {
            let character = (text as NSString).substring(with: match.range)
            
            // Determine if checkbox is checked based on the marker type
            let isChecked: Bool
            let lowercaseCharacter = character.lowercased()
            
            // Check RTF-safe markers first (highest priority)
            if character == "[CHECKBOX_CHECKED]" {
                isChecked = true
            } else if character == "[CHECKBOX_UNCHECKED]" {
                isChecked = false
            } 
            // Legacy Unicode markers  
            else if character == "☑CHECKED☑" || lowercaseCharacter == "[checked]" || lowercaseCharacter == "<checked>" || lowercaseCharacter == "(checked)" {
                isChecked = true
            } else if character == "☐UNCHECKED☐" || lowercaseCharacter == "[unchecked]" || lowercaseCharacter == "<unchecked>" || lowercaseCharacter == "(unchecked)" {
                isChecked = false
            } else {
                // Legacy Unicode pattern - check if it contains any checkmark character
                let checkedPattern = "[✓✔︎☑︎]"
                isChecked = character.range(of: checkedPattern, options: .regularExpression) != nil
            }
            
            // Converting to attachment
            
            // Create checkbox attachment
            let attachment = CheckboxTextAttachment(isChecked: isChecked)
            
            // CRITICAL: Set up state change callback for proper synchronization
            // This ensures the checkbox state changes are properly synchronized with the text view
            // Note: The textView reference will be set up later by the RichTextCoordinator when toggled
            attachment.onStateChange = { newState in
                print("🔄 CheckboxManager: Restored checkbox state changed to \(newState)")
                // The actual text view delegate notification will be set up by toggleCheckbox when first toggled
            }
            
            // Create attachment string with proper font context to ensure rendering compatibility
            let attachmentString = NSMutableAttributedString(attachment: attachment)
            // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
            let systemFont = UIFont.systemFont(ofSize: 16)
            attachmentString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: attachmentString.length))
            
            // Replace marker with attachment
            mutableString.replaceCharacters(in: match.range, with: attachmentString)
        }
        
        print("✅ CheckboxManager: Converted \(matches.count) Unicode checkboxes to attachments")
        return mutableString
    }
    
    /// Convert checkbox attachments to RTF-safe ASCII markers for persistence
    static func convertAttachmentsToUnicodeCheckboxes(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        // Converting attachments to RTF-safe markers
        
        var checkboxCount = 0
        var totalAttachments = 0
        
        // Find checkbox attachments and replace with RTF-safe ASCII markers
        attributedString.enumerateAttribute(.attachment, 
                                          in: NSRange(location: 0, length: attributedString.length),
                                          options: [.reverse]) { value, range, _ in
            if value != nil {
                totalAttachments += 1
            }
            
            if let checkboxAttachment = value as? CheckboxTextAttachment {
                checkboxCount += 1
                // Use RTF-safe ASCII-only markers that will survive RTF encoding/decoding
                let checkboxText = checkboxAttachment.isChecked ? "[CHECKBOX_CHECKED]" : "[CHECKBOX_UNCHECKED]"
                let replacement = NSAttributedString(string: checkboxText)
                mutableString.replaceCharacters(in: range, with: replacement)
            }
        }
        
        // Conversion complete
        
        return mutableString
    }
    
    /// Insert a new checkbox at the specified location
    static func insertCheckbox(in textView: UITextView, at range: NSRange, isChecked: Bool = false) {
        guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            return
        }
        
        // Inserting new checkbox
        
        let attachment = CheckboxTextAttachment(isChecked: isChecked)
        
        // Set up immediate state change callback for future toggles
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            // Notify delegate immediately for binding synchronization
            textView.delegate?.textViewDidChange?(textView)
        }
        
        // Create attachment string with proper font context to ensure rendering compatibility
        let attachmentString = NSMutableAttributedString(attachment: attachment)
        // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
        let systemFont = UIFont.systemFont(ofSize: 16)
        attachmentString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: attachmentString.length))
        mutableText.insert(attachmentString, at: range.location)
        
        textView.attributedText = mutableText
        textView.selectedRange = NSRange(location: range.location + 1, length: 0)
        
        // Immediately notify delegate that content has changed
        textView.delegate?.textViewDidChange?(textView)
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
        // Starting checkbox toggle
        
        // Set up the state change callback to ensure immediate synchronization
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            
            // Force immediate visual update
            let layoutManager = textView.layoutManager
            layoutManager.invalidateDisplay(forCharacterRange: range)
            textView.setNeedsDisplay()
            
            // Immediately notify delegate of text changes for binding synchronization
            textView.delegate?.textViewDidChange?(textView)
            
            // Ensure layout is committed immediately
            layoutManager.ensureLayout(for: textView.textContainer)
        }
        
        // Toggle the checkbox state (this will trigger the onStateChange callback)
        attachment.isChecked.toggle()
    }
}

// MARK: - RTF Persistence Extension
extension CheckboxTextAttachment {
    
    /// Custom encoding for RTF persistence using RTF-safe ASCII markers
    func encodeForRTF() -> String {
        return isChecked ? "[CHECKBOX_CHECKED]" : "[CHECKBOX_UNCHECKED]"
    }
    
    /// Decode from RTF representation
    static func decodeFromRTF(_ character: String) -> CheckboxTextAttachment? {
        let lowercaseCharacter = character.lowercased()
        switch character {
        // RTF-safe markers (exact match, case-sensitive)
        case "[CHECKBOX_CHECKED]":
            return CheckboxTextAttachment(isChecked: true)
        case "[CHECKBOX_UNCHECKED]":
            return CheckboxTextAttachment(isChecked: false)
        // Unicode markers (legacy support)
        case "☑CHECKED☑":
            return CheckboxTextAttachment(isChecked: true)
        case "☐UNCHECKED☐":
            return CheckboxTextAttachment(isChecked: false)
        default:
            // Legacy markers (case-insensitive)
            switch lowercaseCharacter {
            case "[unchecked]", "<unchecked>", "(unchecked)":
                return CheckboxTextAttachment(isChecked: false)
            case "[checked]", "<checked>", "(checked)":
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
}