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
            // For cursor position, just update typing attributes
            // No need to modify existing text
        }
        
        // Update typing attributes immediately for cursor positions
        // Context state is already updated for snappy UI response
        self.updateTypingAttributes()
        print("🎨 Bold toggle complete - typing attributes refreshed")
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
        }
        
        // Update typing attributes immediately
        // Context state is already updated for snappy UI response
        self.updateTypingAttributes()
        print("🎨 Italic toggle complete - typing attributes refreshed")
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
        }
        
        // Update typing attributes immediately
        // Context state is already updated for snappy UI response
        self.updateTypingAttributes()
        print("🎨 Underline toggle complete - typing attributes refreshed")
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
        }
        
        // Update typing attributes immediately
        // Context state is already updated for snappy UI response
        self.updateTypingAttributes()
        print("🎨 Strikethrough toggle complete - typing attributes refreshed")
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
        print("🔍 RichTextCoordinator: Processing line: '\(trimmedLine)'")
        
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
        // Check if cursor is currently in a code block
        let cursorPosition = textView.selectedRange.location
        let isInCodeBlock = isPositionInCodeBlock(cursorPosition, in: mutableText)
        
        if isInCodeBlock {
            // Turn OFF code formatting - move cursor to line below the code block
            removeCodeBlockAndMoveCursor(at: cursorPosition, in: mutableText)
            print("🔸 RichTextCoordinator: Removing code block, moving cursor below")
        } else {
            // Turn ON code formatting - create new code block with cursor inside
            createCodeBlockAndMoveCursor(at: cursorPosition, in: mutableText)
            print("🔸 RichTextCoordinator: Creating new code block with cursor inside")
        }
        
        // Update the text view with the modified content
        textView.attributedText = mutableText
        
        updateBindingFromTextView()
        updateContextFromTextView()
        
        print("🎯 RichTextCoordinator: Code block format applied")
    }
    
    // MARK: - Code Block Helper Methods
    
    /// Check if the given position is within a code block
    private func isPositionInCodeBlock(_ position: Int, in attributedText: NSMutableAttributedString) -> Bool {
        guard position >= 0 && position < attributedText.length else { return false }
        
        let attributes = attributedText.attributes(at: position, effectiveRange: nil)
        
        // Check if position has Monaco font (indicates code block)
        if let font = attributes[.font] as? UIFont {
            return font.fontName.contains("Monaco")
        }
        
        // Also check for grey background color (indicates code block)
        if let backgroundColor = attributes[.backgroundColor] as? UIColor {
            return backgroundColor == UIColor.systemGray6
        }
        
        return false
    }
    
    /// Create a new code block and position cursor inside it
    private func createCodeBlockAndMoveCursor(at position: Int, in mutableText: NSMutableAttributedString) {
        // Create code block text with space for cursor
        let codeBlockText = "\n \n"
        
        // Insert the code block at current position
        let insertRange = NSRange(location: position, length: 0)
        mutableText.replaceCharacters(in: insertRange, with: codeBlockText)
        
        // Apply Monaco font and grey background to the entire code block
        let codeBlockRange = NSRange(location: position, length: codeBlockText.count)
        
        // Set Monaco font
        if let monacoFont = UIFont(name: "Monaco", size: 14) {
            mutableText.addAttribute(.font, value: monacoFont, range: codeBlockRange)
        } else {
            // Fallback to monospaced system font
            let monospacedFont = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
            mutableText.addAttribute(.font, value: monospacedFont, range: codeBlockRange)
        }
        
        // Set grey background
        mutableText.addAttribute(.backgroundColor, value: UIColor.systemGray6, range: codeBlockRange)
        
        // Set text color to ensure readability
        mutableText.addAttribute(.foregroundColor, value: UIColor.label, range: codeBlockRange)
        
        // Position cursor inside the code block (after the first newline, at the space)
        let cursorPosition = position + 1
        textView.selectedRange = NSRange(location: cursorPosition, length: 0)
        
        print("📦 Created code block at position \(position), cursor at \(cursorPosition)")
    }
    
    /// Remove code block formatting and move cursor to line below
    private func removeCodeBlockAndMoveCursor(at position: Int, in mutableText: NSMutableAttributedString) {
        // Find the range of the current code block
        var codeBlockStart = position
        var codeBlockEnd = position
        
        // Find start of code block (look backwards for first non-Monaco character)
        while codeBlockStart > 0 {
            let prevAttributes = mutableText.attributes(at: codeBlockStart - 1, effectiveRange: nil)
            if let font = prevAttributes[.font] as? UIFont, font.fontName.contains("Monaco") {
                codeBlockStart -= 1
            } else {
                break
            }
        }
        
        // Find end of code block (look forwards for first non-Monaco character)
        while codeBlockEnd < mutableText.length {
            let attributes = mutableText.attributes(at: codeBlockEnd, effectiveRange: nil)
            if let font = attributes[.font] as? UIFont, font.fontName.contains("Monaco") {
                codeBlockEnd += 1
            } else {
                break
            }
        }
        
        let codeBlockRange = NSRange(location: codeBlockStart, length: codeBlockEnd - codeBlockStart)
        
        // Get the text content without formatting
        let codeBlockText = mutableText.attributedSubstring(from: codeBlockRange).string
        let cleanedText = codeBlockText.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Replace code block with clean text
        let replacementText = cleanedText.isEmpty ? "" : cleanedText + "\n"
        mutableText.replaceCharacters(in: codeBlockRange, with: replacementText)
        
        // Apply normal formatting to the replacement text
        let replacementRange = NSRange(location: codeBlockStart, length: replacementText.count)
        if replacementRange.length > 0 {
            // Remove code block formatting
            mutableText.removeAttribute(.backgroundColor, range: replacementRange)
            
            // Apply normal font
            let normalFont = UIFont(name: context.fontName, size: context.fontSize) ?? UIFont.systemFont(ofSize: context.fontSize)
            mutableText.addAttribute(.font, value: normalFont, range: replacementRange)
        }
        
        // Position cursor at the end of the replacement text (on new line below)
        let newCursorPosition = codeBlockStart + replacementText.count
        textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
        
        print("🗑️ Removed code block, cursor moved to position \(newCursorPosition)")
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
            print("🏁 RichTextCoordinator: Reset isUpdatingFromTextView flag after binding update")
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
        
        // Update formatting state
        context.updateFormattingState()
        
        // Only reset the flag if we set it (not if binding update set it)
        if !wasAlreadyUpdating {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isUpdatingFromTextView = false
                print("🏁 RichTextCoordinator: Reset isUpdatingFromTextView flag after context update")
            }
        }
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
        
        // Handle automatic bullet/checkbox conversion
        if text == " " {
            return handleAutomaticFormatting(textView, range)
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
                
                textView.attributedText = mutableText
                updateBindingFromTextView()
                updateContextFromTextView()
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
            textView.attributedText = mutableText
            updateBindingFromTextView()
            updateContextFromTextView()
            print("🔄 RichTextCoordinator: Toggled Unicode checkbox to checked")
        } else if trimmedLine.hasPrefix("● ") {
            // Change checked to unchecked - replace just the checkbox character, preserve the space
            guard checkboxStartPosition < mutableText.length else { return }
            let checkboxCharRange = NSRange(location: checkboxStartPosition, length: 1)
            mutableText.replaceCharacters(in: checkboxCharRange, with: "○")
            textView.attributedText = mutableText
            updateBindingFromTextView()
            updateContextFromTextView()
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
        
        // Use a fixed, smaller size that aligns better with text
        let checkboxSize: CGFloat = 14 // Fixed size that works well with most text sizes
        
        // Simple baseline alignment - position checkbox to align with text baseline
        // Negative Y value moves the checkbox down to align with text
        let yOffset: CGFloat = -2 // Slight downward offset to align with text baseline
        
        attachment.bounds = CGRect(
            origin: CGPoint(x: 0, y: yOffset), 
            size: CGSize(width: checkboxSize, height: checkboxSize)
        )
        
        return attachment
    }
    
    /// Generate a custom checkbox image programmatically
    private func generateCheckboxImage(isChecked: Bool) -> UIImage {
        let size = CGSize(width: 14, height: 14) // Smaller size to match text better
        
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
            let insetValue: CGFloat = 1.5
            let insetRect = rect.insetBy(dx: insetValue, dy: insetValue)
            
            // Validate rect dimensions
            guard insetRect.width > 0 && insetRect.height > 0 else {
                print("⚠️ RichTextCoordinator: Invalid inset rect for checkbox")
                return
            }
            
            // Draw circle outline with better styling
            cgContext.setStrokeColor(UIColor.systemGray.cgColor)
            cgContext.setLineWidth(1.8)
            cgContext.addEllipse(in: insetRect)
            cgContext.strokePath()
            
            // Fill background if checked
            if isChecked {
                cgContext.setFillColor(UIColor.systemGreen.withAlphaComponent(0.15).cgColor)
                cgContext.addEllipse(in: insetRect)
                cgContext.fillPath()
            }
            
            // Draw green checkmark if checked
            if isChecked {
                cgContext.setStrokeColor(UIColor.systemGreen.cgColor)
                cgContext.setLineWidth(1.8) // Thinner line for smaller checkbox
                cgContext.setLineCap(.round)
                cgContext.setLineJoin(.round)
                
                // Draw checkmark path with coordinates adjusted for 14x14 size
                let checkmarkPath = UIBezierPath()
                let startX: CGFloat = 3.5
                let startY: CGFloat = 7.0
                let midX: CGFloat = 6.0
                let midY: CGFloat = 9.5
                let endX: CGFloat = 10.5
                let endY: CGFloat = 4.5
                
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
            // This is a custom checkbox attachment - toggle it using the unified method
            toggleCheckboxAtPosition(tapIndex)
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