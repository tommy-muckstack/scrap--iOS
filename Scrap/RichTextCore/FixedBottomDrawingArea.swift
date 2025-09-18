import SwiftUI
import PencilKit
import UIKit

/// A fixed drawing area that appears at the bottom of notes
/// Supports the single drawing per note architecture
struct FixedBottomDrawingArea: View {
    @Binding var drawingData: Data?
    @Binding var drawingHeight: CGFloat
    @Binding var drawingColor: DrawingColor
    @State private var showingDrawingEditor = false
    @State private var canvasView = PKCanvasView()
    
    let onDrawingChanged: (Data?) -> Void
    
    private let defaultHeight: CGFloat = 200
    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 400
    
    init(
        drawingData: Binding<Data?>,
        drawingHeight: Binding<CGFloat>,
        drawingColor: Binding<DrawingColor>,
        onDrawingChanged: @escaping (Data?) -> Void = { _ in }
    ) {
        self._drawingData = drawingData
        self._drawingHeight = drawingHeight
        self._drawingColor = drawingColor
        self.onDrawingChanged = onDrawingChanged
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drawing area
            drawingAreaView
                .frame(height: drawingHeight)
                .background(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .clipped()
            
            // Controls
            drawingControlsView
                .padding(.top, 8)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .sheet(isPresented: $showingDrawingEditor) {
            DrawingView(
                drawingData: $drawingData,
                canvasHeight: $drawingHeight,
                selectedColor: $drawingColor,
                onSave: { data, height, color in
                    drawingData = data
                    drawingHeight = height
                    drawingColor = color
                    onDrawingChanged(data)
                    showingDrawingEditor = false
                },
                onDelete: {
                    drawingData = nil
                    onDrawingChanged(nil)
                    showingDrawingEditor = false
                }
            )
        }
    }
    
    @ViewBuilder
    private var drawingAreaView: some View {
        if let data = drawingData, !data.isEmpty {
            // Show existing drawing
            DrawingDisplayView(drawingData: data)
                .onTapGesture {
                    showingDrawingEditor = true
                }
        } else {
            // Show empty state with prompt to draw
            VStack(spacing: 12) {
                Image(systemName: "scribble")
                    .font(.system(size: 32))
                    .foregroundColor(.gray)
                
                Text("Tap to add a scribble")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture {
                showingDrawingEditor = true
            }
        }
    }
    
    @ViewBuilder
    private var drawingControlsView: some View {
        HStack {
            // Edit button
            Button(action: {
                showingDrawingEditor = true
            }) {
                Label("Edit", systemImage: "pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.blue)
            }
            
            Spacer()
            
            // Height controls
            HStack(spacing: 8) {
                Button(action: {
                    if drawingHeight > minHeight {
                        drawingHeight = max(minHeight, drawingHeight - 50)
                    }
                }) {
                    Image(systemName: "minus.circle")
                        .foregroundColor(drawingHeight > minHeight ? .blue : .gray)
                }
                .disabled(drawingHeight <= minHeight)
                
                Text("\(Int(drawingHeight))px")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.gray)
                    .frame(width: 50)
                
                Button(action: {
                    if drawingHeight < maxHeight {
                        drawingHeight = min(maxHeight, drawingHeight + 50)
                    }
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(drawingHeight < maxHeight ? .blue : .gray)
                }
                .disabled(drawingHeight >= maxHeight)
            }
            
            Spacer()
            
            // Delete button (only show if drawing exists)
            if drawingData != nil {
                Button(action: {
                    drawingData = nil
                    onDrawingChanged(nil)
                }) {
                    Label("Delete", systemImage: "trash")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.horizontal, 12)
    }
}

/// A view that displays a PencilKit drawing
struct DrawingDisplayView: UIViewRepresentable {
    let drawingData: Data
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.isUserInteractionEnabled = false // Read-only for display
        canvasView.backgroundColor = UIColor.clear
        
        // Load the drawing data
        if let drawing = try? PKDrawing(data: drawingData) {
            canvasView.drawing = drawing
        }
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update drawing if data changes
        if let drawing = try? PKDrawing(data: drawingData) {
            if uiView.drawing.dataRepresentation() != drawingData {
                uiView.drawing = drawing
            }
        }
    }
}



// MARK: - Preview
struct FixedBottomDrawingArea_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Text("Note content goes here...")
                .padding()
            
            Spacer()
            
            FixedBottomDrawingArea(
                drawingData: .constant(nil),
                drawingHeight: .constant(200),
                drawingColor: .constant(.black)
            )
            .padding()
        }
        .previewLayout(.sizeThatFits)
    }
}