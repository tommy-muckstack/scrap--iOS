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
    @State private var showingFormatting = false
    
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
            
            // Content editor with inline formatting button
            VStack(alignment: .leading, spacing: 0) {
                // Inline formatting button at start of content area
                HStack {
                    Button(action: { showingFormatting.toggle() }) {
                        HStack(spacing: 2) {
                            Text("B")
                                .font(.system(size: 14, weight: .bold))
                            Text("7")
                                .font(.system(size: 12))
                                .underline()
                            Text("U")
                                .font(.system(size: 14))
                                .underline()
                        }
                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(GentleLightning.Colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                
                // Text editor
                TextEditor(text: $editedText)
                    .font(GentleLightning.Typography.bodyInput)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .padding(.horizontal, 16)
                    .focused($isTextFocused)
                    .onChange(of: editedText) { updateContent($0) }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if isTextFocused {
                        FormattingToolbar(
                            text: $editedText,
                            showingFormatting: $showingFormatting
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .bottom).combined(with: .opacity).animation(GentleLightning.Animation.swoosh),
                            removal: .move(edge: .bottom).combined(with: .opacity).animation(GentleLightning.Animation.gentle)
                        ))
                    }
                }
            }
            
            Divider()
            
            // Category section (simplified for now)
            HStack {
                Text("Categories:")
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        // .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Options") { showingOptions = true }
                    .font(.system(size: 14))
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
        .sheet(isPresented: $showingFormatting) {
            FormattingSheet(text: $editedText)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(GentleLightning.Animation.swoosh) {
                    isTextFocused = true
                }
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

// MARK: - Formatting Toolbar
struct FormattingToolbar: View {
    @Binding var text: String
    @Binding var showingFormatting: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // Format button (like B7U in your screenshot)
            Button(action: { showingFormatting.toggle() }) {
                HStack(spacing: 2) {
                    Text("B")
                        .font(.system(size: 16, weight: .bold))
                    Text("7")
                        .font(.system(size: 14))
                        .underline()
                    Text("U")
                        .font(.system(size: 16))
                        .underline()
                }
                .foregroundColor(GentleLightning.Colors.accentNeutral)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(GentleLightning.Colors.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                        )
                )
            }
            
            Spacer()
            
            // Done button
            Button("Done") {
                // Dismiss keyboard
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
            .foregroundColor(GentleLightning.Colors.accentNeutral)
        }
        .padding(.horizontal, 16)
        .sheet(isPresented: $showingFormatting) {
            FormattingSheet(text: $text)
        }
    }
}

// MARK: - Formatting Sheet
struct FormattingSheet: View {
    @Binding var text: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Text Formatting")
                    .font(GentleLightning.Typography.title)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .padding(.top, 20)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    FormatButton(title: "Bold", symbol: "bold", action: { applyFormat("**", "**") })
                    FormatButton(title: "Italic", symbol: "italic", action: { applyFormat("*", "*") })
                    FormatButton(title: "Underline", symbol: "underline", action: { applyFormat("<u>", "</u>") })
                    FormatButton(title: "Strikethrough", symbol: "strikethrough", action: { applyFormat("~~", "~~") })
                    FormatButton(title: "Code", symbol: "chevron.left.forwardslash.chevron.right", action: { applyFormat("`", "`") })
                    FormatButton(title: "Quote", symbol: "quote.bubble", action: { applyFormat("> ", "") })
                    FormatButton(title: "Bullet", symbol: "list.bullet", action: { applyFormat("• ", "") })
                    FormatButton(title: "Number", symbol: "list.number", action: { applyFormat("1. ", "") })
                    FormatButton(title: "Header 1", symbol: "textformat.size.larger", action: { applyFormat("# ", "") })
                    FormatButton(title: "Header 2", symbol: "textformat.size", action: { applyFormat("## ", "") })
                    FormatButton(title: "Link", symbol: "link", action: { applyFormat("[", "](url)") })
                    FormatButton(title: "Highlight", symbol: "highlighter", action: { applyFormat("==", "==") })
                }
                .padding(.horizontal, 20)
                
                Spacer()
            }
            .navigationTitle("Formatting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
    
    private func applyFormat(_ prefix: String, _ suffix: String) {
        text += prefix + "text" + suffix
        dismiss()
    }
}

// MARK: - Format Button
struct FormatButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                
                Text(title)
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GentleLightning.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

