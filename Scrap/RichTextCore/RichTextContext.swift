//
//  RichTextContext.swift
//  Scrap
//
//  Adapted from RichTextKit by Daniel Saidi
//  Customized for Scrap's specific needs
//

import SwiftUI
import Combine

/**
 This observable context manages the state of a rich text editor
 and provides a clean interface for text formatting operations.
 
 Key improvements over the original:
 - Simplified for mobile-first experience  
 - Optimized for bullet/checkbox lists
 - Better cursor positioning handling
 */
public class RichTextContext: ObservableObject {
    
    /// Create a new rich text context instance.
    public init() {}
    
    // MARK: - Text Content
    
    /// The currently attributed string (read-only to prevent editor redraws)
    public internal(set) var attributedString = NSAttributedString()
    
    /// The currently selected range
    public internal(set) var selectedRange = NSRange()
    
    // MARK: - Editor State
    
    /// Whether the rich text editor is editable
    @Published public var isEditable = true
    
    /// Whether text is currently being edited
    @Published public var isEditingText = false
    
    /// The current font name (validated to prevent font loading issues)
    @Published public var fontName = "SpaceGrotesk-Regular" {
        didSet {
            // Validate font name to ensure it's available
            if fontName.isEmpty {
                print("❌ RichTextContext: Empty fontName detected, reverting to SpaceGrotesk-Regular")
                fontName = "SpaceGrotesk-Regular"
            } else if UIFont(name: fontName, size: 16) == nil {
                print("⚠️ RichTextContext: Font '\(fontName)' not available, reverting to SpaceGrotesk-Regular")
                fontName = "SpaceGrotesk-Regular"
            }
        }
    }
    
    /// The current font size (validated to prevent NaN errors)
    @Published public var fontSize: CGFloat = 16 {
        didSet {
            // Validate font size to prevent CoreGraphics NaN errors
            if !fontSize.isFinite || fontSize.isNaN || fontSize <= 0 {
                print("❌ RichTextContext: Invalid fontSize (\(fontSize)) detected, reverting to 16")
                fontSize = 16.0
            } else if fontSize < 8.0 {
                print("⚠️ RichTextContext: fontSize (\(fontSize)) too small, clamping to 8.0")
                fontSize = 8.0
            } else if fontSize > 72.0 {
                print("⚠️ RichTextContext: fontSize (\(fontSize)) too large, clamping to 72.0")
                fontSize = 72.0
            }
        }
    }
    
    // MARK: - Formatting State
    
    /// Whether bold formatting is active
    @Published public internal(set) var isBoldActive = false
    
    /// Whether italic formatting is active
    @Published public internal(set) var isItalicActive = false
    
    /// Whether underline formatting is active
    @Published public internal(set) var isUnderlineActive = false
    
    /// Whether strikethrough formatting is active
    @Published public internal(set) var isStrikethroughActive = false
    
    /// Whether bullet list formatting is active
    @Published public internal(set) var isBulletListActive = false
    
    /// Whether checkbox formatting is active
    @Published public internal(set) var isCheckboxActive = false
    
    /// Whether code block formatting is active
    @Published public internal(set) var isCodeBlockActive = false
    
    // MARK: - Editor Capabilities
    
    /// Whether content can be copied
    @Published public internal(set) var canCopy = false
    
    /// Whether the last action can be undone
    @Published public internal(set) var canUndo = false
    
    /// Whether the last undo can be redone
    @Published public internal(set) var canRedo = false
    
    // MARK: - Action Publisher
    
    /// Publisher for sending actions to the text view coordinator
    public let actionPublisher = PassthroughSubject<RichTextAction, Never>()
    
    // MARK: - Public Methods
    
    /// Set the attributed string without causing editor redraws
    public func setAttributedString(_ attributedString: NSAttributedString) {
        self.attributedString = attributedString
        actionPublisher.send(.setAttributedString(attributedString))
        updateFormattingState()
    }
    
