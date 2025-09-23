//
//  RichTextCoordinator.swift
//  Scrap
//
//  Adapted from RichTextKit by Daniel Saidi
//  Customized for robust text synchronization and cursor positioning
//

import UIKit
import SwiftUI
import Combine

/**
 This coordinator manages the synchronization between a UITextView,
 SwiftUI binding, and RichTextContext. It handles the complex
 text delegate operations that were causing issues in the original implementation.
 
 Key improvements:
 - Prevents race conditions in text synchronization
 - Proper cursor positioning for list items  
 - Robust undo/redo handling
 - Clean separation of concerns
 */
public class RichTextCoordinator: NSObject {
    
    // MARK: - Properties
    
    private let textBinding: Binding<NSAttributedString>
    private var textView: UITextView
    private let context: RichTextContext
    private var cancellables = Set<AnyCancellable>()
    
    /// Prevents infinite loops during text synchronization
    private var isUpdatingFromContext = false
    public private(set) var isUpdatingFromTextView = false
    
    /// Prevents re-entrant calls during newline insertion
    private var isHandlingNewlineInsertion = false
    
    /// Prevents checkbox cursor detection during checkbox toggling
    private var isTogglingSelf = false
    
    /// Tracks when user has explicitly exited a code block to prevent automatic re-activation
    private var hasExplicitlyExitedCodeBlock = false
    
    /// Tracks the timestamp of the last user tap for tap-to-left behavior detection
    private var lastUserTapTime = Date()
    
    /// Drawing overlay manager for handling drawings as overlays instead of attachments
    weak var drawingManager: DrawingOverlayManager?
    
    // MARK: - Initialization
    
    public init(
        text: Binding<NSAttributedString>,
        textView: UITextView,
        context: RichTextContext
    ) {
        self.textBinding = text
        self.textView = textView
        self.context = context
        
        super.init()
        
        setupContextObservation()
        setupKeyboardNotifications()
    }
    
    deinit {
        // Clean up keyboard notifications
        NotificationCenter.default.removeObserver(self)
    }
    
    /// Connect this coordinator to the actual textView (called from makeUIView)
    public func connectTextView(_ textView: UITextView) {
        // Prevent duplicate connections to the same text view
        if self.textView === textView {
            print("⚠️ RichTextCoordinator: Already connected to this text view, skipping")
            return
        }
        
        // Clean up previous connection if exists
        if self.textView != textView {
            print("🧹 RichTextCoordinator: Disconnecting from previous text view \(self.textView)")
            self.textView.delegate = nil
        }
        
        self.textView = textView
        setupTextView()
        syncInitialState()
    }
    
    // MARK: - Setup
    
