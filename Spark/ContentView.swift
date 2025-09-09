import SwiftUI
import Foundation
import Combine
import NaturalLanguage
import UIKit

// MARK: - Gentle Lightning Design System
struct GentleLightning {
    struct Colors {
        static let background = Color.white
        static let backgroundWarm = Color.white
        static let surface = Color.white
        static let textPrimary = Color(red: 0.12, green: 0.12, blue: 0.15)
        static let textSecondary = Color(red: 0.45, green: 0.45, blue: 0.5)
        static let accentIdea = Color(red: 1.0, green: 0.85, blue: 0.4)
        static let accentTask = Color(red: 0.4, green: 0.65, blue: 1.0)
        static let accentNeutral = Color(red: 0.65, green: 0.7, blue: 1.0)
        static let shadowLight = Color.black.opacity(0.03)
    }
    
    struct Typography {
        static let hero = Font.custom("Hadley", size: 36)
        static let body = Font.custom("Hadley", size: 17)
        static let bodyInput = Font.custom("Hadley", size: 18)
        static let title = Font.custom("Hadley", size: 22)
        static let caption = Font.custom("Hadley", size: 14)
        static let small = Font.custom("Hadley", size: 12)
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
        struct Spacing {
            static let comfortable: CGFloat = 12
        }
    }
    
    struct Animation {
        static let gentle = SwiftUI.Animation.easeInOut(duration: 0.4)
        static let elastic = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.6)
        static let swoosh = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
    }
    
    struct Sound {
        enum Haptic {
            case swoosh
            
            func trigger() {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }
    }
    
    struct Context {
        static func accentColor(isTask: Bool) -> Color {
            return isTask ? Colors.accentTask : Colors.accentIdea
        }
        
        static func backgroundWarmth(isActive: Bool) -> Color {
            return isActive ? Colors.backgroundWarm : Colors.background
        }
    }
}

// MARK: - Simple Item Model (Compatible with Firebase)
class SparkItem: ObservableObject, Identifiable {
    let id: String
    @Published var content: String
    @Published var isTask: Bool
    @Published var isCompleted: Bool
    let createdAt: Date
    var firebaseId: String?
    
    var wrappedContent: String { content }
    
    init(content: String, isTask: Bool = false, id: String = UUID().uuidString) {
        self.id = id
        self.content = content
        self.isTask = isTask
        self.isCompleted = false
        self.createdAt = Date()
    }
    
    // Initialize from Firebase note
    init(from firebaseNote: FirebaseNote) {
        self.id = firebaseNote.id ?? UUID().uuidString
        self.content = firebaseNote.content
        self.isTask = firebaseNote.isTask
        self.isCompleted = false // Firebase notes don't have completion status yet
        self.createdAt = firebaseNote.createdAt
        self.firebaseId = firebaseNote.id
    }
}

// MARK: - Firebase Data Manager
class FirebaseDataManager: ObservableObject {
    @Published var items: [SparkItem] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let firebaseManager = FirebaseManager.shared
    
    init() {
        // Start listening for data when manager is created
        Task {
            await startListening()
        }
    }
    
    private func startListening() async {
        firebaseManager.startListening { [weak self] firebaseNotes in
            let sparkItems = firebaseNotes.map { SparkItem(from: $0) }
            self?.items = sparkItems
        }
    }
    
    func createItem(from text: String) {
        // Create optimistic local item - always a note, never a task
        let newItem = SparkItem(content: text, isTask: false)
        items.insert(newItem, at: 0)
        
        // Save to Firebase
        Task {
            do {
                let categories = await categorizeText(text)
                let firebaseId = try await firebaseManager.createNote(
                    content: text, 
                    isTask: false, 
                    categories: categories
                )
                
                await MainActor.run {
                    newItem.firebaseId = firebaseId
                }
                
                // TODO: Save to Pinecone for vector search
                
            } catch {
                await MainActor.run {
                    // Remove optimistic item on error
                    self.items.removeAll { $0.id == newItem.id }
                    self.error = "Failed to save note: \(error.localizedDescription)"
                }
            }
        }
    }
    
    
    func deleteItem(_ item: SparkItem) {
        // Track item deletion before removing
        AnalyticsManager.shared.trackItemDeleted(isTask: item.isTask)
        
        // Remove from local array immediately (optimistic)
        items.removeAll { $0.id == item.id }
        
        // Delete from Firebase
        if let firebaseId = item.firebaseId {
            Task {
                do {
                    try await firebaseManager.deleteNote(noteId: firebaseId)
                } catch {
                    await MainActor.run {
                        self.error = "Failed to delete note: \(error.localizedDescription)"
                        // Re-add the item since deletion failed
                        self.items.insert(item, at: 0)
                    }
                }
            }
        }
    }
    
