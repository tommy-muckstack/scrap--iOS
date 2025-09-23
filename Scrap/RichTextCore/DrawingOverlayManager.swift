import SwiftUI
import UIKit
import PencilKit

// MARK: - Drawing Overlay Manager
/// Manages drawing overlays positioned over text markers instead of using NSTextAttachment
public class DrawingOverlayManager: ObservableObject {
    
    // MARK: - Constants
    public static let fixedCanvasHeight: CGFloat = 120
    public static let totalDrawingHeight: CGFloat = fixedCanvasHeight + 40 // Canvas + padding
    
    // MARK: - Drawing Model
    public struct DrawingMarker: Identifiable, Codable {
        public let id: String
        public var drawingData: Data?
        public var selectedColor: DrawingColor
        public var position: CGPoint
        public var width: CGFloat
        
        // Canvas height is now fixed
        public var canvasHeight: CGFloat {
            return DrawingOverlayManager.fixedCanvasHeight
        }
        
        public init(id: String = UUID().uuidString, 
                    drawingData: Data? = nil, 
                    selectedColor: DrawingColor = .black,
                    position: CGPoint = .zero,
                    width: CGFloat = 300) {
            self.id = id
            self.drawingData = drawingData
            self.selectedColor = selectedColor
            self.position = position
            self.width = width
        }
        
        // MARK: - Codable Implementation
        private enum CodingKeys: String, CodingKey {
            case id, drawingData, selectedColor, position, width
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            drawingData = try container.decodeIfPresent(Data.self, forKey: .drawingData)
            selectedColor = try container.decode(DrawingColor.self, forKey: .selectedColor)
            
            // Decode CGPoint manually
            if let positionData = try container.decodeIfPresent(Data.self, forKey: .position) {
                position = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSValue.self, from: positionData)?.cgPointValue ?? .zero
            } else {
                position = .zero
            }
            
            width = try container.decode(CGFloat.self, forKey: .width)
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(drawingData, forKey: .drawingData)
            try container.encode(selectedColor, forKey: .selectedColor)
            
            // Encode CGPoint manually
            let positionValue = NSValue(cgPoint: position)
            let positionData = try NSKeyedArchiver.archivedData(withRootObject: positionValue, requiringSecureCoding: false)
            try container.encode(positionData, forKey: .position)
            
