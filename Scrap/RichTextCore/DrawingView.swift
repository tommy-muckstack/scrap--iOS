import SwiftUI
import PencilKit
import UIKit

// MARK: - Drawing Editor View
/// SwiftUI view for editing drawings with options menu
struct DrawingEditorView: View {
    @Binding var drawingData: Data?
    @Binding var canvasHeight: CGFloat
    @Binding var selectedColor: DrawingColor
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingOptions = false
    @State private var showingDeleteConfirmation = false
    @State private var canvasView = PKCanvasView()
    
    var onSave: (Data?, CGFloat, DrawingColor) -> Void
    var onDelete: () -> Void
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Drawing canvas
                DrawingCanvasView(
                    canvasView: $canvasView,
                    drawingData: $drawingData,
                    canvasHeight: $canvasHeight,
                    selectedColor: $selectedColor
                )
                
                // Color picker toolbar
                ColorPickerToolbar(
                    selectedColor: $selectedColor,
                    canvasHeight: $canvasHeight
                ) { color in
                    updateCanvasColor(color)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGray6))
            }
            .navigationTitle("Drawing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: { showingOptions = true }) {
                            Image(systemName: "ellipsis.circle")
                        }
                        
                        Button("Save") {
                            saveDrawing()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
            .actionSheet(isPresented: $showingOptions) {
                ActionSheet(
                    title: Text("Drawing Options"),
                    buttons: [
                        .default(Text("Resize Canvas")) {
                            // Height adjustment handled by DrawingCanvasView
                        },
                        .destructive(Text("Delete Drawing")) {
                            showingDeleteConfirmation = true
                        },
                        .cancel()
                    ]
                )
            }
            .alert("Delete Drawing", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    private func updateCanvasColor(_ color: DrawingColor) {
        let ink = PKInk(.pen, color: color.uiColor)
        canvasView.tool = PKInkingTool(ink: ink, width: 2.0)
    }
    
    private func saveDrawing() {
        let drawing = canvasView.drawing
        let data = drawing.dataRepresentation()
        onSave(data.isEmpty ? nil : data, canvasHeight, selectedColor)
        dismiss()
    }
}

// MARK: - Drawing Canvas View
struct DrawingCanvasView: UIViewRepresentable {
    @Binding var canvasView: PKCanvasView
    @Binding var drawingData: Data?
    @Binding var canvasHeight: CGFloat
    @Binding var selectedColor: DrawingColor
    
    func makeUIView(context: Context) -> PKCanvasView {
        canvasView.drawingPolicy = .anyInput
        canvasView.backgroundColor = UIColor.systemBackground
        
        // Load existing drawing if available
        if let data = drawingData,
           let drawing = try? PKDrawing(data: data) {
            canvasView.drawing = drawing
        }
        
        // Set initial tool
        let ink = PKInk(.pen, color: selectedColor.uiColor)
        canvasView.tool = PKInkingTool(ink: ink, width: 2.0)
        
        // Add resize gesture
        let resizeGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleResize(_:)))
        canvasView.addGestureRecognizer(resizeGesture)
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        // Update tool color when selected color changes
        let ink = PKInk(.pen, color: selectedColor.uiColor)
        uiView.tool = PKInkingTool(ink: ink, width: 2.0)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(canvasHeight: $canvasHeight)
    }
    
    class Coordinator: NSObject {
        @Binding var canvasHeight: CGFloat
        
        init(canvasHeight: Binding<CGFloat>) {
            self._canvasHeight = canvasHeight
        }
        
        @objc func handleResize(_ gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            
            if gesture.state == .changed {
                let newHeight = max(80, canvasHeight + translation.y)
                canvasHeight = min(400, newHeight) // Max height limit
                gesture.setTranslation(.zero, in: gesture.view)
            }
        }
    }
}

// MARK: - Color Picker Toolbar
struct ColorPickerToolbar: View {
    @Binding var selectedColor: DrawingColor
    @Binding var canvasHeight: CGFloat
    let onColorSelected: (DrawingColor) -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            Text("Color:")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            
            HStack(spacing: 12) {
                ForEach(DrawingColor.allCases, id: \.rawValue) { color in
                    Button(action: {
                        selectedColor = color
                        onColorSelected(color)
                    }) {
                        Circle()
                            .fill(color.color)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(Color.primary, lineWidth: selectedColor == color ? 2 : 0)
                            )
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 1)
                            )
                    }
                }
            }
            
            Spacer()
            
            // Height indicator
            Text("Height: \(Int(canvasHeight))pt")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Drawing Options Menu
struct DrawingOptionsMenu: View {
    let attachment: DrawingTextAttachment
    @State private var showingEditor = false
    @State private var showingDeleteConfirmation = false
    
    var onUpdate: (DrawingTextAttachment) -> Void
    var onDelete: (DrawingTextAttachment) -> Void
    
    var body: some View {
        Menu {
            Button(action: { showingEditor = true }) {
                Label("Edit Drawing", systemImage: "pencil")
            }
            
            Button(action: { showingDeleteConfirmation = true }) {
                Label("Delete Drawing", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .foregroundColor(.gray)
                .font(.system(size: 16))
        }
        .sheet(isPresented: $showingEditor) {
            DrawingEditorView(
                drawingData: .constant(attachment.drawingData),
                canvasHeight: .constant(attachment.canvasHeight),
                selectedColor: .constant(attachment.selectedColor),
                onSave: { data, height, color in
                    attachment.drawingData = data
                    attachment.canvasHeight = height
                    attachment.selectedColor = color
                    onUpdate(attachment)
                },
                onDelete: {
                    onDelete(attachment)
                }
            )
        }
        .alert("Delete Drawing", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                onDelete(attachment)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This action cannot be undone.")
        }
    }
}

// MARK: - Drawing Tap Handler
/// Extension to handle drawing attachment taps
extension DrawingTextAttachment {
    
    /// Set up tap handlers for editing and options
    func setupTapHandlers(in textView: UITextView, at range: NSRange) {
        self.onEditDrawing = { [weak textView] attachment in
            guard let textView = textView else { return }
            
            // Present drawing editor
            if let viewController = textView.findViewController() {
                let editorView = DrawingEditorView(
                    drawingData: .constant(attachment.drawingData),
                    canvasHeight: .constant(attachment.canvasHeight),
                    selectedColor: .constant(attachment.selectedColor),
                    onSave: { data, height, color in
                        attachment.drawingData = data
                        attachment.canvasHeight = height
                        attachment.selectedColor = color
                        
                        // Force text view to update
                        textView.setNeedsDisplay()
                        textView.delegate?.textViewDidChange?(textView)
                    },
                    onDelete: {
                        // Remove the drawing attachment
                        if let mutableText = textView.attributedText?.mutableCopy() as? NSMutableAttributedString {
                            mutableText.removeAttribute(.attachment, range: range)
                            mutableText.replaceCharacters(in: range, with: NSAttributedString(string: ""))
                            textView.attributedText = mutableText
                            textView.delegate?.textViewDidChange?(textView)
                        }
                    }
                )
                
                let hostingController = UIHostingController(rootView: editorView)
                viewController.present(hostingController, animated: true)
            }
        }
    }
}

// MARK: - UIView Extension
extension UIView {
    func findViewController() -> UIViewController? {
        if let nextResponder = self.next as? UIViewController {
            return nextResponder
        } else if let nextResponder = self.next as? UIView {
            return nextResponder.findViewController()
        } else {
            return nil
        }
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
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
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}