    /// Set the selected range and update formatting state
    public func setSelectedRange(_ range: NSRange) {
        // Ensure range is valid for current attributed string
        guard range.location >= 0 && range.location <= attributedString.length,
              range.length >= 0 && range.location + range.length <= attributedString.length else {
            // Set to safe default range
            selectedRange = NSRange(location: 0, length: 0)
            actionPublisher.send(.setSelectedRange(NSRange(location: 0, length: 0)))
            updateFormattingState()
            return
        }
        
        selectedRange = range
        actionPublisher.send(.setSelectedRange(range))
        updateFormattingState()
    }
    
    /// Toggle bold formatting
    public func toggleBold() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackBoldToggled(isActive: !isBoldActive)
        
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        // based on the actual text selection and current formatting
        actionPublisher.send(.toggleStyle(.bold))
    }
    
    /// Toggle italic formatting
    public func toggleItalic() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackItalicToggled(isActive: !isItalicActive)
        
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.italic))
    }
    
    /// Toggle underline formatting
    public func toggleUnderline() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackUnderlineToggled(isActive: !isUnderlineActive)
        
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.underline))
    }
    
    /// Toggle strikethrough formatting
    public func toggleStrikethrough() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackStrikethroughToggled(isActive: !isStrikethroughActive)
        
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.strikethrough))
    }
    
    /// Toggle bullet list formatting
    public func toggleBulletList() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackBulletListToggled(isActive: !isBulletListActive)
        
        isBulletListActive.toggle()
        isCheckboxActive = false // Exclusive with checkbox
        actionPublisher.send(.toggleBlockFormat(.bulletList))
    }
    
    /// Toggle checkbox formatting
    public func toggleCheckbox() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackCheckboxToggled(isActive: !isCheckboxActive)
        
        isCheckboxActive.toggle()
        isBulletListActive = false // Exclusive with bullet list
        actionPublisher.send(.toggleBlockFormat(.checkbox))
    }
    
    /// Toggle code block formatting
    public func toggleCodeBlock() {
        // Track analytics before toggling
        AnalyticsManager.shared.trackCodeBlockToggled(isActive: !isCodeBlockActive)
        
        // Don't immediately toggle state - let the coordinator determine the correct action
        // based on the actual text selection and current formatting
        // Code blocks are exclusive with lists
        isBulletListActive = false
        isCheckboxActive = false
        actionPublisher.send(.toggleBlockFormat(.codeBlock))
    }
    
    /// Increase indentation
    public func indentIn() {
        // Track analytics
        AnalyticsManager.shared.trackIndentChanged(direction: "in")
        
        actionPublisher.send(.indentIn)
    }
    
    /// Decrease indentation
    public func indentOut() {
        // Track analytics
        AnalyticsManager.shared.trackIndentChanged(direction: "out")
        
        actionPublisher.send(.indentOut)
    }
    
    /// Perform undo action
    public func undo() {
        guard canUndo else { return }
        actionPublisher.send(.undo)
    }
    
    /// Perform redo action  
    public func redo() {
        guard canRedo else { return }
        actionPublisher.send(.redo)
    }
    
    // MARK: - Internal State Updates
    
    /// Update formatting state based on current selection
    internal func updateFormattingState() {
        // Defer to avoid SwiftUI update conflicts
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.selectedRange.length >= 0 && self.attributedString.length > 0 else { return }
        
        // For cursor position (no selection), check if we're at the end of formatted text
        // If so, preserve the formatting intent for new text
        if self.selectedRange.length == 0 && self.selectedRange.location > 0 {
            // Check the character just before the cursor to see if it has formatting
            let prevIndex = self.selectedRange.location - 1
            if prevIndex < self.attributedString.length {
                let prevAttributes = self.attributedString.attributes(
                    at: prevIndex,
                    effectiveRange: nil
                )
                
                // If the previous character has bold formatting, maintain it for typing
                if let font = prevAttributes[.font] as? UIFont {
                    // Only consider text as bold if it has symbolic traits OR is explicitly SpaceGrotesk-Bold
                    // (not just any font name containing "Bold")
                    let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                    let isExplicitlyBold = font.fontName == "SpaceGrotesk-Bold" // Exact match only
                    let hadBold = hasTraitBold || isExplicitlyBold
                    if hadBold && !self.isBoldActive {
                        if Thread.isMainThread {
                            self.isBoldActive = true
                        } else {
                            DispatchQueue.main.async {
                                self.isBoldActive = true
                            }
                        }
                    }
                }
                
                // Check other formatting attributes
                if let underlineStyle = prevAttributes[.underlineStyle] as? Int, underlineStyle != 0 {
                    if !self.isUnderlineActive {
                        if Thread.isMainThread {
                            self.isUnderlineActive = true
                        } else {
                            DispatchQueue.main.async {
                                self.isUnderlineActive = true
                            }
                        }
                    }
                }
                
                if let strikethroughStyle = prevAttributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                    if !self.isStrikethroughActive {
                        if Thread.isMainThread {
                            self.isStrikethroughActive = true
                        } else {
                            DispatchQueue.main.async {
                                self.isStrikethroughActive = true
                            }
                        }
                    }
                }
            }
        }
        
        // Only read from cursor position if we have a selection or no previous character formatting
        if self.selectedRange.length > 0 || self.selectedRange.location == 0 {
            let safeIndex = max(0, min(self.selectedRange.location, self.attributedString.length - 1))
            guard safeIndex < self.attributedString.length else { return }
            
            let attributes = self.attributedString.attributes(
                at: safeIndex,
                effectiveRange: nil
            )
            
            // Update formatting state immediately for snappy response
            self.updateBoldState(from: attributes)
            self.updateItalicState(from: attributes)
            self.updateUnderlineState(from: attributes)
            self.updateStrikethroughState(from: attributes)
        }
        
            self.updateBlockFormatState()
        }
    }
    
    private func updateBoldState(from attributes: [NSAttributedString.Key: Any]) {
        let newBoldState: Bool
        if let font = attributes[.font] as? UIFont {
            // Check symbolic traits and only specific bold font names to prevent false positives
            let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            // Only consider exact matches for SpaceGrotesk-Bold, not partial matches
            let isExplicitlyBold = font.fontName == "SpaceGrotesk-Bold" || 
                                 font.fontName == "SpaceGrotesk-SemiBold" ||
                                 font.fontName == "SpaceGrotesk-Heavy"
            newBoldState = hasTraitBold || isExplicitlyBold
        } else {
            newBoldState = false
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isBoldActive = newBoldState
    }
    
    private func updateItalicState(from attributes: [NSAttributedString.Key: Any]) {
        let newItalicState: Bool
        if let font = attributes[.font] as? UIFont {
            newItalicState = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        } else {
            newItalicState = false
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isItalicActive = newItalicState
    }
    
    private func updateUnderlineState(from attributes: [NSAttributedString.Key: Any]) {
        let newUnderlineState: Bool
        if let underlineStyle = attributes[.underlineStyle] as? Int {
            newUnderlineState = underlineStyle != 0
        } else {
            newUnderlineState = false
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isUnderlineActive = newUnderlineState
    }
    
    private func updateStrikethroughState(from attributes: [NSAttributedString.Key: Any]) {
        let newStrikethroughState: Bool
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int {
            newStrikethroughState = strikethroughStyle != 0
        } else {
            newStrikethroughState = false
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isStrikethroughActive = newStrikethroughState
    }
    
    private func updateBlockFormatState() {
        // Check if current line has bullet, checkbox, or code block formatting
        let currentText = attributedString.string
        guard selectedRange.location < currentText.count else {
            self.isBulletListActive = false
            self.isCheckboxActive = false
            self.isCodeBlockActive = false
            return
        }
        
        // Find the current line
        let lineRange = (currentText as NSString).lineRange(for: selectedRange)
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Check for list markers and formatting
        let bulletActive = trimmedLine.hasPrefix("•")
        
        // Check for checkbox formatting - Unicode checkboxes
        var checkboxActive = trimmedLine.hasPrefix("☐") || trimmedLine.hasPrefix("☑")
        
        // Also check for Unicode checkboxes at the beginning of the line
        if !checkboxActive && attributedString.length > 0 {
            let lineStart = lineRange.location
            let leadingWhitespace = lineText.count - lineText.ltrimmed().count
            let checkboxPosition = lineStart + leadingWhitespace
            
            if checkboxPosition < attributedString.length {
                let character = (attributedString.string as NSString).character(at: checkboxPosition)
                // Check for Unicode checkbox characters ☐ ☑
                if character == 0x2610 || character == 0x2611 {
                    checkboxActive = true
                }
            }
        }
        
        // Check for code block formatting by looking at font attributes and surrounding context
        let codeBlockActive: Bool
        if attributedString.length > 0 {
            let detectedCodeBlock = isPositionInCodeBlock(selectedRange.location)
            
            // If we're currently in code block mode and the detection confirms we're still in a code block,
            // don't change the state to avoid button flickering
            if self.isCodeBlockActive && detectedCodeBlock {
                codeBlockActive = true
                print("🔒 RichTextContext: Keeping code block state active (preventing flicker)")
            } else {
                codeBlockActive = detectedCodeBlock
                print("🔍 RichTextContext: updateBlockFormatState - position: \(selectedRange.location), isCodeBlockActive: \(codeBlockActive)")
            }
        } else {
            codeBlockActive = false
            print("🔍 RichTextContext: updateBlockFormatState - empty text, isCodeBlockActive: false")
        }
        
        // Add logging for checkbox state detection
        if checkboxActive != self.isCheckboxActive {
            print("📋 RichTextContext: Checkbox state changing from \(self.isCheckboxActive) to \(checkboxActive) at position \(selectedRange.location)")
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isBulletListActive = bulletActive
        self.isCheckboxActive = checkboxActive
        
        // Add logging to track code block state changes
        if self.isCodeBlockActive != codeBlockActive {
            print("🔄 RichTextContext: Code block state changing from \(self.isCodeBlockActive) to \(codeBlockActive)")
        }
        self.isCodeBlockActive = codeBlockActive
    }
    
    /// Update undo/redo capabilities
    internal func updateUndoRedoState(canUndo: Bool, canRedo: Bool) {
        // Always defer to next run loop to avoid SwiftUI update conflicts
        DispatchQueue.main.async {
            self.canUndo = canUndo
            self.canRedo = canRedo
        }
    }
    
    /// Update copy capability
    internal func updateCopyState(_ canCopy: Bool) {
        // Always defer to next run loop to avoid SwiftUI update conflicts
        DispatchQueue.main.async {
            self.canCopy = canCopy
        }
    }
    
    // MARK: - Code Block Detection
    
    /// Check if the given position is within a code block with more robust detection
    private func isPositionInCodeBlock(_ position: Int) -> Bool {
        guard position >= 0 && attributedString.length > 0 else { 
            print("🔍 isPositionInCodeBlock: Invalid position \(position) or empty text (length: \(attributedString.length))")
            return false 
        }
        
        // If position is at the end of text, check the previous character
        let checkPosition = min(position, attributedString.length - 1)
        print("🔍 isPositionInCodeBlock: Checking position \(position), adjusted to \(checkPosition)")
        
        // First check the exact position
        if checkPosition < attributedString.length {
            let attributes = attributedString.attributes(at: checkPosition, effectiveRange: nil)
            
            // Check if position has monospaced font (indicates code block)
            if let font = attributes[.font] as? UIFont {
                let hasMonaco = font.fontName.contains("Monaco")
                let hasMonospaceTrait = font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
                let hasSystemMonospace = font.fontName.contains("SFMono") || font.fontName.contains("Menlo") || font.fontName.contains("Courier")
                let hasAppleSystemMonospace = font.fontName.contains(".AppleSystemUIFontMonospaced")
                let fontDescriptor = font.fontDescriptor
                print("🔍 isPositionInCodeBlock: Font at \(checkPosition):")
                print("   - Font name: \(font.fontName)")
                print("   - Font family: \(font.familyName)")
                print("   - Symbolic traits: \(fontDescriptor.symbolicTraits.rawValue)")
                print("   - hasMonaco: \(hasMonaco)")
                print("   - hasMonospaceTrait: \(hasMonospaceTrait)")
                print("   - hasSystemMonospace: \(hasSystemMonospace)")
                print("   - hasAppleSystemMonospace: \(hasAppleSystemMonospace)")
                
                if hasMonaco || hasMonospaceTrait || hasSystemMonospace || hasAppleSystemMonospace {
                    print("✅ isPositionInCodeBlock: Found monospaced font -> TRUE")
                    return true
                }
            }
            
            // Also check for grey background color (indicates code block)
            if let backgroundColor = attributes[.backgroundColor] as? UIColor {
                let isCodeBackground = backgroundColor == UIColor.systemGray6
                print("🔍 isPositionInCodeBlock: Background at \(checkPosition): \(backgroundColor), isCodeBackground: \(isCodeBackground)")
                if isCodeBackground {
                    print("✅ isPositionInCodeBlock: Found code background -> TRUE")
                    return true
                }
            } else {
                print("🔍 isPositionInCodeBlock: No background color at \(checkPosition)")
            }
        }
        
        // If cursor is at the end of text or position 0, also check neighboring positions
        // Check a small range around the position to catch edge cases
        let rangeStart = max(0, position - 2)
        let rangeEnd = min(attributedString.length - 1, position + 1)
        
        for pos in rangeStart...rangeEnd {
            if pos < attributedString.length {
                let attributes = attributedString.attributes(at: pos, effectiveRange: nil)
                
                if let font = attributes[.font] as? UIFont {
                    let hasMonaco = font.fontName.contains("Monaco")
                    let hasMonospaceTrait = font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
                    let hasSystemMonospace = font.fontName.contains("SFMono") || font.fontName.contains("Menlo") || font.fontName.contains("Courier")
                    let hasAppleSystemMonospace = font.fontName.contains(".AppleSystemUIFontMonospaced")
                    
                    if hasMonaco || hasMonospaceTrait || hasSystemMonospace || hasAppleSystemMonospace {
                        print("✅ isPositionInCodeBlock: Found monospaced font in nearby position \(pos) -> TRUE")
                        return true
                    }
                }
                
                if let backgroundColor = attributes[.backgroundColor] as? UIColor {
                    let isCodeBackground = backgroundColor == UIColor.systemGray6
                    if isCodeBackground {
                        print("✅ isPositionInCodeBlock: Found code background in nearby position \(pos) -> TRUE")
                        return true
                    }
                }
            }
        }
        
        print("❌ isPositionInCodeBlock: No code block detected -> FALSE")
        return false
    }
}

// MARK: - Rich Text Actions

public enum RichTextAction {
    case setAttributedString(NSAttributedString)
    case setSelectedRange(NSRange)
    case toggleStyle(RichTextStyle)
    case toggleBlockFormat(RichTextBlockFormat)
    case indentIn
    case indentOut
    case undo
    case redo
}

public enum RichTextStyle {
    case bold
    case italic
    case underline  
    case strikethrough
}

public enum RichTextBlockFormat {
    case bulletList
    case checkbox
    case codeBlock
}