            try container.encode(width, forKey: .width)
        }
    }
    
    // MARK: - Properties
    @Published public var drawingMarkers: [String: DrawingMarker] = [:]
    @Published public var showingDrawingEditor = false
    @Published public var currentEditingDrawing: DrawingMarker?
    
    private weak var textView: UITextView?
    
    // MARK: - Initialization
    public init() {}
    
    public func connectTextView(_ textView: UITextView) {
        // Prevent duplicate connections to the same text view
        if self.textView === textView {
            print("⚠️ DrawingOverlayManager: Already connected to this text view, skipping")
            return
        }
        
        // Clean up previous connection if exists
        if let previousTextView = self.textView {
            print("🧹 DrawingOverlayManager: Disconnecting from previous text view \(previousTextView)")
            disconnectTextView()
        }
        
        self.textView = textView
        print("🔗 DrawingOverlayManager: Connected to text view \(textView)")
    }
    
    /// Clean up connections and resources
    public func disconnectTextView() {
        if let textView = self.textView {
            print("🔌 DrawingOverlayManager: Disconnecting from text view \(textView)")
        }
        self.textView = nil
        // Clear any drawing overlays that might be retained
        drawingMarkers.removeAll()
    }
    
    // MARK: - Drawing Management
    
    /// Insert a new drawing marker at the current cursor position
    public func insertDrawing(at range: NSRange) {
        guard let textView = textView,
              let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString else {
            print("❌ DrawingOverlayManager: No text view or attributed text available")
            return
        }
        
        print("🎨 DrawingOverlayManager: Inserting new drawing at range \(range)")
        
        let drawingId = UUID().uuidString
        let marker = DrawingMarker(id: drawingId)
        
        // Create text marker that reserves space for the drawing
        let markerText = "[DRAWING:\(drawingId)]"
        let spacerHeight = DrawingOverlayManager.totalDrawingHeight
        
        // Create a paragraph style that reserves the needed vertical space
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.minimumLineHeight = spacerHeight
        paragraphStyle.maximumLineHeight = spacerHeight
        
        let markerAttributedString = NSAttributedString(string: markerText, attributes: [
            .font: UIFont.systemFont(ofSize: 0.1), // Nearly invisible text
            .foregroundColor: UIColor.clear,
            .backgroundColor: UIColor.clear,
            .paragraphStyle: paragraphStyle
        ])
        
        // Insert newline before drawing if not at start of line
        let lineRange = (textView.text as NSString).lineRange(for: NSRange(location: range.location, length: 0))
        let isAtStartOfLine = range.location == lineRange.location
        
        var insertionRange = range
        if !isAtStartOfLine {
            let newlineString = NSAttributedString(string: "\n")
            mutableText.insert(newlineString, at: range.location)
            insertionRange = NSRange(location: range.location + 1, length: 0)
        }
        
        // Insert the marker with reserved space
        mutableText.insert(markerAttributedString, at: insertionRange.location)
        
        // Add newline after marker to return to normal text
        let trailingNewline = NSAttributedString(string: "\n")
        mutableText.insert(trailingNewline, at: insertionRange.location + markerAttributedString.length)
        
        // Update text view
        textView.attributedText = mutableText
        
        // Store the drawing marker
        drawingMarkers[drawingId] = marker
        
        // Calculate position for overlay
        updateDrawingPosition(for: drawingId)
        
        // Set cursor after the drawing
        let newCursorPosition = insertionRange.location + markerAttributedString.length + 1
        textView.selectedRange = NSRange(location: newCursorPosition, length: 0)
        
        // Open drawing editor
        currentEditingDrawing = marker
        showingDrawingEditor = true
        
        print("🎨 DrawingOverlayManager: Created drawing marker with ID: \(drawingId)")
    }
    
    /// Update drawing position based on text layout
    func updateDrawingPosition(for drawingId: String) {
        guard let textView = textView,
              let marker = drawingMarkers[drawingId] else { return }
        
        let text = textView.text ?? ""
        let markerText = "[DRAWING:\(drawingId)]"
        
        if let range = text.range(of: markerText) {
            let nsRange = NSRange(range, in: text)
            
            // Get the position of the marker in the text view
            let rect = textView.layoutManager.boundingRect(
                forGlyphRange: nsRange,
                in: textView.textContainer
            )
            
            // Position overlay directly over the reserved space
            let position = CGPoint(
                x: 0, // Full width, no horizontal offset needed
                y: rect.minY + textView.textContainerInset.top - DrawingOverlayManager.totalDrawingHeight / 2
            )
            
            var updatedMarker = marker
            updatedMarker.position = position
            updatedMarker.width = textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right
            
            drawingMarkers[drawingId] = updatedMarker
            print("🎨 DrawingOverlayManager: Updated position for drawing \(drawingId) to \(position)")
        }
    }
    
    /// Update all drawing positions (call when text changes)
    public func updateAllDrawingPositions() {
        for drawingId in drawingMarkers.keys {
            updateDrawingPosition(for: drawingId)
        }
    }
    
    /// Save drawing data
    public func saveDrawing(_ drawingId: String, data: Data?, color: DrawingColor) {
        guard var marker = drawingMarkers[drawingId] else { return }
        
        marker.drawingData = data
        marker.selectedColor = color
        
        drawingMarkers[drawingId] = marker
        
        print("🎨 DrawingOverlayManager: Saved drawing data for \(drawingId)")
    }
    
    /// Delete a drawing
    public func deleteDrawing(_ drawingId: String) {
        guard let textView = textView else { return }
        
        let markerText = "[DRAWING:\(drawingId)]"
        let text = textView.text ?? ""
        
        if let range = text.range(of: markerText) {
            let nsRange = NSRange(range, in: text)
            
            if let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                // Remove the marker and any surrounding newlines
                var deleteRange = nsRange
                
                // Extend to include trailing newline
                if deleteRange.upperBound < mutableText.length {
                    let nextChar = mutableText.string[mutableText.string.index(mutableText.string.startIndex, offsetBy: deleteRange.upperBound)]
                    if nextChar == "\n" {
                        deleteRange = NSRange(location: deleteRange.location, length: deleteRange.length + 1)
                    }
                }
                
                mutableText.deleteCharacters(in: deleteRange)
                textView.attributedText = mutableText
            }
        }
        
        // Remove from markers
        drawingMarkers.removeValue(forKey: drawingId)
        
        print("🎨 DrawingOverlayManager: Deleted drawing \(drawingId)")
    }
    
    /// Extract drawing markers from text for persistence and convert to text markers
    public func convertToTextMarkers(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let text = mutableString.string
        let pattern = "\\[DRAWING:([^\\]]+)\\]"
        
        // Debug: Print what text we're searching for drawing markers
        print("🎨 DrawingOverlayManager: Searching for drawing markers in text: '\(text.prefix(200))'")
        print("🎨 DrawingOverlayManager: Current stored drawing markers: \(Array(drawingMarkers.keys))")
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            
            print("🎨 DrawingOverlayManager: Found \(matches.count) drawing markers to convert for persistence")
            
            // If no matches found, check if we have orphaned markers that need to be converted anyway
            if matches.isEmpty && !drawingMarkers.isEmpty {
                print("⚠️ DrawingOverlayManager: No drawing markers found in text, but we have \(drawingMarkers.count) stored drawings")
                print("⚠️ DrawingOverlayManager: This suggests the [DRAWING:ID] markers were lost from the text")
                
                // Try to add the drawing markers at the end of the text
                for (drawingId, marker) in drawingMarkers {
                    if let drawingData = marker.drawingData {
                        let base64Data = drawingData.base64EncodedString()
                        let color = marker.selectedColor.rawValue
                        let textMarker = "\n🎨DRAWING:\(base64Data):\(DrawingOverlayManager.fixedCanvasHeight):\(color)🎨\n"
                        
                        let markerAttributedString = NSAttributedString(string: textMarker)
                        mutableString.append(markerAttributedString)
                        
                        print("🎨 DrawingOverlayManager: Added orphaned drawing \(drawingId) as text marker")
                    }
                }
            } else {
                // Process found matches in reverse order to maintain indices
                for match in matches.reversed() {
                    if match.numberOfRanges >= 2 {
                        let drawingId = (text as NSString).substring(with: match.range(at: 1))
                        
                        if let marker = drawingMarkers[drawingId] {
                            // Convert to text marker format
                            let base64Data = marker.drawingData?.base64EncodedString() ?? ""
                            let color = marker.selectedColor.rawValue
                            let textMarker = "🎨DRAWING:\(base64Data):\(DrawingOverlayManager.fixedCanvasHeight):\(color)🎨"
                            
                            let replacement = NSAttributedString(string: textMarker)
                            mutableString.replaceCharacters(in: match.range, with: replacement)
                            
                            print("🎨 DrawingOverlayManager: Converted drawing \(drawingId) to text marker")
                        } else {
                            print("⚠️ DrawingOverlayManager: Drawing marker \(drawingId) not found in current markers")
                            // Remove orphaned marker
                            mutableString.deleteCharacters(in: match.range)
                        }
                    }
                }
            }
        } catch {
            print("❌ DrawingOverlayManager: Failed to convert drawing markers: \(error)")
        }
        
        return mutableString
    }
    
    /// Restore drawing markers from text markers
    public func restoreFromTextMarkers(_ attributedString: NSAttributedString) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        let text = attributedString.string
        
        // Find drawing markers
        let drawingPattern = "🎨DRAWING:([^:]*):([^:]*):([^:]*)🎨"
        guard let regex = try? NSRegularExpression(pattern: drawingPattern, options: []) else {
            print("❌ DrawingOverlayManager: Failed to create regex for drawing restoration")
            return attributedString
        }
        
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
        print("🎨 DrawingOverlayManager: Found \(matches.count) text markers to restore")
        
        // Process matches in reverse order to maintain indices
        for match in matches.reversed() {
            if match.numberOfRanges >= 4 {
                let base64Data = (text as NSString).substring(with: match.range(at: 1))
                let _ = (text as NSString).substring(with: match.range(at: 2)) // Height is now fixed
                let colorString = (text as NSString).substring(with: match.range(at: 3))
                
                let color = DrawingColor(rawValue: colorString) ?? .black
                let drawingData = base64Data.isEmpty ? nil : Data(base64Encoded: base64Data)
                
                let drawingId = UUID().uuidString
                let marker = DrawingMarker(
                    id: drawingId,
                    drawingData: drawingData,
                    selectedColor: color
                )
                
                // Store in current markers
                drawingMarkers[drawingId] = marker
                
                // Create space-reserving marker text
                let markerText = "[DRAWING:\(drawingId)]"
                let spacerHeight = DrawingOverlayManager.totalDrawingHeight
                
                let paragraphStyle = NSMutableParagraphStyle()
                paragraphStyle.minimumLineHeight = spacerHeight
                paragraphStyle.maximumLineHeight = spacerHeight
                
                let markerAttributedString = NSAttributedString(string: markerText, attributes: [
                    .font: UIFont.systemFont(ofSize: 0.1),
                    .foregroundColor: UIColor.clear,
                    .backgroundColor: UIColor.clear,
                    .paragraphStyle: paragraphStyle
                ])
                
                // Replace text marker with space-reserving marker
                mutableString.replaceCharacters(in: match.range, with: markerAttributedString)
                
                print("🎨 DrawingOverlayManager: Restored drawing \(drawingId) from text marker")
            }
        }
        
        // Update positions for all restored drawings
        DispatchQueue.main.async {
            self.updateAllDrawingPositions()
        }
        
        return mutableString
    }
    
    /// Restore drawing markers to text
    func restoreDrawingMarkers(_ attributedString: NSAttributedString, markers: [String: DrawingMarker]) -> NSAttributedString {
        let mutableString = NSMutableAttributedString(attributedString: attributedString)
        
        // For now, just add markers at the end - in a real implementation,
        // you'd want to store position information
        for (drawingId, marker) in markers {
            let markerText = "[DRAWING:\(drawingId)]"
            let markerAttributedString = NSAttributedString(string: markerText, attributes: [
                .font: UIFont.systemFont(ofSize: 0.1),
                .foregroundColor: UIColor.clear
            ])
            
            mutableString.append(NSAttributedString(string: "\n"))
            mutableString.append(markerAttributedString)
            mutableString.append(NSAttributedString(string: "\n"))
            
            drawingMarkers[drawingId] = marker
        }
        
        return mutableString
    }
    
    // MARK: - Cleanup Methods
    
    /// Clear all drawing markers (call when note is deleted/archived)
    public func clearAllDrawings() {
        print("🗑️ DrawingOverlayManager: Clearing all drawing markers")
        drawingMarkers.removeAll()
        currentEditingDrawing = nil
        showingDrawingEditor = false
        print("✅ DrawingOverlayManager: Successfully cleared all drawing markers")
    }
    
    /// Clear specific drawing markers by their IDs
    public func clearDrawings(withIds drawingIds: [String]) {
        print("🗑️ DrawingOverlayManager: Clearing \(drawingIds.count) specific drawing markers")
        for drawingId in drawingIds {
            drawingMarkers.removeValue(forKey: drawingId)
            // If we're currently editing one of these drawings, close the editor
            if currentEditingDrawing?.id == drawingId {
                currentEditingDrawing = nil
                showingDrawingEditor = false
            }
        }
        print("✅ DrawingOverlayManager: Successfully cleared \(drawingIds.count) drawing markers")
    }
    
    /// Extract all drawing IDs from note content for targeted cleanup
    public static func extractDrawingIds(from attributedString: NSAttributedString) -> [String] {
        let text = attributedString.string
        var drawingIds: [String] = []
        
        // Find [DRAWING:ID] markers
        let markerPattern = "\\[DRAWING:([^\\]]+)\\]"
        if let regex = try? NSRegularExpression(pattern: markerPattern, options: []) {
            let matches = regex.matches(in: text, range: NSRange(location: 0, length: text.count))
            for match in matches {
                if match.numberOfRanges >= 2 {
                    let drawingId = (text as NSString).substring(with: match.range(at: 1))
                    drawingIds.append(drawingId)
                }
            }
        }
        
        print("🔍 DrawingOverlayManager: Found \(drawingIds.count) drawing IDs in note content")
        return drawingIds
    }
}

