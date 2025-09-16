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
        
        // Update typing attributes based on context state
        updateTypingAttributes()
        
        // Add tap gesture for checkbox interaction
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        textView.addGestureRecognizer(tapGesture)
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
        
        // Update binding to sync the attributed text with the formatted content
        updateBindingFromTextView()
        
        // Update context state to reflect the new formatting state
        updateContextFromTextView()
        
        // For text selection, we no longer need to prevent context updates
        // The formatting should persist in the text itself
        print("🎯 RichTextCoordinator: Applied formatting to selection - text should persist")
        
        // Update typing attributes for future typing
        updateTypingAttributes()
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
            let isBoldInTypingAttributes = currentFont.fontDescriptor.symbolicTraits.contains(.traitBold) || 
                                         currentFont.fontName.contains("Bold")
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
                    if shouldAddBold {
                        // Add bold - use specific SpaceGrotesk-Bold font
                        if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: font.pointSize) {
                            newFont = boldFont
                            print("✅ Applied SpaceGrotesk-Bold font at size \(font.pointSize)")
                        } else {
                            // Fallback to system bold font if custom font not available
                            newFont = UIFont.boldSystemFont(ofSize: font.pointSize)
                            print("⚠️ SpaceGrotesk-Bold not available, using system bold font")
                        }
                    } else {
                        // Remove bold - revert to regular SpaceGrotesk font
                        if let regularFont = UIFont(name: "SpaceGrotesk-Regular", size: font.pointSize) {
                            newFont = regularFont
                            print("✅ Applied SpaceGrotesk-Regular font at size \(font.pointSize)")
                        } else {
                            // Fallback to system regular font
                            newFont = UIFont.systemFont(ofSize: font.pointSize)
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
                            newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                        } else {
                            newFont = UIFont.italicSystemFont(ofSize: font.pointSize)
                        }
                    } else {
                        // Remove italic
                        let traits = font.fontDescriptor.symbolicTraits.subtracting(.traitItalic)
                        if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                            newFont = UIFont(descriptor: descriptor, size: font.pointSize)
                        } else {
                            newFont = UIFont(name: context.fontName, size: font.pointSize) ?? font
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
        // Remove all checkboxes but preserve spaces after content
        var withoutCheckboxes = line.replacingOccurrences(of: "○ ", with: "")
                                   .replacingOccurrences(of: "● ", with: "")
        
        // Only trim leading whitespace, preserve trailing and internal spaces
        while withoutCheckboxes.hasPrefix(" ") {
            withoutCheckboxes = String(withoutCheckboxes.dropFirst())
        }
        
        // Add single checkbox at start (preserve checked state if any were checked)
        let hadCheckedBox = line.contains("● ")
        return (hadCheckedBox ? "● " : "○ ") + withoutCheckboxes
    }
    
    private func applyCheckboxFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        // Don't process lines that are only whitespace/newlines
        if trimmedLine.isEmpty {
            // Add custom checkbox attachment to empty line
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let attachmentString = NSAttributedString(attachment: checkboxAttachment)
            let spaceString = NSAttributedString(string: " ")
            let checkboxWithSpace = NSMutableAttributedString()
            checkboxWithSpace.append(attachmentString)
            checkboxWithSpace.append(spaceString)
            
            if lineText.hasSuffix("\n") {
                checkboxWithSpace.append(NSAttributedString(string: "\n"))
            }
            
            mutableText.replaceCharacters(in: lineRange, with: checkboxWithSpace)
            
            textView.attributedText = mutableText
            let newCursorPosition = lineRange.location + 2 // Position after checkbox + space
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
            // Line starts with checkbox (but no space) - remove it completely but preserve trailing spaces
            var withoutCheckbox = String(trimmedLine.dropFirst(1))
            // Only trim leading whitespace, preserve trailing spaces
            while withoutCheckbox.hasPrefix(" ") {
                withoutCheckbox = String(withoutCheckbox.dropFirst())
            }
            mutableLineText = withoutCheckbox
            newCursorPosition = lineRange.location + mutableLineText.count
            print("🔸 RichTextCoordinator: Removing checkbox (no space) from line")
        } else if trimmedLine.hasPrefix("• ") {
            // Replace bullet with custom checkbox
            let contentAfterBullet = String(trimmedLine.dropFirst(2))
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let attachmentString = NSAttributedString(attachment: checkboxAttachment)
            let spaceString = NSAttributedString(string: " ")
            let contentString = NSAttributedString(string: contentAfterBullet)
            
            let checkboxWithContent = NSMutableAttributedString()
            checkboxWithContent.append(attachmentString)
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
            
            print("🔸 RichTextCoordinator: Replaced bullet with custom checkbox")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        } else if !trimmedLine.contains("○") && !trimmedLine.contains("●") {
            // Add custom checkbox attachment with space
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let attachmentString = NSAttributedString(attachment: checkboxAttachment)
            let spaceString = NSAttributedString(string: " ")
            let contentString = NSAttributedString(string: trimmedLine)
            
            let checkboxWithContent = NSMutableAttributedString()
            checkboxWithContent.append(attachmentString)
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
            
            print("🔸 RichTextCoordinator: Added custom checkbox to line")
            updateBindingFromTextView()
            updateContextFromTextView()
            return
        } else {
            // Line already contains checkboxes somewhere - don't add another
            print("🚫 RichTextCoordinator: Line already contains checkboxes - not adding another")
            return
        }
        
        // Legacy fallback for Unicode checkbox removal (for existing checkboxes)
        // This handles removal of existing Unicode checkboxes while maintaining the spacing fix
        let newLine = mutableLineText + (lineText.hasSuffix("\n") ? "\n" : "")
        mutableText.replaceCharacters(in: lineRange, with: newLine)
        
        // Update text view with correct cursor position  
        textView.attributedText = mutableText
        
        // Ensure cursor position is valid for the new text length
        let safePosition = min(newCursorPosition, mutableText.length)
        textView.selectedRange = NSRange(location: safePosition, length: 0)
        
        updateBindingFromTextView()
        updateContextFromTextView()
        
        print("🎯 RichTextCoordinator: Legacy checkbox format applied - cursor at position \(safePosition)")
    }
    
    private func applyCodeBlockFormat(_ mutableText: NSMutableAttributedString, _ lineRange: NSRange, _ lineText: String) {
        // Check if cursor is currently in a code block using the same reliable detection method
        let cursorPosition = textView.selectedRange.location
        let isInCodeBlock = checkIfPositionIsInCodeBlock(cursorPosition)
        
        print("🔍 applyCodeBlockFormat: cursor at \(cursorPosition), isInCodeBlock: \(isInCodeBlock), context.isCodeBlockActive: \(context.isCodeBlockActive)")
        
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
                print("✅ applyCodeBlockFormat: Immediately set context.isCodeBlockActive = true")
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
        
        // Remove code block formatting and replace with normal text formatting
        if codeBlockRange.length > 0 {
            // Get the plain text content
            let codeBlockText = mutableText.attributedSubstring(from: codeBlockRange).string
            
            // Create new attributed string with normal formatting
            let normalFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
            let normalAttributes: [NSAttributedString.Key: Any] = [
                .font: normalFont,
                .foregroundColor: UIColor.label,
                .backgroundColor: UIColor.clear,
                .paragraphStyle: NSParagraphStyle.default // Clear any paragraph formatting
            ]
            
            let normalText = NSAttributedString(string: codeBlockText, attributes: normalAttributes)
            mutableText.replaceCharacters(in: codeBlockRange, with: normalText)
            
            print("✅ exitCodeBlockAndMoveCursor: Removed code block formatting from range \(codeBlockRange)")
        }
        
        // Position cursor at the end of the now-normal text
        let newCursorPosition = codeBlockStart + codeBlockRange.length
        
        // Add a newline with normal formatting after the text to ensure clean transition
        let newlineString = NSAttributedString(string: "\n", attributes: [
            .font: UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize),
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: NSParagraphStyle.default
        ])
        mutableText.insert(newlineString, at: newCursorPosition)
        
        // Position cursor after the newline
        let finalCursorPosition = newCursorPosition + 1
        textView.selectedRange = NSRange(location: finalCursorPosition, length: 0)
        
        // Force update of typing attributes to normal before updating context
        let normalTypingAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize),
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: NSParagraphStyle.default
        ]
        textView.typingAttributes = normalTypingAttributes
        
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
    
    /// Exit code block on Enter key while preserving existing code block formatting
    private func exitCodeBlockOnEnterKey(at position: Int, in mutableText: NSMutableAttributedString) {
        // Create a completely clean paragraph style with no indentation
        let normalParagraphStyle = NSMutableParagraphStyle()
        normalParagraphStyle.lineSpacing = 0
        normalParagraphStyle.paragraphSpacing = 0
        normalParagraphStyle.firstLineHeadIndent = 0
        normalParagraphStyle.headIndent = 0
        normalParagraphStyle.tailIndent = 0
        
        // Insert a newline with normal formatting at the current position
        let normalFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: normalFont,
            .foregroundColor: UIColor.label,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: normalParagraphStyle
        ]
        
        let newlineString = NSAttributedString(string: "\n", attributes: normalAttributes)
        mutableText.insert(newlineString, at: position)
        
        // Position cursor after the newline
        let newCursorPosition = position + 1
        textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
        
        // Force update typing attributes to normal formatting for future typing
        textView.typingAttributes = normalAttributes
        
        // Update context to indicate code mode is now off for future typing
        DispatchQueue.main.async {
            self.context.isCodeBlockActive = false
        }
        
        print("✅ exitCodeBlockOnEnterKey: Added newline at position \(position), cursor moved to \(newCursorPosition), code mode disabled for future typing")
    }
    
    /// Exit code block formatting at current cursor position without moving cursor (for button toggle)
    private func exitCodeBlockInPlace(at position: Int) {
        // Create normal formatting attributes for future typing
        let normalFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
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
        let normalFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
        
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
        if !textBinding.wrappedValue.isEqual(to: textView.attributedText) {
            print("💾 RichTextCoordinator: Updating binding with formatted text (length: \(textView.attributedText.length))")
            textBinding.wrappedValue = textView.attributedText
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
        if isActuallyInCodeBlock {
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
                let hasBoldName = font.fontName.contains("Bold") || font.fontName.contains("SemiBold") || font.fontName.contains("Heavy")
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
            self.context.isCheckboxActive = trimmedLine.hasPrefix("○") || trimmedLine.hasPrefix("●")
            
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
            let baseFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
            
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
    
    private func applyBoldToFont(_ font: UIFont) -> UIFont {
        // Use specific SpaceGrotesk-Bold font for bold formatting
        if let boldFont = UIFont(name: "SpaceGrotesk-Bold", size: font.pointSize) {
            print("✅ applyBoldToFont: Using SpaceGrotesk-Bold at size \(font.pointSize)")
            return boldFont
        } else {
            // Fallback to system bold font
            let boldSystemFont = UIFont.boldSystemFont(ofSize: font.pointSize)
            print("⚠️ applyBoldToFont: SpaceGrotesk-Bold not available, using system bold font: \(boldSystemFont.fontName)")
            return boldSystemFont
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
        
        print("📍 textViewDidChangeSelection: Selection changed to \(textView.selectedRange)")
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
            
            // Replace the '[]' with custom checkbox
            let replacementRange = NSRange(location: range.location - 2, length: 2)
            
            let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
            let attachmentString = NSAttributedString(attachment: checkboxAttachment)
            let spaceString = NSAttributedString(string: " ")
            
            let checkboxWithSpace = NSMutableAttributedString()
            checkboxWithSpace.append(attachmentString)
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
        if hasCheckboxAtStart || trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
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
                
                // Create new checkbox with newline prefix
                let newlineString = NSAttributedString(string: "\n")
                let checkboxAttachment = createCustomCheckboxAttachment(isChecked: false)
                let attachmentString = NSAttributedString(attachment: checkboxAttachment)
                let spaceString = NSAttributedString(string: " ")
                
                let newCheckboxLine = NSMutableAttributedString()
                newCheckboxLine.append(newlineString)
                newCheckboxLine.append(attachmentString)
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
            
            // Check for custom checkbox attachment first
            if markerPosition < mutableText.length,
               let attachment = mutableText.attribute(.attachment, at: markerPosition, effectiveRange: nil) as? NSTextAttachment,
               attachment.image != nil {
                // Remove custom checkbox attachment + space
                let lengthToRemove = min(2, mutableText.length - markerPosition)
                guard lengthToRemove > 0 else { return true }
                
                let markerRange = NSRange(location: markerPosition, length: lengthToRemove)
                mutableText.replaceCharacters(in: markerRange, with: "")
                textView.attributedText = mutableText
                
                // Position cursor where the marker was
                textView.selectedRange = NSRange(location: markerPosition, length: 0)
                
                updateBindingFromTextView()
                updateContextFromTextView()
                
                print("🔄 RichTextCoordinator: Removed checkbox with backspace")
                return false
            }
            // Check for Unicode checkboxes and bullets
            else if trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● ") {
                // Remove the list marker + space
                let lengthToRemove = min(2, mutableText.length - markerPosition)
                guard lengthToRemove > 0 else { return true }
                
                let markerRange = NSRange(location: markerPosition, length: lengthToRemove)
                mutableText.replaceCharacters(in: markerRange, with: "")
                textView.attributedText = mutableText
                
                // Position cursor where the marker was
                textView.selectedRange = NSRange(location: markerPosition, length: 0)
                
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
                           (trimmedLine.hasPrefix("• ") || trimmedLine.hasPrefix("○ ") || trimmedLine.hasPrefix("● "))
        
        // Also check for custom checkbox attachment
        let hasCustomCheckbox = markerPosition < textView.attributedText.length && 
                               textView.attributedText.attribute(.attachment, at: markerPosition, effectiveRange: nil) is NSTextAttachment
        
        // If we're right after a marker and this line only has the marker + one character, remove the whole line
        if (isAfterMarker || (hasCustomCheckbox && range.location > markerPosition + 1)) {
            let contentAfterMarker = trimmedLine.dropFirst(2) // Remove "• " or similar
            let trimmedContent = contentAfterMarker.trimmingCharacters(in: .whitespaces)
            
            // If there's only one character after the marker, remove the entire marker when backspacing
            if trimmedContent.count == 1 {
                let mutableText = NSMutableAttributedString(attributedString: textView.attributedText)
                
                // Remove the entire marker and its content
                if hasCustomCheckbox {
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
    
    /// Toggle a specific checkbox between unchecked and checked (handles both custom attachments and Unicode)
    public func toggleCheckboxAtPosition(_ position: Int) {
        guard let attributedText = textView.attributedText else { return }
        let text = attributedText.string
        guard position < text.count else { return }
        
        let lineRange = (text as NSString).lineRange(for: NSRange(location: position, length: 0))
        let lineText = (text as NSString).substring(with: lineRange)
        let trimmedLine = lineText.trimmingCharacters(in: .whitespaces)
        
        let mutableText = NSMutableAttributedString(attributedString: attributedText)
        let checkboxStartPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count)
        
        // First, check for custom checkbox attachment at the start of the line
        if checkboxStartPosition < mutableText.length {
            if let attachment = mutableText.attribute(.attachment, at: checkboxStartPosition, effectiveRange: nil) as? NSTextAttachment,
               attachment.image != nil {
                // This is a custom checkbox attachment - toggle it
                let isCurrentlyChecked = isCheckboxAttachmentChecked(attachment)
                let newAttachment = createCustomCheckboxAttachment(isChecked: !isCurrentlyChecked)
                
                // Replace the attachment while preserving the space (validate bounds first)
                guard checkboxStartPosition < mutableText.length else { return }
                mutableText.replaceCharacters(in: NSRange(location: checkboxStartPosition, length: 1), 
                                            with: NSAttributedString(attachment: newAttachment))
                
                // Store the current selection to restore after update
                let currentSelection = textView.selectedRange
                
                // Update the text view with the new content
                textView.attributedText = mutableText
                
                // Force comprehensive visual refresh without clearing the content
                DispatchQueue.main.async {
                    // Restore selection first
                    if currentSelection.location <= mutableText.length {
                        self.textView.selectedRange = currentSelection
                    }
                    
                    // Multiple refresh strategies to force visual update
                    self.textView.layoutManager.invalidateLayout(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1), actualCharacterRange: nil)
                    self.textView.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1))
                    self.textView.setNeedsDisplay()
                    self.textView.setNeedsLayout()
                    self.textView.layoutIfNeeded()
                    
                    // Force text container to recalculate
                    let textRange = NSRange(location: 0, length: self.textView.attributedText.length)
                    self.textView.layoutManager.invalidateLayout(forCharacterRange: textRange, actualCharacterRange: nil)
                    self.textView.layoutManager.ensureLayout(for: self.textView.textContainer)
                }
                
                updateBindingFromTextView()
                updateContextFromTextView()
                
                // Track analytics
                AnalyticsManager.shared.trackCheckboxClicked(isChecked: !isCurrentlyChecked, checkboxType: "attachment")
                
                print("🔄 RichTextCoordinator: Toggled custom checkbox to \(isCurrentlyChecked ? "unchecked" : "checked")")
                return
            }
        }
        
        // Fallback: Handle legacy Unicode checkboxes
        if trimmedLine.hasPrefix("○ ") {
            // Change unchecked to checked - replace just the checkbox character, preserve the space
            guard checkboxStartPosition < mutableText.length else { return }
            let checkboxCharRange = NSRange(location: checkboxStartPosition, length: 1)
            mutableText.replaceCharacters(in: checkboxCharRange, with: "●")
            
            // Store the current selection to restore after update
            let currentSelection = textView.selectedRange
            
            // Update the text view with the new content
            textView.attributedText = mutableText
            
            // Force comprehensive visual refresh
            DispatchQueue.main.async {
                // Restore selection first
                if currentSelection.location <= mutableText.length {
                    self.textView.selectedRange = currentSelection
                }
                
                // Multiple refresh strategies to force visual update
                self.textView.layoutManager.invalidateLayout(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1), actualCharacterRange: nil)
                self.textView.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1))
                self.textView.setNeedsDisplay()
                self.textView.setNeedsLayout()
                self.textView.layoutIfNeeded()
                
                // Force text container to recalculate
                let textRange = NSRange(location: 0, length: self.textView.attributedText.length)
                self.textView.layoutManager.invalidateLayout(forCharacterRange: textRange, actualCharacterRange: nil)
                self.textView.layoutManager.ensureLayout(for: self.textView.textContainer)
            }
            
            updateBindingFromTextView()
            updateContextFromTextView()
            
            // Track analytics
            AnalyticsManager.shared.trackCheckboxClicked(isChecked: true, checkboxType: "unicode")
            
            print("🔄 RichTextCoordinator: Toggled Unicode checkbox to checked")
        } else if trimmedLine.hasPrefix("● ") {
            // Change checked to unchecked - replace just the checkbox character, preserve the space
            guard checkboxStartPosition < mutableText.length else { return }
            let checkboxCharRange = NSRange(location: checkboxStartPosition, length: 1)
            mutableText.replaceCharacters(in: checkboxCharRange, with: "○")
            
            // Store the current selection to restore after update
            let currentSelection = textView.selectedRange
            
            // Update the text view with the new content
            textView.attributedText = mutableText
            
            // Force comprehensive visual refresh
            DispatchQueue.main.async {
                // Restore selection first
                if currentSelection.location <= mutableText.length {
                    self.textView.selectedRange = currentSelection
                }
                
                // Multiple refresh strategies to force visual update
                self.textView.layoutManager.invalidateLayout(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1), actualCharacterRange: nil)
                self.textView.layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: checkboxStartPosition, length: 1))
                self.textView.setNeedsDisplay()
                self.textView.setNeedsLayout()
                self.textView.layoutIfNeeded()
                
                // Force text container to recalculate
                let textRange = NSRange(location: 0, length: self.textView.attributedText.length)
                self.textView.layoutManager.invalidateLayout(forCharacterRange: textRange, actualCharacterRange: nil)
                self.textView.layoutManager.ensureLayout(for: self.textView.textContainer)
            }
            
            updateBindingFromTextView()
            updateContextFromTextView()
            
            // Track analytics
            AnalyticsManager.shared.trackCheckboxClicked(isChecked: false, checkboxType: "unicode")
            
            print("🔄 RichTextCoordinator: Toggled Unicode checkbox to unchecked")
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
        
        // Use a larger size for better tap interaction (Apple Notes style)
        let checkboxSize: CGFloat = 20 // Larger size for easier tapping
        
        // Adjust baseline alignment for larger checkbox
        // Negative Y value moves the checkbox down to align with text baseline
        let yOffset: CGFloat = -3 // Adjusted offset for larger checkbox
        
        attachment.bounds = CGRect(
            origin: CGPoint(x: 0, y: yOffset), 
            size: CGSize(width: checkboxSize, height: checkboxSize)
        )
        
        return attachment
    }
    
    /// Generate Apple Notes-style checkbox using SF Symbols (no custom drawing)
    private func generateCheckboxImage(isChecked: Bool) -> UIImage {
        // Use SF Symbols like Apple Notes actually does - clean and simple
        let symbolName = isChecked ? "checkmark.circle.fill" : "circle"
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        
        // Try to create the SF Symbol image with proper tinting
        if let symbolImage = UIImage(systemName: symbolName, withConfiguration: config) {
            // For checked state, render in black. For unchecked, render in gray
            let color = isChecked ? UIColor.label : UIColor.systemGray2
            
            // Use withTintColor for clean, simple rendering (no custom graphics context)
            let tintedImage = symbolImage.withTintColor(color, renderingMode: .alwaysOriginal)
            return tintedImage
        } else {
            // Fallback to simple colored square if SF Symbol fails
            return createFallbackCheckboxImage(isChecked: isChecked)
        }
    }
    
    /// Create a simple fallback checkbox image when regular generation fails
    private func createFallbackCheckboxImage(isChecked: Bool) -> UIImage {
        // Use system-provided images as absolute fallback to avoid any CoreGraphics issues
        if isChecked {
            // Use a simple system checkmark image
            if let systemImage = UIImage(systemName: "checkmark.square.fill") {
                return systemImage.withTintColor(.label, renderingMode: .alwaysOriginal)
            }
            // Ultra-simple fallback - just a black square
            return UIImage(systemName: "square.fill")?.withTintColor(.label, renderingMode: .alwaysOriginal) ?? UIImage()
        } else {
            // Use a simple system square image
            if let systemImage = UIImage(systemName: "square") {
                return systemImage.withTintColor(.systemGray2, renderingMode: .alwaysOriginal)
            }
            // Ultra-simple fallback
            return UIImage(systemName: "square")?.withTintColor(.systemGray2, renderingMode: .alwaysOriginal) ?? UIImage()
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
        
        // Check for NSTextAttachment (custom checkbox) with expanded tap area
        // Check a range around the tap position to make checkboxes easier to tap
        let checkRange = max(0, tapIndex - 2)...min(attributedText.length - 1, tapIndex + 2)
        
        for checkIndex in checkRange {
            if let attachment = attributedText.attribute(.attachment, at: checkIndex, effectiveRange: nil) as? NSTextAttachment,
               attachment.image != nil {
                // This is a custom checkbox attachment - toggle it using the unified method
                toggleCheckboxAtPosition(checkIndex)
                print("🎯 RichTextCoordinator: Toggled custom checkbox attachment at position \(checkIndex) (tapped at \(tapIndex))")
                return
            }
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
            
            // Much larger tap area for easier interaction
            // Allow tapping on the checkbox itself, the space after it, and a bit beyond
            let tapTolerance = 8 // Much larger tap area
            if abs(tapIndex - checkboxPosition) <= tapTolerance {
                toggleCheckboxAtPosition(checkboxPosition) // Use checkbox position, not tap position
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
        // Use the attachment's accessibilityLabel to track state - this is the primary method
        if let label = attachment.accessibilityLabel {
            return label == "checked"
        }
        
        // Simple fallback without pixel analysis to avoid CoreGraphics NaN errors
        // If no accessibility label is set, assume unchecked state
        // This avoids complex pixel analysis that can cause CoreGraphics issues
        print("⚠️ isCheckboxAttachmentChecked: No accessibility label found, assuming unchecked")
        return false
    }
    
    // MARK: - Helper Methods
    
    /// Check if a line starts with a custom checkbox attachment
    private func checkForCheckboxAtLineStart(mutableText: NSMutableAttributedString, lineRange: NSRange, lineText: String) -> Bool {
        let checkboxStartPosition = lineRange.location + (lineText.count - lineText.ltrimmed().count)
        
        if checkboxStartPosition < mutableText.length {
            if let attachment = mutableText.attribute(.attachment, at: checkboxStartPosition, effectiveRange: nil) as? NSTextAttachment,
               attachment.image != nil {
                // This looks like a checkbox attachment
                return true
            }
        }
        return false
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow our tap gesture to work alongside UITextView's built-in gestures
        return true
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