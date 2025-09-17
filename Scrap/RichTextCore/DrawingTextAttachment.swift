import UIKit
import Foundation
import PencilKit
import SwiftUI

// MARK: - Drawing Text Attachment
/// A native iOS NSTextAttachment implementation for drawings/whiteboards
/// Provides resizable drawing canvas with PencilKit integration and RTF persistence
class DrawingTextAttachment: NSTextAttachment, NSCopying {
    
    // MARK: - Properties
    
    /// PencilKit drawing data
    var drawingData: Data? {
        didSet {
            // Regenerate image with new drawing data
            let bounds = CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
            let newImage = generateDrawingImage(bounds: bounds)
            self.image = newImage
        }
    }
    
    /// Height of the drawing canvas (user-resizable)
    var canvasHeight: CGFloat = 120 { // 5 lines high (24pt line height * 5)
        didSet {
            if canvasHeight != oldValue {
                // Regenerate image with new height
                let bounds = CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
                let newImage = generateDrawingImage(bounds: bounds)
                self.image = newImage
            }
        }
    }
    
    /// Current drawing color selection
    var selectedColor: DrawingColor = .black
    
    /// Unique identifier for this drawing
    let drawingId = UUID().uuidString
    
    /// Callback for when drawing needs to be edited
    var onEditDrawing: ((DrawingTextAttachment) -> Void)?
    
    /// Callback for when drawing should be deleted
    var onDeleteDrawing: ((DrawingTextAttachment) -> Void)?
    
    // MARK: - Initialization
    
    init(drawingData: Data? = nil, height: CGFloat = 120) {
        super.init(data: nil, ofType: nil)
        self.drawingData = drawingData
        self.canvasHeight = height
        
        // Immediately generate and set the initial image to ensure rendering
        let initialBounds = CGRect(x: 0, y: 0, width: 300, height: height + 40)
        let initialImage = generateDrawingImage(bounds: initialBounds)
        self.image = initialImage
        
        // CRITICAL: Force bounds to ensure proper layout
        self.bounds = CGRect(x: 0, y: 0, width: 300, height: height + 40)
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.drawingData = coder.decodeObject(forKey: "drawingData") as? Data
        self.canvasHeight = coder.decodeObject(forKey: "canvasHeight") as? CGFloat ?? 120
        self.selectedColor = DrawingColor(rawValue: coder.decodeObject(forKey: "selectedColor") as? String ?? "") ?? .black
        
        // Generate and set the image after decoding
        let initialBounds = CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
        let initialImage = generateDrawingImage(bounds: initialBounds)
        self.image = initialImage
        
        // CRITICAL: Force bounds to ensure proper layout
        self.bounds = CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
    }
    
    override func encode(with coder: NSCoder) {
        super.encode(with: coder)
        coder.encode(drawingData, forKey: "drawingData")
        coder.encode(canvasHeight, forKey: "canvasHeight")
        coder.encode(selectedColor.rawValue, forKey: "selectedColor")
    }
    
    func copy(with zone: NSZone? = nil) -> Any {
        let copy = DrawingTextAttachment(drawingData: drawingData, height: canvasHeight)
        copy.selectedColor = selectedColor
        copy.onEditDrawing = onEditDrawing
        copy.onDeleteDrawing = onDeleteDrawing
        return copy
    }
    
    // MARK: - NSTextAttachment Overrides
    
    override func attachmentBounds(for textContainer: NSTextContainer?, 
                                 proposedLineFragment lineFrag: CGRect, 
                                 glyphPosition position: CGPoint, 
                                 characterIndex charIndex: Int) -> CGRect {
        // Always full width of text container, fallback to a reasonable width
        let width = textContainer?.size.width ?? max(lineFrag.width, 300)
        // Add padding for the options button and border
        let totalHeight = canvasHeight + 40 // 20pt top padding + 20pt bottom padding
        
        // CRITICAL FIX: Use small negative Y offset to align properly with text baseline
        // Too large negative offset can push drawing outside visible area
        let yOffset: CGFloat = -5 // Small negative offset to align with text baseline
        
        return CGRect(x: 0, y: yOffset, width: width, height: totalHeight)
    }
    
