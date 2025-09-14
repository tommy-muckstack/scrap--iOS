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
    @State private var showingCategoryManager = false
    @State private var userCategories: [Category] = []
    @State private var isLoadingCategories = false
    
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
            
            // Simple tags display
            if !selectedCategories.isEmpty {
                HStack {
                    Text("Tags:")
                        .font(GentleLightning.Typography.caption)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                    
                    // Simple text list of tag names
                    Text(userCategories.filter { category in
                        selectedCategories.contains(category.firebaseId ?? category.id)
                    }.map { $0.name }.joined(separator: ", "))
                        .font(GentleLightning.Typography.caption)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
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
            Button("Add Tag") { 
                showingCategoryManager = true 
                loadCategories()
            }
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
        .sheet(isPresented: $showingCategoryManager) {
            CategoryManagerView(
                item: item, 
                selectedCategories: $selectedCategories,
                userCategories: $userCategories,
                onCategoryUpdate: { categoryIds in
                    updateCategories(categoryIds)
                }
            )
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(GentleLightning.Animation.swoosh) {
                    isTextFocused = true
                }
            }
            loadCategories()
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
    
    private func loadCategories() {
        isLoadingCategories = true
        Task {
            do {
                let categories = try await CategoryService.shared.getUserCategories()
                await MainActor.run {
                    userCategories = categories
                    isLoadingCategories = false
                }
            } catch {
                await MainActor.run {
                    isLoadingCategories = false
                }
                print("Failed to load categories: \(error)")
            }
        }
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

// MARK: - Category Manager View
struct CategoryManagerView: View {
    let item: SparkItem
    @Binding var selectedCategories: [String]
    @Binding var userCategories: [Category]
    let onCategoryUpdate: ([String]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var showingCreateCategory = false
    @State private var newCategoryName = ""
    @State private var selectedColorKey = ""
    @State private var availableColors: [(key: String, hex: String, name: String)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Manage Categories")
                        .font(GentleLightning.Typography.title)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    Text("\(userCategories.count)/5 categories used")
                        .font(GentleLightning.Typography.caption)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                // Existing Categories
                if userCategories.isEmpty {
                    VStack(spacing: 12) {
                        Text("No categories yet")
                            .font(GentleLightning.Typography.subtitle)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Text("Create your first category to organize your notes")
                            .font(GentleLightning.Typography.secondary)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(40)
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(userCategories) { category in
                                CategoryCard(
                                    category: category,
                                    isSelected: selectedCategories.contains(category.firebaseId ?? category.id),
                                    onToggle: { toggleCategory(category) }
                                )
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                }
                
                Spacer()
                
                // Create Category Button
                if userCategories.count < 5 {
                    Button(action: { 
                        loadAvailableColors()
                        showingCreateCategory = true 
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                            Text("Create New Category")
                                .font(GentleLightning.Typography.body)
                        }
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(GentleLightning.Colors.accentNeutral)
                        .cornerRadius(12)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Categories")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
            .sheet(isPresented: $showingCreateCategory) {
                CreateCategoryView(
                    categoryName: $newCategoryName,
                    selectedColorKey: $selectedColorKey,
                    availableColors: availableColors,
                    onCreate: { name, colorKey in
                        createCategory(name: name, colorKey: colorKey)
                    }
                )
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
        }
    }
    
    private func toggleCategory(_ category: Category) {
        let categoryId = category.firebaseId ?? category.id
        
        if selectedCategories.contains(categoryId) {
            selectedCategories.removeAll { $0 == categoryId }
        } else {
            selectedCategories.append(categoryId)
        }
        
        onCategoryUpdate(selectedCategories)
    }
    
    private func loadAvailableColors() {
        Task {
            do {
                let colors = try await CategoryService.shared.getAvailableColors()
                await MainActor.run {
                    availableColors = colors
                    selectedColorKey = colors.first?.key ?? ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load available colors: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func createCategory(name: String, colorKey: String) {
        isLoading = true
        Task {
            do {
                let newCategory = try await CategoryService.shared.createCustomCategory(name: name, colorKey: colorKey)
                
                await MainActor.run {
                    userCategories.append(newCategory)
                    showingCreateCategory = false
                    newCategoryName = ""
                    selectedColorKey = ""
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Category Card
struct CategoryCard: View {
    let category: Category
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(spacing: 12) {
                // Color circle
                Circle()
                    .fill(category.uiColor)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(.white, lineWidth: isSelected ? 3 : 0)
                    )
                    .overlay(
                        Circle()
                            .stroke(GentleLightning.Colors.accentNeutral, lineWidth: isSelected ? 2 : 0)
                    )
                
                // Category name
                Text(category.name)
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                
                // Usage count
                Text("\(category.usageCount) notes")
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .frame(height: 120)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GentleLightning.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Create Category View
struct CreateCategoryView: View {
    @Binding var categoryName: String
    @Binding var selectedColorKey: String
    let availableColors: [(key: String, hex: String, name: String)]
    let onCreate: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create Category")
                        .font(GentleLightning.Typography.title)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    Text("Choose a name and color for your new category")
                        .font(GentleLightning.Typography.secondary)
                        .foregroundColor(GentleLightning.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                
                // Category Name Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category Name")
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                    
                    TextField("Enter category name", text: $categoryName)
                        .font(GentleLightning.Typography.bodyInput)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .padding(.horizontal, 20)
                
                // Color Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Choose Color")
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(GentleLightning.Colors.textPrimary)
                        .padding(.horizontal, 20)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                        ForEach(availableColors, id: \.key) { colorInfo in
                            Button(action: { selectedColorKey = colorInfo.key }) {
                                VStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: colorInfo.hex) ?? Color.gray)
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Circle()
                                                .stroke(GentleLightning.Colors.accentNeutral, lineWidth: selectedColorKey == colorInfo.key ? 3 : 0)
                                        )
                                    
                                    Text(colorInfo.name)
                                        .font(GentleLightning.Typography.caption)
                                        .foregroundColor(GentleLightning.Colors.textPrimary)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Create Button
                Button(action: {
                    onCreate(categoryName, selectedColorKey)
                    dismiss()
                }) {
                    Text("Create Category")
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(.white)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity)
                        .background(
                            categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedColorKey.isEmpty
                                ? Color.gray
                                : GentleLightning.Colors.accentNeutral
                        )
                        .cornerRadius(12)
                }
                .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedColorKey.isEmpty)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("New Category")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
    }
}

