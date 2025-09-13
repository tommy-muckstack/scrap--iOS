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
    private var isUpdatingFromTextView = false
    
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
    }
    
    /// Connect this coordinator to the actual textView (called from makeUIView)
    public func connectTextView(_ textView: UITextView) {
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
        
        // Configure for rich text editing
        textView.typingAttributes = [
            .font: UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize),
            .foregroundColor: UIColor.label
        ]
        
        // No custom gestures needed - UITextView handles all selection natively
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
        let maxLocation = max(0, textView.attributedText.length)
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
            applyBlockFormat(format)
            
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
        let textLength = textView.attributedText.length
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
        
        // Update binding first to sync the attributed text
        updateBindingFromTextView()
        
        // Update typing attributes based on new formatting state
        updateTypingAttributes()
    }
    
    private func toggleBoldInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        mutableText.enumerateAttribute(.font, in: range) { value, subRange, _ in
            if let font = value as? UIFont {
                let newFont: UIFont
                if font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    // Remove bold
                    let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitBold)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont(name: context.fontName, size: font.pointSize) ?? font
                    }
                } else {
                    // Add bold
                    let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont.boldSystemFont(ofSize: font.pointSize)
                    }
                }
                mutableText.addAttribute(.font, value: newFont, range: subRange)
            }
        }
    }
    
    private func toggleItalicInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        mutableText.enumerateAttribute(.font, in: range) { value, subRange, _ in
            if let font = value as? UIFont {
                let newFont: UIFont
                if font.fontDescriptor.symbolicTraits.contains(.traitItalic) {
                    // Remove italic
                    let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitItalic)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont(name: context.fontName, size: font.pointSize) ?? font
                    }
                } else {
                    // Add italic
                    let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont.italicSystemFont(ofSize: font.pointSize)
                    }
                }
                mutableText.addAttribute(.font, value: newFont, range: subRange)
            }
        }
    }
    
    private func toggleUnderlineInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        mutableText.enumerateAttribute(.underlineStyle, in: range) { value, subRange, _ in
            let currentStyle = value as? Int ?? 0
            let newStyle = currentStyle == 0 ? 
                          NSUnderlineStyle.single.rawValue : 
                          0
            mutableText.addAttribute(.underlineStyle, value: newStyle, range: subRange)
        }
    }
    
    private func toggleStrikethroughInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        mutableText.enumerateAttribute(.strikethroughStyle, in: range) { value, subRange, _ in
            let currentStyle = value as? Int ?? 0
            let newStyle = currentStyle == 0 ? 
                          NSUnderlineStyle.single.rawValue : 
                          0
            mutableText.addAttribute(.strikethroughStyle, value: newStyle, range: subRange)
        }
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
        }
        
        updateBindingFromTextView()
    }
    
    private func applyBulletFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        print("🔍 RichTextCoordinator: Processing line: '\(trimmedLine)'")
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add bullet to empty line and position cursor after it
            let mutableLineText = "◉ "
            let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            textView.attributedText = mutableText
            let newCursorPosition = lineRange.location + 2 // Position after "◉ "
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added bullet to empty line, cursor at position \(safePosition)")
            return
        }
        
        let mutableLineText: String
        let newCursorPosition: Int
        
        // Check if line already has a bullet (prevent duplicates)
        if trimmedLine.hasPrefix("◉ ") {
            // Remove bullet - keep cursor at the beginning of the content
            mutableLineText = String(trimmedLine.dropFirst(2))
            newCursorPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count) + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing bullet from line")
        } else if trimmedLine.hasPrefix("◉") {
            // Line starts with bullet (but no space) - remove it completely
            mutableLineText = String(trimmedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            newCursorPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count) + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing bullet (no space) from line")
        } else if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // Replace checkbox with bullet - cursor goes after "◉ "
            let contentAfterCheckbox = String(trimmedLine.dropFirst(2))
            mutableLineText = "◉ " + contentAfterCheckbox
            newCursorPosition = lineRange.location + 2 // Position after "◉ "
            print("🔸 RichTextCoordinator: Replacing checkbox with bullet")
        } else if !trimmedLine.contains("◉") {
            // Add bullet only if line doesn't already contain bullets - cursor goes after "◉ "
            mutableLineText = "◉ " + trimmedLine
            newCursorPosition = lineRange.location + 2 // Position after "◉ "
            print("🔸 RichTextCoordinator: Adding bullet to line")
        } else {
            // Line already contains bullets somewhere - clean up duplicates instead of adding more
            print("🚫 RichTextCoordinator: Line contains bullets - cleaning up duplicates")
            mutableLineText = cleanupDuplicateBullets(trimmedLine)
            newCursorPosition = lineRange.location + 2 // Position after single "◉ "
        }
        
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
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
        let withoutBullets = line.replacingOccurrences(of: "◉ ", with: "").trimmingCharacters(in: .whitespaces)
        // Add single bullet at start
        return "◉ " + withoutBullets
    }
    
    /// Clean up the entire text content to remove duplicate bullets/checkboxes
    public func cleanupDuplicateFormatting() {
        let currentText = textView.attributedText.string
        let lines = currentText.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Count bullets and checkboxes
            let bulletCount = trimmedLine.components(separatedBy: "◉ ").count - 1
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
        // Remove all checkboxes and clean up extra spaces
        let withoutCheckboxes = line.replacingOccurrences(of: "☐ ", with: "")
                                   .replacingOccurrences(of: "☑ ", with: "")
                                   .trimmingCharacters(in: .whitespaces)
        // Add single checkbox at start (preserve checked state if any were checked)
        let hadCheckedBox = line.contains("☑ ")
        return (hadCheckedBox ? "☑ " : "☐ ") + withoutCheckboxes
    }
    
    private func applyCheckboxFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add checkbox to empty line and position cursor after it  
            let mutableLineText = "☐ "  // U+2610 BALLOT BOX (unchecked)
            let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            textView.attributedText = mutableText
            let newCursorPosition = lineRange.location + 2 // Position after "☐ "
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added checkbox to empty line, cursor at position \(safePosition)")
            return
        }
        
        let mutableLineText: String
        let newCursorPosition: Int
        
        // Check if line already has a checkbox (prevent duplicates)
        if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // Remove checkbox - cursor goes to start of text content
            mutableLineText = String(trimmedLine.dropFirst(2))
            newCursorPosition = lineRange.location + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing checkbox from line")
        } else if trimmedLine.hasPrefix("☐") || trimmedLine.hasPrefix("☑") {
            // Line starts with checkbox (but no space) - remove it completely
            mutableLineText = String(trimmedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            newCursorPosition = lineRange.location + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing checkbox (no space) from line")
        } else if trimmedLine.hasPrefix("◉ ") {
            // Replace bullet with checkbox - cursor goes after "☐ "
            let contentAfterBullet = String(trimmedLine.dropFirst(2))
            mutableLineText = "☐ " + contentAfterBullet
            newCursorPosition = lineRange.location + 2 // Position after "☐ "
            print("🔸 RichTextCoordinator: Replacing bullet with checkbox")
        } else if !trimmedLine.contains("☐") && !trimmedLine.contains("☑") {
            // Add checkbox only if line doesn't already contain checkboxes - cursor goes after "☐ "
            mutableLineText = "☐ " + trimmedLine
            newCursorPosition = lineRange.location + 2 // Position after "☐ "
            print("🔸 RichTextCoordinator: Adding checkbox to line")
        } else {
            // Line already contains checkboxes somewhere - don't add another
            print("🚫 RichTextCoordinator: Line already contains checkboxes - not adding another")
            return
        }
        
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Update text view with correct cursor position
        textView.attributedText = mutableText
        
        // Ensure cursor position is valid for the new text length
        let safePosition = min(newCursorPosition, mutableText.length)
        textView.selectedRange = NSRange(location: safePosition, length: 0)
        
        print("🎯 RichTextCoordinator: Checkbox format applied - cursor at position \(safePosition)")
    }
    
    // MARK: - Binding Updates
    
    private func updateBindingFromTextView() {
        guard !isUpdatingFromContext else { return }
        
        // Only update binding if the text actually changed to prevent loops
        if !textBinding.wrappedValue.isEqual(to: textView.attributedText) {
            textBinding.wrappedValue = textView.attributedText
        }
    }
    
    private func updateContextFromTextView() {
        guard !isUpdatingFromContext else { return }
        
        isUpdatingFromTextView = true
        defer { isUpdatingFromTextView = false }
        
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
        
        // Update formatting state
        context.updateFormattingState()
    }
    
    private func updateTypingAttributes() {
        // Build typing attributes based on current context state and selection
        var typingAttributes = textView.typingAttributes
        
        // Get base font
        let baseFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
        
        // Apply formatting based on current context state
        var font = baseFont
        if context.isBoldActive {
            font = applyBoldToFont(font)
        }
        if context.isItalicActive {
            font = applyItalicToFont(font)
        }
        
        typingAttributes[.font] = font
        typingAttributes[.foregroundColor] = UIColor.label
        
        // Apply other formatting
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
        
        textView.typingAttributes = typingAttributes
        print("🎨 Updated typing attributes - Bold: \(context.isBoldActive), Italic: \(context.isItalicActive)")
    }
    
    private func applyBoldToFont(_ font: UIFont) -> UIFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        } else {
            return UIFont.boldSystemFont(ofSize: font.pointSize)
        }
    }
    
    private func applyItalicToFont(_ font: UIFont) -> UIFont {
        let traits = font.fontDescriptor.symbolicTraits.union(.traitItalic)
        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
            return UIFont(descriptor: descriptor, size: font.pointSize)
        } else {
            return UIFont.italicSystemFont(ofSize: font.pointSize)
        }
    }
}

