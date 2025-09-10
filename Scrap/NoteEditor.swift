import SwiftUI

// MARK: - Simple Note Editor (replaces both NoteEditView and NavigationNoteEditView)
struct NoteEditor: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedText: String
    @State private var editedTitle: String
    @State private var selectedCategories: [String]
    @FocusState private var isTextFocused: Bool
    @State private var showingOptions = false
    @State private var showingDelete = false
    
    init(item: SparkItem, dataManager: FirebaseDataManager) {
        self.item = item
        self.dataManager = dataManager
        self._editedText = State(initialValue: item.content)
        self._editedTitle = State(initialValue: item.title)
        self._selectedCategories = State(initialValue: item.categoryIds)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title field
            TextField("Title (optional)", text: $editedTitle)
                .font(GentleLightning.Typography.title)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .onChange(of: editedTitle) { updateTitle($0) }
            
            Divider()
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            
            // Content editor
            TextEditor(text: $editedText)
                .font(GentleLightning.Typography.bodyInput)
                .foregroundColor(GentleLightning.Colors.textPrimary)
                .padding(.horizontal, 16)
                .focused($isTextFocused)
                .onChange(of: editedText) { updateContent($0) }
            
            Divider()
            
            // Category picker
            CategoryPicker(selectedCategoryIds: $selectedCategories, maxSelections: 3)
                .padding(16)
                .onChange(of: selectedCategories) { updateCategories($0) }
        }
        // .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Options") { showingOptions = true }
            }
        }
        .confirmationDialog("Note Options", isPresented: $showingOptions) {
            Button("Share") { shareNote() }
            Button("Delete", role: .destructive) { showingDelete = true }
            Button("Cancel", role: .cancel) { }
        }
        .alert("Delete Note?", isPresented: $showingDelete) {
            Button("Delete", role: .destructive) { deleteNote() }
            Button("Cancel", role: .cancel) { }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTextFocused = true
            }
        }
    }
    
    // MARK: - Actions
    
    private func updateTitle(_ newTitle: String) {
        item.title = newTitle
        if let firebaseId = item.firebaseId {
            Task {
                try? await dataManager.firebaseManager.updateNoteTitle(noteId: firebaseId, title: newTitle)
            }
        }
    }
    
    private func updateContent(_ newContent: String) {
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        dataManager.updateItem(item, newContent: trimmed)
    }
    
    private func updateCategories(_ categoryIds: [String]) {
        item.categoryIds = categoryIds
        if let firebaseId = item.firebaseId {
            Task {
                try? await dataManager.firebaseManager.updateNoteCategories(noteId: firebaseId, categoryIds: categoryIds)
                for categoryId in categoryIds {
                    await CategoryService.shared.updateCategoryUsage(categoryId)
                }
            }
        }
    }
    
    private func shareNote() {
        let shareText = item.title.isEmpty ? item.content : "\(item.title)\n\n\(item.content)"
        let activityController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
    }
    
    private func deleteNote() {
        dataManager.deleteItem(item)
        dismiss()
    }
}