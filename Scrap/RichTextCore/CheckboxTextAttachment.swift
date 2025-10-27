import UIKit
import Foundation

// MARK: - Checkbox Text Attachment
/// A native iOS NSTextAttachment implementation for checkboxes that replaces Unicode characters
/// This provides reliable tap targets, consistent appearance, and proper RTF persistence
class CheckboxTextAttachment: NSTextAttachment {
    
    // MARK: - Properties
    
    /// Static image cache for checkbox states - shared across all instances for better performance
    private static var imageCache: [String: UIImage] = [:]
    private static var cacheQueue = DispatchQueue(label: "checkbox.image.cache", qos: .userInteractive)
    
    /// The checkbox state - this is the source of truth
    var isChecked: Bool = false {
        didSet {
            print("🔔 CHECKBOX didSet: isChecked=\(isChecked), oldValue=\(oldValue), changed=\(isChecked != oldValue)")
            if isChecked != oldValue {
                print("✅ CHECKBOX didSet: State changed, proceeding with updates")
                // Clear cached content to force redraw (only instance-specific cache)
                contents = nil
                image = nil

                // Notify about state change for persistence
                print("📢 CHECKBOX didSet: Calling onStateChange callback")
                onStateChange?(isChecked)

                // Update the text storage to reflect the change
                print("📢 CHECKBOX didSet: About to call updateTextStorage()")
                updateTextStorage()
                print("✅ CHECKBOX didSet: Called updateTextStorage()")
            } else {
                print("⏭️ CHECKBOX didSet: State unchanged, skipping updates")
            }
        }
    }
    
    /// Callback for when checkbox state changes
    var onStateChange: ((Bool) -> Void)?
    
    /// Reference to the text view containing this attachment
    weak var textView: UITextView?

    /// Character range of this attachment in the text storage
    var characterRange: NSRange = NSRange(location: NSNotFound, length: 0)

    /// Flag to indicate if keyboard is currently animating (prevents visual glitches)
    var isKeyboardAnimating: Bool = false

    /// Size of the checkbox (optimized for easy touch targets)
    private let checkboxSize = CGSize(width: 28, height: 28)
    
    /// Clear the image cache - useful for memory management
    static func clearImageCache() {
        cacheQueue.async {
            imageCache.removeAll()
        }
    }
    
    // MARK: - Text Storage Integration
    
    /// Update the text storage to reflect the current checkbox state
    /// This ensures the checkbox state persists in the document and applies strikethrough formatting
    private func updateTextStorage() {
        print("🔧 updateTextStorage: Called for checkbox (checked=\(isChecked))")

        guard let textView = textView,
              characterRange.location != NSNotFound else {
            print("❌ updateTextStorage: Blocked - textView=\(textView != nil), characterRange.location=\(characterRange.location)")
            return
        }

        // If keyboard is animating, defer the visual update but still apply strikethrough
        if isKeyboardAnimating {
            print("⏰ updateTextStorage: Keyboard animating - deferring visual update")
            // Apply strikethrough to text storage immediately (data layer)
            applyStrikethroughToLine()

            // Defer visual update until animation completes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak textView] in
                guard let self = self, let textView = textView else { return }
                print("✅ updateTextStorage: Applying deferred visual update")
                self.forceVisualUpdate(textView: textView)
            }
            return
        }

        print("✅ updateTextStorage: Proceeding with immediate update")

        // Save current cursor position to prevent jumping
        let savedSelectedRange = textView.selectedRange

        let textStorage = textView.textStorage

        // Validate range bounds
        guard characterRange.location >= 0 &&
              characterRange.location < textStorage.length &&
              characterRange.length > 0 &&
              characterRange.location + characterRange.length <= textStorage.length else {
            return
        }

        // Apply strikethrough formatting to the entire line containing this checkbox
        applyStrikethroughToLine()

        // Force visual update immediately
        forceVisualUpdate(textView: textView)

        // Restore cursor position
        textView.selectedRange = savedSelectedRange