// MARK: - Native UITextView Behavior
// All text selection, copy/paste, and interaction handled natively by UITextView

// MARK: - UITextViewDelegate

extension RichTextCoordinator: UITextViewDelegate {
    
    public func textViewDidChange(_ textView: UITextView) {
        updateBindingFromTextView()
        updateContextFromTextView()
    }
    
    public func textViewDidChangeSelection(_ textView: UITextView) {
        updateContextFromTextView()
        updateTypingAttributes()
    }
    
    public func textViewDidBeginEditing(_ textView: UITextView) {
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
        
        // Handle backspace at beginning of list items
        if text.isEmpty && range.length > 0 {
            return handleBackspaceInList(textView, range)
        }
        
        return true
    }
    
    private func handleNewlineInsertion(_ textView: UITextView, _ range: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: range)
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Continue bullet lists
        if trimmedLine.hasPrefix("◉ ") {
            let remainingText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if remainingText.isEmpty {
                // Empty bullet - remove it
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                let newLineRange = NSRange(location: lineRange.location, length: lineRange.length - (lineText.hasSuffix("\n") ? 0 : 1))
                mutableText.replaceCharacters(in: newLineRange, with: "")
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: lineRange.location, length: 0)
                return false
            } else {
                // Add new bullet
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                mutableText.replaceCharacters(in: range, with: "\n◉ ")
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: range.location + 3, length: 0)
                return false
            }
        }
        
        // Continue checkbox lists  
        if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            let remainingText = String(trimmedLine.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if remainingText.isEmpty {
                // Empty checkbox - remove it
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                let newLineRange = NSRange(location: lineRange.location, length: lineRange.length - (lineText.hasSuffix("\n") ? 0 : 1))
                mutableText.replaceCharacters(in: newLineRange, with: "")
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: lineRange.location, length: 0)
                return false
            } else {
                // Add new checkbox
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                mutableText.replaceCharacters(in: range, with: "\n☐ ")
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: range.location + 3, length: 0)
                return false
            }
        }
        
        return true
    }
    
    private func handleBackspaceInList(_ textView: UITextView, _ range: NSRange) -> Bool {
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if we're at the beginning of a list item
        if range.location == lineRange.location + (lineText.count - lineText.ltrimmed().count) {
            if trimmedLine.hasPrefix("◉ ") || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
                // Remove the list marker
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                let markerRange = NSRange(location: lineRange.location + (lineText.count - lineText.ltrimmed().count), length: 2)
                mutableText.replaceCharacters(in: markerRange, with: "")
                textView.attributedText = mutableText
                textView.selectedRange = NSRange(location: range.location - 2, length: 0)
                return false
            }
        }
        
        return true
    }
    
    // MARK: - Checkbox Toggling (via toolbar buttons only)
    // Checkbox toggling is now handled via the formatting toolbar buttons
    // No custom tap gestures needed - UITextView handles all text selection natively
}

// MARK: - String Extensions

private extension String {
    func ltrimmed() -> String {
        guard let index = firstIndex(where: { !$0.isWhitespace }) else {
            return ""
        }
        return String(self[index...])
    }
}