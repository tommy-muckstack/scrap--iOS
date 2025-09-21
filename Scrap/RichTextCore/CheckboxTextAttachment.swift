import UIKit
import Foundation

// MARK: - Checkbox Text Attachment
/// A native iOS NSTextAttachment implementation for checkboxes that replaces Unicode characters
/// This provides reliable tap targets, consistent appearance, and proper RTF persistence
class CheckboxTextAttachment: NSTextAttachment {
    
    // MARK: - Properties
    
    /// The checkbox state - this is the source of truth
    var isChecked: Bool = false {
        didSet {
            if isChecked != oldValue {
                print("🔄 CheckboxTextAttachment: State changed to \(isChecked)")
                
                // Clear cached content to force redraw
                contents = nil
                image = nil
                
                // Notify about state change for persistence
                onStateChange?(isChecked)
                
                // Update the text storage to reflect the change
                updateTextStorage()
            }
        }
    }
    
    /// Callback for when checkbox state changes
    var onStateChange: ((Bool) -> Void)?
    
    /// Reference to the text view containing this attachment
    weak var textView: UITextView?
    
    /// Character range of this attachment in the text storage
    var characterRange: NSRange = NSRange(location: NSNotFound, length: 0)
    
    /// Size of the checkbox (optimized for easy touch targets)
    private let checkboxSize = CGSize(width: 28, height: 28)
    
    // MARK: - Text Storage Integration
    
    /// Update the text storage to reflect the current checkbox state
    /// This ensures the checkbox state persists in the document
    private func updateTextStorage() {
        guard let textView = textView,
              characterRange.location != NSNotFound else {
            print("⚠️ CheckboxTextAttachment.updateTextStorage: Missing textView or invalid range")
            return
        }
        
        let textStorage = textView.textStorage
        
        // Validate range bounds
        guard characterRange.location >= 0 && 
              characterRange.location < textStorage.length &&
              characterRange.length > 0 &&
              characterRange.location + characterRange.length <= textStorage.length else {
            print("⚠️ CheckboxTextAttachment.updateTextStorage: Invalid range \(characterRange) for text length \(textStorage.length)")
            return
        }
        
        print("🔄 CheckboxTextAttachment.updateTextStorage: Updating character range \(characterRange) to state \(isChecked)")
        
        // Force layout manager to update the display for this attachment
        let layoutManager = textView.layoutManager
        layoutManager.invalidateDisplay(forCharacterRange: characterRange)
        layoutManager.invalidateLayout(forCharacterRange: characterRange, actualCharacterRange: nil)
        
        // Force immediate redraw
        textView.setNeedsDisplay()
        
        // Notify text view delegate of content changes for state persistence
        DispatchQueue.main.async {
            textView.delegate?.textViewDidChange?(textView)
        }
    }
    
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
        // Store the character range for this attachment
        characterRange = NSRange(location: charIndex, length: 1)
        
        // Validate and sanitize all values to prevent CoreGraphics NaN errors
        let safeOriginX: CGFloat = 0.0
        let safeOriginY: CGFloat = -2.0
        let safeWidth = checkboxSize.width.isFinite ? checkboxSize.width : 24.0
        let safeHeight = checkboxSize.height.isFinite ? checkboxSize.height : 24.0
        