    override var image: UIImage? {
        get {
            // Always return the current cached image or generate if needed
            if let cachedImage = super.image {
                return cachedImage
            } else {
                let bounds = CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
                let generatedImage = generateDrawingImage(bounds: bounds)
                super.image = generatedImage // Cache the generated image
                return generatedImage
            }
        }
        set {
            super.image = newValue
        }
    }
    
    override func image(forBounds imageBounds: CGRect, 
                       textContainer: NSTextContainer?, 
                       characterIndex charIndex: Int) -> UIImage? {
        
        // Use the bounds from attachmentBounds if imageBounds is invalid
        let renderBounds = imageBounds.width > 0 && imageBounds.height > 0 ? 
            imageBounds : 
            CGRect(x: 0, y: 0, width: 300, height: canvasHeight + 40)
            
        let generatedImage = generateDrawingImage(bounds: renderBounds)
        
        // Also cache this image in the main image property
        super.image = generatedImage
        
        return generatedImage
    }
    
    // MARK: - Image Generation
    
    /// Generate the drawing view image with borders and controls
    private func generateDrawingImage(bounds: CGRect) -> UIImage {
        
        // Ensure bounds are valid
        guard bounds.width > 0 && bounds.height > 0 else {
            // Create a visible error placeholder with black border
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100))
            return renderer.image { context in
                let cgContext = context.cgContext
                
                // Red background to indicate error
                cgContext.setFillColor(UIColor.systemRed.withAlphaComponent(0.3).cgColor)
                cgContext.fill(CGRect(x: 0, y: 0, width: 300, height: 100))
                
                // Black border for visibility
                cgContext.setStrokeColor(UIColor.black.cgColor)
                cgContext.setLineWidth(2.0)
                cgContext.stroke(CGRect(x: 1, y: 1, width: 298, height: 98))
                
                // Error text
                let text = "Drawing Error"
                let font = UIFont.systemFont(ofSize: 16, weight: .semibold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .foregroundColor: UIColor.black
                ]
                let attributedText = NSAttributedString(string: text, attributes: attributes)
                let textSize = attributedText.size()
                let textRect = CGRect(
                    x: 150 - textSize.width / 2,
                    y: 50 - textSize.height / 2,
                    width: textSize.width,
                    height: textSize.height
                )
                attributedText.draw(in: textRect)
            }
        }
        
        // Ensure minimum visible size and reasonable dimensions
        let actualBounds = CGRect(
            x: bounds.origin.x,
            y: bounds.origin.y, 
            width: max(bounds.width, 300), // Ensure full width for visibility
            height: max(bounds.height, 120) // Ensure minimum canvas height
        )
        
        let renderer = UIGraphicsImageRenderer(bounds: actualBounds)
        let generatedImage = renderer.image { context in
            let cgContext = context.cgContext
            
            // Set up drawing context
            cgContext.setShouldAntialias(true)
            cgContext.setAllowsAntialiasing(true)
            
            // Draw background with rounded corners
            let drawingRect = CGRect(x: 8, y: 20, width: actualBounds.width - 16, height: canvasHeight)
            let cornerRadius: CGFloat = 8.0
            
            
            // Background color - use a light gray to make it more visible
            cgContext.setFillColor(UIColor.systemGray6.cgColor)
            
            // Border color - use strong black border for visibility
            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(2.0)
            
            // Draw rounded rectangle background
            let path = UIBezierPath(roundedRect: drawingRect, cornerRadius: cornerRadius)
            cgContext.addPath(path.cgPath)
            cgContext.drawPath(using: .fillStroke)
            
            // Draw the actual drawing if we have data
            if let drawingData = drawingData,
               let drawing = try? PKDrawing(data: drawingData) {
                
                // Create a temporary canvas view to render the drawing
                let canvasView = PKCanvasView(frame: drawingRect)
                canvasView.drawing = drawing
                canvasView.backgroundColor = UIColor.clear
                
                // Render the drawing content
                let drawingImage = canvasView.drawing.image(from: drawingRect, scale: UIScreen.main.scale)
                drawingImage.draw(in: drawingRect)
            } else {
                // Draw placeholder grid lines for empty canvas
                drawGridLines(in: cgContext, rect: drawingRect)
                
                // Add placeholder text to make it clear this is a drawing area
                drawPlaceholderText(in: cgContext, rect: drawingRect)
            }
            
            // Draw options button (three dots) in top right
            drawOptionsButton(in: cgContext, bounds: actualBounds)
            
            // Draw resize handle at bottom
            drawResizeHandle(in: cgContext, bounds: actualBounds)
        }
        
        
        return generatedImage
    }
    
    /// Draw subtle grid lines for empty canvas
    private func drawGridLines(in context: CGContext, rect: CGRect) {
        context.setStrokeColor(UIColor.systemGray4.cgColor)
        context.setLineWidth(1.0)
        
        let gridSpacing: CGFloat = 20
        let startX = rect.minX
        let endX = rect.maxX
        let startY = rect.minY
        let endY = rect.maxY
        
        // Horizontal lines
        var y = startY + gridSpacing
        while y < endY {
            context.move(to: CGPoint(x: startX, y: y))
            context.addLine(to: CGPoint(x: endX, y: y))
            y += gridSpacing
        }
        
        // Vertical lines
        var x = startX + gridSpacing
        while x < endX {
            context.move(to: CGPoint(x: x, y: startY))
            context.addLine(to: CGPoint(x: x, y: endY))
            x += gridSpacing
        }
        
        context.strokePath()
    }
    
    /// Draw placeholder text for empty canvas
    private func drawPlaceholderText(in context: CGContext, rect: CGRect) {
        let text = "Tap to draw"
        let font = UIFont.systemFont(ofSize: 14, weight: .medium)
        let textColor = UIColor.systemGray2
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedText.size()
        
        // Center the text in the drawing area
        let textRect = CGRect(
            x: rect.midX - textSize.width / 2,
            y: rect.midY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        
        attributedText.draw(in: textRect)
    }
    
    /// Draw the options button (three dots)
    private func drawOptionsButton(in context: CGContext, bounds: CGRect) {
        let buttonSize: CGFloat = 24
        let buttonRect = CGRect(
            x: bounds.width - buttonSize - 12,
            y: 4,
            width: buttonSize,
            height: buttonSize
        )
        
        // Button background
        context.setFillColor(UIColor.systemGray5.cgColor)
        let buttonPath = UIBezierPath(roundedRect: buttonRect, cornerRadius: 4)
        context.addPath(buttonPath.cgPath)
        context.fillPath()
        
        // Three dots
        context.setFillColor(UIColor.label.cgColor)
        let dotSize: CGFloat = 2
        let dotSpacing: CGFloat = 4
        let centerX = buttonRect.midX
        let centerY = buttonRect.midY
        
        for i in 0..<3 {
            let dotX = centerX - dotSize/2
            let dotY = centerY - dotSize/2 + CGFloat(i - 1) * (dotSize + dotSpacing)
            let dotRect = CGRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
            context.fillEllipse(in: dotRect)
        }
    }
    
    /// Draw resize handle at bottom center
    private func drawResizeHandle(in context: CGContext, bounds: CGRect) {
        let handleWidth: CGFloat = 40
        let handleHeight: CGFloat = 8
        let handleRect = CGRect(
            x: bounds.midX - handleWidth/2,
            y: bounds.height - handleHeight - 4,
            width: handleWidth,
            height: handleHeight
        )
        
        // Handle background
        context.setFillColor(UIColor.systemGray4.cgColor)
        let handlePath = UIBezierPath(roundedRect: handleRect, cornerRadius: 4)
        context.addPath(handlePath.cgPath)
        context.fillPath()
        
        // Handle lines
        context.setStrokeColor(UIColor.systemGray2.cgColor)
        context.setLineWidth(1)
        
        let lineSpacing: CGFloat = 3
        for i in 0..<3 {
            let lineY = handleRect.minY + 2 + CGFloat(i) * lineSpacing
            context.move(to: CGPoint(x: handleRect.minX + 4, y: lineY))
            context.addLine(to: CGPoint(x: handleRect.maxX - 4, y: lineY))
        }
        context.strokePath()
    }
}