    private func setupTextView() {
        textView.delegate = self
        textView.allowsEditingTextAttributes = true
        textView.isEditable = true
        textView.isSelectable = true
        
        // CRITICAL: Ensure keyboard dismissal mode is always set
        // This can be reset by resignFirstResponder calls
        textView.keyboardDismissMode = .interactive
        
        // Configure for rich text editing
        textView.typingAttributes = [
            .font: UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize)),
            .foregroundColor: UIColor.label
        ]
        
        // Update typing attributes based on context state
        updateTypingAttributes()
        
        // Tap gesture for checkbox interaction is added by RichTextEditor
        // to avoid duplicate gesture recognizers that could conflict
    }
    
    private func setupContextObservation() {
        // Listen to context actions
        context.actionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] action in
                self?.handleContextAction(action)
            }
            .store(in: &cancellables)
    }
    
    private func setupKeyboardNotifications() {
        // Listen for keyboard events to restore interactive dismissal
        // This fixes the issue where swipe-to-dismiss stops working after the first use
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow(_:)),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }
    
    @objc private func keyboardWillShow(_ notification: Notification) {
        // Ensure keyboard dismissal mode is restored
        // This can be reset by manual resignFirstResponder calls
        DispatchQueue.main.async { [weak self] in
            self?.textView.keyboardDismissMode = .interactive
        }
    }
    
    @objc private func keyboardDidShow(_ notification: Notification) {
        // Double-check that interactive dismissal is still enabled
        // Some input accessory view operations can reset this
        DispatchQueue.main.async { [weak self] in
            if self?.textView.keyboardDismissMode != .interactive {
                self?.textView.keyboardDismissMode = .interactive
                print("🔧 RichTextCoordinator: Restored keyboard dismissal mode after keyboard appeared")
            }
        }
    }
    
    private func syncInitialState() {
        // Set initial content safely
        let initialText = textBinding.wrappedValue
        
        // Ensure we have a valid attributed string
        let safeInitialText = initialText.length > 0 ? initialText : NSAttributedString(string: "")
        
        if textView.attributedText != safeInitialText {
            textView.attributedText = safeInitialText
            context.setAttributedString(safeInitialText)
        }
        
        // Clean up any existing duplicate formatting
        cleanupDuplicateFormatting()
        
        // Ensure selectedRange is valid for the content
        let currentRange = textView.selectedRange
        let maxLocation = max(0, textView.attributedText?.length ?? 0)
        let safeRange = NSRange(
            location: min(currentRange.location, maxLocation),
            length: 0
        )
        textView.selectedRange = safeRange
        
        // Update initial formatting state
        updateContextFromTextView()
    }
    
    // MARK: - Context Action Handling
    
    private func handleContextAction(_ action: RichTextAction) {
        guard !isUpdatingFromTextView else { return }
        
        isUpdatingFromContext = true
        defer { isUpdatingFromContext = false }
        
        switch action {
        case .setAttributedString(let attributedString):
            updateTextView(with: attributedString)
            
        case .setSelectedRange(let range):
            updateSelectedRange(range)
            
        case .toggleStyle(let style):
            applyStyleToggle(style)
            
        case .toggleBlockFormat(let format):
            print("🎨 RichTextCoordinator: Received toggleBlockFormat action: \(format)")
            applyBlockFormat(format)
            
        case .indentIn:
            applyIndentation(increase: true)
            
        case .indentOut:
            applyIndentation(increase: false)
            
        case .undo:
            textView.undoManager?.undo()
            
        case .redo:
            textView.undoManager?.redo()
        }
    }
    
    // MARK: - Text View Updates
    
    private func updateTextView(with attributedString: NSAttributedString) {
        let currentRange = textView.selectedRange
        textView.attributedText = attributedString
        
        // Restore cursor position safely
        let newLocation = min(currentRange.location, attributedString.length)
        let safeRange = NSRange(location: newLocation, length: 0)
        textView.selectedRange = safeRange
        
        updateBindingFromTextView()
    }
    
    private func updateSelectedRange(_ range: NSRange) {
        let textLength = textView.attributedText?.length ?? 0
        let safeLocation = max(0, min(range.location, textLength))
        let remainingLength = textLength - safeLocation
        let safeLength = max(0, min(range.length, remainingLength))
        
        let safeRange = NSRange(location: safeLocation, length: safeLength)
        
        // Additional validation to prevent CoreGraphics errors
        if safeRange.location >= 0 && 
           safeRange.length >= 0 && 
           safeRange.location + safeRange.length <= textLength {
            textView.selectedRange = safeRange
        } else {
            // Fallback to cursor at end
            textView.selectedRange = NSRange(location: textLength, length: 0)
        }
    }
    
    // MARK: - Style Application
    
    private func applyStyleToggle(_ style: RichTextStyle) {
        let selectedRange = textView.selectedRange
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        guard selectedRange.location + selectedRange.length <= mutableText.length else { return }
        
        // Apply or remove the style
        switch style {
        case .bold:
            toggleBoldInRange(mutableText, selectedRange)
        case .italic:
            toggleItalicInRange(mutableText, selectedRange)
        case .underline:
            toggleUnderlineInRange(mutableText, selectedRange)
        case .strikethrough:
            toggleStrikethroughInRange(mutableText, selectedRange)
        }
        
        // Update text view and maintain selection
        textView.attributedText = mutableText
        textView.selectedRange = selectedRange
        
        // Update context state to reflect the new formatting state
        updateContextFromTextView()
        
        // For text selection, we no longer need to prevent context updates
        // The formatting should persist in the text itself
        print("🎯 RichTextCoordinator: Applied formatting to selection - text should persist")
        
        // Update typing attributes for future typing
        updateTypingAttributes()
        
        // Delay binding update to prevent overwriting formatting during rapid formatting changes
        // This is crucial for preserving previously applied formatting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.updateBindingFromTextView()
        }
    }
    
    private func toggleBoldInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        // Determine the action based on the actual text formatting, not context state
        var shouldAddBold = true
        var hasBoldText = false
        
        if range.length > 0 {
            // For selections, check if ANY text in selection is bold
            mutableText.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? UIFont {
                    // Check for SpaceGrotesk-Bold font or symbolic traits
                    if font.fontName == "SpaceGrotesk-Bold" || 
                       font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                        hasBoldText = true
                    }
                }
            }
            // If any text is bold, remove bold from all; otherwise add bold to all
            shouldAddBold = !hasBoldText
        } else {
            // For cursor position (no selection), check the current typing attributes
            // to determine if bold should be added or removed
            let currentFont = textView.typingAttributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: 16)
            // Use exact font name matching to prevent false positives
            let isBoldInTypingAttributes = currentFont.fontDescriptor.symbolicTraits.contains(.traitBold) || 
                                         currentFont.fontName == "SpaceGrotesk-Bold"
            shouldAddBold = !isBoldInTypingAttributes
        }
        
        print("🎯 RichTextCoordinator: Bold toggle - shouldAddBold: \(shouldAddBold), range: \(range)")
        
        // Debug available Space Grotesk fonts
        let availableFonts = UIFont.familyNames.filter { $0.contains("SpaceGrotesk") }
        print("📝 Available Space Grotesk fonts: \(availableFonts)")
        let spaceGroteskFonts = UIFont.fontNames(forFamilyName: "Space Grotesk")
        print("📝 Space Grotesk font names: \(spaceGroteskFonts)")
        // Test if bold font is actually available
        if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: 17) {
            print("✅ SpaceGrotesk-Bold is available: \(boldFont.fontName)")
        } else {
            print("❌ SpaceGrotesk-Bold is NOT available")
        }
        
        // Apply formatting consistently across the range
        if range.length > 0 {
            // For selections, apply to the selected text
            mutableText.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? UIFont {
                    let newFont: UIFont
                    let safeSize = safeFontSize(font.pointSize)
                    if shouldAddBold {
                        // Add bold - use specific SpaceGrotesk-Bold font
                        if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: safeSize) {
                            newFont = boldFont
                            print("✅ Applied SpaceGrotesk-Bold font at size \(safeSize)")
                        } else {
                            // Fallback to system bold font if custom font not available
                            newFont = UIFont.boldSystemFont(ofSize: safeSize)
                            print("⚠️ SpaceGrotesk-Bold not available, using system bold font")
                        }
                    } else {
                        // Remove bold - revert to regular SpaceGrotesk font
                        if let regularFont = UIFont(name: "SpaceGrotesk-Regular", size: safeSize) {
                            newFont = regularFont
                            print("✅ Applied SpaceGrotesk-Regular font at size \(safeSize)")
                        } else {
                            // Fallback to system regular font
                            newFont = UIFont.systemFont(ofSize: safeSize)
                            print("⚠️ SpaceGrotesk-Regular not available, using system regular font")
                        }
                    }
                    mutableText.addAttribute(.font, value: newFont, range: subRange)
                    print("🎯 Applied font '\(newFont.fontName)' to range \(subRange)")
                }
            }
        } else {
            // For cursor position, immediately update context state to reflect the intended formatting
            // This ensures that updateTypingAttributes() has the correct state to work with
            DispatchQueue.main.async {
                self.context.isBoldActive = shouldAddBold
                // Update typing attributes after context state is updated
                self.updateTypingAttributes()
            }
            return // Don't call updateTypingAttributes() again below
        }
        
        // For text selections, update typing attributes normally
        // Context state will be updated when updateContextFromTextView() is called
        self.updateTypingAttributes()
    }
    
    private func toggleItalicInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        var shouldAddItalic = true
        var hasItalicText = false
        
        if range.length > 0 {
            // For selections, check if ANY text in selection is italic
            mutableText.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? UIFont,
                   font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                    hasItalicText = true
                }
            }
            shouldAddItalic = !hasItalicText
        } else {
            // For cursor position, check the current typing attributes
            let currentFont = textView.typingAttributes[.font] as? UIFont ?? UIFont.systemFont(ofSize: 16)
            let isItalicInTypingAttributes = currentFont.fontDescriptor.symbolicTraits.contains(.traitItalic)
            shouldAddItalic = !isItalicInTypingAttributes
        }
        
        if range.length > 0 {
            // Apply to selection
            mutableText.enumerateAttribute(.font, in: range) { value, subRange, _ in
                if let font = value as? UIFont {
                    let newFont: UIFont
                    if shouldAddItalic {
                        // Add italic
                        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
                        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                            newFont = UIFont(descriptor: descriptor, size: safeFontSize(font.pointSize))
                        } else {
                            newFont = UIFont.italicSystemFont(ofSize: safeFontSize(font.pointSize))
                        }
                    } else {
                        // Remove italic
                        let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitItalic)
                        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                            newFont = UIFont(descriptor: descriptor, size: safeFontSize(font.pointSize))
                        } else {
                            newFont = UIFont(name: context.fontName, size: safeFontSize(font.pointSize)) ?? font
                        }
                    }
                    mutableText.addAttribute(.font, value: newFont, range: subRange)
                }
            }
        } else {
            // For cursor position, immediately update context state to reflect the intended formatting
            DispatchQueue.main.async {
                self.context.isItalicActive = shouldAddItalic
                // Update typing attributes after context state is updated
                self.updateTypingAttributes()
            }
            return // Don't call updateTypingAttributes() again below
        }
        
        // For text selections, update typing attributes normally
        self.updateTypingAttributes()
    }
    
    private func toggleUnderlineInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        var shouldAddUnderline = true
        
        if range.length > 0 {
            // Check if any text has underline
            var hasUnderline = false
            mutableText.enumerateAttribute(.underlineStyle, in: range) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    hasUnderline = true
                }
            }
            shouldAddUnderline = !hasUnderline
        } else {
            // For cursor position, check the current typing attributes
            let currentUnderlineStyle = textView.typingAttributes[.underlineStyle] as? Int ?? 0
            shouldAddUnderline = currentUnderlineStyle == 0
        }
        
        if range.length > 0 {
            // Apply to selection
            mutableText.enumerateAttribute(.underlineStyle, in: range) { value, subRange, _ in
                let newStyle = shouldAddUnderline ? NSUnderlineStyle.single.rawValue : 0
                mutableText.addAttribute(.underlineStyle, value: newStyle, range: subRange)
            }
        } else {
            // For cursor position, immediately update context state to reflect the intended formatting
            DispatchQueue.main.async {
                self.context.isUnderlineActive = shouldAddUnderline
                // Update typing attributes after context state is updated
                self.updateTypingAttributes()
            }
            return // Don't call updateTypingAttributes() again below
        }
        
        // For text selections, update typing attributes normally
        self.updateTypingAttributes()
    }
    
    private func toggleStrikethroughInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        var shouldAddStrikethrough = true
        
        if range.length > 0 {
            // Check if any text has strikethrough
            var hasStrikethrough = false
            mutableText.enumerateAttribute(.strikethroughStyle, in: range) { value, _, _ in
                if let style = value as? Int, style != 0 {
                    hasStrikethrough = true
                }
            }
            shouldAddStrikethrough = !hasStrikethrough
        } else {
            // For cursor position, check the current typing attributes
            let currentStrikethroughStyle = textView.typingAttributes[.strikethroughStyle] as? Int ?? 0
            shouldAddStrikethrough = currentStrikethroughStyle == 0
        }
        
        if range.length > 0 {
            // Apply to selection
            mutableText.enumerateAttribute(.strikethroughStyle, in: range) { value, subRange, _ in
                let newStyle = shouldAddStrikethrough ? NSUnderlineStyle.single.rawValue : 0
                mutableText.addAttribute(.strikethroughStyle, value: newStyle, range: subRange)
            }
        } else {
            // For cursor position, immediately update context state to reflect the intended formatting
            DispatchQueue.main.async {
                self.context.isStrikethroughActive = shouldAddStrikethrough
                // Update typing attributes after context state is updated
                self.updateTypingAttributes()
            }
            return // Don't call updateTypingAttributes() again below
        }
        
        // For text selections, update typing attributes normally
        self.updateTypingAttributes()
    }
    
    // MARK: - Block Format Application
    
    private func applyBlockFormat(_ format: RichTextBlockFormat) {
        let selectedRange = textView.selectedRange
        let text = textView.text ?? ""
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        // Find the current line
        let lineRange = (text as NSString).lineRange(for: selectedRange)
        let lineText = (text as NSString).substring(with: lineRange)
        
        switch format {
        case .bulletList:
            applyBulletFormat(mutableText, lineRange, lineText)
        case .checkbox:
            applyCheckboxFormat(mutableText, lineRange, lineText)
        case .codeBlock:
            applyCodeBlockFormat(mutableText, lineRange, lineText)
        case .drawing:
            print("🎨 RichTextCoordinator: Handling .drawing block format at range \(selectedRange)")
            applyDrawingFormat(selectedRange)
        }
        
        updateBindingFromTextView()
    }
    
    private func applyBulletFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add bullet to empty line and position cursor after it
            let mutableLineText = "• "
            let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            
            // Clear formatting from bullet character only (first 2 characters: "• ")
            let bulletRange = NSRange(location: lineRange.location, length: 2)
            if bulletRange.location + bulletRange.length <= mutableText.length {
                // Apply clean attributes to bullet point only
                mutableText.removeAttribute(.font, range: bulletRange)
                mutableText.removeAttribute(.foregroundColor, range: bulletRange)
                mutableText.removeAttribute(.backgroundColor, range: bulletRange)
                mutableText.removeAttribute(.underlineStyle, range: bulletRange)
                mutableText.removeAttribute(.strikethroughStyle, range: bulletRange)
                
                // Set basic font for bullet
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: bulletRange)
                mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: bulletRange)
            }
            
            textView.attributedText = mutableText
            let newCursorPosition = lineRange.location + 2 // Position after "• "
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added bullet to empty line, cursor at position \(safePosition)")
            return
        }
        
        let mutableLineText: String
        let newCursorPosition: Int
        
        // Check if line already has a bullet (prevent duplicates)
        if trimmedLine.hasPrefix("• ") {
            // Remove bullet - keep cursor at the beginning of the content
            mutableLineText = String(trimmedLine.dropFirst(2))
            newCursorPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count) + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing bullet from line")
        } else if trimmedLine.hasPrefix("•") {
            // Line starts with bullet (but no space) - remove it completely
            mutableLineText = String(trimmedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            newCursorPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count) + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing bullet (no space) from line")
        } else if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // Replace checkbox with bullet - cursor goes after "• "
            let contentAfterCheckbox = String(trimmedLine.dropFirst(2))
            mutableLineText = "• " + contentAfterCheckbox
            newCursorPosition = lineRange.location + 2 // Position after "• "
            print("🔸 RichTextCoordinator: Replacing checkbox with bullet")
        } else if !trimmedLine.contains("•") {
            // Add bullet only if line doesn't already contain bullets - cursor goes after "• "
            mutableLineText = "• " + trimmedLine
            newCursorPosition = lineRange.location + 2 // Position after "• "
            print("🔸 RichTextCoordinator: Adding bullet to line")
        } else {
            // Line already contains bullets somewhere - clean up duplicates instead of adding more
            print("🚫 RichTextCoordinator: Line contains bullets - cleaning up duplicates")
            mutableLineText = cleanupDuplicateBullets(trimmedLine)
            newCursorPosition = lineRange.location + 2 // Position after single "• "
        }
        
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Clear formatting from bullet character only (first 2 characters: "• ")
        if mutableLineText.hasPrefix("• ") {
            let bulletRange = NSRange(location: lineRange.location, length: min(2, newLine.count))
            if bulletRange.location + bulletRange.length <= mutableText.length {
                // Apply clean attributes to bullet point only
                mutableText.removeAttribute(.font, range: bulletRange)
                mutableText.removeAttribute(.foregroundColor, range: bulletRange)
                mutableText.removeAttribute(.backgroundColor, range: bulletRange)
                mutableText.removeAttribute(.underlineStyle, range: bulletRange)
                mutableText.removeAttribute(.strikethroughStyle, range: bulletRange)
                
                // Set basic font for bullet
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: bulletRange)
                mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: bulletRange)
            }
        }
        
        // Update text view with correct cursor position
        textView.attributedText = mutableText
        
        // Ensure cursor position is valid for the new text length
        let safePosition = min(newCursorPosition, mutableText.length)
        textView.selectedRange = NSRange(location: safePosition, length: 0)
        
        print("🎯 RichTextCoordinator: Bullet format applied - result: '\(mutableLineText)', cursor at position \(safePosition)")
    }
    
    /// Clean up duplicate bullets on a line, keeping only one at the start
    private func cleanupDuplicateBullets(_ line: String) -> String {
        // Remove all bullet points and clean up extra spaces
        let withoutBullets = line.replacingOccurrences(of: "• ", with: "").trimmingCharacters(in: .whitespaces)
        // Add single bullet at start
        return "• " + withoutBullets
    }
    
    /// Clean up the entire text content to remove duplicate bullets/checkboxes
    public func cleanupDuplicateFormatting() {
        let currentText = textView.attributedText?.string ?? ""
        let lines = currentText.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Count bullets and checkboxes
            let bulletCount = trimmedLine.components(separatedBy: "• ").count - 1
            let checkboxCount = (trimmedLine.components(separatedBy: "☐ ").count - 1) + 
                               (trimmedLine.components(separatedBy: "☑ ").count - 1)
            
            if bulletCount > 1 {
                // Multiple bullets - clean up
                let cleanedLine = cleanupDuplicateBullets(trimmedLine)
                cleanedLines.append(cleanedLine)
                print("🧹 RichTextCoordinator: Cleaned duplicate bullets: '\(trimmedLine)' → '\(cleanedLine)'")
            } else if checkboxCount > 1 {
                // Multiple checkboxes - clean up
                let cleanedLine = cleanupDuplicateCheckboxes(trimmedLine)
                cleanedLines.append(cleanedLine)
                print("🧹 RichTextCoordinator: Cleaned duplicate checkboxes: '\(trimmedLine)' → '\(cleanedLine)'")
            } else {
                // Line is clean
                cleanedLines.append(line)
            }
        }
        
        let cleanedText = cleanedLines.joined(separator: "\n")
        if cleanedText != currentText {
            let attributedCleanedText = NSAttributedString(string: cleanedText)
            textView.attributedText = attributedCleanedText
            updateBindingFromTextView()
            print("✅ RichTextCoordinator: Text cleanup completed - removed duplicate formatting")
        }
    }
    
    /// Clean up duplicate checkboxes on a line, keeping only one at the start
    private func cleanupDuplicateCheckboxes(_ line: String) -> String {
        // Remove all checkboxes but preserve spaces after content
        var withoutCheckboxes = line.replacingOccurrences(of: "☐ ", with: "")
                                   .replacingOccurrences(of: "☑ ", with: "")
        
        // Only trim leading whitespace, preserve trailing and internal spaces
        while withoutCheckboxes.hasPrefix(" ") {
            withoutCheckboxes = String(withoutCheckboxes.dropFirst())
        }
        
        // Add single checkbox at start (preserve checked state if any were checked)
        let hadCheckedBox = line.contains("☑ ")
        let checkboxString = createUnicodeCheckbox(isChecked: hadCheckedBox)
        let spaceString = NSAttributedString(string: " ")
        let checkboxWithSpace = NSMutableAttributedString()
        checkboxWithSpace.append(checkboxString)
        checkboxWithSpace.append(spaceString)
        return checkboxWithSpace.string + withoutCheckboxes
    }
    
    private func applyCheckboxFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add NSTextAttachment checkbox for reliable tap detection and consistent sizing
            let attachment = CheckboxTextAttachment(isChecked: false)
            
            // Create attachment string with proper font context to ensure rendering compatibility
            let checkboxString = NSMutableAttributedString(attachment: attachment)
            // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
            let systemFont = UIFont.systemFont(ofSize: context.fontSize)
            checkboxString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: checkboxString.length))
            
            let spaceString = NSAttributedString(string: " ")
            
            let checkboxWithSpace = NSMutableAttributedString()
            checkboxWithSpace.append(checkboxString)
            checkboxWithSpace.append(spaceString)
            
            if lineText.hasSuffix("\n") {
                checkboxWithSpace.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: checkboxWithSpace)
            
            textView.attributedText = mutableText
            let newCursorPosition = lineRange.location + 2 // Position after checkbox + space
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added NSTextAttachment checkbox to empty line, cursor at position \(safePosition)")
            return
        }
        
        // Check for existing NSTextAttachment checkboxes first
        var hasCheckboxAttachment = false
        mutableText.enumerateAttribute(.attachment, in: lineRange, options: []) { value, _, _ in
            if value is CheckboxTextAttachment {
                hasCheckboxAttachment = true
            }
        }
        
        if hasCheckboxAttachment {
            // Remove existing checkbox attachment
            let mutableLine = NSMutableAttributedString(attributedString: mutableText.attributedSubstring(from: lineRange))
            mutableLine.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutableLine.length), options: [.reverse]) { value, range, _ in
                if value is CheckboxTextAttachment {
                    mutableLine.deleteCharacters(in: range)
                }
            }
            
            // Also remove the space after checkbox if present
            if mutableLine.length > 0 && mutableLine.string.hasPrefix(" ") {
                mutableLine.deleteCharacters(in: NSRange(location: 0, length: 1))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: mutableLine)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location
            textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
            print("🔸 RichTextCoordinator: Removed NSTextAttachment checkbox from line")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        }
        
        // Check for legacy Unicode checkboxes (for backward compatibility)
        if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // TODO: Remove Unicode checkbox and replace with NSTextAttachment when CheckboxTextAttachment.swift is added
            // For now, keep the Unicode checkbox as is
            let contentAfterCheckbox = String(trimmedLine.dropFirst(2))
            let checkboxString = NSAttributedString(string: trimmedLine.hasPrefix("☑") ? "☑ " : "☐ ")
            let contentString = NSAttributedString(string: contentAfterCheckbox)
            
            let checkboxWithContent = NSMutableAttributedString()
            checkboxWithContent.append(checkboxString)
            checkboxWithContent.append(contentString)
            
            if lineText.hasSuffix("\n") {
                checkboxWithContent.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: checkboxWithContent)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 2 // Position after checkbox + space
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            
            print("🔸 RichTextCoordinator: Converted Unicode checkbox to NSTextAttachment")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        } else if trimmedLine.hasPrefix("• ") {
            // Replace bullet with NSTextAttachment checkbox
            let contentAfterBullet = String(trimmedLine.dropFirst(2))
            let attachment = CheckboxTextAttachment(isChecked: false)
            
            // Create attachment string with proper font context to ensure rendering compatibility
            let checkboxString = NSMutableAttributedString(attachment: attachment)
            // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
            let systemFont = UIFont.systemFont(ofSize: context.fontSize)
            checkboxString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: checkboxString.length))
            
            let spaceString = NSAttributedString(string: " ")
            let contentString = NSAttributedString(string: contentAfterBullet)
            
            let checkboxWithContent = NSMutableAttributedString()
            checkboxWithContent.append(checkboxString)
            checkboxWithContent.append(spaceString)
            checkboxWithContent.append(contentString)
            
            if lineText.hasSuffix("\n") {
                checkboxWithContent.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: checkboxWithContent)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 2 // Position after checkbox + space
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            
            print("🔸 RichTextCoordinator: Replaced bullet with NSTextAttachment checkbox")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        } else if !trimmedLine.contains("☐") && !trimmedLine.contains("☑") {
            // Add NSTextAttachment checkbox to line with content
            let attachment = CheckboxTextAttachment(isChecked: false)
            
            // Create attachment string with proper font context to ensure rendering compatibility
            let checkboxString = NSMutableAttributedString(attachment: attachment)
            // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
            let systemFont = UIFont.systemFont(ofSize: context.fontSize)
            checkboxString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: checkboxString.length))
            
            let spaceString = NSAttributedString(string: " ")
            let contentString = NSAttributedString(string: trimmedLine)
            
            let checkboxWithContent = NSMutableAttributedString()
            checkboxWithContent.append(checkboxString)
            checkboxWithContent.append(spaceString)
            checkboxWithContent.append(contentString)
            
            if lineText.hasSuffix("\n") {
                checkboxWithContent.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: checkboxWithContent)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 2 // Position after checkbox + space
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            
            print("🔸 RichTextCoordinator: Added NSTextAttachment checkbox to line")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        } else {
            // Line already contains legacy checkboxes - don't add another
            print("🚫 RichTextCoordinator: Line already contains legacy checkboxes - not adding another")
            return
        }
    }
    
    private func applyCodeBlockFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        // Reset the explicit exit flag since user is manually toggling code block
        hasExplicitlyExitedCodeBlock = false
        
        // Check if cursor is currently in a code block using the same reliable detection method
        let cursorPosition = textView.selectedRange.location
        let isInCodeBlock = checkIfPositionIsInCodeBlock(cursorPosition)
        
        // Code block format check at cursor position
        
        var newCursorPosition: Int? = nil
        
        if isInCodeBlock {
            // Turn OFF code formatting - implement behavior for toggling off
            if context.isCodeBlockActive {
                // Exit code block and move to next line
                exitCodeBlockAndMoveToNextLine(at: cursorPosition, in: mutableText)
                print("🔸 RichTextCoordinator: Exiting code mode and moving to next line")
                
                // Update text view with changes
                textView.attributedText = mutableText
                updateBindingFromTextView()
            } else {
                // Just turn off without moving cursor (fallback)
                exitCodeBlockInPlace(at: cursorPosition)
                print("🔸 RichTextCoordinator: Exiting code mode in place without moving cursor")
            }
        } else {
            // Turn ON code formatting - create new code block with cursor inside
            newCursorPosition = createCodeBlockAndMoveCursor(at: cursorPosition, in: mutableText)
            print("🔸 RichTextCoordinator: Creating new code block with cursor inside")
            
            // Update text view and set cursor position
            textView.attributedText = mutableText
            
            // Set cursor position AFTER updating the text view to prevent UIKit from resetting it
            if let targetPosition = newCursorPosition {
                textView.selectedRange = NSRange(location: targetPosition, length: 0)
                print("🎯 Set cursor position to \(targetPosition) AFTER text view update")
            }
            
            // Immediately set the context state to show button as active
            // This prevents the race condition where the button doesn't appear selected
            DispatchQueue.main.async {
                self.context.isCodeBlockActive = true
                // Set context.isCodeBlockActive = true
            }
            
            updateBindingFromTextView()
        }
        
        // Always update context to reflect the current state
        // This will be called after the immediate state update above for creation
        updateContextFromTextView()
        
        print("🎯 RichTextCoordinator: Code block format applied")
    }
    
    // MARK: - Code Block Helper Methods
    
    /// Check if the given position is within a code block
    private func isPositionInCodeBlock(_ position: Int, in attributedText: NSMutableAttributedString) -> Bool {
        guard position >= 0 && position < attributedText.length else { return false }
        
        let attributes = attributedText.attributes(at: position, effectiveRange: nil)
        
        // Check if position has monospaced font (indicates code block)
        if let font = attributes[.font] as? UIFont {
            let hasMonaco = font.fontName.contains("Monaco")
            let hasMonospaceTrait = font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            let hasSystemMonospace = font.fontName.contains("SFMono") || font.fontName.contains("Menlo") || font.fontName.contains("Courier")
            let hasAppleSystemMonospace = font.fontName.contains(".AppleSystemUIFontMonospaced")
            
            if hasMonaco || hasMonospaceTrait || hasSystemMonospace || hasAppleSystemMonospace {
                return true
            }
        }
        
        // Also check for grey background color (indicates code block)
        if let backgroundColor = attributes[.backgroundColor] as? UIColor {
            if backgroundColor == UIColor.systemGray6 {
                return true
            }
        }
        
        return false
    }
    
    /// Create a new code block and position cursor inside it
    /// Returns the desired cursor position for after the text view is updated
    private func createCodeBlockAndMoveCursor(at position: Int, in mutableText: NSMutableAttributedString) -> Int {
        // Create code block text - start directly with spaces, no leading newline
        let codeBlockText = "    "  // Just padding spaces, no newlines
        
        // Insert the code block at current position
        let insertRange = NSRange(location: position, length: 0)
        mutableText.replaceCharacters(in: insertRange, with: codeBlockText)
        
        // Apply code block formatting to the entire block
        let codeBlockRange = NSRange(location: position, length: codeBlockText.count)
        
        // Set monospaced font for code blocks
        let monospacedFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        print("🔧 createCodeBlockAndMoveCursor: Applied monospaced font:")
        print("   - Font name: \(monospacedFont.fontName)")
        print("   - Font family: \(monospacedFont.familyName)")
        print("   - Symbolic traits: \(monospacedFont.fontDescriptor.symbolicTraits.rawValue)")
        print("   - Has monospace trait: \(monospacedFont.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))")
        mutableText.addAttribute(.font, value: monospacedFont, range: codeBlockRange)
        
        // Set grey background for the full width effect
        mutableText.addAttribute(.backgroundColor, value: UIColor.systemGray6, range: codeBlockRange)
        
        // Set green text color for code
        mutableText.addAttribute(.foregroundColor, value: UIColor.systemGreen, range: codeBlockRange)
        
        // Add paragraph style for better spacing and appearance
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2
        paragraphStyle.paragraphSpacing = 4
        paragraphStyle.firstLineHeadIndent = 16  // Left padding
        paragraphStyle.headIndent = 16           // Left padding for wrapped lines
        paragraphStyle.tailIndent = -16         // Right padding (negative value)
        mutableText.addAttribute(.paragraphStyle, value: paragraphStyle, range: codeBlockRange)
        
        // Calculate cursor position at the end of the code block (after the spaces)
        let cursorPosition = position + codeBlockText.count
        
        print("📦 Created code block with padding at position \(position), will set cursor at \(cursorPosition)")
        return cursorPosition
    }
    
    /// Exit code block and move cursor to line below
    private func exitCodeBlockAndMoveCursor(at position: Int, in mutableText: NSMutableAttributedString) {
        // Find the range of the current code block more aggressively to catch all remnants
        var codeBlockStart = position
        var codeBlockEnd = position
        
        // Expand search range to catch more remnants
        let searchBackward = min(position, 50) // Look back up to 50 characters
        let searchForward = min(mutableText.length - position, 50) // Look forward up to 50 characters
        
        // Find start of code block (look backwards for first non-code-block character)
        codeBlockStart = max(0, position - searchBackward)
        while codeBlockStart < position {
            let attributes = mutableText.attributes(at: codeBlockStart, effectiveRange: nil)
            if isAttributesInCodeBlock(attributes) {
                break
            }
            codeBlockStart += 1
        }
        
        // Find end of code block (look forwards for first non-code-block character)
        codeBlockEnd = min(mutableText.length, position + searchForward)
        while codeBlockEnd > position {
            let attributes = mutableText.attributes(at: codeBlockEnd - 1, effectiveRange: nil)
            if isAttributesInCodeBlock(attributes) {
                break
            }
            codeBlockEnd -= 1
        }
        
        // Expand the range to include any adjacent monospaced text
        while codeBlockStart > 0 {
            let prevAttributes = mutableText.attributes(at: codeBlockStart - 1, effectiveRange: nil)
            if isAttributesInCodeBlock(prevAttributes) {
                codeBlockStart -= 1
            } else {
                break
            }
        }
        
        while codeBlockEnd < mutableText.length {
            let attributes = mutableText.attributes(at: codeBlockEnd, effectiveRange: nil)
            if isAttributesInCodeBlock(attributes) {
                codeBlockEnd += 1
            } else {
                break
            }
        }
        
        let codeBlockRange = NSRange(location: codeBlockStart, length: codeBlockEnd - codeBlockStart)
        print("🔄 exitCodeBlockAndMoveCursor: Found code block at range \(codeBlockRange)")
        
        // Remove code block formatting and replace with normal text formatting while preserving text attributes
        if codeBlockRange.length > 0 {
            // Process each character in the code block to preserve non-code-block formatting
            let codeBlockText = mutableText.attributedSubstring(from: codeBlockRange)
            let normalizedText = NSMutableAttributedString()
            
            codeBlockText.enumerateAttributes(in: NSRange(location: 0, length: codeBlockText.length), options: []) { attributes, range, _ in
                let substring = codeBlockText.attributedSubstring(from: range)
                
                // Start with normal base attributes
                let normalFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
                var normalAttributes: [NSAttributedString.Key: Any] = [
                    .font: normalFont,
                    .foregroundColor: UIColor.label,
                    .backgroundColor: UIColor.clear,
                    .paragraphStyle: NSParagraphStyle.default
                ]
                
                // Preserve formatting attributes from the original text
                if let originalFont = attributes[.font] as? UIFont {
                    let hasTraitBold = originalFont.fontDescriptor.symbolicTraits.contains(.traitBold)
                    let isExplicitlyBold = originalFont.fontName == "SpaceGrotesk-Bold" || 
                                         originalFont.fontName == "SpaceGrotesk-SemiBold" ||
                                         originalFont.fontName == "SpaceGrotesk-Heavy"
                    let hasTraitItalic = originalFont.fontDescriptor.symbolicTraits.contains(.traitItalic)
                    
                    // If text has bold or italic, preserve it
                    if hasTraitBold || isExplicitlyBold || hasTraitItalic {
                        var traits = originalFont.fontDescriptor.symbolicTraits
                        // Remove monospace trait but keep bold/italic
                        traits.remove(.traitMonoSpace)
                        
                        let descriptor = UIFontDescriptor(name: context.fontName, size: safeFontSize(context.fontSize))
                        if let newDescriptor = descriptor.withSymbolicTraits(traits) {
                            normalAttributes[.font] = UIFont(descriptor: newDescriptor, size: safeFontSize(context.fontSize))
                        } else {
                            // Fallback: manually create font with preserved traits
                            if hasTraitBold || isExplicitlyBold {
                                normalAttributes[.font] = UIFont(name: "SpaceGrotesk-Bold", size: safeFontSize(context.fontSize)) ?? normalFont
                            }
                        }
                    }
                }
                
                // Preserve underline formatting
                if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
                    normalAttributes[.underlineStyle] = underlineStyle
                }
                
                // Preserve strikethrough formatting
                if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                    normalAttributes[.strikethroughStyle] = strikethroughStyle
                }
                
                let normalizedSubstring = NSAttributedString(string: substring.string, attributes: normalAttributes)
                normalizedText.append(normalizedSubstring)
            }
            
            mutableText.replaceCharacters(in: codeBlockRange, with: normalizedText)
            
            print("✅ exitCodeBlockAndMoveCursor: Removed code block formatting from range \(codeBlockRange)")
        }
        
        // Position cursor at the end of the now-normal text
        let newCursorPosition = codeBlockStart + codeBlockRange.length
        
        // Add a newline with normal formatting after the text to ensure clean transition
        let newlineString = NSAttributedString(string: "\n", attributes: [
            .font: UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize)),
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: NSParagraphStyle.default
        ])
        mutableText.insert(newlineString, at: newCursorPosition)
        
        // Position cursor after the newline
        let finalCursorPosition = newCursorPosition + 1
        textView.selectedRange = NSRange(location: finalCursorPosition, length: 0)
        
        // Check for existing formatting to preserve in typing attributes
        var typingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize)),
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: NSParagraphStyle.default
        ]
        
        // If there's text at the cursor position, check for formatting to preserve
        if finalCursorPosition > 0 && finalCursorPosition <= mutableText.length {
            let checkIndex = min(finalCursorPosition - 1, mutableText.length - 1)
            if checkIndex >= 0 && checkIndex < mutableText.length {
                let attributes = mutableText.attributes(at: checkIndex, effectiveRange: nil)
                
                // Preserve bold/italic from normalized text
                if let font = attributes[.font] as? UIFont {
                    let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                    let isExplicitlyBold = font.fontName == "SpaceGrotesk-Bold" || 
                                         font.fontName == "SpaceGrotesk-SemiBold" ||
                                         font.fontName == "SpaceGrotesk-Heavy"
                    let hasTraitItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                    
                    if hasTraitBold || isExplicitlyBold || hasTraitItalic {
                        typingAttributes[.font] = font
                    }
                }
                
                // Preserve underline and strikethrough
                if let underlineStyle = attributes[.underlineStyle] as? Int, underlineStyle != 0 {
                    typingAttributes[.underlineStyle] = underlineStyle
                }
                if let strikethroughStyle = attributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                    typingAttributes[.strikethroughStyle] = strikethroughStyle
                }
            }
        }
        
        textView.typingAttributes = typingAttributes
        
        // Update context to reflect that we're no longer in a code block
        DispatchQueue.main.async {
            self.context.isCodeBlockActive = false
        }
        
        print("✅ exitCodeBlockAndMoveCursor: Cursor moved to position \(finalCursorPosition), code block mode disabled, added clean newline")
        
        print("🗑️ Exited code block, cursor moved to position \(finalCursorPosition)")
    }
    
    /// Helper method to check if attributes indicate code block
    private func isAttributesInCodeBlock(_ attributes: [NSAttributedString.Key: Any]) -> Bool {
        // Check font
        if let font = attributes[.font] as? UIFont {
            let hasMonaco = font.fontName.contains("Monaco")
            let hasMonospaceTrait = font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
            let hasSystemMonospace = font.fontName.contains("SFMono") || font.fontName.contains("Menlo") || font.fontName.contains("Courier")
            let hasAppleSystemMonospace = font.fontName.contains(".AppleSystemUIFontMonospaced")
            
            if hasMonaco || hasMonospaceTrait || hasSystemMonospace || hasAppleSystemMonospace {
                return true
            }
        }
        
        // Check background color
        if let backgroundColor = attributes[.backgroundColor] as? UIColor {
            if backgroundColor == UIColor.systemGray6 {
                return true
            }
        }
        
        return false
    }
    
    /// Exit code block on Enter key while preserving existing text formatting
    private func exitCodeBlockOnEnterKey(at position: Int, in mutableText: NSMutableAttributedString) {
        // Create a completely clean paragraph style with no indentation
        let normalParagraphStyle = NSMutableParagraphStyle()
        normalParagraphStyle.lineSpacing = 0
        normalParagraphStyle.paragraphSpacing = 0
        normalParagraphStyle.firstLineHeadIndent = 0
        normalParagraphStyle.headIndent = 0
        normalParagraphStyle.tailIndent = 0
        
        // Check for existing text formatting before the cursor to preserve it
        var preservedAttributes: [NSAttributedString.Key: Any] = [:]
        
        if position > 0 && position <= mutableText.length {
            let prevIndex = position - 1
            if prevIndex < mutableText.length {
                let prevAttributes = mutableText.attributes(at: prevIndex, effectiveRange: nil)
                
                // Preserve bold formatting
                if let font = prevAttributes[.font] as? UIFont {
                    let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                    let isExplicitlyBold = font.fontName == "SpaceGrotesk-Bold" || 
                                         font.fontName == "SpaceGrotesk-SemiBold" ||
                                         font.fontName == "SpaceGrotesk-Heavy"
                    let hasTraitItalic = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
                    
                    if hasTraitBold || isExplicitlyBold || hasTraitItalic {
                        // Create a new font that preserves bold/italic but uses normal font family
                        var traits = font.fontDescriptor.symbolicTraits
                        // Remove monospace trait but keep bold/italic
                        traits.remove(.traitMonoSpace)
                        
                        let descriptor = UIFontDescriptor(name: context.fontName, size: safeFontSize(context.fontSize))
                        if let newDescriptor = descriptor.withSymbolicTraits(traits) {
                            preservedAttributes[.font] = UIFont(descriptor: newDescriptor, size: safeFontSize(context.fontSize))
                        } else {
                            // Fallback: manually create font with preserved traits
                            var normalFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
                            if hasTraitBold || isExplicitlyBold {
                                normalFont = UIFont(name: "SpaceGrotesk-Bold", size: safeFontSize(context.fontSize)) ?? normalFont
                            }
                            preservedAttributes[.font] = normalFont
                        }
                    }
                }
                
                // Preserve underline formatting
                if let underlineStyle = prevAttributes[.underlineStyle] as? Int, underlineStyle != 0 {
                    preservedAttributes[.underlineStyle] = underlineStyle
                }
                
                // Preserve strikethrough formatting
                if let strikethroughStyle = prevAttributes[.strikethroughStyle] as? Int, strikethroughStyle != 0 {
                    preservedAttributes[.strikethroughStyle] = strikethroughStyle
                }
            }
        }
        
        // Start with normal font and basic attributes
        let normalFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
        var normalAttributes: [NSAttributedString.Key: Any] = [
            .font: preservedAttributes[.font] ?? normalFont,
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: normalParagraphStyle
        ]
        
        // Add preserved formatting attributes
        if let underlineStyle = preservedAttributes[.underlineStyle] {
            normalAttributes[.underlineStyle] = underlineStyle
        }
        if let strikethroughStyle = preservedAttributes[.strikethroughStyle] {
            normalAttributes[.strikethroughStyle] = strikethroughStyle
        }
        
        let newlineString = NSAttributedString(string: "\n", attributes: normalAttributes)
        mutableText.insert(newlineString, at: position)
        
        // Position cursor after the newline
        let newCursorPosition = position + 1
        textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
        
        // Force update typing attributes to preserve formatting for future typing
        textView.typingAttributes = normalAttributes
        
        // Update context to indicate code mode is now off for future typing
        // Use immediate update to prevent race conditions with other formatting updates
        context.isCodeBlockActive = false
        hasExplicitlyExitedCodeBlock = true
        
        print("✅ exitCodeBlockOnEnterKey: Added newline at position \(position), cursor moved to \(newCursorPosition), code mode disabled, preserved formatting: \(preservedAttributes.keys)")
    }
    
    /// Exit code block formatting at current cursor position without moving cursor (for button toggle)
    private func exitCodeBlockInPlace(at position: Int) {
        // Create normal formatting attributes for future typing
        let normalFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
        let normalParagraphStyle = NSMutableParagraphStyle()
        normalParagraphStyle.lineSpacing = 0
        normalParagraphStyle.paragraphSpacing = 0
        normalParagraphStyle.firstLineHeadIndent = 0
        normalParagraphStyle.headIndent = 0
        normalParagraphStyle.tailIndent = 0
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: normalFont,
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: normalParagraphStyle
        ]
        
        // Update typing attributes for future typing (don't modify existing text)
        textView.typingAttributes = normalAttributes
        
        // Update context to indicate code mode is now off
        DispatchQueue.main.async {
            self.context.isCodeBlockActive = false
        }
        
        print("✅ exitCodeBlockInPlace: Set normal typing attributes at position \(position), code mode disabled for future typing")
    }
    
    /// Exit code block formatting and move cursor to next line (for button toggle when in code block)
    private func exitCodeBlockAndMoveToNextLine(at position: Int, in mutableText: NSMutableAttributedString) {
        // Create a completely clean paragraph style with no indentation
        let normalParagraphStyle = NSMutableParagraphStyle()
        normalParagraphStyle.lineSpacing = 0
        normalParagraphStyle.paragraphSpacing = 0
        normalParagraphStyle.firstLineHeadIndent = 0
        normalParagraphStyle.headIndent = 0
        normalParagraphStyle.tailIndent = 0
        
        // Insert a newline with normal formatting at the current position
        let normalFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
        
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: normalFont,
            .foregroundColor: UIColor.label, // Use system label color
            .paragraphStyle: normalParagraphStyle
            // Explicitly omit .backgroundColor to ensure no grey background
        ]
        
        let newlineText = NSAttributedString(string: "\n", attributes: normalAttributes)
        
        // Insert the newline at current position
        mutableText.insert(newlineText, at: position)
        
        // Set cursor position after the newline (position + 1)
        let newCursorPosition = position + 1
        
        // Set normal typing attributes for the new position
        DispatchQueue.main.async {
            self.textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
            self.textView.typingAttributes = normalAttributes
            self.context.isCodeBlockActive = false
        }
        
        print("✅ exitCodeBlockAndMoveToNextLine: Added newline at position \(position), cursor moved to \(newCursorPosition), code mode disabled")
    }
    
    // MARK: - Indentation
    
    private func applyIndentation(increase: Bool) {
        let selectedRange = textView.selectedRange
        let text = textView.text ?? ""
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        // Find the current line or selection range
        let lineRange: NSRange
        if selectedRange.length > 0 {
            // Multi-line selection - apply to all lines in selection
            lineRange = (text as NSString).lineRange(for: selectedRange)
        } else {
            // Single cursor - apply to current line
            lineRange = (text as NSString).lineRange(for: selectedRange)
        }
        
        // Process line by line to preserve formatting
        let selectedText = (text as NSString).substring(with: lineRange)
        let lines = selectedText.components(separatedBy: .newlines)
        
        var currentOffset = lineRange.location
        
        for (index, line) in lines.enumerated() {
            let lineLength = line.count
            let lineEndLength = (index == lines.count - 1) ? 0 : 1 // Account for \n except last line
            let _ = NSRange(location: currentOffset, length: lineLength + lineEndLength)
            
            if increase {
                // Add 4 spaces at the beginning while preserving all formatting
                let indentString = NSAttributedString(string: "    ")
                mutableText.insert(indentString, at: currentOffset)
                currentOffset += 4 // Account for added spaces
            } else {
                // Remove up to 4 spaces from the beginning while preserving formatting
                let spacesToRemove = min(4, line.prefix(4).count { $0 == " " })
                if spacesToRemove > 0 {
                    let removalRange = NSRange(location: currentOffset, length: spacesToRemove)
                    if removalRange.location + removalRange.length <= mutableText.length {
                        mutableText.deleteCharacters(in: removalRange)
                        currentOffset -= spacesToRemove // Account for removed spaces
                    }
                }
            }
            
            // Move to next line
            currentOffset += lineLength + lineEndLength
            if !increase {
                // Adjust for any spaces we removed
                let spacesRemoved = min(4, line.prefix(4).count { $0 == " " })
                currentOffset -= spacesRemoved
            }
        }
        
        // Update text view
        textView.attributedText = mutableText
        
        // Adjust cursor position based on indentation change
        let spacesChange = increase ? 4 : -min(4, text.prefix(4).count { $0 == " " })
        let newCursorLocation = min(max(0, selectedRange.location + spacesChange), mutableText.length)
        textView.selectedRange = NSRange(location: newCursorLocation, length: 0)
        
        updateBindingFromTextView()
        updateContextFromTextView()
        
        print("🔄 RichTextCoordinator: Applied indentation - increase: \(increase)")
    }
    
    // MARK: - Binding Updates
    
    private func updateBindingFromTextView() {
        guard !isUpdatingFromContext else { return }
        
        // Set flag to prevent updateUIView from overwriting our changes
        isUpdatingFromTextView = true
        
        // Only update binding if the text actually changed to prevent loops
        // Make a defensive copy to ensure we don't have reference issues
        guard let currentTextViewContent = textView.attributedText else {
            isUpdatingFromTextView = false
            return
        }
        
        let textViewCopy = NSAttributedString(attributedString: currentTextViewContent)
        
        if !textBinding.wrappedValue.isEqual(to: textViewCopy) {
            // Updating binding with formatted text
            // Create a completely new attributed string to prevent any reference sharing
            textBinding.wrappedValue = NSAttributedString(attributedString: textViewCopy)
        }
        
        // Reset flag after a longer delay to ensure SwiftUI has fully processed the binding update
        // This prevents the race condition where updateUIView is called before the flag is reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.isUpdatingFromTextView = false
            // Binding update complete
        }
    }
    
    private func updateContextFromTextView() {
        guard !isUpdatingFromContext else { return }
        
        // Don't override the isUpdatingFromTextView flag if it's already set by binding update
        let wasAlreadyUpdating = isUpdatingFromTextView
        if !wasAlreadyUpdating {
            isUpdatingFromTextView = true
        }
        
        // Update context state without triggering actions
        context.attributedString = textView.attributedText
        context.selectedRange = textView.selectedRange
        
        // Update undo/redo state
        let undoManager = textView.undoManager
        context.updateUndoRedoState(
            canUndo: undoManager?.canUndo ?? false,
            canRedo: undoManager?.canRedo ?? false
        )
        
        // Update copy state
        context.updateCopyState(textView.selectedRange.length > 0)
        
        // Update formatting state but protect code block state from flickering
        updateFormattingStateWithCodeBlockProtection()
        
        // Only reset the flag if we set it (not if binding update set it)
        if !wasAlreadyUpdating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isUpdatingFromTextView = false
                // Context update complete
            }
        }
    }
    
    /// Update formatting state while protecting code block state from flickering
    private func updateFormattingStateWithCodeBlockProtection() {
        // Check if we're actually in a code block by examining the text attributes
        let cursorPosition = textView.selectedRange.location
        let isActuallyInCodeBlock = checkIfPositionIsInCodeBlock(cursorPosition)
        
        // Debug: cursor position and code block state
        
        // If we detect we're actually in a code block, ensure the context shows active state
        // This prevents flickering when typing in code blocks
        // BUT respect when user has explicitly exited a code block
        if isActuallyInCodeBlock && !hasExplicitlyExitedCodeBlock {
            // In code block - ensure active state
            
            // Ensure code block state is active - defer to avoid SwiftUI update warnings
            DispatchQueue.main.async {
                self.context.isCodeBlockActive = true
            }
            
            // Update other formatting states but preserve code block state
            updateNonCodeBlockFormattingState()
            return
        }
        
        // If we're not in a code block but context shows active, reset it
        if !isActuallyInCodeBlock && context.isCodeBlockActive {
            // Not in code block but context active - reset state
            DispatchQueue.main.async {
                self.context.isCodeBlockActive = false
            }
        }
        
        // Update all formatting states normally when not in code block
        context.updateFormattingState()
    }
    
    /// Update formatting state for everything except code block (to preserve code block state)
    private func updateNonCodeBlockFormattingState() {
        // This is a simplified version of updateFormattingState that skips code block detection
        // but still updates bold, italic, etc.
        
        guard textView.selectedRange.length >= 0 && textView.attributedText.length > 0 else { return }
        
        let safeIndex = max(0, min(textView.selectedRange.location, textView.attributedText.length - 1))
        guard safeIndex < textView.attributedText.length else { return }
        
        let attributes = textView.attributedText.attributes(at: safeIndex, effectiveRange: nil)
        
        // Update formatting state on main thread to avoid SwiftUI conflicts
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Update bold state
            if let font = attributes[.font] as? UIFont {
                let hasTraitBold = font.fontDescriptor.symbolicTraits.contains(.traitBold)
                // Use exact font name matching to prevent false positives
                let hasBoldName = font.fontName == "SpaceGrotesk-Bold" || 
                                font.fontName == "SpaceGrotesk-SemiBold" || 
                                font.fontName == "SpaceGrotesk-Heavy"
                self.context.isBoldActive = hasTraitBold || hasBoldName
                
                // Update italic state
                self.context.isItalicActive = font.fontDescriptor.symbolicTraits.contains(.traitItalic)
            } else {
                self.context.isBoldActive = false
                self.context.isItalicActive = false
            }
            
            // Update underline state
            if let underlineStyle = attributes[.underlineStyle] as? Int {
                self.context.isUnderlineActive = underlineStyle != 0
            } else {
                self.context.isUnderlineActive = false
            }
            
            // Update strikethrough state
            if let strikethroughStyle = attributes[.strikethroughStyle] as? Int {
                self.context.isStrikethroughActive = strikethroughStyle != 0
            } else {
                self.context.isStrikethroughActive = false
            }
            
            // Update list states (these are safe to update normally)
            let currentText = self.textView.attributedText.string
            let lineRange = (currentText as NSString).lineRange(for: self.textView.selectedRange)
            let lineText = (currentText as NSString).substring(with: lineRange)
            let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
            
            self.context.isBulletListActive = trimmedLine.hasPrefix("•")
            self.context.isCheckboxActive = trimmedLine.hasPrefix("☐") || trimmedLine.hasPrefix("☑")
            
            print("🔄 updateNonCodeBlockFormattingState: Updated other states, preserved code block active state")
        }
    }
    
    private func updateTypingAttributes() {
        // Build typing attributes based on current context state and selection
        var typingAttributes = textView.typingAttributes
        
        // Update typing attributes based on code block state
        
        // Check if we're ACTUALLY in a code block by examining the text attributes at cursor position
        let cursorPosition = textView.selectedRange.location
        let isActuallyInCodeBlock = checkIfPositionIsInCodeBlock(cursorPosition)
        
        // Check if cursor is actually in code block
        
        // Check if we're in a code block first - this overrides other font formatting
        // Use ACTUAL code block detection, not just context state
        var font: UIFont
        if isActuallyInCodeBlock || context.isCodeBlockActive {
            // Use monospaced font for code blocks (Monaco equivalent on iOS)
            font = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            // Using monospaced font for code block
            print("   - Font name: \(font.fontName)")
            print("   - Font family: \(font.familyName)")
            print("   - Symbolic traits: \(font.fontDescriptor.symbolicTraits.rawValue)")
            print("   - Has monospace trait: \(font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace))")
            
            // Apply code block styling
            typingAttributes[.backgroundColor] = UIColor.systemGray6
            typingAttributes[.foregroundColor] = UIColor.systemGreen  // Green text color for code
            
            // Apply paragraph style for full-width background with padding
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            paragraphStyle.paragraphSpacing = 4
            paragraphStyle.firstLineHeadIndent = 16  // Left padding
            paragraphStyle.headIndent = 16           // Left padding for wrapped lines
            paragraphStyle.tailIndent = -16         // Right padding (negative value)
            typingAttributes[.paragraphStyle] = paragraphStyle
            
            // Force context to stay in code block mode if we detect we're actually in one
            if isActuallyInCodeBlock && !context.isCodeBlockActive {
                // Force code block active state based on attributes
                DispatchQueue.main.async {
                    self.context.isCodeBlockActive = true
                }
            }
        } else {
            // Get base font for regular text
            let baseFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
            
            // Apply formatting based on current context state
            font = baseFont
            if context.isBoldActive {
                font = applyBoldToFont(font)
            }
            if context.isItalicActive {
                font = applyItalicToFont(font)
            }
            
            // Remove background color and paragraph style for normal text
            typingAttributes.removeValue(forKey: .backgroundColor)
            typingAttributes.removeValue(forKey: .paragraphStyle)
            
            // Set normal text color (only for non-code-block text)
            typingAttributes[.foregroundColor] = UIColor.label
        }
        
        typingAttributes[.font] = font
        
        // Apply other formatting (only if not in code block)
        if !context.isCodeBlockActive {
            if context.isUnderlineActive {
                typingAttributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            } else {
                typingAttributes.removeValue(forKey: .underlineStyle)
            }
            
            if context.isStrikethroughActive {
                typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            } else {
                typingAttributes.removeValue(forKey: .strikethroughStyle)
            }
        } else {
            // Remove underline and strikethrough in code blocks
            typingAttributes.removeValue(forKey: .underlineStyle)
            typingAttributes.removeValue(forKey: .strikethroughStyle)
        }
        
        textView.typingAttributes = typingAttributes
    }
    
    /// Reset typing attributes to normal formatting after removing checkboxes/bullets
    /// This prevents formatting inheritance from surrounding text
    private func resetTypingAttributesToNormal() {
        // Get the base font for normal text
        let baseFont = UIFont(name: context.fontName, size: safeFontSize(context.fontSize)) ?? UIFont.systemFont(ofSize: safeFontSize(context.fontSize))
        
        // Create clean typing attributes with normal formatting
        var normalAttributes: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]
        
        // Remove any special formatting
        normalAttributes.removeValue(forKey: .backgroundColor)
        normalAttributes.removeValue(forKey: .paragraphStyle)
        normalAttributes.removeValue(forKey: .underlineStyle)
        normalAttributes.removeValue(forKey: .strikethroughStyle)
        
        // Apply the clean attributes
        textView.typingAttributes = normalAttributes
        
        print("🔄 resetTypingAttributesToNormal: Reset typing attributes to normal formatting")
    }
    
    private func applyBoldToFont(_ font: UIFont) -> UIFont {
        let safeSize = safeFontSize(font.pointSize)
        // Use specific SpaceGrotesk-Bold font for bold formatting
        if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: safeSize) {
            print("✅ applyBoldToFont: Using SpaceGrotesk-Bold at size \(safeSize)")
            return boldFont
        } else {
            // Fallback to system bold font
            let boldSystemFont = UIFont.boldSystemFont(ofSize: safeSize)
            print("⚠️ applyBoldToFont: SpaceGrotesk-Bold not available, using system bold font: \(boldSystemFont.fontName)")
            return boldSystemFont
        }
    }
    
    private func applyItalicToFont(_ font: UIFont) -> UIFont {
        let safeSize = safeFontSize(font.pointSize)
        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: safeSize)
        } else {
            return UIFont.italicSystemFont(ofSize: safeSize)
        }
    }
}

