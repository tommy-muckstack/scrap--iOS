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
    @Published public var fontName = "SharpGrotesk-Book"
    
    /// The current font size
    @Published public var fontSize: CGFloat = 17
    
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
        isBoldActive.toggle()
        actionPublisher.send(.toggleStyle(.bold))
    }
    
    /// Toggle italic formatting
    public func toggleItalic() {
        isItalicActive.toggle()
        actionPublisher.send(.toggleStyle(.italic))
    }
    
    /// Toggle underline formatting
    public func toggleUnderline() {
        isUnderlineActive.toggle()
        actionPublisher.send(.toggleStyle(.underline))
    }
    
    /// Toggle strikethrough formatting
    public func toggleStrikethrough() {
        isStrikethroughActive.toggle()
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
        // Defer all formatting updates to prevent publishing changes during view updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            guard self.selectedRange.length >= 0 && self.attributedString.length > 0 else { return }
            
            // Get attributes at current selection with safe bounds checking
            let safeIndex = max(0, min(self.selectedRange.location, self.attributedString.length - 1))
            guard safeIndex < self.attributedString.length else { return }
            
            let attributes = self.attributedString.attributes(
                at: safeIndex,
                effectiveRange: nil
            )
            
            // Update formatting state
            self.updateBoldState(from: attributes)
            self.updateItalicState(from: attributes)
            self.updateUnderlineState(from: attributes)
            self.updateStrikethroughState(from: attributes)
            self.updateBlockFormatState()
        }
    }
    
    private func updateBoldState(from attributes: [NSAttributedString.Key: Any]) {
        if let font = attributes[.font] as? UIFont {
            isBoldActive = font.fontDescriptor.symbolicTraits.contains(.traitBold)
        } else {
            isBoldActive = false
        }
    }
    
    private func updateItalicState(from attributes: [NSAttributedString.Key: Any]) {
        if let font = attributes[.font] as? UIFont {
            isItalicActive = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
        } else {
            isItalicActive = false
        }
    }
    
    private func updateUnderlineState(from attributes: [NSAttributedString.Key: Any]) {
        if let underlineStyle = attributes[.underlineStyle] as? Int {
            isUnderlineActive = underlineStyle != 0
        } else {
            isUnderlineActive = false
        }
    }
    
    private func updateStrikethroughState(from attributes: [NSAttributedString.Key: Any]) {
        if let strikethroughStyle = attributes[.strikethroughStyle] as? Int {
            isStrikethroughActive = strikethroughStyle != 0
        } else {
            isStrikethroughActive = false
        }
    }
    
    private func updateBlockFormatState() {
        // Check if current line has bullet or checkbox formatting
        let currentText = attributedString.string
        guard selectedRange.location < currentText.count else {
            isBulletListActive = false
            isCheckboxActive = false
            return
        }
        
        // Find the current line
        let lineRange = (currentText as NSString).lineRange(for: selectedRange)
        let lineText = (currentText as NSString).substring(with: lineRange)
        
        // Check for list markers
        let bulletActive = lineText.trimmingCharacters(in: .whitespaces).hasPrefix("•")
        let checkboxActive = lineText.trimmingCharacters(in: .whitespaces).hasPrefix("○") || 
                            lineText.trimmingCharacters(in: .whitespaces).hasPrefix("●")
        
        isBulletListActive = bulletActive
        isCheckboxActive = checkboxActive
    }
    
    /// Update undo/redo capabilities
    internal func updateUndoRedoState(canUndo: Bool, canRedo: Bool) {
        DispatchQueue.main.async {
            self.canUndo = canUndo
            self.canRedo = canRedo
        }
    }
    
    /// Update copy capability
    internal func updateCopyState(_ canCopy: Bool) {
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
}