// MARK: - Drawing Color
public enum DrawingColor: String, CaseIterable, Codable {
    case black = "#000000"
    case blue = "#6B73FF"
    case purple = "#9F7AEA"
    case teal = "#4FD1C7"
    case green = "#68D391"
    case orange = "#F6AD55"
    
    public var uiColor: UIColor {
        return UIColor(hex: rawValue) ?? UIColor.black
    }
    
    public var color: Color {
        return Color(hex: rawValue) ?? Color.black
    }
    
    public var name: String {
        switch self {
        case .black: return "Black"
        case .blue: return "Blue"
        case .purple: return "Purple"
        case .teal: return "Teal"
        case .green: return "Green"
        case .orange: return "Orange"
        }
    }
}

// MARK: - Drawing Manager
class DrawingManager {
    
    /// Convert drawing attachments to text markers for RTF persistence
    static func convertAttachmentsToTextMarkers(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        var drawingCount = 0
        
        // Find drawing attachments and replace with text markers
        attributedString.enumerateAttribute(.attachment, 
                                          in: NSRange(location: 0, length: attributedString.length),
                                          options: [.reverse]) { value, range, _ in
            
            if let drawingAttachment = value as? DrawingTextAttachment {
                drawingCount += 1
                
                // Create marker with drawing data and height
                let base64Data = drawingAttachment.drawingData?.base64EncodedString() ?? ""
                let height = drawingAttachment.canvasHeight
                let color = drawingAttachment.selectedColor.rawValue
                let drawingMarker = "🎨DRAWING:\(base64Data):\(height):\(color)🎨"
                
                let replacement = NSAttributedString(string: drawingMarker)
                mutableString.replaceCharacters(in: range, with: replacement)
            }
        }
        
        
        return mutableString
    }
    