// MARK: - Native UITextView Behavior
// All text selection, copy/paste, and interaction handled natively by UITextView

// MARK: - UITextViewDelegate

extension RichTextCoordinator: UITextViewDelegate, UIGestureRecognizerDelegate {
    
    public func textViewDidChange(_ textView: UITextView) {
        // Skip updates if we're currently handling newline insertion to avoid race conditions
        guard !isHandlingNewlineInsertion else { return }
        updateBindingFromTextView()
        updateContextFromTextView()
    }
    
    public func textViewDidChangeSelection(_ textView: UITextView) {
        // Skip updates if we're currently handling newline insertion to avoid race conditions
        guard !isHandlingNewlineInsertion else { return }
        
        // Selection changed
        
        // Prevent cursor from being placed to the left of checkboxes or bullets
        preventCursorLeftOfListMarkers(textView)
        
        // If user taps to a position that's NOT in a code block, reset the explicit exit flag
        // This allows normal code block detection to work again
        let cursorPosition = textView.selectedRange.location
        let isInCodeBlock = checkIfPositionIsInCodeBlock(cursorPosition)
        if !isInCodeBlock {
            hasExplicitlyExitedCodeBlock = false
        }
        
        // Disabled cursor-based checkbox detection due to over-triggering
        // Rely on tap gesture recognition instead
        // if !isTogglingSelf {
        //     checkForCheckboxAtCursorPosition()
        // }
        
        updateContextFromTextView()
        updateTypingAttributes()
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
        // Update typing attributes immediately when editing begins
        // This ensures that if formatting is active, it applies to the first character
        updateTypingAttributes()
        
        DispatchQueue.main.async { [weak self] in
            self?.context.isEditingText = true
        }
        updateContextFromTextView()
    }
    
