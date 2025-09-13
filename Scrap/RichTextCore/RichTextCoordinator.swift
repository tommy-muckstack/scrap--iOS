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
    
    /// Prevents re-entrant calls during newline insertion
    private var isHandlingNewlineInsertion = false
    
    /// Prevents context updates from overriding recently applied selection formatting
    private var isPreventingContextUpdates = false
    
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
        
        // Update binding first to sync the attributed text
        updateBindingFromTextView()
        
        // For selections, don't update the context formatting state immediately
        // This prevents the formatting from being overridden
        if selectedRange.length == 0 {
            // For cursor position (no selection), update typing attributes
            updateTypingAttributes()
        } else {
            // For text selection, prevent context updates for a longer period
            isPreventingContextUpdates = true
            print("🎯 RichTextCoordinator: Applied formatting to selection - preventing context updates")
            
            // Reset prevention flag after a longer delay to allow user to complete their action
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.isPreventingContextUpdates = false
                print("🔓 RichTextCoordinator: Context update prevention reset")
            }
        }
    }
    
    private func toggleBoldInRange(_ mutableText: NSMutableAttributedString, _ range: NSRange) {
        // Determine the action based on the actual text formatting, not context state
        var shouldAddBold = true
        var hasBoldText = false
        
        if range.length > 0 {
            // For selections, check if ANY text in selection is bold
            mutableText.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? UIFont,
                   font.fontDescriptor.symbolicTraits.contains(.traitBold) {
                    hasBoldText = true
                }
            }
            // If any text is bold, remove bold from all; otherwise add bold to all
            shouldAddBold = !hasBoldText
        } else if range.location > 0 {
            // For cursor position, check typing attributes or previous character
            let prevIndex = range.location - 1
            if prevIndex < mutableText.length {
                let prevFont = mutableText.attribute(.font, at: prevIndex, effectiveRange: nil) as? UIFont
                shouldAddBold = !(prevFont?.fontDescriptor.symbolicTraits.contains(.traitBold) ?? false)
            }
        }
        
        print("🎯 RichTextCoordinator: Bold toggle - shouldAddBold: \(shouldAddBold), range: \(range)")
        
        // Apply formatting consistently across the range
        let targetRange = range.length > 0 ? range : NSRange(location: range.location, length: 0)
        
        mutableText.enumerateAttribute(.font, in: targetRange.length > 0 ? targetRange : NSRange(location: 0, length: mutableText.length)) { value, subRange, _ in
            if range.length == 0 && subRange.location != range.location && subRange.location + subRange.length != range.location {
                return // Skip ranges that don't include cursor position
            }
            
            if let font = value as? UIFont {
                let newFont: UIFont
                if shouldAddBold {
                    // Add bold
                    let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont.boldSystemFont(ofSize: font.pointSize)
                    }
                } else {
                    // Remove bold
                    let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitBold)
                    if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                        newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                    } else {
                        newFont = UIFont(name: context.fontName, size: font.pointSize) ?? font
                    }
                }
                mutableText.addAttribute(.font, value: newFont, range: subRange)
            }
        }
        
        // Update context state to reflect the actual result
        DispatchQueue.main.async {
            self.context.isBoldActive = shouldAddBold
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
            
            // Clear formatting from bullet character only (first 2 characters: "◉ ")
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
        
        // Clear formatting from bullet character only (first 2 characters: "◉ ")
        if mutableLineText.hasPrefix("◉ ") {
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
        let withoutBullets = line.replacingOccurrences(of: "◉ ", with: "").trimmingCharacters(in: .whitespaces)
        // Add single bullet at start
        return "◉ " + withoutBullets
    }
    
    /// Clean up the entire text content to remove duplicate bullets/checkboxes
    public func cleanupDuplicateFormatting() {
        let currentText = textView.attributedText?.string ?? ""
        let lines = currentText.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Count bullets and checkboxes
            let bulletCount = trimmedLine.components(separatedBy: "◉ ").count - 1
            let checkboxCount = (trimmedLine.components(separatedBy: "○ ").count - 1) + 
                               (trimmedLine.components(separatedBy: "● ").count - 1)
            
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
        let withoutCheckboxes = line.replacingOccurrences(of: "○ ", with: "")
                                   .replacingOccurrences(of: "● ", with: "")
                                   .trimmingCharacters(in: .whitespaces)
        // Add single checkbox at start (preserve checked state if any were checked)
        let hadCheckedBox = line.contains("● ")
        return (hadCheckedBox ? "● " : "○ ") + withoutCheckboxes
    }
    
    private func applyCheckboxFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add custom checkbox to empty line
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let checkboxString = NSMutableAttributedString(attachment: checkboxAttachment)
            checkboxString.append(NSAttributedString(string: " ")) // Space after checkbox
            
            let newLine = NSMutableAttributedString()
            newLine.append(checkboxString)
            if lineText.hasSuffix("\n") {
                newLine.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 1 // Position after checkbox attachment
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added custom checkbox to empty line, cursor at position \(safePosition)")
            return
        }
        
        // For now, keep using Unicode characters for existing checkboxes to maintain compatibility
        // TODO: Convert all existing checkboxes to custom attachments gradually
        let mutableLineText: String
        let newCursorPosition: Int
        
        // Check if line already has a checkbox (prevent duplicates)
        if trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
            // Remove checkbox - cursor goes to start of text content
            mutableLineText = String(trimmedLine.dropFirst(2))
            newCursorPosition = lineRange.location + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing checkbox from line")
        } else if trimmedLine.hasPrefix("○") || trimmedLine.hasPrefix("●") {
            // Line starts with checkbox (but no space) - remove it completely
            mutableLineText = String(trimmedLine.dropFirst(1)).trimmingCharacters(in: .whitespaces)
            newCursorPosition = lineRange.location + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing checkbox (no space) from line")
        } else if trimmedLine.hasPrefix("◉ ") {
            // Replace bullet with custom checkbox
            let contentAfterBullet = String(trimmedLine.dropFirst(2))
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let checkboxString = NSMutableAttributedString(attachment: checkboxAttachment)
            checkboxString.append(NSAttributedString(string: " " + contentAfterBullet))
            
            let newLine = NSMutableAttributedString()
            newLine.append(checkboxString)
            if lineText.hasSuffix("\n") {
                newLine.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 1 // Position after checkbox attachment
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Replaced bullet with custom checkbox")
            return
        } else if !trimmedLine.contains("○") && !trimmedLine.contains("●") {
            // Add custom checkbox to line
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let checkboxString = NSMutableAttributedString(attachment: checkboxAttachment)
            checkboxString.append(NSAttributedString(string: " " + trimmedLine))
            
            let newLine = NSMutableAttributedString()
            newLine.append(checkboxString)
            if lineText.hasSuffix("\n") {
                newLine.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: newLine)
            textView.attributedText = mutableText
            
            let newCursorPosition = lineRange.location + 1 // Position after checkbox attachment
            let safePosition = min(newCursorPosition, mutableText.length)
            textView.selectedRange = NSRange(location: safePosition, length: 0)
            print("🔸 RichTextCoordinator: Added custom checkbox to line")
            return
        } else {
            // Line already contains checkboxes somewhere - don't add another
            print("🚫 RichTextCoordinator: Line already contains checkboxes - not adding another")
            return
        }
        
        // Fallback for Unicode checkbox removal
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Clear formatting from checkbox characters only (first 2 characters if Unicode checkbox: "○ " or "● ")  
        let checkboxRange = NSRange(location: lineRange.location, length: min(2, newLine.count))
        if checkboxRange.location + checkboxRange.length <= mutableText.length {
            let lineStart = (newLine as NSString).substring(to: min(2, newLine.count))
            if lineStart == "○ " || lineStart == "● " {
                // Apply clean attributes to checkbox characters only
                mutableText.removeAttribute(.font, range: checkboxRange)
                mutableText.removeAttribute(.foregroundColor, range: checkboxRange)
                mutableText.removeAttribute(.backgroundColor, range: checkboxRange)
                mutableText.removeAttribute(.underlineStyle, range: checkboxRange)
                mutableText.removeAttribute(.strikethroughStyle, range: checkboxRange)
                
                // Set basic font for checkbox
                mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: checkboxRange)
                mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: checkboxRange)
            }
        }
        
        // Update text view with correct cursor position
        textView.attributedText = mutableText
        
        // Ensure cursor position is valid for the new text length
        let safePosition = min(newCursorPosition, mutableText.length)
        textView.selectedRange = NSRange(location: safePosition, length: 0)
        
        print("🎯 RichTextCoordinator: Checkbox format applied - cursor at position \(safePosition)")
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
        
        // Get all lines that overlap with the selection
        let selectedText = (text as NSString).substring(with: lineRange)
        let lines = selectedText.components(separatedBy: .newlines)
        
        var newLines: [String] = []
        for line in lines {
            if increase {
                // Add 4 spaces for indentation
                newLines.append("    " + line)
            } else {
                // Remove up to 4 spaces from the beginning
                let trimmed = line.hasPrefix("    ") ? String(line.dropFirst(4)) :
                             line.hasPrefix("   ") ? String(line.dropFirst(3)) :
                             line.hasPrefix("  ") ? String(line.dropFirst(2)) :
                             line.hasPrefix(" ") ? String(line.dropFirst(1)) : line
                newLines.append(trimmed)
            }
        }
        
        let newContent = newLines.joined(separator: "\n")
        mutableText.replaceCharacters(in: lineRange, with: newContent)
        
        // Update text view
        textView.attributedText = mutableText
        
        // Adjust cursor position based on indentation change
        let lengthDifference = newContent.count - selectedText.count
        let newCursorLocation = min(selectedRange.location + lengthDifference, mutableText.length)
        textView.selectedRange = NSRange(location: max(0, newCursorLocation), length: 0)
        
        updateBindingFromTextView()
        updateContextFromTextView()
        
        print("🔄 RichTextCoordinator: Applied indentation - increase: \(increase)")
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
        
        // Skip context updates if we just applied formatting to prevent overriding
        if isPreventingContextUpdates {
            print("🛡️ RichTextCoordinator: Skipping context update - formatting protection active")
            return
        }
        
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
        // Prevent re-entrant calls
        guard !isHandlingNewlineInsertion else { return true }
        
        let currentText = textView.text ?? ""
        let lineRange = (currentText as NSString).lineRange(for: range)
        let lineText = (currentText as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Continue bullet lists
        if trimmedLine.hasPrefix("◉ ") {
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
                mutableText.replaceCharacters(in: range, with: "\n◉ ")
                
                // Clear formatting from new bullet line (bullet + space only, not affecting existing text)
                let bulletRange = NSRange(location: range.location + 1, length: 2) // "\n◉ " -> just "◉ "
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
                
                // Reset text formatting state in context (keep bullets active)
                DispatchQueue.main.async { [weak self] in
                    self?.context.isBoldActive = false
                    self?.context.isItalicActive = false
                    self?.context.isUnderlineActive = false
                    self?.context.isStrikethroughActive = false
                }
                
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
        
        // Continue checkbox lists  
        if trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
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
                // Add new checkbox
                isHandlingNewlineInsertion = true
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                mutableText.replaceCharacters(in: range, with: "\n○ ")
                
                // Clear formatting from new checkbox line (checkbox + space only, not affecting existing text)
                let checkboxRange = NSRange(location: range.location + 1, length: 2) // "\n○ " -> just "○ "
                if checkboxRange.location + checkboxRange.length <= mutableText.length {
                    // Remove all text formatting from checkbox
                    mutableText.removeAttribute(.font, range: checkboxRange)
                    mutableText.removeAttribute(.foregroundColor, range: checkboxRange)
                    mutableText.removeAttribute(.backgroundColor, range: checkboxRange)
                    mutableText.removeAttribute(.underlineStyle, range: checkboxRange)
                    mutableText.removeAttribute(.strikethroughStyle, range: checkboxRange)
                    
                    // Set clean attributes for checkbox
                    mutableText.addAttribute(.font, value: UIFont.systemFont(ofSize: 16), range: checkboxRange)
                    mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: checkboxRange)
                }
                
                textView.attributedText = mutableText
                let newCursorPosition = range.location + 3
                textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
                
                // Clear typing attributes to reset formatting for new text
                textView.typingAttributes = [
                    .font: UIFont.systemFont(ofSize: 16),
                    .foregroundColor: UIColor.label
                ]
                
                // Reset text formatting state in context (keep checkboxes active)
                DispatchQueue.main.async { [weak self] in
                    self?.context.isBoldActive = false
                    self?.context.isItalicActive = false
                    self?.context.isUnderlineActive = false
                    self?.context.isStrikethroughActive = false
                }
                
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
        
        // No bullets or checkboxes - just reset formatting for regular new line
        // Clear typing attributes to reset formatting for new text after Enter
        textView.typingAttributes = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.label
        ]
        
        // Reset text formatting state in context
        DispatchQueue.main.async { [weak self] in
            self?.context.isBoldActive = false
            self?.context.isItalicActive = false
            self?.context.isUnderlineActive = false
            self?.context.isStrikethroughActive = false
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
            if trimmedLine.hasPrefix("◉ ") || trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
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
    
    // MARK: - Individual Checkbox Toggling
    
    /// Toggle a specific checkbox between ○ (unchecked) and ● (checked)
    public func toggleCheckboxAtPosition(_ position: Int) {
        let text = textView.text ?? ""
        guard position < text.count else { return }
        
        let lineRange = (text as NSString).lineRange(for: NSRange(location: position, length: 0))
        let lineText = (text as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
        
        if trimmedLine.hasPrefix("○ ") {
            // Change unchecked to checked
            let checkboxRange = NSRange(location: lineRange.location + (lineText.count - lineText.ltrimmed().count), length: 2)
            let checkedAttachment = createCustomCheckboxAttachment(isChecked: true)
            mutableText.replaceCharacters(in: checkboxRange, with: NSAttributedString(attachment: checkedAttachment))
            textView.attributedText = mutableText
            updateBindingFromTextView()
            updateContextFromTextView()
            print("🔄 RichTextCoordinator: Toggled checkbox to checked")
        } else if trimmedLine.hasPrefix("● ") {
            // Change checked to unchecked
            let checkboxRange = NSRange(location: lineRange.location + (lineText.count - lineText.ltrimmed().count), length: 2)
            let uncheckedAttachment = createCustomCheckboxAttachment(isChecked: false)
            mutableText.replaceCharacters(in: checkboxRange, with: NSAttributedString(attachment: uncheckedAttachment))
            textView.attributedText = mutableText
            updateBindingFromTextView()
            updateContextFromTextView()
            print("🔄 RichTextCoordinator: Toggled checkbox to unchecked")
        }
    }
    
    // MARK: - Custom Checkbox Creation
    
    /// Create a custom checkbox NSTextAttachment with proper styling
    private func createCustomCheckboxAttachment(isChecked: Bool) -> NSTextAttachment {
        let attachment = NSTextAttachment()
        let checkboxImage = generateCheckboxImage(isChecked: isChecked)
        attachment.image = checkboxImage
        
        // Set accessibility label to track checkbox state
        attachment.accessibilityLabel = isChecked ? "checked" : "unchecked"
        
        // Size the checkbox to match text line height with safe bounds
        let fontSize = max(12.0, min(context.fontSize, 24.0)) // Clamp to reasonable range
        let sizeFactor: CGFloat = 0.9
        let checkboxWidth = fontSize * sizeFactor
        let checkboxHeight = fontSize * sizeFactor
        
        // Validate dimensions to prevent NaN errors
        guard checkboxWidth > 0 && checkboxHeight > 0 && 
              checkboxWidth.isFinite && checkboxHeight.isFinite else {
            print("⚠️ RichTextCoordinator: Invalid checkbox dimensions, using defaults")
            attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
            return attachment
        }
        
        let checkboxSize = CGSize(width: checkboxWidth, height: checkboxHeight)
        let yOffset = max(-fontSize * 0.2, -4.0) // Reasonable offset
        
        // Validate offset to prevent NaN
        let safeYOffset = yOffset.isFinite && !yOffset.isNaN ? yOffset : -2.0
        
        attachment.bounds = CGRect(
            origin: CGPoint(x: 0, y: safeYOffset), 
            size: checkboxSize
        )
        
        return attachment
    }
    
    /// Generate a custom checkbox image programmatically
    private func generateCheckboxImage(isChecked: Bool) -> UIImage {
        let size = CGSize(width: 16, height: 16)
        
        // Validate size to prevent NaN errors
        guard size.width > 0 && size.height > 0 && size.width.isFinite && size.height.isFinite else {
            print("⚠️ RichTextCoordinator: Invalid size for checkbox image, using fallback")
            return UIImage() // Return empty image as fallback
        }
        
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            let cgContext = context.cgContext
            let rect = CGRect(origin: .zero, size: size)
            
            // Ensure all coordinates are valid
            let insetValue: CGFloat = 1.0
            let insetRect = rect.insetBy(dx: insetValue, dy: insetValue)
            
            // Validate rect dimensions
            guard insetRect.width > 0 && insetRect.height > 0 else {
                print("⚠️ RichTextCoordinator: Invalid inset rect for checkbox")
                return
            }
            
            // Draw black circle outline
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(1.5)
            cgContext.addEllipse(in: insetRect)
            cgContext.strokePath()
            
            // Draw green checkmark if checked
            if isChecked {
                cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
                cgContext.setLineWidth(2.0)
                cgContext.setLineCap(.round)
                cgContext.setLineJoin(.round)
                
                // Draw checkmark path with validated coordinates
                let checkmarkPath = UIBezierPath()
                let startX: CGFloat = 4.0
                let startY: CGFloat = 8.0
                let midX: CGFloat = 7.0
                let midY: CGFloat = 11.0
                let endX: CGFloat = 12.0
                let endY: CGFloat = 5.0
                
                // Validate all coordinates
                let points = [startX, startY, midX, midY, endX, endY]
                guard points.allSatisfy({ $0.isFinite && !$0.isNaN }) else {
                    print("⚠️ RichTextCoordinator: Invalid checkmark coordinates")
                    return
                }
                
                checkmarkPath.move(to: CGPoint(x: startX, y: startY))
                checkmarkPath.addLine(to: CGPoint(x: midX, y: midY))
                checkmarkPath.addLine(to: CGPoint(x: endX, y: endY))
                
                cgContext.addPath(checkmarkPath.cgPath)
                cgContext.strokePath()
            }
        }
    }
    
    // MARK: - Gesture Handling
    
    @objc func handleTap(_ gesture: UITapGestureRecognizer) {
        let location = gesture.location(in: textView)
        let tapPosition = textView.closestPosition(to: location)
        
        guard let tapPosition = tapPosition else { return }
        let tapIndex = textView.offset(from: textView.beginningOfDocument, to: tapPosition)
        
        // Check if we tapped on a checkbox character or attachment
        guard let attributedText = textView.attributedText else { return }
        guard tapIndex < attributedText.length else { return }
        
        // Check for NSTextAttachment (custom checkbox)
        if let attachment = attributedText.attribute(.attachment, at: tapIndex, effectiveRange: nil) as? NSTextAttachment,
           attachment.image != nil {
            // This is a custom checkbox attachment - toggle it
            toggleCustomCheckboxAtPosition(tapIndex)
            print("🎯 RichTextCoordinator: Toggled custom checkbox attachment at position \(tapIndex)")
            return
        }
        
        // Check for Unicode checkbox characters (fallback for existing checkboxes)
        let text = textView.text ?? ""
        guard tapIndex < text.count else { return }
        
        let lineRange = (text as NSString).lineRange(for: NSRange(location: tapIndex, length: 0))
        let lineText = (text as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Only handle taps on checkbox lines
        if trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
            // Calculate the position of the checkbox character
            let lineStart = lineRange.location
            let leadingWhitespace = lineText.count - lineText.ltrimmed().count
            let checkboxPosition = lineStart + leadingWhitespace
            
            // Check if the tap was on or near the checkbox character (give some tolerance)
            if abs(tapIndex - checkboxPosition) <= 2 {
                toggleCheckboxAtPosition(tapIndex)
                return
            }
        }
        
        // If not a checkbox tap, allow normal text view handling
        // The text view will handle text selection normally
    }
    
    /// Toggle a custom checkbox NSTextAttachment between checked and unchecked states
    private func toggleCustomCheckboxAtPosition(_ position: Int) {
        guard let attributedText = textView.attributedText else { return }
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        guard position < mutableText.length else { return }
        
        // Get the current attachment
        if let currentAttachment = mutableText.attribute(.attachment, at: position, effectiveRange: nil) as? NSTextAttachment {
            // Determine if it's currently checked by trying to decode the image
            // For simplicity, we'll toggle based on a simple heuristic or store state
            let isCurrentlyChecked = isCheckboxAttachmentChecked(currentAttachment)
            let newAttachment = createCustomCheckboxAttachment(isChecked: !isCurrentlyChecked)
            
            // Replace the attachment
            mutableText.replaceCharacters(in: NSRange(location: position, length: 1), with: NSAttributedString(attachment: newAttachment))
            
            textView.attributedText = mutableText
            updateBindingFromTextView()
            updateContextFromTextView()
            
            print("🔄 RichTextCoordinator: Toggled custom checkbox attachment - now \(isCurrentlyChecked ? "unchecked" : "checked")")
        }
    }
    
    /// Determine if a checkbox attachment is currently in checked state
    private func isCheckboxAttachmentChecked(_ attachment: NSTextAttachment) -> Bool {
        // Use the attachment's accessibilityLabel to track state
        if let label = attachment.accessibilityLabel {
            return label == "checked"
        }
        
        // Fallback: analyze the image for green pixels (checkmark detection)
        guard let image = attachment.image else { return false }
        
        // Simple pixel analysis to detect green checkmark
        guard let cgImage = image.cgImage else { return false }
        
        // Check a few key pixels where the checkmark would be
        let width = cgImage.width
        let height = cgImage.height
        
        guard width > 0 && height > 0 else { return false }
        
        // Sample the center area where a checkmark would appear
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        var pixelData = [UInt8](repeating: 0, count: width * height * bytesPerPixel)
        
        guard let context = CGContext(
            data: &pixelData,
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Check for green pixels in the checkmark area
        for y in height/4..<3*height/4 {
            for x in width/4..<3*width/4 {
                let pixelIndex = ((width * y) + x) * bytesPerPixel
                let red = pixelData[pixelIndex]
                let green = pixelData[pixelIndex + 1]
                let blue = pixelData[pixelIndex + 2]
                let alpha = pixelData[pixelIndex + 3]
                
                // Check for green-ish pixels (checkmark color)
                if alpha > 128 && green > red && green > blue && green > 128 {
                    return true
                }
            }
        }
        
        return false
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow our tap gesture to work alongside UITextView's built-in gestures
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