        // Position checkbox slightly below baseline for better text alignment
        return CGRect(
            origin: CGPoint(x: safeOriginX, y: safeOriginY), 
            size: CGSize(width: safeWidth, height: safeHeight)
        )
    }
    
    override func image(forBounds imageBounds: CGRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> UIImage? {
        print("🖼️ CheckboxTextAttachment.image: Called for bounds \(imageBounds), checked: \(isChecked)")
        
        // Always generate fresh image - no caching for proper state updates
        contents = nil
        image = nil
        
        // Store character index if not already set
        if characterRange.location == NSNotFound {
            characterRange = NSRange(location: charIndex, length: 1)
        }
        
        // Validate bounds to prevent CoreGraphics NaN errors
        let safeBounds = validateBounds(imageBounds)
        let generatedImage = generateCheckboxImage(bounds: safeBounds)
        
        print("✅ CheckboxTextAttachment.image: Generated fresh image with safe bounds \(safeBounds)")
        return generatedImage
    }
    
    // MARK: - Image Generation
    
    /// Validate bounds to prevent CoreGraphics NaN errors
    private func validateBounds(_ bounds: CGRect) -> CGRect {
        // Check for invalid values that cause CoreGraphics NaN errors
        let safeX = bounds.origin.x.isFinite ? bounds.origin.x : 0.0
        let safeY = bounds.origin.y.isFinite ? bounds.origin.y : 0.0
        let safeWidth = bounds.size.width.isFinite && bounds.size.width > 0 ? bounds.size.width : checkboxSize.width
        let safeHeight = bounds.size.height.isFinite && bounds.size.height > 0 ? bounds.size.height : checkboxSize.height
        
        return CGRect(
            x: safeX,
            y: safeY,
            width: safeWidth,
            height: safeHeight
        )
    }
    
    /// Generate a checkbox image with the current state
    private func generateCheckboxImage(bounds: CGRect) -> UIImage {
        // Additional bounds validation with fallback to default size
        let validatedBounds = validateBounds(bounds)
        
        // Ensure minimum size for proper rendering
        let finalBounds = CGRect(
            x: validatedBounds.origin.x,
            y: validatedBounds.origin.y,
            width: max(validatedBounds.width, 16.0), // Minimum width
            height: max(validatedBounds.height, 16.0) // Minimum height
        )
        
        let renderer = UIGraphicsImageRenderer(bounds: finalBounds)
        return renderer.image { context in
            let cgContext = context.cgContext
            
            // Set up drawing context with additional safety checks
            cgContext.setShouldAntialias(true)
            cgContext.setAllowsAntialiasing(true)
            
            // Draw checkbox background and border with safe insets
            let insetValue: CGFloat = min(2.0, finalBounds.width * 0.1, finalBounds.height * 0.1)
            let checkboxRect = finalBounds.insetBy(dx: insetValue, dy: insetValue)
            let cornerRadius: CGFloat = min(3.0, checkboxRect.width * 0.15, checkboxRect.height * 0.15)
            
            // Ensure the inset rectangle is still valid
            guard checkboxRect.width > 0 && checkboxRect.height > 0 else {
                // Fallback: draw a simple square if inset causes invalid dimensions
                cgContext.setFillColor(UIColor.systemGray3.cgColor)
                cgContext.fill(finalBounds)
                return
            }
            
            // Background color
            cgContext.setFillColor(UIColor.systemBackground.cgColor)
            
            // Border color - use system colors for proper light/dark mode support
            cgContext.setStrokeColor(UIColor.systemGray3.cgColor)
            cgContext.setLineWidth(max(1.0, min(1.5, checkboxRect.width * 0.05)))
            
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
        // Validate bounds before drawing to prevent NaN errors
        guard bounds.width > 0 && bounds.height > 0 && 
              bounds.width.isFinite && bounds.height.isFinite &&
              bounds.minX.isFinite && bounds.minY.isFinite else {
            print("⚠️ CheckboxTextAttachment: Invalid bounds for checkmark, skipping draw")
            return
        }
        
        context.setStrokeColor(UIColor.label.cgColor) // Use label color (black in light mode, white in dark mode)
        context.setLineWidth(max(1.0, min(2.0, bounds.width * 0.1))) // Scale line width to bounds
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        // Create checkmark path (similar to Apple's design) with validated coordinates
        let checkPath = UIBezierPath()
        
        // Calculate positions with bounds validation
        let startX = bounds.minX + bounds.width * 0.28
        let startY = bounds.minY + bounds.height * 0.53
        let midX = bounds.minX + bounds.width * 0.42
        let midY = bounds.minY + bounds.height * 0.66
        let endX = bounds.minX + bounds.width * 0.72
        let endY = bounds.minY + bounds.height * 0.36
        
        // Validate all coordinates before using them
        let safeStartX = startX.isFinite ? startX : bounds.minX
        let safeStartY = startY.isFinite ? startY : bounds.midY
        let safeMidX = midX.isFinite ? midX : bounds.midX
        let safeMidY = midY.isFinite ? midY : bounds.midY
        let safeEndX = endX.isFinite ? endX : bounds.maxX
        let safeEndY = endY.isFinite ? endY : bounds.minY
        
        checkPath.move(to: CGPoint(x: safeStartX, y: safeStartY))
        checkPath.addLine(to: CGPoint(x: safeMidX, y: safeMidY))
        checkPath.addLine(to: CGPoint(x: safeEndX, y: safeEndY))
        
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
                    print("🔄 CheckboxManager: Plain text converted checkbox state changed to \(newState)")
                    // The actual text view delegate notification will be set up by toggleCheckbox when first toggled
                }
                
                // Set up character range for this attachment (will be refined when text view is available)
                attachment.characterRange = NSRange(location: match.range.location, length: 1)
                
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
            
            // Set up character range for this attachment (will be refined when text view is available)
            attachment.characterRange = NSRange(location: match.range.location, length: 1)
            
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
        
        print("📝 CheckboxManager: Inserting new checkbox at range \(range)")
        
        let attachment = CheckboxTextAttachment(isChecked: isChecked)
        
        // CRITICAL: Set up text view reference and character range immediately
        attachment.textView = textView
        attachment.characterRange = NSRange(location: range.location, length: 1)
        
        // Set up immediate state change callback for future toggles
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            print("🔄 CheckboxManager: New checkbox state changed to \(newState)")
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
    
    /// Find checkbox attachment at a given tap location with enhanced tap-to-left detection
    static func findCheckboxAtLocation(_ location: CGPoint, in textView: UITextView) -> (attachment: CheckboxTextAttachment, range: NSRange)? {
        guard let attributedText = textView.attributedText else { return nil }
        
        // Use layout manager to find more precise location
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let locationInTextContainer = CGPoint(
            x: location.x - textView.textContainerInset.left,
            y: location.y - textView.textContainerInset.top
        )
        
        // Get the character index at the tap location
        let charIndex = layoutManager.characterIndex(for: locationInTextContainer, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        print("🎯 CheckboxManager.findCheckboxAtLocation: Tap at location \(location), charIndex: \(charIndex)")
        
        // ENHANCEMENT: First check direct tap on checkbox
        if charIndex < attributedText.length {
            if let attachment = attributedText.attribute(.attachment, at: charIndex, effectiveRange: nil) as? CheckboxTextAttachment {
                print("✅ CheckboxManager.findCheckboxAtLocation: Direct tap on checkbox at index \(charIndex)")
                return (attachment, NSRange(location: charIndex, length: 1))
            }
        }
        
        // ENHANCEMENT: Check for tap-to-left behavior with very generous search range
        // Look for checkboxes to the right of the tap location (very generous range for easy tapping)
        let searchRangeEnd = min(charIndex + 20, attributedText.length)
        for index in charIndex..<searchRangeEnd {
            if let attachment = attributedText.attribute(.attachment, at: index, effectiveRange: nil) as? CheckboxTextAttachment {
                // Found a checkbox to the right of the tap - this counts as tap-to-left
                print("🎯 CheckboxManager.findCheckboxAtLocation: Tap-to-left detected - checkbox at index \(index), tap at \(charIndex)")
                
                // Set up text view reference if missing
                if attachment.textView == nil {
                    attachment.textView = textView
                    attachment.characterRange = NSRange(location: index, length: 1)
                    print("🔧 CheckboxManager.findCheckboxAtLocation: Set up missing textView reference for checkbox")
                }
                
                return (attachment, NSRange(location: index, length: 1))
            }
        }
        
        // Check a very generous range around the tap location for easy tap targets
        let checkRange = max(0, charIndex - 10)...min(charIndex + 10, attributedText.length - 1)
        
        for index in checkRange {
            if let attachment = attributedText.attribute(.attachment, at: index, effectiveRange: nil) as? CheckboxTextAttachment {
                print("✅ CheckboxManager.findCheckboxAtLocation: Found checkbox near tap at index \(index)")
                
                // Set up text view reference if missing
                if attachment.textView == nil {
                    attachment.textView = textView
                    attachment.characterRange = NSRange(location: index, length: 1)
                    print("🔧 CheckboxManager.findCheckboxAtLocation: Set up missing textView reference for checkbox")
                }
                
                return (attachment, NSRange(location: index, length: 1))
            }
        }
        
        // Also check if we're at the beginning of a line with a checkbox
        let lineRange = (attributedText.string as NSString).lineRange(for: NSRange(location: min(charIndex, attributedText.length), length: 0))
        var foundCheckbox: (CheckboxTextAttachment, NSRange)?
        
        attributedText.enumerateAttribute(.attachment, in: lineRange, options: []) { value, range, stop in
            if let checkbox = value as? CheckboxTextAttachment {
                // Check if this checkbox is anywhere on the line (very generous line-level detection)
                // This makes it easy to tap anywhere on a checkbox line to toggle it
                print("✅ CheckboxManager.findCheckboxAtLocation: Found checkbox on line at range \(range)")
                
                // Set up text view reference if missing
                if checkbox.textView == nil {
                    checkbox.textView = textView
                    checkbox.characterRange = range
                    print("🔧 CheckboxManager.findCheckboxAtLocation: Set up missing textView reference for line checkbox")
                }
                
                foundCheckbox = (checkbox, range)
                stop.pointee = true
            }
        }
        
        return foundCheckbox
    }
    
    /// Toggle checkbox state and update the text view using model-backed system
    static func toggleCheckbox(_ attachment: CheckboxTextAttachment, in textView: UITextView, at range: NSRange) {
        print("🎯 CheckboxManager: Starting model-backed checkbox toggle for attachment at range \(range)")
        
        // CRITICAL: Ensure text view reference and range are properly set
        if attachment.textView == nil {
            attachment.textView = textView
            print("🔧 CheckboxManager: Set up missing textView reference")
        }
        
        if attachment.characterRange.location == NSNotFound {
            attachment.characterRange = range
            print("🔧 CheckboxManager: Set up missing characterRange: \(range)")
        }
        
        // Set up the state change callback to ensure immediate synchronization
        attachment.onStateChange = { [weak textView] newState in
            guard let textView = textView else { return }
            
            print("🔄 CheckboxManager: Model-backed state change callback triggered - new state: \(newState)")
            
            // The attachment's updateTextStorage method handles most of the update logic
            // We just need to ensure the text view delegate is notified for persistence
            DispatchQueue.main.async {
                textView.delegate?.textViewDidChange?(textView)
                print("✅ CheckboxManager: Notified delegate of model-backed checkbox state change")
            }
        }
        
        // Toggle the checkbox state (this will trigger the onStateChange callback and updateTextStorage)
        let oldState = attachment.isChecked
        attachment.isChecked.toggle()
        print("🔄 CheckboxManager: Model-backed toggle from \(oldState) to \(attachment.isChecked)")
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