    // Simple categorization (will be enhanced with AI later)
    private func categorizeText(_ text: String) async -> [String] {
        var categories: [String] = []
        
        if text.lowercased().contains("work") || text.lowercased().contains("meeting") {
            categories.append("work")
        }
        if text.lowercased().contains("personal") || text.lowercased().contains("family") {
            categories.append("personal")
        }
        if text.lowercased().contains("todo") || text.lowercased().contains("task") {
            categories.append("task")
        }
        
        return categories.isEmpty ? ["general"] : categories
    }
}

// MARK: - Content View Model
class ContentViewModel: ObservableObject {
    @Published var inputText = ""
    @Published var placeholderText = "Just start typing..."
}

// MARK: - Input Field
struct InputField: View {
    @Binding var text: String
    let placeholder: String
    let onCommit: () -> Void
    @FocusState var isFieldFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField(placeholder, text: $text)
                .font(GentleLightning.Typography.bodyInput)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .submitLabel(.done)
                .onSubmit(onCommit)
                .focused($isFieldFocused)
                .onAppear {
                    // Auto-focus on appear
                    Task {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                        await MainActor.run {
                            isFieldFocused = true
                        }
                    }
                }
            
            // Simple microphone button (for now)
            Button(action: {
                GentleLightning.Sound.Haptic.swoosh.trigger()
                // Track microphone button tap
                AnalyticsManager.shared.trackEvent("mic_button_tapped")
            }) {
                Image(systemName: "mic.circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, GentleLightning.Layout.Padding.lg)
        .padding(.vertical, GentleLightning.Layout.Padding.lg)
        .background(Color.white)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    var body: some View {
        // Completely empty state - no visual elements
        EmptyView()
    }
}

// MARK: - Item Row
struct ItemRowSimple: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Simple bullet point for notes
            Circle()
                .fill(GentleLightning.Colors.accentIdea.opacity(0.3))
                .frame(width: 6, height: 6)
                .padding(.horizontal, 8)
            
            Text(item.wrappedContent)
                .font(GentleLightning.Typography.body)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .lineLimit(nil)
                .multilineTextAlignment(.leading)
            
            Spacer()
        }
        .padding(.horizontal, GentleLightning.Layout.Padding.lg)
        .padding(.vertical, GentleLightning.Layout.Padding.lg)
        .background(
            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                .fill(GentleLightning.Colors.surface)
                .shadow(color: GentleLightning.Colors.shadowLight, radius: 8, x: 0, y: 2)
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") {
                withAnimation(GentleLightning.Animation.gentle) {
                    dataManager.deleteItem(item)
                }
            }
            .tint(.red)
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @StateObject private var dataManager = FirebaseDataManager()
    @StateObject private var viewModel = ContentViewModel()
    
    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header - empty for clean design
                HStack {
                    // Empty header for clean design
                }
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                .padding(.top, GentleLightning.Layout.Padding.xl)
                .padding(.bottom, GentleLightning.Layout.Padding.lg)
                
                // Large spacer to push input field lower
                Spacer()
                Spacer()
                
                // Input Field - positioned lower on screen
                InputField(text: $viewModel.inputText, 
                          placeholder: viewModel.placeholderText,
                          onCommit: {
                    if !viewModel.inputText.isEmpty {
                        dataManager.createItem(from: viewModel.inputText)
                        viewModel.inputText = ""
                    }
                })
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                
                // Smaller spacer below
                Spacer()
                    .frame(maxHeight: 100)
                
                // Items List - always show recent items (last 3)
                ScrollView {
                    LazyVStack(spacing: GentleLightning.Layout.Spacing.comfortable) {
                        if dataManager.items.isEmpty {
                            EmptyStateView()
                                .padding(.top, 60)
                        } else {
                            ForEach(Array(dataManager.items.prefix(3))) { item in
                                ItemRowSimple(item: item, dataManager: dataManager)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)
                                    ))
                            }
                            
                            if dataManager.items.count > 3 {
                                HStack {
                                    Spacer()
                                    Text("\(dataManager.items.count - 3) more notes")
                                        .font(GentleLightning.Typography.small)
                                        .foregroundColor(GentleLightning.Colors.textSecondary.opacity(0.6))
                                    Spacer()
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                    .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                    .padding(.bottom, GentleLightning.Layout.Padding.xl)
                }
            }
            
            // Logout button positioned at bottom of screen, behind keyboard
            VStack {
                Spacer()
                
                Button(action: {
                    do {
                        try FirebaseManager.shared.signOut()
                    } catch {
                        print("Sign out error: \(error)")
                    }
                }) {
                    Text("Logout")
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 24)
                }
                .buttonStyle(PlainButtonStyle())
                .padding(.bottom, 50) // Position behind keyboard area
            }
        }
    }
}

// MARK: - Preview
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}