    public func textViewDidEndEditing(_ textView: UITextView) {
        DispatchQueue.main.async { [weak self] in
            self?.context.isEditingText = false
        }
        updateContextFromTextView()
    }
    
    public func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        // Handle special cases like enter key for list continuation
        if text == "\n" {
            return handleNewlineInsertion(textView, range)
        }
        
        // Handle backspace at beginning of list items (both selection deletion and single character backspace)
        if text.isEmpty && range.length > 0 {
            return handleBackspaceInList(textView, range)
        }
        
        // Handle single character backspace that might remove list markers
        if text.isEmpty && range.length == 1 {
            return handleSingleCharacterBackspace(textView, range)
        }
        
        // Handle space key in code blocks - maintain code formatting
        if text == " " {
            // Check if we're in a code block
            let isInCodeBlock = isPositionInCodeBlock(range.location, in: NSMutableAttributedString(attributedString: textView.attributedText))
            
            if isInCodeBlock {
                // We're in a code block - allow the space but ensure typing attributes maintain code formatting
                updateTypingAttributes()
                return true
            } else {
                // Not in code block - handle automatic bullet/checkbox conversion
                return handleAutomaticFormatting(textView, range)
            }
        }
        
        // For any other text input in code blocks, ensure typing attributes are maintained
        if !text.isEmpty && range.length == 0 {
            let isInCodeBlock = isPositionInCodeBlock(range.location, in: NSMutableAttributedString(attributedString: textView.attributedText))
            if isInCodeBlock {
                // Ensure code block formatting is applied to new text
                print("🔧 shouldChangeTextIn: Detected typing in code block at position \(range.location)")
                
                // Apply code block attributes directly to the new text
                let monospacedFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
                let codeAttributes: [NSAttributedString.Key: Any] = [
                    .font: monospacedFont,
                    .backgroundColor: UIColor.systemGray6,
                    .foregroundColor: UIColor.systemGreen
                ]
                
                // Update typing attributes immediately
                textView.typingAttributes = codeAttributes
                print("✅ shouldChangeTextIn: Applied code block typing attributes")
                
                // Also ensure context knows we're in a code block
                DispatchQueue.main.async {
                    self.context.isCodeBlockActive = true
                }
            }
        }
        
