import SwiftUI
import Foundation
import Combine
import NaturalLanguage
import UIKit
import Speech
import AVFoundation

// MARK: - Gentle Lightning Design System
struct GentleLightning {
    struct Colors {
        static let background = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let shadowLight = Color.black.opacity(0.03)
    }
    
    struct Typography {
        // HEADINGS / TITLES → SharpGrotesk-Medium (sometimes SemiBold for emphasis)
        static let hero = Font.custom("SharpGrotesk-SemiBold", size: 34)
        static let title = Font.custom("SharpGrotesk-Medium", size: 20)
        static let titleEmphasis = Font.custom("SharpGrotesk-SemiBold", size: 20)
        static let subtitle = Font.custom("SharpGrotesk-Medium", size: 18)
        static let heading = Font.custom("SharpGrotesk-Medium", size: 16)
        
        // BODY TEXT → SharpGrotesk-Book (regular reading weight)
        static let body = Font.custom("SharpGrotesk-Book", size: 16)
        static let bodyInput = Font.custom("SharpGrotesk-Book", size: 17)
        static let bodyLarge = Font.custom("SharpGrotesk-Book", size: 18)
        
        // SECONDARY / SUBTLE TEXT → SharpGrotesk-Light
        static let caption = Font.custom("SharpGrotesk-Light", size: 13)
        static let small = Font.custom("SharpGrotesk-Light", size: 11)
        static let secondary = Font.custom("SharpGrotesk-Light", size: 14)
        static let metadata = Font.custom("SharpGrotesk-Light", size: 12)
        
        // ITALIC VARIANTS
        static let bodyItalic = Font.custom("SharpGrotesk-BookItalic", size: 16)
        static let titleItalic = Font.custom("SharpGrotesk-MediumItalic", size: 20)
        static let secondaryItalic = Font.custom("SharpGrotesk-LightItalic", size: 14)
    }
    
    struct Layout {
        struct Padding {
            static let lg: CGFloat = 16
            static let xl: CGFloat = 20
        }
        struct Radius {
            static let medium: CGFloat = 12
            static let large: CGFloat = 16
        }
    }
    
    struct Animation {
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let elastic = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6)
    }
}

// MARK: - Main App View
struct MainApp: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var voiceRecorder = VoiceRecorder()
    @State private var navigationPath = NavigationPath()
    @State private var inputText = ""
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 20) {
                // Header
                Text("Scrap")
                    .font(GentleLightning.Typography.hero)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                
                // Input field
                InputField(
                    text: $inputText,
                    voiceRecorder: voiceRecorder,
                    onSave: { text in
                        dataManager.createItem(from: text, creationType: "text")
                        inputText = ""
                    },
                    onVoiceNote: { text in
                        dataManager.createItem(from: text, creationType: "voice")
                    }
                )
                
                // Notes list
                if dataManager.items.isEmpty {
                    EmptyState()
                } else {
                    ScrollView {
                        NoteList(dataManager: dataManager, navigationPath: $navigationPath)
                            .padding(.horizontal, 16)
                    }
                }
                
                Spacer()
            }
            .padding(.top, 20)
            .background(GentleLightning.Colors.background)
            .navigationDestination(for: SparkItem.self) { item in
                NoteEditor(item: item, dataManager: dataManager)
            }
        }
    }
}

// MARK: - Empty State
struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("No notes yet")
                .font(GentleLightning.Typography.title)
                .foregroundColor(GentleLightning.Colors.textSecondary)
            
            Text("Start by typing a note or recording a voice memo")
                .font(GentleLightning.Typography.secondary)
                .foregroundColor(GentleLightning.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    @ObservedObject var voiceRecorder: VoiceRecorder
    let onSave: (String) -> Void
    let onVoiceNote: (String) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Add a note...", text: $text)
                .font(GentleLightning.Typography.bodyInput)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(20)
                .onSubmit {
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSave(text)
                    }
                }
            
            // Voice/Save button
            Button(action: handleButtonTap) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(buttonColor)
                        .frame(width: buttonWidth, height: 44)
                    
                    if voiceRecorder.isRecording {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC")
                                .font(GentleLightning.Typography.small)
                                .foregroundColor(.white)
                        }
                    } else if hasText {
                        Text("SAVE")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(.white)
                    } else {
                        Image(systemName: "mic.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 18))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .onChange(of: voiceRecorder.transcribedText) { transcription in
            if !transcription.isEmpty {
                onVoiceNote(transcription)
            }
        }
    }
    
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var buttonWidth: CGFloat {
        hasText && !voiceRecorder.isRecording ? 80 : 44
    }
    
    private var buttonColor: Color {
        voiceRecorder.isRecording ? Color.red : GentleLightning.Colors.accentNeutral
    }
    
    private func handleButtonTap() {
        if hasText && !voiceRecorder.isRecording {
            onSave(text)
        } else {
            voiceRecorder.toggleRecording()
        }
    }
}

