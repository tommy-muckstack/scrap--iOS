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
    @State private var isKeyboardVisible = false
    
    let onDrawingChanged: (Data?) -> Void
    
    private let defaultHeight: CGFloat = 200
    private let minHeight: CGFloat = 150
    private let maxHeight: CGFloat = 400
    
    /// Compute the adaptive height based on keyboard visibility
    private var adaptiveHeight: CGFloat {
        if isKeyboardVisible {
            // When keyboard is visible, reduce height to 1/3
            return drawingHeight / 3
        } else {
            // When keyboard is hidden, use normal height
            return drawingHeight
        }
    }
    
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
                .frame(height: adaptiveHeight)
                .background(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
                .clipped()
                .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: isKeyboardVisible)
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            // Extract keyboard animation duration from notification for perfect sync
            let keyboardDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            let _ = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
            
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: keyboardDuration)) {
                isKeyboardVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { notification in
            // Extract keyboard animation duration from notification for perfect sync
            let keyboardDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25
            
            withAnimation(.timingCurve(0.25, 0.1, 0.25, 1.0, duration: keyboardDuration)) {
                isKeyboardVisible = false
            }
        }
        .sheet(isPresented: $showingDrawingEditor) {
            DrawingEditorView(
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
            // Show existing drawing with Open button overlay
            ZStack(alignment: .topTrailing) {
                DrawingDisplayView(drawingData: data)
                    .scaleEffect(isKeyboardVisible ? 0.95 : 1.0)
                    .onTapGesture {
                        showingDrawingEditor = true
                    }
                
                // "Open Scribble" button in top-right corner
                Button("Open Scribble") {
                    showingDrawingEditor = true
                }
                .font(.custom("SpaceGrotesk-Medium", size: 12))
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black)
                .cornerRadius(12)
                .padding(8)
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