        return true
    }
    
    // MARK: - Automatic Formatting
    
    private func handleAutomaticFormatting(_ textView: UITextView, _ range: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: range)
        let lineText = (currentText as NSString).substring(with: lineRange)
        let _ = lineText.trimmingCharacters(in: .whitespaces)
        
        // Get the text from start of line to current cursor position
        let lineStartToRange = NSRange(location: lineRange.location, length: range.location - lineRange.location)
        let textBeforeCursor = (currentText as NSString).substring(with: lineStartToRange).trimmingCharacters(in: .whitespaces)
        
        // Convert '* ' to bullet point
        if textBeforeCursor == "*" {
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            // Replace the '*' with '• '
            let replacementRange = NSRange(location: range.location - 1, length: 1)
            mutableText.replaceCharacters(in: replacementRange, with: "• ")
            
            // Clear formatting from bullet character only (first 2 characters: "• ")
            let bulletRange = NSRange(location: replacementRange.location, length: 2)
            if bulletRange.location + bulletRange.length <= mutableText.length {
                // Apply clean attributes to bullet point only
                mutableText.removeAttribute(.font, range: bulletRange)
                mutableText.removeAttribute(.foregroundColor, range: bulletRange)
                mutableText.removeAttribute(.backgroundColor, range: bulletRange)
                mutableText.removeAttribute(.underlineStyle, range: bulletRange)
                mutableText.removeAttribute(.strikethroughStyle, range: bulletRange)
                
                // Set basic font for bullet
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: bulletRange)
                mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: bulletRange)
            }
            
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: range.location + 1, length: 0) // Position after "• "
            
            updateBindingFromTextView()
            updateContextFromTextView()
            
            print("🔄 RichTextCoordinator: Auto-converted '* ' to bullet point")
            return false // Prevent the space from being added
        }
        
        // Convert '- ' to bullet point
        if textBeforeCursor == "-" {
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            // Replace the '-' with '• '
            let replacementRange = NSRange(location: range.location - 1, length: 1)
            mutableText.replaceCharacters(in: replacementRange, with: "• ")
            
            // Clear formatting from bullet character only (first 2 characters: "• ")
            let bulletRange = NSRange(location: replacementRange.location, length: 2)
            if bulletRange.location + bulletRange.length <= mutableText.length {
                // Apply clean attributes to bullet point only
                mutableText.removeAttribute(.font, range: bulletRange)
                mutableText.removeAttribute(.foregroundColor, range: bulletRange)
                mutableText.removeAttribute(.backgroundColor, range: bulletRange)
                mutableText.removeAttribute(.underlineStyle, range: bulletRange)
                mutableText.removeAttribute(.strikethroughStyle, range: bulletRange)
                
                // Set basic font for bullet
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: bulletRange)
                mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: bulletRange)
            }
            
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: range.location + 1, length: 0) // Position after "• "
            
            updateBindingFromTextView()
            updateContextFromTextView()
            
            print("🔄 RichTextCoordinator: Auto-converted '- ' to bullet point")
            return false // Prevent the space from being added
        }
        
        // Convert '[] ' to checkbox
        if textBeforeCursor == "[]" {
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            // Replace the '[]' with Unicode checkbox
            let replacementRange = NSRange(location: range.location - 2, length: 2)
            
            let checkboxString = createUnicodeCheckbox(isChecked: false)
            let spaceString = NSAttributedString(string: " ")
            
            let checkboxWithSpace = NSMutableAttributedString()
            checkboxWithSpace.append(checkboxString)
            checkboxWithSpace.append(spaceString)
            
            mutableText.replaceCharacters(in: replacementRange, with: checkboxWithSpace)
            
            textView.attributedText = mutableText
            textView.selectedRange = NSRange(location: range.location, length: 0) // Position after checkbox + space
            
            updateBindingFromTextView()
            updateContextFromTextView()
            
            print("🔄 RichTextCoordinator: Auto-converted '[] ' to checkbox")
            return false // Prevent the space from being added
        }
        
        // No automatic conversion needed - allow normal space
        return true
    }
    
    private func handleNewlineInsertion(_ textView: UITextView, _ range: NSRange) -> Bool {
        // Prevent re-entrant calls
        guard !isHandlingNewlineInsertion else { return true }
        
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: range)
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if we're currently in a code block and auto-exit on enter
        let cursorPosition = range.location
        if checkIfPositionIsInCodeBlock(cursorPosition) {
            isHandlingNewlineInsertion = true
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            // Exit the code block and move cursor to a new line with normal formatting (preserving existing code block)
            exitCodeBlockOnEnterKey(at: cursorPosition, in: mutableText)
            
            // Apply the updated text
            textView.attributedText = mutableText
            
            // Update binding and context after the change
            updateBindingFromTextView()
            updateContextFromTextView()
            
            // Reset flag after a brief delay
            DispatchQueue.main.async {
                self.isHandlingNewlineInsertion = false
            }
            
            print("🔚 handleNewlineInsertion: Auto-exited code block on enter key")
            return false
        }
        
        // Continue bullet lists
        if trimmedLine.hasPrefix("• ") {
            let remainingText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if remainingText.isEmpty {
                // Empty bullet - remove it
                isHandlingNewlineInsertion = true
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                let newLineRange = NSRange(location: lineRange.location, length: lineRange.length - (lineText.hasSuffix("\n") ? 0 : 1))
                mutableText.replaceCharacters(in: newLineRange, with: "")
                textView.attributedText = mutableText
                let newCursorPosition = lineRange.location
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Update binding and context after the change
                updateBindingFromTextView()
                updateContextFromTextView()
                
                // Reset flag after a brief delay
                DispatchQueue.main.async {
                    self.isHandlingNewlineInsertion = false
                }
                return false
            } else {
                // Add new bullet
                isHandlingNewlineInsertion = true
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                mutableText.replaceCharacters(in: range, with: "\n• ")
                
                // Clear formatting from new bullet line (bullet + space only, not affecting existing text)
                let bulletRange = NSRange(location: range.location + 1, length: 2) // "\n• " -> just "• "
                if bulletRange.location + bulletRange.length <= mutableText.length {
                    // Remove all text formatting from bullet
                    mutableText.removeAttribute(.font, range: bulletRange)
                    mutableText.removeAttribute(.foregroundColor, range: bulletRange)
                    mutableText.removeAttribute(.backgroundColor, range: bulletRange)
                    mutableText.removeAttribute(.underlineStyle, range: bulletRange)
                    mutableText.removeAttribute(.strikethroughStyle, range: bulletRange)
                    
                    // Set clean attributes for bullet
                    mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: bulletRange)
                    mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: bulletRange)
                }
                
                textView.attributedText = mutableText
                let newCursorPosition = range.location + 3
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Clear typing attributes to reset formatting for new text
                textView.typingAttributes = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ]
                
                // Don't reset text formatting state - let user continue with their selected formatting
                // Only reset for bullet content, not for regular text formatting
                
                // Update binding and context after the change
                updateBindingFromTextView()
                updateContextFromTextView()
                
                // Reset flag after a brief delay
                DispatchQueue.main.async {
                    self.isHandlingNewlineInsertion = false
                }
                return false
            }
        }
        
        // Continue checkbox lists (handle both custom attachments and Unicode checkboxes)
        let hasCheckboxAtStart = checkForCheckboxAtLineStart(mutableText: NSMutableAttributedString(attributedString: textView.attributedText), lineRange: lineRange, lineText: lineText)
        if hasCheckboxAtStart || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            let remainingText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if remainingText.isEmpty {
                // Empty checkbox - remove it
                isHandlingNewlineInsertion = true
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                let newLineRange = NSRange(location: lineRange.location, length: lineRange.length - (lineText.hasSuffix("\n") ? 0 : 1))
                mutableText.replaceCharacters(in: newLineRange, with: "")
                textView.attributedText = mutableText
                let newCursorPosition = lineRange.location
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Update binding and context after the change
                updateBindingFromTextView()
                updateContextFromTextView()
                
                // Reset flag after a brief delay
                DispatchQueue.main.async {
                    self.isHandlingNewlineInsertion = false
                }
                return false
            } else {
                // Add new custom checkbox
                isHandlingNewlineInsertion = true
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                
                // Create new checkbox with newline prefix using NSTextAttachment
                let newlineString = NSAttributedString(string: "\n")
                let attachment = CheckboxTextAttachment(isChecked: false)
                
                // Create attachment string with proper font context to ensure rendering compatibility
                let checkboxString = NSMutableAttributedString(attachment: attachment)
                // Apply system font to the attachment to avoid SpaceGrotesk font conflicts
                let systemFont = UIFont.systemFont(ofSize: context.fontSize)
                checkboxString.addAttribute(.font, value: systemFont, range: NSRange(location: 0, length: checkboxString.length))
                
                let spaceString = NSAttributedString(string: " ")
                
                let newCheckboxLine = NSMutableAttributedString()
                newCheckboxLine.append(newlineString)
                newCheckboxLine.append(checkboxString)
                newCheckboxLine.append(spaceString)
                
                mutableText.replaceCharacters(in: range, with: newCheckboxLine)
                
                textView.attributedText = mutableText
                let newCursorPosition = range.location + 3 // Position after "\n" + checkbox + space
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Update typing attributes to maintain current formatting state
                updateTypingAttributes()
                
                // Don't reset text formatting state - let user continue with their selected formatting
                
                // Update binding and context after the change
                updateBindingFromTextView()
                updateContextFromTextView()
                
                // Reset flag after a brief delay
                DispatchQueue.main.async {
                    self.isHandlingNewlineInsertion = false
                }
                return false
            }
        }
        
        // No bullets or checkboxes - maintain current formatting for regular new line
        // Update typing attributes to maintain current formatting state
        updateTypingAttributes()
        
        // Don't reset formatting state - let user continue with their selected formatting
        
        return true
    }
    
    private func handleBackspaceInList(_ textView: UITextView, _ range: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the start of the list marker (after any leading whitespace)
        let leadingWhitespaceCount = lineText.count - lineText.ltrimmed().count
        let markerPosition = lineRange.location + leadingWhitespaceCount
        
        // Check if we're positioned right after a bullet/checkbox marker (cursor is at marker position + 2)
        let isAfterMarker = range.location == markerPosition + 2
        let isAtLineStart = range.location == lineRange.location + leadingWhitespaceCount
        
        // Handle backspace if cursor is at beginning of line or right after marker
        if isAtLineStart || isAfterMarker {
            let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
            
            // Check for Unicode checkbox first
            if markerPosition < mutableText.length {
                let character = (mutableText.string as NSString).character(at: markerPosition)
                
                // Check for Unicode checkbox characters
                if character == 0x2610 || character == 0x2611 { // ☐ or ☑
                    // Remove Unicode checkbox + space
                    let lengthToRemove = min(2, mutableText.length - markerPosition)
                    guard lengthToRemove > 0 else { return true }
                    
                    let markerRange = NSRange(location: markerPosition, length: lengthToRemove)
                    mutableText.replaceCharacters(in: markerRange, with: "")
                    textView.attributedText = mutableText
                    
                    // Position cursor where the marker was
                    textView.selectedRange = NSRange(location: markerPosition, length: 0)
                    
                    // Reset typing attributes to prevent formatting inheritance after checkbox removal
                    resetTypingAttributesToNormal()
                    
                    updateBindingFromTextView()
                    updateContextFromTextView()
                    
                    print("🔄 RichTextCoordinator: Removed Unicode checkbox with backspace")
                    return false
                }
            }
            // Check for Unicode checkboxes and bullets
            else if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
                // Remove the list marker + space
                let lengthToRemove = min(2, mutableText.length - markerPosition)
                guard lengthToRemove > 0 else { return true }
                
                let markerRange = NSRange(location: markerPosition, length: lengthToRemove)
                mutableText.replaceCharacters(in: markerRange, with: "")
                textView.attributedText = mutableText
                
                // Position cursor where the marker was
                textView.selectedRange = NSRange(location: markerPosition, length: 0)
                
                // Reset typing attributes to prevent formatting inheritance after checkbox removal
                resetTypingAttributesToNormal()
                
                updateBindingFromTextView()
                updateContextFromTextView()
                
                print("🔄 RichTextCoordinator: Removed bullet/checkbox with backspace")
                return false
            }
        }
        
        return true
    }
    
    private func handleSingleCharacterBackspace(_ textView: UITextView, _ range: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        guard range.location > 0 else { return true }
        
        let lineRange = (currentText as NSString).lineRange(for: NSRange(location: range.location - 1, length: 0))
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Find the start of the list marker (after any leading whitespace)
        let leadingWhitespaceCount = lineText.count - lineText.ltrimmed().count
        let markerPosition = lineRange.location + leadingWhitespaceCount
        
        // Check if we're backspacing right after a bullet/checkbox marker
        // The marker is 2 characters (e.g. "• " or "○ "), so check if cursor is anywhere after that
        let isAfterMarker = range.location > markerPosition + 1 && 
                           (trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ "))
        
        // Also check for Unicode checkbox
        let hasUnicodeCheckbox: Bool
        if markerPosition < textView.attributedText.length {
            let character = (textView.attributedText.string as NSString).character(at: markerPosition)
            hasUnicodeCheckbox = character == 0x2610 || character == 0x2611 // ☐ or ☑
        } else {
            hasUnicodeCheckbox = false
        }
        
        // If we're right after a marker and this line only has the marker + one character, remove the whole line
        if (isAfterMarker || (hasUnicodeCheckbox && range.location > markerPosition + 1)) {
            let contentAfterMarker = trimmedLine.dropFirst(2) // Remove "• " or similar
            let trimmedContent = contentAfterMarker.trimmingCharacters(in: .whitespaces)
            
            // If there's only one character after the marker, remove the entire marker when backspacing
            if trimmedContent.count == 1 {
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                
                // Remove the entire marker and its content
                if hasUnicodeCheckbox {
                    let lengthToRemove = min(3, mutableText.length - markerPosition) // attachment + space + character
                    let removeRange = NSRange(location: markerPosition, length: lengthToRemove)
                    mutableText.replaceCharacters(in: removeRange, with: "")
                } else {
                    let lengthToRemove = min(3, mutableText.length - markerPosition) // marker + space + character  
                    let removeRange = NSRange(location: markerPosition, length: lengthToRemove)
                    mutableText.replaceCharacters(in: removeRange, with: "")
                }
                
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: markerPosition, length: 0)
                
                updateBindingFromTextView()
                updateContextFromTextView()
                
                print("🔄 RichTextCoordinator: Removed marker and first character with single backspace")
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Individual Checkbox Toggling
    
    /// Toggle a specific checkbox between unchecked and checked (Unicode based)
    public func toggleCheckboxAtPosition(_ position: Int) {
        guard let attributedText = textView.attributedText else { return }
        guard position < attributedText.length else { return }
        
        // Check for Unicode checkbox characters  
        let character = (attributedText.string as NSString).character(at: position)
        
        if character == 0x2610 { // ☐ unchecked
            toggleUnicodeCheckboxAtPosition(position, isCurrentlyChecked: false)
        } else if character == 0x2611 { // ☑ checked
            toggleUnicodeCheckboxAtPosition(position, isCurrentlyChecked: true)
        } else {
            print("⚠️ RichTextCoordinator: No Unicode checkbox found at position \(position)")
        }
    }
    
    // MARK: - Helper Functions
    
    /// Ensure font size is safe (not NaN, infinite, or too small/large)
    private func safeFontSize(_ size: CGFloat) -> CGFloat {
        // Check for NaN, infinity, or invalid values
        guard size.isFinite && size > 0 else {
            print("⚠️ RichTextCoordinator: Invalid font size \(size), using default 17")
            return 17.0 // Default font size
        }
        
        // Clamp to reasonable bounds
        let minSize: CGFloat = 8.0
        let maxSize: CGFloat = 72.0
        return max(minSize, min(maxSize, size))
    }
    
    // MARK: - Checkbox Customization (Easy to modify for future visual changes)
    
    /// Create simple Unicode checkbox - much simpler than NSTextAttachment
    /// This method creates checkbox text that works like Apple Notes with consistent sizing
    private func createUnicodeCheckbox(isChecked: Bool) -> NSAttributedString {
        let checkboxChar = isChecked ? "☑" : "☐"
        
        // Use slightly larger font size than text for better tap targets (Apple Notes style)
        // Apple Notes checkboxes are about 1.2x the text size for better usability
        let contextFontSize = context.fontSize
        print("🔍 createUnicodeCheckbox: context.fontSize = \(contextFontSize)")
        
        let textFontSize = safeFontSize(contextFontSize)
        print("🔍 createUnicodeCheckbox: safeFontSize = \(textFontSize)")
        
        let checkboxSize = textFontSize * 1.2 // Slightly larger than text for better tapping
        print("🔍 createUnicodeCheckbox: checkboxSize = \(checkboxSize)")
        
        // Use system font with medium weight to match Apple Notes style
        let checkboxFont = UIFont.systemFont(ofSize: checkboxSize, weight: .medium)
        
        let checkboxColor = UIColor.label
        
        // Validate the font before creating attributes
        let actualSize = checkboxFont.pointSize
        guard actualSize.isFinite && !actualSize.isNaN && actualSize > 0 else {
            print("❌ createUnicodeCheckbox: Invalid font size \(actualSize), using fallback")
            let fallbackFont = UIFont.systemFont(ofSize: 17.0, weight: .medium)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: fallbackFont,
                .foregroundColor: checkboxColor
            ]
            return NSAttributedString(string: checkboxChar, attributes: attributes)
        }
        
        // Create attributes with consistent styling for both states
        // Validate baseline offset to prevent NaN
        let safeBaselineOffset: CGFloat = 0.0
        guard safeBaselineOffset.isFinite && !safeBaselineOffset.isNaN else {
            print("❌ createUnicodeCheckbox: Invalid baseline offset, skipping")
            let attributes: [NSAttributedString.Key: Any] = [
                .font: checkboxFont,
                .foregroundColor: checkboxColor
            ]
            return NSAttributedString(string: checkboxChar, attributes: attributes)
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: checkboxFont,
            .foregroundColor: checkboxColor,
            // Add consistent baseline to align both characters identically
            .baselineOffset: safeBaselineOffset
        ]
        
        // Validate the attributed string before returning
        let checkboxString = NSAttributedString(string: checkboxChar, attributes: attributes)
        let issues = validateAttributedStringForNaN(checkboxString)
        if !issues.isEmpty {
            print("❌ createUnicodeCheckbox: Found issues in checkbox string:")
            for issue in issues {
                print("   \(issue)")
            }
        }
        
        print("✅ createUnicodeCheckbox: Created \(isChecked ? "checked" : "unchecked") checkbox with size \(actualSize) (1.2x text size for better tapping)")
        
        return checkboxString
    }
    
    /// Validate NSAttributedString for NaN values that could cause CoreGraphics errors
    private func validateAttributedStringForNaN(_ attributedString: NSAttributedString) -> [String] {
        var issues: [String] = []
        let range = NSRange(location: 0, length: attributedString.length)
        
        attributedString.enumerateAttributes(in: range, options: []) { attributes, subRange, _ in
            for (key, value) in attributes {
                switch key {
                case .font:
                    if let font = value as? UIFont {
                        let size = font.pointSize
                        if !size.isFinite || size.isNaN {
                            issues.append("Font size NaN/infinite: \(size)")
                        }
                    }
                case .baselineOffset:
                    if let offset = value as? NSNumber {
                        let offsetValue = offset.doubleValue
                        if !offsetValue.isFinite || offsetValue.isNaN {
                            issues.append("Baseline offset NaN/infinite: \(offsetValue)")
                        }
                    }
                case .kern:
                    if let kern = value as? NSNumber {
                        let kernValue = kern.doubleValue
                        if !kernValue.isFinite || kernValue.isNaN {
                            issues.append("Kerning NaN/infinite: \(kernValue)")
                        }
                    }
                case .paragraphStyle:
                    if let paragraphStyle = value as? NSParagraphStyle {
                        let values = [
                            paragraphStyle.lineSpacing,
                            paragraphStyle.paragraphSpacing,
                            paragraphStyle.headIndent,
                            paragraphStyle.tailIndent,
                            paragraphStyle.firstLineHeadIndent,
                            paragraphStyle.minimumLineHeight,
                            paragraphStyle.maximumLineHeight
                        ]
                        
                        for (index, val) in values.enumerated() {
                            if !val.isFinite || val.isNaN {
                                let names = ["lineSpacing", "paragraphSpacing", "headIndent", "tailIndent", "firstLineHeadIndent", "minimumLineHeight", "maximumLineHeight"]
                                issues.append("ParagraphStyle.\(names[index]) NaN/infinite: \(val)")
                            }
                        }
                    }
                default:
                    // Check if any other value is a numeric type that could be NaN
                    if let number = value as? NSNumber {
                        let doubleValue = number.doubleValue
                        if !doubleValue.isFinite || doubleValue.isNaN {
                            issues.append("Attribute \(key.rawValue) NaN/infinite: \(doubleValue)")
                        }
                    }
                }
            }
        }
        
        return issues
    }
    
    
    // MARK: - Gesture Handling
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: textView)
        print("🎯 handleTap: METHOD CALLED! Gesture state: \(gesture.state)")
        print("👆 handleTap: Tap detected at location \(location) in textView bounds \(textView.bounds)")
        
        // Validate tap location is within bounds
        guard location.x.isFinite && location.y.isFinite else {
            print("⚠️ handleTap: Invalid tap location \(location)")
            return
        }
        
        // Record the timestamp for tap-to-left behavior detection
        lastUserTapTime = Date()
        
        // Check if we're at the end state
        guard gesture.state == .ended else { 
            print("⚠️ handleTap: Gesture state is not .ended, it's \(gesture.state)")
            return 
        }
        
        // Debug: Log all attachments in the text
        if let attributedText = textView.attributedText {
            print("👆 handleTap: Attributed text length: \(attributedText.length)")
            
            attributedText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributedText.length), options: []) { value, range, _ in
                if let attachment = value as? NSTextAttachment {
                    let attachmentType = type(of: attachment)
                    print("🔍 handleTap: Found attachment type \(attachmentType) at range \(range)")
                    
                    // Calculate attachment bounds
                    let layoutManager = textView.layoutManager
                    let textContainer = textView.textContainer
                    let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                    let attachmentRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                    let adjustedRect = CGRect(
                        x: attachmentRect.origin.x + textView.textContainerInset.left,
                        y: attachmentRect.origin.y + textView.textContainerInset.top,
                        width: attachmentRect.width,
                        height: attachmentRect.height
                    )
                    print("🔍 handleTap: Attachment frame: \(adjustedRect)")
                    
                    if adjustedRect.contains(location) {
                        print("✅ handleTap: Tap location \(location) IS within attachment bounds \(adjustedRect)")
                    } else {
                        print("❌ handleTap: Tap location \(location) is NOT within attachment bounds \(adjustedRect)")
                    }
                }
            }
        }
        
        // First check for new NSTextAttachment checkboxes
        if let (attachment, range) = CheckboxManager.findCheckboxAtLocation(location, in: textView) {
            print("✅ handleTap: Found NSTextAttachment checkbox at location \(location)")
            
            // CRITICAL: Prevent first responder activation during checkbox toggle
            if let pasteTextView = textView as? PasteHandlingTextView {
                pasteTextView.preventFirstResponder = true
            }
            
            CheckboxManager.toggleCheckbox(attachment, in: textView, at: range)
            print("🎯 RichTextCoordinator: Toggled NSTextAttachment checkbox")
            
            // Reset the flag after toggle is complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if let pasteTextView = self.textView as? PasteHandlingTextView {
                    pasteTextView.preventFirstResponder = false
                }
            }
            return
        }
        
        // Check for drawing attachments
        if let (drawingAttachment, range) = findDrawingAttachmentAtLocation(location, in: textView) {
            print("🎨 handleTap: Found DrawingTextAttachment at location \(location)")
            openDrawingEditor(for: drawingAttachment, at: range)
            return
        }
        
        print("❌ handleTap: No attachments found at tap location")
        
        guard let attributedText = textView.attributedText else { return }
        
        // Fallback: Check for legacy Unicode checkbox characters for backward compatibility
        if let tapPosition = textView.closestPosition(to: location) {
            let tapIndex = textView.offset(from: textView.beginningOfDocument, to: tapPosition)
            print("📍 handleTap: Tap index calculated as \(tapIndex), text length: \(attributedText.length)")
            
            if tapIndex >= 0 && tapIndex < attributedText.length {
                // Check around the tap position for checkbox Unicode characters
                let tapTolerance = 15 // Reduced tolerance since NSTextAttachment has better hit detection
                let checkStartRange = max(0, tapIndex - tapTolerance)
                let checkEndRange = min(attributedText.length - 1, tapIndex + tapTolerance)
                print("🔍 handleTap: Checking range \(checkStartRange) to \(checkEndRange) for legacy Unicode checkboxes")
                
                for checkIndex in checkStartRange...checkEndRange {
                    if checkIndex < attributedText.length {
                        let character = (attributedText.string as NSString).character(at: checkIndex)
                        
                        // Check for Unicode checkbox characters (legacy support)
                        if character == 0x2610 { // ☐ unchecked
                            print("✅ handleTap: Found legacy unchecked checkbox '☐' at position \(checkIndex)")
                            toggleUnicodeCheckboxAtPosition(checkIndex, isCurrentlyChecked: false)
                            print("🎯 RichTextCoordinator: Toggled legacy Unicode checkbox at position \(checkIndex)")
                            return
                        } else if character == 0x2611 { // ☑ checked
                            print("✅ handleTap: Found legacy checked checkbox '☑' at position \(checkIndex)")
                            toggleUnicodeCheckboxAtPosition(checkIndex, isCurrentlyChecked: true)
                            print("🎯 RichTextCoordinator: Toggled legacy Unicode checkbox at position \(checkIndex)")
                            return
                        }
                    }
                }
            }
        }
        
        print("📍 handleTap: No checkbox found at tap location \(location)")
    }
    
    /// Toggle a Unicode checkbox between checked and unchecked state
    private func toggleUnicodeCheckboxAtPosition(_ position: Int, isCurrentlyChecked: Bool) {
        // Prevent recursive checkbox detection during toggle
        guard !isTogglingSelf else { 
            print("⚠️ toggleUnicodeCheckboxAtPosition: Already toggling, skipping")
            return 
        }
        
        print("🔄 toggleUnicodeCheckboxAtPosition: Starting toggle at position \(position), currently checked: \(isCurrentlyChecked)")
        guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            print("❌ toggleUnicodeCheckboxAtPosition: Could not get mutableText")
            return
        }
        guard position < mutableText.length else {
            print("❌ toggleUnicodeCheckboxAtPosition: Position \(position) >= text length \(mutableText.length)")
            return
        }
        
        // Set flag to prevent cursor-based detection during toggle
        isTogglingSelf = true
        defer { 
            // Reset flag after a brief delay to ensure all selection changes are processed
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isTogglingSelf = false
            }
        }
        
        // Create the new checkbox with opposite state
        let newCheckbox = createUnicodeCheckbox(isChecked: !isCurrentlyChecked)
        
        // Replace the character at the position
        mutableText.replaceCharacters(in: NSRange(location: position, length: 1), with: newCheckbox)
        
        // Update the text view
        textView.attributedText = mutableText
        
        // Update the binding and context to reflect the changes
        updateBindingFromTextView()
        updateContextFromTextView()
        
        // Track analytics
        AnalyticsManager.shared.trackCheckboxClicked(isChecked: !isCurrentlyChecked, checkboxType: "unicode")
        
        print("✅ RichTextCoordinator: Toggled Unicode checkbox to \(isCurrentlyChecked ? "unchecked" : "checked") at position \(position)")
    }
    
    /// Check if the cursor is positioned on or near a checkbox and toggle it
    /// This provides an alternative to gesture-based checkbox detection
    private func checkForCheckboxAtCursorPosition() {
        guard let attributedText = textView.attributedText else { return }
        guard textView.selectedRange.length == 0 else { return } // Only for cursor, not selection
        
        let cursorPosition = textView.selectedRange.location
        guard cursorPosition >= 0 && cursorPosition <= attributedText.length else { return }
        
        // For cursor at end of text, check if the last character is a checkbox
        let checkPosition = cursorPosition == attributedText.length ? cursorPosition - 1 : cursorPosition
        guard checkPosition >= 0 && checkPosition < attributedText.length else { return }
        
        // Check exact cursor position and adjacent positions for checkboxes
        let checkRange = 1
        let startRange = max(0, checkPosition - checkRange)
        let endRange = min(attributedText.length - 1, checkPosition + checkRange)
        
        print("🎯 checkForCheckboxAtCursorPosition: Checking range \(startRange) to \(endRange) around cursor at \(cursorPosition)")
        
        // Prioritize exact position first
        if checkPosition < attributedText.length {
            let character = (attributedText.string as NSString).character(at: checkPosition)
            if character == 0x2610 { // ☐ unchecked
                print("🎯 checkForCheckboxAtCursorPosition: Found unchecked checkbox at exact position \(checkPosition), toggling!")
                toggleUnicodeCheckboxAtPosition(checkPosition, isCurrentlyChecked: false)
                return
            } else if character == 0x2611 { // ☑ checked
                print("🎯 checkForCheckboxAtCursorPosition: Found checked checkbox at exact position \(checkPosition), toggling!")
                toggleUnicodeCheckboxAtPosition(checkPosition, isCurrentlyChecked: true)
                return
            }
        }
        
        // Then check adjacent positions
        for checkIndex in startRange...endRange {
            if checkIndex != checkPosition && checkIndex < attributedText.length {
                let character = (attributedText.string as NSString).character(at: checkIndex)
                
                // Check for Unicode checkbox characters
                if character == 0x2610 { // ☐ unchecked
                    print("🎯 checkForCheckboxAtCursorPosition: Found unchecked checkbox at adjacent position \(checkIndex), toggling!")
                    toggleUnicodeCheckboxAtPosition(checkIndex, isCurrentlyChecked: false)
                    return
                } else if character == 0x2611 { // ☑ checked
                    print("🎯 checkForCheckboxAtCursorPosition: Found checked checkbox at adjacent position \(checkIndex), toggling!")
                    toggleUnicodeCheckboxAtPosition(checkIndex, isCurrentlyChecked: true)
                    return
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    /// Check if a line starts with a checkbox (either NSTextAttachment or Unicode)
    private func checkForCheckboxAtLineStart(mutableText: NSMutableAttributedString, lineRange: NSRange, lineText: String) -> Bool {
        // Calculate the position where a checkbox would be (after leading whitespace)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        let leadingWhitespace = lineText.count - trimmedLine.count
        let checkboxStartPosition = lineRange.location + leadingWhitespace
        
        // First check for NSTextAttachment checkboxes (preferred)
        let searchRange = NSRange(location: checkboxStartPosition, length: min(3, max(0, lineRange.location + lineRange.length - checkboxStartPosition)))
        
        // Check for NSTextAttachment checkboxes first
        var foundCheckbox = false
        mutableText.enumerateAttribute(.attachment, in: searchRange, options: []) { value, range, stop in
            if value is CheckboxTextAttachment {
                print("✅ checkForCheckboxAtLineStart: Found NSTextAttachment checkbox at position \(range.location)")
                foundCheckbox = true
                stop.pointee = true
            }
        }
        
        if foundCheckbox {
            return true
        }
        
        // Fallback: Check for legacy Unicode checkboxes
        for i in 0..<searchRange.length {
            let checkPosition = searchRange.location + i
            if checkPosition < mutableText.length {
                let character = (mutableText.string as NSString).character(at: checkPosition)
                // Check for Unicode checkbox characters
                if character == 0x2610 || character == 0x2611 { // ☐ or ☑
                    print("✅ checkForCheckboxAtLineStart: Found Unicode checkbox at position \(checkPosition)")
                    return true
                }
            }
        }
        
        print("❌ checkForCheckboxAtLineStart: No checkbox found in line range \(lineRange)")
        return false
    }
    
    /// Insert a new drawing overlay at the specified position
    private func applyDrawingFormat(_ selectedRange: NSRange) {
        print("🎨 RichTextCoordinator: applyDrawingFormat called at range \(selectedRange)")
        
        // Use the new overlay approach instead of NSTextAttachment
        if let drawingManager = drawingManager {
            print("🎨 RichTextCoordinator: Using overlay manager to insert drawing")
            drawingManager.insertDrawing(at: selectedRange)
        } else {
            print("❌ RichTextCoordinator: No drawing manager available, falling back to old method")
            // Fallback to old attachment method if overlay manager not available
            DrawingManager.insertDrawing(in: textView, at: selectedRange)
        }
        
        // Reset drawing active state to prevent UI cycling
        DispatchQueue.main.async {
            self.context.isDrawingActive = false
            print("🎨 RichTextCoordinator: Reset isDrawingActive to false after drawing action")
        }
        
        print("🎨 RichTextCoordinator: Drawing handling complete at range \(selectedRange)")
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow our tap gesture to work alongside UITextView's built-in gestures
        // BUT also allow SwiftUI drag gestures for keyboard dismissal
        print("🖱️ shouldRecognizeSimultaneously: \(type(of: gestureRecognizer)) with \(type(of: otherGestureRecognizer))")
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let location = touch.location(in: textView)
        print("🖱️ gestureRecognizer shouldReceive touch at location: \(location)")
        print("🖱️ gestureRecognizer: touch.view = \(String(describing: touch.view))")
        
        // Check if this touch might be on a checkbox
        if let (_, _) = CheckboxManager.findCheckboxAtLocation(location, in: textView) {
            print("🖱️ gestureRecognizer: Detected touch on checkbox, preventing first responder")
            // CANCEL touches to prevent UITextView default tap behavior when checkbox is clicked
            gestureRecognizer.cancelsTouchesInView = true
            
            // CRITICAL: Prevent text view from becoming first responder on checkbox taps
            // This prevents cursor movement and keyboard activation
            if let pasteTextView = textView as? PasteHandlingTextView {
                pasteTextView.preventFirstResponder = true
                
                // Reset the flag after a short delay to allow normal editing behavior later
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    pasteTextView.preventFirstResponder = false
                }
            }
            return true
        }
        
        // Check if this touch might be on a drawing attachment
        // If so, we want to ensure our gesture recognizer can handle it
        if let touchView = touch.view {
            // Check if this looks like a drawing attachment view
            let viewClassName = String(describing: type(of: touchView))
            if viewClassName.contains("Attachment") || touchView.frame.width > 200 {
                print("🖱️ gestureRecognizer: Detected potential attachment view, ensuring recognition")
                // CANCEL touches for drawing attachments too
                gestureRecognizer.cancelsTouchesInView = true
                return true
            }
        }
        
        // For normal text touches, don't interfere with text editing or other gestures
        gestureRecognizer.cancelsTouchesInView = false
        return true
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't wait for other gestures to fail - process checkbox taps immediately
        return false
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't require our gesture to fail for other gestures (especially drag gestures for keyboard dismissal)
        print("🖱️ shouldBeRequiredToFailBy: \(type(of: gestureRecognizer)) by \(type(of: otherGestureRecognizer))")
        return false
    }
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive event: UIEvent) -> Bool {
        print("🖱️ gestureRecognizer shouldReceive event: \(event)")
        return true
    }
    
    // MARK: - Cursor Position Helpers
    
    /// Prevent cursor from being placed to the left of checkboxes or bullets
    /// Also implements tap-to-left behavior for checkboxes per user requirements
    private func preventCursorLeftOfListMarkers(_ textView: UITextView) {
        guard let attributedText = textView.attributedText else { return }
        
        let currentPosition = textView.selectedRange.location
        let currentLine = (attributedText.string as NSString).lineRange(for: NSRange(location: min(currentPosition, attributedText.length), length: 0))
        
        // Check if there's a checkbox attachment at the beginning of this line
        var foundCheckboxAttachment: CheckboxTextAttachment?
        var foundCheckboxPosition: Int?
        var foundBulletPosition: Int?
        
        // Look for checkbox attachments in this line
        attributedText.enumerateAttribute(.attachment, in: currentLine, options: []) { value, range, stop in
            if let checkboxAttachment = value as? CheckboxTextAttachment {
                // Found a checkbox - check if it's at or near the beginning of the line
                if range.location <= currentLine.location + 3 {  // Allow for some whitespace
                    foundCheckboxAttachment = checkboxAttachment
                    foundCheckboxPosition = range.location
                    stop.pointee = true
                }
            }
        }
        
        // Check for bullet points at the beginning of the line
        if foundCheckboxPosition == nil {
            let lineText = (attributedText.string as NSString).substring(with: currentLine)
            let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
            if trimmedLine.hasPrefix("• ") {
                let leadingWhitespaceCount = lineText.count - lineText.ltrimmed().count
                foundBulletPosition = currentLine.location + leadingWhitespaceCount
            }
        }
        
        // Enhanced cursor restriction with tap-to-left checkbox behavior
        if let checkboxPos = foundCheckboxPosition, 
           let checkboxAttachment = foundCheckboxAttachment,
           currentPosition <= checkboxPos {
            
            // Check if this was a recent user tap that should toggle the checkbox
            // (as opposed to programmatic cursor movement)
            let timeSinceLastTap = Date().timeIntervalSince(lastUserTapTime)
            let isRecentUserTap = timeSinceLastTap < 0.5 // Within 500ms of user tap
            
            if isRecentUserTap {
                print("🎯 preventCursorLeftOfListMarkers: Detected tap-to-left of checkbox - toggling instead of moving cursor")
                
                // Toggle the checkbox without moving the cursor
                let range = NSRange(location: checkboxPos, length: 1)
                CheckboxManager.toggleCheckbox(checkboxAttachment, in: textView, at: range)
                
                // For tap-to-left behavior, position cursor after the checkbox (not where they tapped)
                // This prevents the cursor from being left of the checkbox after toggling
                let newPosition = checkboxPos + 2  // Checkbox + space
                if newPosition <= attributedText.length {
                    textView.selectedRange = NSRange(location: newPosition, length: 0)
                    print("📍 preventCursorLeftOfListMarkers: Toggled checkbox and positioned cursor after checkbox at \(newPosition)")
                }
                
                // Return early to avoid the normal cursor repositioning logic below
                return
            } else {
                // Regular cursor movement - just reposition after checkbox
                let newPosition = checkboxPos + 2  // Checkbox + space
                if newPosition <= attributedText.length {
                    textView.selectedRange = NSRange(location: newPosition, length: 0)
                    print("📍 preventCursorLeftOfListMarkers: Moved cursor from \(currentPosition) to \(newPosition) (after checkbox)")
                }
            }
        } else if let bulletPos = foundBulletPosition, currentPosition < bulletPos + 2 {
            // Move cursor after bullet and space (bullets don't toggle)
            let newPosition = bulletPos + 2  // "• "
            if newPosition <= attributedText.length {
                textView.selectedRange = NSRange(location: newPosition, length: 0)
                print("📍 preventCursorLeftOfListMarkers: Moved cursor from \(currentPosition) to \(newPosition) (after bullet)")
            }
        }
    }
    
    // MARK: - Code Block Helper Methods
    
    /// Check if the given position is actually in a code block by examining text attributes
    /// This is more reliable than relying on context state during typing
    private func checkIfPositionIsInCodeBlock(_ position: Int) -> Bool {
        guard let attributedText = textView.attributedText,
              position >= 0 && position <= attributedText.length else { 
            return false 
        }
        
        // If position is at the end of text, check the previous character
        let checkPosition = position == attributedText.length ? max(0, position - 1) : position
        
        // If we have no text or are at position 0 of empty text, not in code block
        guard checkPosition < attributedText.length && attributedText.length > 0 else { 
            return false 
        }
        
        // Check a small range around the position (similar to RichTextContext but more focused)
        let rangeStart = max(0, checkPosition - 1)
        let rangeEnd = min(attributedText.length - 1, checkPosition + 1)
        
        for pos in rangeStart...rangeEnd {
            if pos < attributedText.length {
                let attributes = attributedText.attributes(at: pos, effectiveRange: nil)
                
                // Check for monospaced font (most reliable indicator)
                if let font = attributes[.font] as? UIFont {
                    let hasMonaco = font.fontName.contains("Monaco")
                    let hasMonospaceTrait = font.fontDescriptor.symbolicTraits.contains(.traitMonoSpace)
                    let hasSystemMonospace = font.fontName.contains("SFMono") || font.fontName.contains("Menlo") || font.fontName.contains("Courier")
                    let hasAppleSystemMonospace = font.fontName.contains(".AppleSystemUIFontMonospaced")
                    
                    if hasMonaco || hasMonospaceTrait || hasSystemMonospace || hasAppleSystemMonospace {
                        // Found monospaced font indicating code block
                        return true
                    }
                }
                
                // Also check for grey background color
                if let backgroundColor = attributes[.backgroundColor] as? UIColor {
                    if backgroundColor == UIColor.systemGray6 {
                        // Found code background color
                        return true
                    }
                }
            }
        }
        
        // No code block detected at this position
        return false
    }
    
    // MARK: - Drawing Attachment Helper Methods
    
    /// Find drawing attachment at the given tap location
    private func findDrawingAttachmentAtLocation(_ location: CGPoint, in textView: UITextView) -> (DrawingTextAttachment, NSRange)? {
        print("🔍 findDrawingAttachmentAtLocation: Searching for drawing button at location \(location)")
        
        guard let textPosition = textView.closestPosition(to: location) else { 
            print("❌ findDrawingAttachmentAtLocation: Could not get text position")
            return nil 
        }
        
        let tapIndex = textView.offset(from: textView.beginningOfDocument, to: textPosition)
        guard let attributedText = textView.attributedText else { 
            print("❌ findDrawingAttachmentAtLocation: No attributed text")
            return nil 
        }
        
        print("🔍 findDrawingAttachmentAtLocation: Tap index \(tapIndex), text length \(attributedText.length)")
        
        // Function to check if tap is in the "Open" button area of a drawing attachment
        func isInOpenButtonArea(drawingAttachment: DrawingTextAttachment, characterIndex: Int) -> Bool {
            // Get the attachment bounds from the layout manager
            let layoutManager = textView.layoutManager
            let textContainer = textView.textContainer
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
            let attachmentRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyphIndex, length: 1), in: textContainer)
            
            // Adjust for text container insets
            let adjustedRect = CGRect(
                x: attachmentRect.origin.x + textView.textContainerInset.left,
                y: attachmentRect.origin.y + textView.textContainerInset.top,
                width: attachmentRect.width,
                height: attachmentRect.height
            )
            
            print("🔍 findDrawingAttachmentAtLocation: Attachment rect: \(adjustedRect)")
            
            // Check if tap is within the attachment bounds first
            guard adjustedRect.contains(location) else {
                print("🔍 findDrawingAttachmentAtLocation: Tap not within attachment bounds")
                return false
            }
            
            // Calculate "Open" button area (top right of attachment)
            // Button dimensions from drawOptionsButton method: width=50, height=24, positioned at x=bounds.width-50-8, y=4
            let buttonWidth: CGFloat = 50
            let buttonHeight: CGFloat = 24
            let buttonRect = CGRect(
                x: adjustedRect.maxX - buttonWidth - 8,
                y: adjustedRect.minY + 4,
                width: buttonWidth,
                height: buttonHeight
            )
            
            print("🔍 findDrawingAttachmentAtLocation: Open button rect: \(buttonRect)")
            
            let isInButton = buttonRect.contains(location)
            print("🔍 findDrawingAttachmentAtLocation: Tap \(isInButton ? "IS" : "IS NOT") in Open button area")
            
            return isInButton
        }
        
        // Check for attachment at tap position
        if tapIndex < attributedText.length {
            let attachment = attributedText.attribute(.attachment, at: tapIndex, effectiveRange: nil)
            
            if let drawingAttachment = attachment as? DrawingTextAttachment {
                print("🔍 findDrawingAttachmentAtLocation: Found DrawingTextAttachment at index \(tapIndex)")
                
                // Only return the attachment if the tap is specifically in the "Open" button area
                if isInOpenButtonArea(drawingAttachment: drawingAttachment, characterIndex: tapIndex) {
                    print("✅ findDrawingAttachmentAtLocation: Tap is in Open button area!")
                    return (drawingAttachment, NSRange(location: tapIndex, length: 1))
                } else {
                    print("❌ findDrawingAttachmentAtLocation: Tap is not in Open button area, ignoring")
                    return nil
                }
            }
        }
        
        // Check previous character (in case tap was on the edge)
        if tapIndex > 0 && tapIndex - 1 < attributedText.length {
            let attachment = attributedText.attribute(.attachment, at: tapIndex - 1, effectiveRange: nil)
            
            if let drawingAttachment = attachment as? DrawingTextAttachment {
                print("🔍 findDrawingAttachmentAtLocation: Found DrawingTextAttachment at index \(tapIndex - 1)")
                
                // Only return the attachment if the tap is specifically in the "Open" button area
                if isInOpenButtonArea(drawingAttachment: drawingAttachment, characterIndex: tapIndex - 1) {
                    print("✅ findDrawingAttachmentAtLocation: Tap is in Open button area!")
                    return (drawingAttachment, NSRange(location: tapIndex - 1, length: 1))
                } else {
                    print("❌ findDrawingAttachmentAtLocation: Tap is not in Open button area, ignoring")
                    return nil
                }
            }
        }
        
        // Try a broader search around the tap position using layout manager
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        print("🔍 findDrawingAttachmentAtLocation: Trying layout manager approach")
        
        // Convert location to text container coordinates
        let containerLocation = CGPoint(
            x: location.x - textView.textContainerInset.left,
            y: location.y - textView.textContainerInset.top
        )
        
        // Find glyph index
        let glyphIndex = layoutManager.glyphIndex(for: containerLocation, in: textContainer)
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        
        print("🔍 findDrawingAttachmentAtLocation: Layout manager - glyph index: \(glyphIndex), char index: \(charIndex)")
        
        if charIndex < attributedText.length {
            let attachment = attributedText.attribute(.attachment, at: charIndex, effectiveRange: nil)
            print("🔍 findDrawingAttachmentAtLocation: Layout manager attachment at \(charIndex): \(String(describing: attachment))")
            
            if let drawingAttachment = attachment as? DrawingTextAttachment {
                print("✅ findDrawingAttachmentAtLocation: Found DrawingTextAttachment via layout manager at \(charIndex)")
                return (drawingAttachment, NSRange(location: charIndex, length: 1))
            }
        }
        
        print("❌ findDrawingAttachmentAtLocation: No DrawingTextAttachment found")
        return nil
    }
    
    /// Open drawing editor for the given drawing attachment
    private func openDrawingEditor(for attachment: DrawingTextAttachment, at range: NSRange) {
        // Find the view controller to present the drawing editor
        guard let viewController = textView.findViewController() else {
            print("❌ openDrawingEditor: Could not find view controller")
            return
        }
        
        // Create the drawing editor view
        let editorView = DrawingEditorView(
            drawingData: .constant(attachment.drawingData),
            canvasHeight: .constant(attachment.canvasHeight),
            selectedColor: .constant(attachment.selectedColor),
            onSave: { [weak self] data, height, color in
                // Update the attachment with the new drawing data
                attachment.drawingData = data
                attachment.canvasHeight = height
                attachment.selectedColor = color
                
                // Force text view to update
                self?.textView.setNeedsDisplay()
                self?.textView.delegate?.textViewDidChange?(self?.textView ?? UITextView())
            },
            onDelete: { [weak self] in
                // Remove the drawing attachment
                guard let self = self,
                      let mutableText = self.textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
                    return
                }
                
                mutableText.removeAttribute(.attachment, range: range)
                mutableText.replaceCharacters(in: range, with: NSAttributedString(string: ""))
                self.textView.attributedText = mutableText
                self.textView.delegate?.textViewDidChange?(self.textView)
            }
        )
        
        let hostingController = UIHostingController(rootView: editorView)
        viewController.present(hostingController, animated: true)
    }
    
}

// MARK: - String Extensions

extension String {
    func ltrimmed() -> String {
        guard let index = firstIndex(where: { !$0.isWhitespace }) else {
            return ""
        }
        return String(self[index...])
    }
}