// MARK: - Drawing Overlay View
public struct DrawingOverlayView: View {
    let marker: DrawingOverlayManager.DrawingMarker
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    public init(marker: DrawingOverlayManager.DrawingMarker, onEdit: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.marker = marker
        self.onEdit = onEdit
        self.onDelete = onDelete
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Drawing preview
            DrawingPreviewView(drawingData: marker.drawingData, height: marker.canvasHeight)
                .frame(height: DrawingOverlayManager.totalDrawingHeight)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black, lineWidth: 2)
                )
                .overlay(
                    // Options button
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: onEdit) {
                                Image(systemName: "ellipsis.circle.fill")
                                    .foregroundColor(.gray)
                                    .font(.system(size: 24))
                            }
                            .padding(.top, 8)
                            .padding(.trailing, 12)
                        }
                        Spacer()
                    }
                )
                .onTapGesture {
                    onEdit()
                }
        }
        .offset(x: marker.position.x, y: marker.position.y)
    }
}

// MARK: - Drawing Preview View
struct DrawingPreviewView: View {
    let drawingData: Data?
    let height: CGFloat
    
    var body: some View {
        if let data = drawingData {
            if let drawing = try? PKDrawing(data: data) {
                DrawingImageView(drawing: drawing)
                    .frame(height: height)
                    .onAppear {
                        print("🖼️ DrawingPreviewView: Successfully created PKDrawing from \(data.count) bytes, strokes: \(drawing.strokes.count)")
                    }
            } else {
                // Fallback to empty state when drawing data is corrupted
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.orange)
                    Text("Drawing error")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.orange)
                }
                .frame(height: height)
                .frame(maxWidth: .infinity)
                .background(Color(UIColor.systemGray5))
                .onAppear {
                    print("❌ DrawingPreviewView: Failed to create PKDrawing from \(data.count) bytes")
                }
            }
        } else {
            // Empty state - more visible placeholder
            VStack(spacing: 8) {
                Image(systemName: "pencil.and.scribble")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)
                Text("Tap to draw")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background(Color(UIColor.systemGray5))
        }
    }
}

// MARK: - Drawing Image View
struct DrawingImageView: UIViewRepresentable {
    let drawing: PKDrawing
    
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        return imageView
    }
    
    func updateUIView(_ uiView: UIImageView, context: Context) {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: DrawingOverlayManager.fixedCanvasHeight)
        let image = drawing.image(from: bounds, scale: UIScreen.main.scale)
        uiView.image = image
        print("🖼️ DrawingImageView: Generated image from bounds \(bounds), image size: \(image.size), strokes: \(drawing.strokes.count)")
    }
}