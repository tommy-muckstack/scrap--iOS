//
//  RichTextEditor.swift
//  Scrap
//
//  Adapted from RichTextKit by Daniel Saidi
//  Simplified and optimized for Scrap's mobile experience
//

import SwiftUI
import UIKit
import Combine

/**
 A SwiftUI wrapper for UITextView with rich text editing capabilities.
 
 This provides a clean interface between SwiftUI and UIKit, handling
 all the complex text synchronization through the RichTextCoordinator.
 
 Usage:
 ```swift
 @State private var text = NSAttributedString()
 @StateObject private var context = RichTextContext()
 
 var body: some View {
     RichTextEditor(text: $text, context: context)
 }
 ```
 */
public struct RichTextEditor: UIViewRepresentable {
    
    // MARK: - Properties
    
    @Binding private var text: NSAttributedString
    @ObservedObject private var context: RichTextContext
    private let configuration: (UITextView) -> Void
    
    // MARK: - Initialization
    
    public init(
        text: Binding<NSAttributedString>,
        context: RichTextContext,
        configuration: @escaping (UITextView) -> Void = { _ in }
    ) {
        self._text = text
        self.context = context
        self.configuration = configuration
    }
    
    // MARK: - UIViewRepresentable
    
    public func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        
        // Basic configuration
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        
        // Enable standard iOS text interactions
        textView.isUserInteractionEnabled = true
        textView.isMultipleTouchEnabled = true
        textView.isExclusiveTouch = false
        
        // Configure selection and editing behaviors
        textView.clearsOnInsertion = false
        
        // Enable copy/paste menu
        textView.canCancelContentTouches = true
        textView.delaysContentTouches = true
        
        // Font and appearance
        textView.font = UIFont(name: self.context.fontName, size: self.context.fontSize) ?? 
                        UIFont.systemFont(ofSize: self.context.fontSize)
        
        // Rich text attributes
        textView.typingAttributes = [
            .font: textView.font ?? UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.label
        ]
        
        // Set initial content
        textView.attributedText = text
        
        // Connect the coordinator to this textView
        let coordinator = context.coordinator
        coordinator.connectTextView(textView)
        
        // Add tap gesture for checkbox toggling with minimal interference
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(RichTextCoordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.cancelsTouchesInView = false      // Don't block other touches
        tapGesture.delaysTouchesEnded = false        // Don't delay text selection
        tapGesture.delaysTouchesBegan = false        // Don't delay touch start
        tapGesture.requiresExclusiveTouchType = false // Allow multiple touch types
        textView.addGestureRecognizer(tapGesture)
        
        // Apply custom configuration
        configuration(textView)
        
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update text if it's actually different to avoid cursor jumps
        if !uiView.attributedText.isEqual(to: text) {
            let selectedRange = uiView.selectedRange
            uiView.attributedText = text
            
            // Restore cursor position safely
            let newLocation = min(selectedRange.location, text.length)
            let safeRange = NSRange(location: newLocation, length: selectedRange.length)
            if safeRange.location + safeRange.length <= text.length {
                uiView.selectedRange = safeRange
            }
        }
        
        // Update editable state only if needed
        if uiView.isEditable != self.context.isEditable {
            uiView.isEditable = self.context.isEditable
        }
        
        // Handle focus state carefully
        if self.context.isEditingText && !uiView.isFirstResponder {
            DispatchQueue.main.async {
                uiView.becomeFirstResponder()
            }
        }
    }
    
    public func makeCoordinator() -> RichTextCoordinator {
        RichTextCoordinator(
            text: $text,
            textView: UITextView(), // Will be replaced in makeUIView
            context: context
        )
    }
    
    // MARK: - Static Factory Methods
    
    /// Create a basic rich text editor
    public static func basic(
        text: Binding<NSAttributedString>,
        context: RichTextContext
    ) -> Self {
        RichTextEditor(text: text, context: context)
    }
    
    /// Create a rich text editor optimized for notes
    public static func forNotes(
        text: Binding<NSAttributedString>,
        context: RichTextContext
    ) -> Self {
        RichTextEditor(text: text, context: context) { textView in
            // Optimize for note-taking
            textView.autocorrectionType = .yes
            textView.autocapitalizationType = .sentences
            textView.smartQuotesType = .yes
            textView.smartDashesType = .yes
            textView.spellCheckingType = .yes
            
            // Better line spacing for readability
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8
            
            textView.typingAttributes[.paragraphStyle] = paragraphStyle
        }
    }
}

// MARK: - View Extensions

public extension RichTextEditor {
    
    /// Apply a custom theme to the editor
    func theme(_ theme: RichTextTheme) -> some View {
        self.overlay(
            Color.clear
                .onAppear {
                    // Theme will be applied through configuration
                }
        )
    }
    
    /// Enable or disable the editor
    func disabled(_ isDisabled: Bool) -> some View {
        self.onAppear {
            context.isEditable = !isDisabled
        }
    }
    
    /// Configure keyboard settings
    func keyboard(_ settings: RichTextKeyboardSettings) -> some View {
        RichTextEditor(text: $text, context: context) { textView in
            textView.keyboardType = settings.keyboardType
            textView.returnKeyType = settings.returnKeyType
            textView.autocorrectionType = settings.autocorrectionType
            textView.autocapitalizationType = settings.autocapitalizationType
            configuration(textView)
        }
    }
    
}

// MARK: - Supporting Types

public struct RichTextTheme {
    public let backgroundColor: Color
    public let textColor: Color
    public let font: UIFont
    public let selectionColor: Color
    
    public init(
        backgroundColor: Color = .clear,
        textColor: Color = .primary,
        font: UIFont = UIFont.systemFont(ofSize: 17),
        selectionColor: Color = .accentColor
    ) {
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.font = font
        self.selectionColor = selectionColor
    }
    
    public static let `default` = RichTextTheme()
    
    public static let dark = RichTextTheme(
        backgroundColor: .black,
        textColor: .white
    )
    
    public static let light = RichTextTheme(
        backgroundColor: .white,
        textColor: .black
    )
}

public struct RichTextKeyboardSettings {
    public let keyboardType: UIKeyboardType
    public let returnKeyType: UIReturnKeyType
    public let autocorrectionType: UITextAutocorrectionType
    public let autocapitalizationType: UITextAutocapitalizationType
    
    public init(
        keyboardType: UIKeyboardType = .default,
        returnKeyType: UIReturnKeyType = .default,
        autocorrectionType: UITextAutocorrectionType = .yes,
        autocapitalizationType: UITextAutocapitalizationType = .sentences
    ) {
        self.keyboardType = keyboardType
        self.returnKeyType = returnKeyType
        self.autocorrectionType = autocorrectionType
        self.autocapitalizationType = autocapitalizationType
    }
    
    public static let `default` = RichTextKeyboardSettings()
    
    public static let notes = RichTextKeyboardSettings(
        autocorrectionType: .yes,
        autocapitalizationType: .sentences
    )
}
