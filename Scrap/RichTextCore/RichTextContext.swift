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
    
    /// The current font name
    @Published public var fontName = "SpaceGrotesk-Regular"
    
    /// The current font size
    @Published public var fontSize: CGFloat = 16
    
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
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        // based on the actual text selection and current formatting
        actionPublisher.send(.toggleStyle(.bold))
        
    }
    
    /// Toggle italic formatting
    public func toggleItalic() {
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.italic))
    }
    
    /// Toggle underline formatting
    public func toggleUnderline() {
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.underline))
    }
    
    /// Toggle strikethrough formatting
    public func toggleStrikethrough() {
        // Don't immediately toggle UI state - let the coordinator determine the correct action
        actionPublisher.send(.toggleStyle(.strikethrough))
    }
    
    /// Toggle bullet list formatting
    public func toggleBulletList() {
        isBulletListActive.toggle()
        isCheckboxActive = false // Exclusive with checkbox
        actionPublisher.send(.toggleBlockFormat(.bulletList))
    }
    
    /// Toggle checkbox formatting
    public func toggleCheckbox() {
        isCheckboxActive.toggle()
        isBulletListActive = false // Exclusive with bullet list
        actionPublisher.send(.toggleBlockFormat(.checkbox))
    }
    
    /// Toggle code block formatting
    public func toggleCodeBlock() {
        isCodeBlockActive.toggle()
        // Code blocks are exclusive with lists
        isBulletListActive = false
        isCheckboxActive = false
        actionPublisher.send(.toggleBlockFormat(.codeBlock))
    }
    
    /// Increase indentation
    public func indentIn() {
        actionPublisher.send(.indentIn)
    }
    
    /// Decrease indentation
    public func indentOut() {
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
                    let hadBold = font.fontDescriptor.symbolicTraits.contains(.traitBold) || 
                                 font.fontName.contains("Bold")
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
            // Check both symbolic traits and font name patterns for bold detection
            let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
            let hasBoldName = font.fontName.contains("Bold") || font.fontName.contains("SemiBold") || font.fontName.contains("Heavy")
            newBoldState = hasTraitBold || hasBoldName
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
        let checkboxActive = trimmedLine.hasPrefix("○") || trimmedLine.hasPrefix("●")
        
        // Check for code block formatting by looking at font attributes instead of text markers
        let codeBlockActive: Bool
        if selectedRange.location < attributedString.length && selectedRange.location >= 0 {
            let attributes = attributedString.attributes(at: max(0, min(selectedRange.location, attributedString.length - 1)), effectiveRange: nil)
            codeBlockActive = (attributes[.font] as? UIFont)?.fontName.contains("Monaco") == true
        } else {
            codeBlockActive = false
        }
        
        // Direct update since we're already in async context from updateFormattingState
        self.isBulletListActive = bulletActive
        self.isCheckboxActive = checkboxActive
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