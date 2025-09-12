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
    private let textView: UITextView
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
        
        setupTextView()
        setupContextObservation()
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
        // Set initial content
        let initialText = textBinding.wrappedValue
        if textView.attributedText != initialText {
            textView.attributedText = initialText
            context.setAttributedString(initialText)
        }
        
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
        let safeRange = NSRange(
            location: min(range.location, textView.attributedText.length),
            length: min(range.length, textView.attributedText.length - min(range.location, textView.attributedText.length))
        )
        textView.selectedRange = safeRange
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
        
        // Update typing attributes for future text
        updateTypingAttributes()
        updateBindingFromTextView()
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
        let mutableLineText: String
        
        if trimmedLine.hasPrefix("• ") {
            // Remove bullet
            mutableLineText = String(trimmedLine.dropFirst(2))
        } else if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // Replace checkbox with bullet
            mutableLineText = "• " + String(trimmedLine.dropFirst(2))
        } else {
            // Add bullet
            mutableLineText = "• " + trimmedLine
        }
        
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Update text view and maintain sensible cursor position
        let newCursorLocation = lineRange.location + min(mutableLineText.count, lineRange.length)
        textView.attributedText = mutableText
        textView.selectedRange = NSRange(location: newCursorLocation, length: 0)
    }
    
    private func applyCheckboxFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        let mutableLineText: String
        
        if trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
            // Remove checkbox
            mutableLineText = String(trimmedLine.dropFirst(2))
        } else if trimmedLine.hasPrefix("• ") {
            // Replace bullet with checkbox
            mutableLineText = "☐ " + String(trimmedLine.dropFirst(2))
        } else {
            // Add checkbox
            mutableLineText = "☐ " + trimmedLine
        }
        
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Update text view and maintain sensible cursor position
        let newCursorLocation = lineRange.location + min(mutableLineText.count, lineRange.length)
        textView.attributedText = mutableText
        textView.selectedRange = NSRange(location: newCursorLocation, length: 0)
    }
    
    // MARK: - Binding Updates
    
    private func updateBindingFromTextView() {
        guard !isUpdatingFromContext else { return }
        textBinding.wrappedValue = textView.attributedText
    }
    
    private func updateContextFromTextView() {
        guard !isUpdatingFromContext else { return }
        
        isUpdatingFromTextView = true
        defer { isUpdatingFromTextView = false }
        
        // Update context state
        context.setAttributedString(textView.attributedText)
        context.setSelectedRange(textView.selectedRange)
        
        // Update undo/redo state
        let undoManager = textView.undoManager
        context.updateUndoRedoState(
            canUndo: undoManager?.canUndo ?? false,
            canRedo: undoManager?.canRedo ?? false
        )
        
        // Update copy state
        context.updateCopyState(textView.selectedRange.length > 0)
    }
    
    private func updateTypingAttributes() {
        let selectedRange = textView.selectedRange
        guard selectedRange.length == 0, selectedRange.location > 0 else { return }
        
        let attributes = textView.attributedText.attributes(
            at: selectedRange.location - 1,
            effectiveRange: nil
        )
        textView.typingAttributes = attributes
    }
}

// MARK: - UITextViewDelegate

extension RichTextCoordinator: UITextViewDelegate {
    
    public func textViewDidChange(_ textView: UITextView) {
        updateBindingFromTextView()
        updateContextFromTextView()
    }
    
    public func textViewDidChangeSelection(_ textView: UITextView) {
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
        if trimmedLine.hasPrefix("• ") {
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
                mutableText.replaceCharacters(in: range, with: "\n• ")
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
            if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("☐ ") || trimmedLine.hasPrefix("☑ ") {
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