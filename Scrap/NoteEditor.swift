import SwiftUI

// MARK: - Simple Note Editor (replaces both NoteEditView and NavigationNoteEditView)
struct NoteEditor: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var editedText: NSAttributedString
    @State private var editedTitle: String
    @State private var selectedCategories: [String]
    @StateObject private var richTextContext = RichTextContext()
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
        self._editedText = State(initialValue: NSAttributedString(string: item.content))
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
            
            // Rich Text editor
            RichTextEditor.forNotes(
                text: $editedText,
                context: richTextContext
            )
            .padding(.horizontal, 16)
            .focused($isTextFocused)
            .onChange(of: editedText) { newValue in
                updateContent(newValue.string)
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
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: GentleLightning.Icons.navigationBack)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingOptions = true }) {
                    VStack(spacing: 2) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 3, height: 3)
                        Circle()
                            .fill(Color.black)
                            .frame(width: 3, height: 3)
                        Circle()
                            .fill(Color.black)
                            .frame(width: 3, height: 3)
                    }
                    .frame(width: 20, height: 20)
                }
            }
            
            // Formatting toolbar above keyboard
            ToolbarItemGroup(placement: .keyboard) {
                RichFormattingToolbar(
                    context: richTextContext,
                    showingFormatting: $showingFormatting
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
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
            RichFormattingSheet(context: richTextContext)
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

// MARK: - Rich Formatting Toolbar
struct RichFormattingToolbar: View {
    @ObservedObject var context: RichTextContext
    @Binding var showingFormatting: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            // Bold button
            Button(action: { context.toggleBold() }) {
                Text("B")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(context.isBoldActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isBoldActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            // Italic button
            Button(action: { context.toggleItalic() }) {
                Text("I")
                    .font(.system(size: 16, weight: .medium))
                    .italic()
                    .foregroundColor(context.isItalicActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isItalicActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            // Strikethrough button
            Button(action: { context.toggleStrikethrough() }) {
                Text("S")
                    .font(.system(size: 16, weight: .medium))
                    .strikethrough()
                    .foregroundColor(context.isStrikethroughActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isStrikethroughActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            // Code button
            Button(action: { context.toggleCodeBlock() }) {
                Text("</>")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(context.isCodeBlockActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isCodeBlockActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            // List button
            Button(action: { context.toggleBulletList() }) {
                Image(systemName: GentleLightning.Icons.formatList)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(context.isBulletListActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isBulletListActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            // Checkbox button
            Button(action: { context.toggleCheckbox() }) {
                Image(systemName: GentleLightning.Icons.formatChecklist)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(context.isCheckboxActive ? .blue : .primary)
                    .frame(width: 40, height: 32)
                    .background(context.isCheckboxActive ? Color.blue.opacity(0.1) : Color.clear)
                    .cornerRadius(6)
            }
            
            Spacer()
            
            // More formats button (chevron down)
            Button(action: { showingFormatting.toggle() }) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(width: 40, height: 32)
                    .background(Color.clear)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(Color(UIColor.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: -1)
        )
        .sheet(isPresented: $showingFormatting) {
            RichFormattingSheet(context: context)
        }
    }
}

// MARK: - Rich Formatting Sheet
struct RichFormattingSheet: View {
    @ObservedObject var context: RichTextContext
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Text Formatting")
                    .font(GentleLightning.Typography.title)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                    .padding(.top, 20)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                    RichFormatButton(title: "Bold", symbol: GentleLightning.Icons.formatBold, action: { context.toggleBold() }, isActive: context.isBoldActive)
                    RichFormatButton(title: "Italic", symbol: GentleLightning.Icons.formatItalic, action: { context.toggleItalic() }, isActive: context.isItalicActive)
                    RichFormatButton(title: "Underline", symbol: "underline", action: { context.toggleUnderline() }, isActive: context.isUnderlineActive)
                    RichFormatButton(title: "Strikethrough", symbol: GentleLightning.Icons.formatStrikethrough, action: { context.toggleStrikethrough() }, isActive: context.isStrikethroughActive)
                    RichFormatButton(title: "Code Block", symbol: GentleLightning.Icons.formatCode, action: { context.toggleCodeBlock() }, isActive: context.isCodeBlockActive)
                    RichFormatButton(title: "Bullet List", symbol: GentleLightning.Icons.formatList, action: { context.toggleBulletList() }, isActive: context.isBulletListActive)
                    RichFormatButton(title: "Checkbox", symbol: GentleLightning.Icons.formatChecklist, action: { context.toggleCheckbox() }, isActive: context.isCheckboxActive)
                    RichFormatButton(title: "Indent In", symbol: "increase.indent", action: { context.indentIn() }, isActive: false)
                    RichFormatButton(title: "Indent Out", symbol: "decrease.indent", action: { context.indentOut() }, isActive: false)
                    RichFormatButton(title: "Undo", symbol: "arrow.uturn.left", action: { context.undo() }, isActive: false)
                    RichFormatButton(title: "Redo", symbol: "arrow.uturn.right", action: { context.redo() }, isActive: false)
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
}

// MARK: - Rich Format Button
struct RichFormatButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    let isActive: Bool
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                    .foregroundColor(isActive ? .blue : GentleLightning.Colors.accentNeutral)
                
                Text(title)
                    .font(GentleLightning.Typography.caption)
                    .foregroundColor(isActive ? .blue : GentleLightning.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.blue.opacity(0.1) : GentleLightning.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isActive ? Color.blue : GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: isActive ? 2 : 1)
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
    @State private var showingCreateForm = false
    @State private var newCategoryName = ""
    @State private var selectedColorKey = ""
    @State private var availableColors: [(key: String, hex: String, name: String)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
            if showingCreateForm {
                // Create Tag Form
                CreateTagInlineView(
                    categoryName: $newCategoryName,
                    selectedColorKey: $selectedColorKey,
                    availableColors: availableColors,
                    onCancel: {
                        showingCreateForm = false
                        newCategoryName = ""
                        selectedColorKey = ""
                    },
                    onCreate: { name, colorKey in
                        createCategory(name: name, colorKey: colorKey)
                    }
                )
            } else {
                // Original content
                VStack(spacing: 20) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Manage Tags")
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                        
                        Text("\(userCategories.count)/5 tags used")
                            .font(GentleLightning.Typography.caption)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    
                    // Existing Categories
                    if userCategories.isEmpty {
                        VStack(spacing: 16) {
                            Text("No tags yet")
                                .font(GentleLightning.Typography.subtitle)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                            
                            Text("Create your first tag to organize your notes")
                                .font(GentleLightning.Typography.secondary)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                            
                            // Create First Tag Button
                            Button(action: { 
                                loadAvailableColors()
                                showingCreateForm = true 
                            }) {
                                HStack {
                                    Image(systemName: GentleLightning.Icons.add)
                                        .font(.system(size: 18))
                                    Text("Create New Tag")
                                        .font(GentleLightning.Typography.body)
                                }
                                .foregroundColor(.white)
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(GentleLightning.Colors.accentNeutral)
                                .cornerRadius(12)
                            }
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
                    
                    // Create Tag Button
                    if userCategories.count < 5 {
                        Button(action: { 
                            loadAvailableColors()
                            showingCreateForm = true 
                        }) {
                            HStack {
                                Image(systemName: GentleLightning.Icons.add)
                                    .font(.system(size: 18))
                                Text("Create New Tag")
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
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                }
            }
            .navigationTitle(showingCreateForm ? "New Tag" : "Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(.black)
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
                    // Reset form but stay in tags view
                    showingCreateForm = false
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

// MARK: - Create Tag Inline View
struct CreateTagInlineView: View {
    @Binding var categoryName: String
    @Binding var selectedColorKey: String
    let availableColors: [(key: String, hex: String, name: String)]
    let onCancel: () -> Void
    let onCreate: (String, String) -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Back button and Header
            HStack {
                Button(action: onCancel) {
                    Image(systemName: GentleLightning.Icons.navigationBack)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                }
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Create Tag")
                    .font(GentleLightning.Typography.title)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                
                Text("Choose a name and color for your new tag")
                    .font(GentleLightning.Typography.secondary)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            
            // Tag Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Tag Name")
                    .font(GentleLightning.Typography.body)
                    .foregroundColor(GentleLightning.Colors.textPrimary)
                
                TextField("Enter tag name", text: $categoryName)
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
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(availableColors, id: \.key) { colorInfo in
                        Button(action: { selectedColorKey = colorInfo.key }) {
                            VStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: colorInfo.hex) ?? Color.gray)
                                    .frame(width: 40, height: 40)
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
            }) {
                Text("Create Tag")
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
    }
}

// MARK: - Formattable Text Editor
struct FormattableTextEditor: UIViewRepresentable {
    @Binding var text: String
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.text = text
        textView.font = UIFont(name: "SpaceGrotesk-Regular", size: 19) ?? UIFont.systemFont(ofSize: 19)
        textView.backgroundColor = .clear
        textView.isEditable = true
        textView.isSelectable = true
        textView.delegate = context.coordinator
        
        // Better text view setup for formatting
        textView.allowsEditingTextAttributes = true
        textView.autocorrectionType = .yes
        textView.autocapitalizationType = .sentences
        textView.spellCheckingType = .yes
        textView.smartQuotesType = .yes
        textView.smartDashesType = .yes
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        
        // Register with the text view manager
        TextViewManager.shared.setCurrentTextView(textView)
        
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // Only update text if it's different to avoid cursor jumps
        if uiView.text != text {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            
            // Restore cursor position safely
            let textLength = text.count
            let safeLocation = max(0, min(selectedRange.location, textLength))
            let remainingLength = textLength - safeLocation
            let safeLength = max(0, min(selectedRange.length, remainingLength))
            
            let safeRange = NSRange(location: safeLocation, length: safeLength)
            uiView.selectedRange = safeRange
        }
        
        
        // Ensure this text view is always registered as the current one
        TextViewManager.shared.setCurrentTextView(uiView)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        let parent: FormattableTextEditor
        
        init(_ parent: FormattableTextEditor) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }
        
        func textViewDidBeginEditing(_ textView: UITextView) {
            // Update the text view manager when editing begins
            TextViewManager.shared.setCurrentTextView(textView)
            print("📝 FormattableTextEditor: textViewDidBeginEditing")
        }
        
        func textViewDidEndEditing(_ textView: UITextView) {
            print("📝 FormattableTextEditor: textViewDidEndEditing")
        }
        
        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            print("📝 FormattableTextEditor: textViewShouldBeginEditing")
            return true
        }
    }
}

