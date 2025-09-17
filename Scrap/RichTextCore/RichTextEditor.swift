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
    @Binding private var showingFormatting: Bool
    private var drawingManager: DrawingOverlayManager?
    
    // MARK: - Initialization
    
    public init(
        text: Binding<NSAttributedString>,
        context: RichTextContext,
        showingFormatting: Binding<Bool> = .constant(false),
        drawingManager: DrawingOverlayManager? = nil,
        configuration: @escaping (UITextView) -> Void = { _ in }
    ) {
        self._text = text
        self.context = context
        self._showingFormatting = showingFormatting
        self.drawingManager = drawingManager
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
        
        // CRITICAL: Configure text container for proper attachment display
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.heightTracksTextView = false
        textView.textContainer.maximumNumberOfLines = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        
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
        
        // Connect drawing manager to text view if available
        drawingManager?.connectTextView(textView)
        
        // Add tap gesture for checkbox toggling
        let tapGesture = UITapGestureRecognizer(target: coordinator, action: #selector(RichTextCoordinator.handleTap(_:)))
        tapGesture.numberOfTapsRequired = 1
        tapGesture.delegate = coordinator
        textView.addGestureRecognizer(tapGesture)
        
        // Use native UITextView behavior for text selection and editing
        // Double-tap, long-press, copy/paste all work natively
        
        // Apply custom configuration
        configuration(textView)
        
        // Set up input accessory view for formatting toolbar
        textView.setupRichTextInputAccessory(
            context: self.context,
            showingFormatting: $showingFormatting
        )
        
        return textView
    }
    
    public func updateUIView(_ uiView: UITextView, context: Context) {
        // Get the coordinator to check if it's currently updating from the text view
        let coordinator = context.coordinator
        
        // Enhanced checking to prevent race conditions
        let isCoordinatorUpdating = coordinator.isUpdatingFromTextView
        let textsAreEqual = uiView.attributedText.isEqual(to: text)
        
        
        // Only update text if it's actually different AND we're not in the middle of a text view update
        // This prevents overwriting formatting that was just applied by the coordinator
        if !isCoordinatorUpdating && !textsAreEqual {
            
            let selectedRange = uiView.selectedRange
            uiView.attributedText = text
            
            // Restore cursor position safely with comprehensive validation
            let textLength = text.length
            let safeLocation = max(0, min(selectedRange.location, textLength))
            let remainingLength = textLength - safeLocation
            let safeLength = max(0, min(selectedRange.length, remainingLength))
            
            let safeRange = NSRange(location: safeLocation, length: safeLength)
            
            // Additional validation to prevent CoreGraphics issues
            if safeRange.location >= 0 && 
               safeRange.length >= 0 && 
               safeRange.location + safeRange.length <= textLength {
                uiView.selectedRange = safeRange
            } else {
                // Fallback to cursor at end of text
                uiView.selectedRange = NSRange(location: textLength, length: 0)
            }
        } else {
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
        let coordinator = RichTextCoordinator(
            text: $text,
            textView: UITextView(), // Will be replaced in makeUIView
            context: context
        )
        
        // Set up drawing manager integration if available
        coordinator.drawingManager = drawingManager
        
        return coordinator
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
        context: RichTextContext,
        showingFormatting: Binding<Bool> = .constant(false)
    ) -> Self {
        RichTextEditor(text: text, context: context, showingFormatting: showingFormatting) { textView in
            // Optimize for note-taking
            textView.autocorrectionType = .yes
            textView.autocapitalizationType = .sentences
            textView.smartQuotesType = .yes
            textView.smartDashesType = .yes
            textView.spellCheckingType = .yes
            
            // Set cursor color to black (matching design system)
            textView.tintColor = UIColor.label
            
            // Improve text alignment and padding to match placeholder
            textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
            textView.textContainer.lineFragmentPadding = 4
            
            // Better line spacing for readability
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.paragraphSpacing = 8
            
            // Set default Space Grotesk font for all notes
            let defaultFont = UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
            
            textView.typingAttributes = [
                .paragraphStyle: paragraphStyle,
                .font: defaultFont,
                .foregroundColor: UIColor.label
            ]
        }
    }
}

// MARK: - Rich Text Editor with Drawing Overlays
public struct RichTextEditorWithDrawings: View {
    @Binding private var text: NSAttributedString
    @ObservedObject private var context: RichTextContext
    @Binding private var showingFormatting: Bool
    private let configuration: (UITextView) -> Void
    private let onDrawingManagerReady: ((DrawingOverlayManager) -> Void)?
    
    @StateObject public var drawingManager = DrawingOverlayManager()
    
    public init(
        text: Binding<NSAttributedString>,
        context: RichTextContext,
        showingFormatting: Binding<Bool> = .constant(false),
        configuration: @escaping (UITextView) -> Void = { _ in },
        onDrawingManagerReady: ((DrawingOverlayManager) -> Void)? = nil
    ) {
        self._text = text
        self.context = context
        self._showingFormatting = showingFormatting
        self.configuration = configuration
        self.onDrawingManagerReady = onDrawingManagerReady
    }
    
    public var body: some View {
        ZStack {
            // Base text editor with shared drawing manager
            RichTextEditor(
                text: $text,
                context: context,
                showingFormatting: $showingFormatting,
                drawingManager: drawingManager,
                configuration: configuration
            )
            
            // Drawing overlays
            ForEach(Array(drawingManager.drawingMarkers.keys), id: \.self) { drawingId in
                if let marker = drawingManager.drawingMarkers[drawingId] {
                    let _ = print("🎨 RichTextEditorWithDrawings: Rendering overlay for drawing \(drawingId) at position \(marker.position)")
                    DrawingOverlayView(
                        marker: marker,
                        onEdit: {
                            drawingManager.currentEditingDrawing = marker
                            drawingManager.showingDrawingEditor = true
                        },
                        onDelete: {
                            drawingManager.deleteDrawing(drawingId)
                        }
                    )
                }
            }
        }
        .sheet(isPresented: $drawingManager.showingDrawingEditor) {
            if let currentDrawing = drawingManager.currentEditingDrawing {
                DrawingEditorView(
                    drawingData: .constant(currentDrawing.drawingData),
                    canvasHeight: .constant(DrawingOverlayManager.fixedCanvasHeight),
                    selectedColor: .constant(currentDrawing.selectedColor),
                    onSave: { data, height, color in
                        drawingManager.saveDrawing(currentDrawing.id, data: data, color: color)
                        drawingManager.currentEditingDrawing = nil
                    },
                    onDelete: {
                        drawingManager.deleteDrawing(currentDrawing.id)
                        drawingManager.currentEditingDrawing = nil
                    }
                )
            }
        }
        .onChange(of: text) { _ in
            // Update drawing positions when text changes
            DispatchQueue.main.async {
                drawingManager.updateAllDrawingPositions()
            }
        }
        .onAppear {
            // Provide access to the drawing manager once the view appears
            onDrawingManagerReady?(drawingManager)
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
