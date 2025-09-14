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
        // HEADINGS / TITLES → SpaceGrotesk-SemiBold/Bold for emphasis
        static let hero = Font.custom("SpaceGrotesk-Bold", size: 34)               // Large hero titles
        static let title = Font.custom("SpaceGrotesk-Medium", size: 20)            // Standard titles/headings
        static let titleEmphasis = Font.custom("SpaceGrotesk-SemiBold", size: 20)  // Emphasized titles
        static let subtitle = Font.custom("SpaceGrotesk-Medium", size: 18)         // Subtitles
        static let heading = Font.custom("SpaceGrotesk-Medium", size: 16)          // Section headings
        
        // BODY TEXT → SpaceGrotesk-Regular (regular reading weight)
        static let body = Font.custom("SpaceGrotesk-Regular", size: 16)            // Primary body text
        static let bodyInput = Font.custom("SpaceGrotesk-Regular", size: 17)       // Input fields
        static let bodyLarge = Font.custom("SpaceGrotesk-Regular", size: 18)       // Larger body text
        
        // SECONDARY / SUBTLE TEXT → SpaceGrotesk-Light
        static let caption = Font.custom("SpaceGrotesk-Light", size: 13)           // Subtle captions
        static let small = Font.custom("SpaceGrotesk-Light", size: 11)             // Small subtle text
        static let secondary = Font.custom("SpaceGrotesk-Light", size: 14)         // Secondary information
        static let metadata = Font.custom("SpaceGrotesk-Light", size: 12)          // Timestamps, metadata
        
        // ITALIC VARIANTS - Space Grotesk doesn't have italics, use regular weights
        static let bodyItalic = Font.custom("SpaceGrotesk-Regular", size: 16)      // No italic variant
        static let titleItalic = Font.custom("SpaceGrotesk-Medium", size: 20)      // No italic variant
        static let secondaryItalic = Font.custom("SpaceGrotesk-Light", size: 14)   // No italic variant
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
            .font: UIFont(name: "SpaceGrotesk-Regular", size: 17) ?? UIFont.systemFont(ofSize: 17),
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
                    title = try await OpenAIService.shared.generateTitle(for: text)
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
    
    func createItemFromAttributedText(_ attributedText: NSAttributedString, creationType: String = "rich_text") {
        print("📝 Creating item from NSAttributedString with \(attributedText.length) characters")
        
        // Convert attributed text to RTF data for storage
        var rtfData: Data? = nil
        do {
            rtfData = try attributedText.data(
                from: NSRange(location: 0, length: attributedText.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            print("✅ Successfully created RTF data (\(rtfData?.count ?? 0) bytes)")
        } catch {
            print("❌ Failed to create RTF data: \(error)")
        }
        
        // Extract plain text for display and search
        let plainText = attributedText.string
        
        // Create new item with plain text content and RTF data
        let newItem = SparkItem(content: plainText, isTask: false)
        newItem.rtfData = rtfData
        
        withAnimation(GentleLightning.Animation.elastic) {
            items.insert(newItem, at: 0)
        }
        
        Task {
            do {
                // Generate title from plain text
                var title: String? = nil
                do {
                    title = try await OpenAIService.shared.generateTitle(for: plainText)
                    print("📝 Generated title: '\(title ?? "nil")'")
                } catch {
                    print("Title generation failed: \(error)")
                }
                
                // Create note with RTF content
                let firebaseId = try await firebaseManager.createNote(
                    content: plainText,
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
                
                print("✅ Successfully saved formatted note to Firebase")
            } catch {
                print("❌ Failed to save note: \(error)")
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
        
        // Always extract plain text from RTF for local display/search to prevent showing raw RTF
        do {
            let attributedString = try NSAttributedString(
                data: rtfData,
                options: [.documentType: NSAttributedString.DocumentType.rtf],
                documentAttributes: nil
            )
            let plainText = attributedString.string
            print("💾 updateItemWithRTF: Extracted plain text (\(plainText.count) chars): '\(plainText.prefix(100))...'")
            item.content = plainText
        } catch {
            print("❌ Failed to extract plain text from RTF: \(error)")
            // Don't update content if RTF extraction fails to preserve existing content
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
            
            // Index existing notes for vector search
            Task {
                do {
                    // Test connection first
                    let isConnected = try await VectorSearchService.shared.testConnection()
                    if isConnected {
                        print("🔍 ChromaDB connection successful, indexing \(firebaseNotes.count) existing notes...")
                        await VectorSearchService.shared.reindexAllNotes(firebaseNotes)
                    } else {
                        print("⚠️ ChromaDB connection failed, vector search will not be available")
                    }
                } catch {
                    print("⚠️ Failed to test ChromaDB connection or index notes: \(error)")
                }
            }
        }
    }
}