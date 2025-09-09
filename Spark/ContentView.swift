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
        static let hero = Font.custom("Satoshi-Bold", size: 34)
        static let body = Font.custom("Satoshi-Regular", size: 17)
        static let bodyInput = Font.custom("Satoshi-Regular", size: 18)
        static let title = Font.custom("Satoshi-Medium", size: 20)
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
        let isTask = text.lowercased().contains("todo") || 
                    text.lowercased().contains("task") || 
                    text.lowercased().contains("remind") ||
                    text.lowercased().contains("call") ||
                    text.lowercased().contains("buy")
        
        // Create optimistic local item
        let newItem = SparkItem(content: text, isTask: isTask)
        items.insert(newItem, at: 0)
        
        // Save to Firebase
        Task {
            do {
                let categories = await categorizeText(text)
                let firebaseId = try await firebaseManager.createNote(
                    content: text, 
                    isTask: isTask, 
                    categories: categories
                )
                
                DispatchQueue.main.async {
                    newItem.firebaseId = firebaseId
                }
                
                // TODO: Save to Pinecone for vector search
                
            } catch {
                DispatchQueue.main.async {
                    // Remove optimistic item on error
                    self.items.removeAll { $0.id == newItem.id }
                    self.error = "Failed to save note: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func toggleComplete(_ item: SparkItem) {
        item.isCompleted.toggle()
        
        // Track item completion
        if item.isCompleted {
            AnalyticsManager.shared.trackItemCompleted(isTask: item.isTask)
        }
        
        // TODO: Update completion status in Firebase when we add that field
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
                    DispatchQueue.main.async {
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
    @Published var placeholderText = "What's on your mind?"
    @Published var showingAllNotes = false
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        isFieldFocused = true
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
        .background(
            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                .fill(GentleLightning.Colors.surface)
                .shadow(color: GentleLightning.Colors.shadowLight, radius: 10, x: 0, y: 4)
        )
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
            if item.isTask {
                Button {
                    withAnimation(GentleLightning.Animation.elastic) {
                        dataManager.toggleComplete(item)
                    }
                    GentleLightning.Sound.Haptic.swoosh.trigger()
                } label: {
                    Circle()
                        .stroke(item.isCompleted ? GentleLightning.Context.accentColor(isTask: item.isTask) : GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 2)
                        .background(
                            Circle()
                                .fill(item.isCompleted ? GentleLightning.Context.accentColor(isTask: item.isTask) : Color.clear)
                        )
                        .overlay(
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .scaleEffect(item.isCompleted ? 1 : 0.001)
                                .opacity(item.isCompleted ? 1 : 0)
                        )
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Circle()
                    .fill(GentleLightning.Context.accentColor(isTask: item.isTask).opacity(0.2))
                    .frame(width: 6, height: 6)
                    .padding(.horizontal, 8)
            }
            
            Text(item.wrappedContent)
                .font(GentleLightning.Typography.body)
                .foregroundColor(item.isCompleted ? GentleLightning.Colors.textSecondary : GentleLightning.Colors.textPrimary)
                .strikethrough(item.isCompleted, color: GentleLightning.Colors.textSecondary)
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
                // Header
                HStack {
                    Text("Spark")
                        .font(GentleLightning.Typography.hero)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Subtle "view all notes" toggle
                        if !dataManager.items.isEmpty {
                        Button(action: {
                            withAnimation(GentleLightning.Animation.gentle) {
                                viewModel.showingAllNotes.toggle()
                            }
                            AnalyticsManager.shared.trackEvent("notes_view_toggled", properties: [
                                "showing_all": viewModel.showingAllNotes
                            ])
                        }) {
                            HStack(spacing: 4) {
                                Text(viewModel.showingAllNotes ? "Hide" : "View all")
                                    .font(.custom("Satoshi-Regular", size: 14))
                                    .foregroundColor(GentleLightning.Colors.textSecondary)
                                Image(systemName: viewModel.showingAllNotes ? "eye.slash" : "eye")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(GentleLightning.Colors.accentNeutral.opacity(0.7))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(GentleLightning.Colors.surface.opacity(0.6))
                                    .shadow(color: GentleLightning.Colors.shadowLight, radius: 2, x: 0, y: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.scale.combined(with: .opacity))
                        }
                        
                        // Sign out button
                        Button(action: {
                            do {
                                try FirebaseManager.shared.signOut()
                            } catch {
                                print("Sign out error: \(error)")
                            }
                        }) {
                            Image(systemName: "person.crop.circle")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                .padding(.top, GentleLightning.Layout.Padding.xl)
                .padding(.bottom, GentleLightning.Layout.Padding.lg)
                
                // Input Field
                InputField(text: $viewModel.inputText, 
                          placeholder: viewModel.placeholderText,
                          onCommit: {
                    if !viewModel.inputText.isEmpty {
                        dataManager.createItem(from: viewModel.inputText)
                        viewModel.inputText = ""
                    }
                })
                .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                .padding(.bottom, GentleLightning.Layout.Padding.xl)
                
                // Items List or minimal view
                if viewModel.showingAllNotes {
                    ScrollView {
                        LazyVStack(spacing: GentleLightning.Layout.Spacing.comfortable) {
                            if dataManager.items.isEmpty {
                                EmptyStateView()
                                    .padding(.top, 60)
                            } else {
                                ForEach(dataManager.items) { item in
                                    ItemRowSimple(item: item, dataManager: dataManager)
                                        .transition(.asymmetric(
                                            insertion: .move(edge: .top).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)
                                        ))
                                }
                            }
                        }
                        .padding(.horizontal, GentleLightning.Layout.Padding.xl)
                        .padding(.bottom, GentleLightning.Layout.Padding.xl)
                    }
                } else {
                    // Show only recent items (last 3) in minimal mode
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
                                            .font(.custom("Satoshi-Regular", size: 12))
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
                
                Spacer()
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