        // Notify text view delegate of content changes for state persistence
        DispatchQueue.main.async {
            textView.selectedRange = savedSelectedRange
            textView.delegate?.textViewDidChange?(textView)
        }
    }

    /// Force the visual update of strikethrough formatting
    private func forceVisualUpdate(textView: UITextView) {
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let textStorage = textView.textStorage

        // Get the line range for invalidation
        let text = textStorage.string as NSString
        let lineRange = text.lineRange(for: characterRange)

        // CRITICAL: Force immediate layout update even when keyboard is visible
        // This ensures strikethrough appears immediately when checking boxes during editing
        layoutManager.invalidateDisplay(forCharacterRange: lineRange)
        layoutManager.invalidateLayout(forCharacterRange: lineRange, actualCharacterRange: nil)

        // Force the layout manager to recalculate layout immediately
        layoutManager.ensureLayout(for: textContainer)

        // Force immediate redraw
        textView.setNeedsDisplay()
        textView.layoutIfNeeded()

        // Additional async update to ensure visibility
        DispatchQueue.main.async {
            textView.setNeedsDisplay()
        }
    }
    
    /// Apply or remove strikethrough formatting to the entire line containing this checkbox
    private func applyStrikethroughToLine() {
        print("📝 applyStrikethroughToLine: Called for checkbox (checked=\(isChecked))")

        guard let textView = textView else {
            print("❌ applyStrikethroughToLine: No textView")
            return
        }

        let textStorage = textView.textStorage
        let text = textStorage.string as NSString

        print("📝 applyStrikethroughToLine: characterRange=\(characterRange), textLength=\(textStorage.length)")

        // Find the line range containing this checkbox
        let lineRange = text.lineRange(for: characterRange)

        print("📝 applyStrikethroughToLine: lineRange=\(lineRange)")

        // Validate line range
        guard lineRange.location >= 0 &&
              lineRange.location + lineRange.length <= textStorage.length else {
            print("❌ applyStrikethroughToLine: Invalid line range")
            return
        }

        print("✅ applyStrikethroughToLine: Applying strikethrough=\(isChecked) to line")
        
        // Apply or remove strikethrough formatting to the entire line
        if isChecked {
            // Add strikethrough
            textStorage.addAttribute(.strikethroughStyle, 
                                   value: NSUnderlineStyle.single.rawValue, 
                                   range: lineRange)
            // Optionally dim the text color for checked items
            textStorage.addAttribute(.foregroundColor, 
                                   value: UIColor.secondaryLabel, 
                                   range: lineRange)
        } else {
            // Remove strikethrough
            textStorage.removeAttribute(.strikethroughStyle, range: lineRange)
            // Restore normal text color
            textStorage.addAttribute(.foregroundColor, 
                                   value: UIColor.label, 
                                   range: lineRange)
        }
        
        // Invalidate layout for the entire line to ensure proper redraw
        let layoutManager = textView.layoutManager
        layoutManager.invalidateDisplay(forCharacterRange: lineRange)
        layoutManager.invalidateLayout(forCharacterRange: lineRange, actualCharacterRange: nil)
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
        let safeOriginY: CGFloat = -10.0
        let safeWidth = checkboxSize.width.isFinite ? checkboxSize.width : 24.0
        let safeHeight = checkboxSize.height.isFinite ? checkboxSize.height : 24.0

        // Position checkbox to center-align with text baseline
        let bounds = CGRect(
            origin: CGPoint(x: safeOriginX, y: safeOriginY),
            size: CGSize(width: safeWidth, height: safeHeight)
        )

        // CRITICAL: Final validation to ensure no NaN values in returned rect
        // This prevents CoreGraphics errors even if calculations somehow produce NaN
        guard bounds.isValid else {
            // Fallback to safe default bounds if validation fails
            return CGRect(x: 0, y: -10, width: 24, height: 24)
        }

        return bounds
    }
    
    override func image(forBounds imageBounds: CGRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> UIImage? {
        // Store character index if not already set
        if characterRange.location == NSNotFound {
            characterRange = NSRange(location: charIndex, length: 1)
        }
        
        // Validate bounds to prevent CoreGraphics NaN errors
        let safeBounds = validateBounds(imageBounds)
        
        // Generate cache key based on state and bounds
        let cacheKey = "\(isChecked)_\(Int(safeBounds.width))x\(Int(safeBounds.height))"
        
        // Try to get cached image first
        if let cachedImage = Self.imageCache[cacheKey] {
            return cachedImage
        }
        
        // Generate new image and cache it
        let generatedImage = generateCheckboxImage(bounds: safeBounds)
        
        // Cache the generated image for future use
        Self.cacheQueue.async {
            Self.imageCache[cacheKey] = generatedImage
            
            // Prevent cache from growing too large - keep only last 20 images
            if Self.imageCache.count > 20 {
                let oldestKeys = Array(Self.imageCache.keys.prefix(10))
                for key in oldestKeys {
                    Self.imageCache.removeValue(forKey: key)
                }
            }
        }
        
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
        
        let attachment = CheckboxTextAttachment(isChecked: isChecked)
        
        // CRITICAL: Set up text view reference and character range immediately
        attachment.textView = textView
        attachment.characterRange = NSRange(location: range.location, length: 1)
        
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
    
    /// Find checkbox attachment at a given tap location - restrictive to checkbox icon area only
    static func findCheckboxAtLocation(_ location: CGPoint, in textView: UITextView) -> (attachment: CheckboxTextAttachment, range: NSRange)? {
        guard let attributedText = textView.attributedText else { return nil }
        
        // Use layout manager to find precise location
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        let locationInTextContainer = CGPoint(
            x: location.x - textView.textContainerInset.left,
            y: location.y - textView.textContainerInset.top
        )
        
        // Get the character index at the tap location
        let charIndex = layoutManager.characterIndex(for: locationInTextContainer, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)
        
        // Check direct tap on checkbox attachment only
        if charIndex < attributedText.length {
            if let attachment = attributedText.attribute(.attachment, at: charIndex, effectiveRange: nil) as? CheckboxTextAttachment {
                
                // Get the precise bounds of this checkbox attachment
                let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: charIndex, length: 1), actualCharacterRange: nil)
                let attachmentRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                let adjustedRect = CGRect(
                    x: attachmentRect.minX + textView.textContainerInset.left,
                    y: attachmentRect.minY + textView.textContainerInset.top,
                    width: attachmentRect.width,
                    height: attachmentRect.height
                )
                
                // Only respond if the tap is within the checkbox bounds (28x28 area)
                if adjustedRect.contains(location) {
                    // Set up text view reference if missing
                    if attachment.textView == nil {
                        attachment.textView = textView
                        attachment.characterRange = NSRange(location: charIndex, length: 1)
                    }

                    return (attachment, NSRange(location: charIndex, length: 1))
                }
            }
        }

        return nil
    }
    
    /// Toggle checkbox state and update the text view using model-backed system
    static func toggleCheckbox(_ attachment: CheckboxTextAttachment, in textView: UITextView, at range: NSRange) {
        print("🎯 toggleCheckbox: START - attachment.isChecked=\(attachment.isChecked), range=\(range)")

        // Save the current cursor position to restore it after toggle
        let originalSelectedRange = textView.selectedRange

        // CRITICAL: Completely disable all touch handling during checkbox toggle
        // This prevents UITextView from processing ANY touches that could move the cursor
        textView.isUserInteractionEnabled = false

        // CRITICAL: Ensure text view reference and range are properly set
        // Always update these as text positions can change due to edits
        attachment.textView = textView
        attachment.characterRange = range
        print("🎯 toggleCheckbox: Set textView, characterRange=\(range)")

        // Set up the state change callback to ensure immediate synchronization
        attachment.onStateChange = { [weak textView] newState in
            print("📢 toggleCheckbox onStateChange callback: newState=\(newState)")
            guard let textView = textView else { return }

            // Notify delegate for persistence
            DispatchQueue.main.async {
                textView.delegate?.textViewDidChange?(textView)
            }
        }
        print("🎯 toggleCheckbox: Set up onStateChange callback")

        // Toggle the checkbox state immediately (this will trigger the onStateChange callback and updateTextStorage)
        print("🎯 toggleCheckbox: About to call attachment.isChecked.toggle() - current value=\(attachment.isChecked)")
        attachment.isChecked.toggle()
        print("🎯 toggleCheckbox: AFTER toggle - new value=\(attachment.isChecked)")

        // Re-enable interaction and restore cursor position immediately
        DispatchQueue.main.async {
            // CRITICAL: Re-enable interaction first
            textView.isUserInteractionEnabled = true

            // CRITICAL: Restore cursor position EXACTLY where it was
            textView.selectedRange = originalSelectedRange

            // Force immediate redraw to show checkbox state change
            textView.setNeedsDisplay()
        }
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

// MARK: - CGRect Extension for NaN Validation
extension CGRect {
    /// Checks if the CGRect contains any NaN or Infinite values
    /// This prevents CoreGraphics errors when rendering checkboxes
    var isValid: Bool {
        return origin.x.isFinite &&
               origin.y.isFinite &&
               size.width.isFinite &&
               size.height.isFinite &&
               size.width > 0 &&
               size.height > 0
    }
}