// MARK: - Simple Firebase Data Manager
class FirebaseDataManager: ObservableObject {
    @Published var items: [SparkItem] = []
    @Published var isLoading = false
    
    let firebaseManager = FirebaseManager.shared
    
    init() {
        startListening()
    }
    
    func createItem(from text: String, creationType: String = "text") {
        // Create RTF document from the start
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "SharpGrotesk-Book", size: 17) ?? UIFont.systemFont(ofSize: 17),
            .foregroundColor: UIColor.black
        ]
        let attributedText = NSAttributedString(string: text, attributes: attributes)
        
        // Convert to RTF data
        var rtfData: Data? = nil
        do {
            rtfData = try attributedText.data(
                from: NSRange(location: 0, length: attributedText.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
        } catch {
            print("❌ Failed to create RTF data: \(error)")
        }
        
        let newItem = SparkItem(content: text, isTask: false)
        newItem.rtfData = rtfData
        
        withAnimation(GentleLightning.Animation.elastic) {
            items.insert(newItem, at: 0)
        }
        
        Task {
            do {
                // Generate title
                var title: String? = nil
                do {
                    title = try await OpenAITitleService.shared.generateTitle(for: text)
                } catch {
                    print("Title generation failed: \(error)")
                }
                
                // Create note with RTF content from the start
                let firebaseId = try await firebaseManager.createNote(
                    content: text,
                    title: title,
                    categoryIds: [],
                    isTask: false,
                    categories: [],
                    creationType: creationType,
                    rtfData: rtfData
                )
                
                await MainActor.run {
                    newItem.firebaseId = firebaseId
                    newItem.title = title ?? ""
                }
            } catch {
                print("Failed to save note: \(error)")
            }
        }
    }
    
    func updateItem(_ item: SparkItem, newContent: String) {
        item.content = newContent
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.updateNote(noteId: firebaseId, newContent: newContent)
            }
        }
    }
    
    func updateItemWithRTF(_ item: SparkItem, rtfData: Data) {
        // Store RTF data in the item for persistence
        item.rtfData = rtfData
        
        // Extract plain text from RTF for local display/search, but only if needed
        // Don't update item.content during active editing to prevent formatting loss
        if !item.content.isEmpty {
            do {
                let attributedString = try NSAttributedString(
                    data: rtfData,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                )
                // Only update if the plain text content has actually changed significantly
                let plainText = attributedString.string
                if abs(plainText.count - item.content.count) > 5 || !plainText.contains(item.content.prefix(10)) {
                    print("💾 updateItemWithRTF: Significant content change, updating item.content")
                    item.content = plainText
                } else {
                    print("💾 updateItemWithRTF: Minor changes, preserving existing item.content to prevent sync issues")
                }
            } catch {
                print("❌ Failed to extract plain text from RTF: \(error)")
            }
        }
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.updateNoteWithRTF(noteId: firebaseId, rtfData: rtfData)
            }
        }
    }
    
    func deleteItem(_ item: SparkItem) {
        withAnimation(GentleLightning.Animation.gentle) {
            items.removeAll { $0.id == item.id }
        }
        
        if let firebaseId = item.firebaseId {
            Task {
                try? await firebaseManager.deleteNote(noteId: firebaseId)
            }
        }
    }
    
    private func startListening() {
        firebaseManager.startListening { [weak self] firebaseNotes in
            let sparkItems = firebaseNotes.map(SparkItem.init)
            self?.items = sparkItems
        }
    }
}