    /// Convert text markers back to drawing attachments for display
    static func convertTextMarkersToAttachments(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let text = attributedString.string
        
        
        // Find drawing markers
        let drawingPattern = "🎨DRAWING:([^:]*):([^:]*):([^:]*)🎨"
        guard let regex = try? NSRegularExpression(pattern: drawingPattern, options: []) else {
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        
        // Process matches in reverse order to maintain indices
        for match in matches.reversed() {
            // Extract components
            if match.numberOfRanges >= 4 {
                let base64Data = (text as NSString).substring(with: match.range(at: 1))
                let heightString = (text as NSString).substring(with: match.range(at: 2))
                let colorString = (text as NSString).substring(with: match.range(at: 3))
                
                let height = CGFloat(Double(heightString) ?? 120)
                let color = DrawingColor(rawValue: colorString) ?? .black
                
                // Create drawing attachment
                let drawingData = base64Data.isEmpty ? nil : Data(base64Encoded: base64Data)
                let attachment = DrawingTextAttachment(drawingData: drawingData, height: height)
                attachment.selectedColor = color
                
                let attachmentString = NSAttributedString(attachment: attachment)
                
                // Replace marker with attachment
                mutableString.replaceCharacters(in: match.range, with: attachmentString)
            }
        }
        
        return mutableString
    }
    
    /// Insert a new drawing at the specified location
    static func insertDrawing(in textView: UITextView, at range: NSRange) {
        guard let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            print("❌ DrawingManager: Could not get mutable attributed string from text view")
            return
        }
        
        print("🎨 DrawingManager: Inserting new drawing at range \(range)")
        print("🎨 DrawingManager: Current text length: \(mutableText.length)")
        
        let attachment = DrawingTextAttachment()
        print("🎨 DrawingManager: Created DrawingTextAttachment with ID: \(attachment.drawingId)")
        let attachmentString = NSAttributedString(attachment: attachment)
        print("🎨 DrawingManager: Created attachment string with length: \(attachmentString.length)")
        
        // Insert newline before drawing if not at start of line
        let lineRange = (textView.text as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let isAtStartOfLine = range.location == lineRange.location
        print("🎨 DrawingManager: Line range: \(lineRange), isAtStartOfLine: \(isAtStartOfLine)")
        
        if !isAtStartOfLine {
            let newlineString = NSAttributedString(string: "\n")
            mutableText.insert(newlineString, at: range.location)
            
            // CRITICAL TEST: Check attachment before and after insertion
            print("🔬 BEFORE attachment insertion - mutableText length: \(mutableText.length)")
            mutableText.insert(attachmentString, at: range.location + 1)
            print("🔬 AFTER attachment insertion - mutableText length: \(mutableText.length)")
            
            // IMMEDIATE CHECK: Verify attachment is in mutableText right after insertion
            let insertionPosition = range.location + 1
            if insertionPosition < mutableText.length {
                let attributes = mutableText.attributes(at: insertionPosition, effectiveRange: nil)
                if let foundAttachment = attributes[.attachment] as? DrawingTextAttachment {
                    print("✅ IMMEDIATE VERIFICATION: DrawingTextAttachment found at position \(insertionPosition), ID: \(foundAttachment.drawingId)")
                } else if let foundAttachment = attributes[.attachment] {
                    print("⚠️ IMMEDIATE VERIFICATION: Other attachment found at position \(insertionPosition): \(type(of: foundAttachment))")
                } else {
                    print("❌ IMMEDIATE VERIFICATION: NO ATTACHMENT found at position \(insertionPosition)")
                    print("   Available attributes: \(attributes.keys.map { $0.rawValue })")
                }
            }
            
            textView.selectedRange = NSRange(location: range.location + 2, length: 0)
            print("🎨 DrawingManager: Inserted with newline at position \(range.location + 1)")
        } else {
            // CRITICAL TEST: Check attachment before and after insertion  
            print("🔬 BEFORE attachment insertion - mutableText length: \(mutableText.length)")
            mutableText.insert(attachmentString, at: range.location)
            print("🔬 AFTER attachment insertion - mutableText length: \(mutableText.length)")
            
            // IMMEDIATE CHECK: Verify attachment is in mutableText right after insertion
            if range.location < mutableText.length {
                let attributes = mutableText.attributes(at: range.location, effectiveRange: nil)
                if let foundAttachment = attributes[.attachment] as? DrawingTextAttachment {
                    print("✅ IMMEDIATE VERIFICATION: DrawingTextAttachment found at position \(range.location), ID: \(foundAttachment.drawingId)")
                } else if let foundAttachment = attributes[.attachment] {
                    print("⚠️ IMMEDIATE VERIFICATION: Other attachment found at position \(range.location): \(type(of: foundAttachment))")
                } else {
                    print("❌ IMMEDIATE VERIFICATION: NO ATTACHMENT found at position \(range.location)")
                    print("   Available attributes: \(attributes.keys.map { $0.rawValue })")
                }
            }
            
            textView.selectedRange = NSRange(location: range.location + 1, length: 0)
            print("🎨 DrawingManager: Inserted at start of line at position \(range.location)")
        }
        
        print("🎨 DrawingManager: Final text length: \(mutableText.length)")
        textView.attributedText = mutableText
        print("🎨 DrawingManager: Updated text view attributed text")
        
        // CRITICAL DEBUG: Verify the attachment was actually stored
        print("🔍 DrawingManager: Verifying attachment was stored...")
        let verificationText = textView.attributedText ?? NSAttributedString()
        print("🔍 DrawingManager: Text view attributed text length: \(verificationText.length)")
        
        var foundAttachments = 0
        verificationText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: verificationText.length), options: []) { value, range, _ in
            foundAttachments += 1
            print("🔍 DrawingManager: VERIFICATION - Found attachment #\(foundAttachments) at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
            if let drawingAttachment = value as? DrawingTextAttachment {
                print("🔍 DrawingManager: VERIFICATION - DrawingTextAttachment ID: \(drawingAttachment.drawingId)")
            }
        }
        print("🔍 DrawingManager: VERIFICATION - Total attachments found: \(foundAttachments)")
        
        // Also check the mutableText before setting it to textView
        print("🔍 DrawingManager: Checking mutableText before assignment...")
        var mutableFoundAttachments = 0
        mutableText.enumerateAttribute(.attachment, in: NSRange(location: 0, length: mutableText.length), options: []) { value, range, _ in
            mutableFoundAttachments += 1
            print("🔍 DrawingManager: MUTABLE - Found attachment #\(mutableFoundAttachments) at range \(range): \(value == nil ? "nil" : String(describing: type(of: value!)))")
            if let drawingAttachment = value as? DrawingTextAttachment {
                print("🔍 DrawingManager: MUTABLE - DrawingTextAttachment ID: \(drawingAttachment.drawingId)")
            }
        }
        print("🔍 DrawingManager: MUTABLE - Total attachments found: \(mutableFoundAttachments)")
        
        // CRITICAL: Force comprehensive text view refresh for drawing visibility
        print("🔄 DrawingManager: Starting comprehensive text view refresh...")
        
        // 1. Store the current selection to restore it after refresh
        let currentSelection = textView.selectedRange
        
        // 2. Force text container to recalculate size (critical for attachments)
        let containerSize = textView.textContainer.size
        textView.textContainer.size = CGSize(width: containerSize.width, height: 0) // Reset height
        textView.textContainer.size = containerSize // Restore full size
        
        // 3. Invalidate layout for the entire text range
        let fullRange = NSRange(location: 0, length: mutableText.length)
        textView.layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        textView.layoutManager.invalidateGlyphs(forCharacterRange: fullRange, changeInLength: 0, actualCharacterRange: nil)
        
        // 4. Force complete relayout of text container
        textView.layoutManager.ensureLayout(for: textView.textContainer)
        
        // 5. Force view hierarchy refresh with emphasis on text rendering
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        textView.setNeedsDisplay()
        
        // 5.5. Force text container and layout manager to fully process attachments
        textView.layoutManager.ensureGlyphs(forCharacterRange: fullRange)
        textView.layoutManager.ensureLayout(forBoundingRect: textView.bounds, in: textView.textContainer)
        
        // 6. CRITICAL: Restore selection after layout
        textView.selectedRange = currentSelection
        
        // 7. Force attachment rendering by invalidating image cache
        if let attachmentString = textView.attributedText {
            attachmentString.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attachmentString.length), options: []) { value, range, _ in
                if let drawingAttachment = value as? DrawingTextAttachment {
                    print("🔄 DrawingManager: Forcing attachment image refresh for ID: \(drawingAttachment.drawingId)")
                    // Force image regeneration by clearing cache and requesting new image
                    let originalImage = drawingAttachment.image
                    drawingAttachment.image = nil
                    let newImage = drawingAttachment.image // This will trigger generation
                    print("🔄 DrawingManager: Forced image regeneration - original: \(originalImage?.size ?? CGSize.zero), new: \(newImage?.size ?? CGSize.zero)")
                }
            }
        }
        
        // 8. Force scroll to visible if needed
        DispatchQueue.main.async {
            textView.scrollRangeToVisible(currentSelection)
        }
        
        print("🔄 DrawingManager: Comprehensive refresh complete")
        
        // Notify delegate that content has changed
        textView.delegate?.textViewDidChange?(textView)
        
        print("🎨 DrawingManager: New drawing inserted and text view updated")
    }
}

// MARK: - UIColor Extension
extension UIColor {
    convenience init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: CGFloat(a) / 255
        )
    }
}
