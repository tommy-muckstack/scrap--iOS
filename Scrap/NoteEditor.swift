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
    @FocusState private var isTitleFocused: Bool
    @State private var showingOptions = false
    @State private var showingDelete = false
    @State private var showingCategoryManager = false
    @State private var userCategories: [Category] = []
    @State private var isLoadingCategories = false
    @State private var isContentLoaded = false
    @State private var showingSkeleton = true
    @State private var autoSaveTimer: Timer?
    @State private var noteOpenTime = Date()
    @State private var hasTrackedOpen = false
    @State private var isBeingDeleted = false
    @State private var drawingManager: DrawingOverlayManager?
    
    init(item: SparkItem, dataManager: FirebaseDataManager) {
        self.item = item
        self.dataManager = dataManager
        
        // Initialize with plain text first for fast display, load RTF asynchronously
        let initialText = Self.createFormattedText(from: item.content)
        
        self._editedText = State(initialValue: initialText)
        self._editedTitle = State(initialValue: item.title)
        self._selectedCategories = State(initialValue: item.categoryIds)
    }
    
    var body: some View {
        ZStack {
            if showingSkeleton {
                // Skeletal loading state
                NoteEditorSkeleton()
                    .transition(.opacity)
            } else {
                // Main content
                VStack(spacing: 0) {
                    // Title field
                    ZStack(alignment: .topLeading) {
                        // Placeholder text
                        if editedTitle.isEmpty {
                            Text("Title (optional)")
                                .font(GentleLightning.Typography.title)
                                .foregroundColor(GentleLightning.Colors.textSecondary.opacity(0.6))
                                .padding(.horizontal, 16)
                                .padding(.top, 16 + 8) // Match TextEditor padding + text offset
                                .allowsHitTesting(false)
                        }
                        
                        // Multiline text editor for title
                        TextEditor(text: $editedTitle)
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 16)
                            .frame(minHeight: 60, maxHeight: 120) // Accommodate ~3 lines at 28pt font
                            .focused($isTitleFocused)
                            .onChange(of: editedTitle) { newTitle in
                                // Track title changes
                                AnalyticsManager.shared.trackTitleChanged(noteId: item.firebaseId ?? item.id, titleLength: newTitle.count)
                                
                                // Debounce title updates for better performance  
                                autoSaveTimer?.invalidate()
                                autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                                    updateTitle(newTitle)
                                }
                            }
                    }
                    
                    // Rich Text editor with drawing overlays
                    RichTextEditorWithDrawings(
                        text: $editedText,
                        context: richTextContext,
                        showingFormatting: .constant(true),
                        configuration: { textView in
                        // Apply forNotes configuration
                        textView.autocorrectionType = .yes
                        textView.autocapitalizationType = .sentences
                        textView.smartQuotesType = .yes
                        textView.smartDashesType = .yes
                        textView.spellCheckingType = .yes
                        
                        // Set cursor color to black (matching design system)
                        textView.tintColor = UIColor.label
                        
                        // Improve text alignment and padding to match placeholder
                        textView.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
                        textView.textContainer.lineFragmentPadding = 4
                        
                        // Better line spacing for readability
                        let paragraphStyle = NSMutableParagraphStyle()
                        paragraphStyle.lineSpacing = 4
                        paragraphStyle.paragraphSpacing = 8
                        
                        // Set default Space Grotesk font for all notes
                        let defaultFont = UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
                        
                        textView.typingAttributes = [
                            .paragraphStyle: paragraphStyle,
                            .font: defaultFont,
                            .foregroundColor: UIColor.label
                        ]
                    },
                    onDrawingManagerReady: { manager in
                        drawingManager = manager
                        
                        // Re-process text to restore any drawing markers that were preserved
                        if let rtfData = item.rtfData {
                            do {
                                let loadedRTF = try NSAttributedString(
                                    data: rtfData,
                                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                                    documentAttributes: nil
                                )
                                
                                // Re-process with drawing manager now available
                                print("🎨 NoteEditor: Re-processing text with drawing manager available")
                                let finalText = SparkItem.prepareForDisplay(loadedRTF, drawingManager: manager)
                                
                                // Update the rich text editor
                                DispatchQueue.main.async {
                                    richTextContext.setAttributedString(finalText)
                                }
                                
                                print("🎨 NoteEditor: Drawing restoration complete")
                            } catch {
                                print("❌ NoteEditor: Failed to re-process text for drawing restoration: \(error)")
                            }
                        }
                    }
                    )
                    .padding(.horizontal, 16)
                    .focused($isTextFocused)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
                        // Save when app goes to background (unless being deleted)
                        if !isBeingDeleted {
                            updateContent(editedText)
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
                .transition(.opacity)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Dismiss keyboard when user drags down
                            if value.translation.height > 50 && value.velocity.height > 0 {
                                // Track keyboard dismissal
                                AnalyticsManager.shared.trackKeyboardDismissed(method: "drag")
                                
                                isTextFocused = false
                                isTitleFocused = false
                                print("🔽 NoteEditor: Dismissed keyboard via pull-down gesture")
                            }
                        }
                )
            }
        }
        // .navigationTitle("Edit Note")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .navigationBarItems(
            leading: Button(action: { 
                // Track back button
                AnalyticsManager.shared.trackBackButtonTapped(fromScreen: "note_editor")
                
                // Track note closed with time spent
                let timeSpent = Date().timeIntervalSince(noteOpenTime)
                AnalyticsManager.shared.trackNoteClosed(noteId: item.firebaseId ?? item.id, timeSpent: timeSpent)
                
                // Provide immediate feedback and dismiss
                withAnimation(.easeInOut(duration: 0.2)) {
                    showingSkeleton = false
                }
                
                // Save content quickly before dismiss (unless being deleted)
                if !isBeingDeleted {
                    DispatchQueue.global(qos: .userInitiated).async {
                        updateContent(editedText)
                        
                        DispatchQueue.main.async {
                            dismiss()
                        }
                    }
                } else {
                    dismiss()
                }
            }) {
                Image(systemName: GentleLightning.Icons.navigationBack)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.black)
            },
            trailing: Button(action: { 
                // Track options menu opened
                AnalyticsManager.shared.trackOptionsMenuOpened(noteId: item.firebaseId ?? item.id)
                showingOptions = true 
            }) {
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
        )
        .confirmationDialog("Note Options", isPresented: $showingOptions) {
            Button("Add Tag") { 
                // Track category manager opened
                AnalyticsManager.shared.trackCategoryManagerOpened()
                showingCategoryManager = true 
                loadCategories()
            }
            Button("Share") { shareNote() }
            Button("Delete", role: .destructive) { 
                // Track delete confirmation shown
                AnalyticsManager.shared.trackDeleteConfirmationShown(noteId: item.firebaseId ?? item.id)
                showingDelete = true 
            }
            Button("Cancel", role: .cancel) { 
                // Track options menu closed
                AnalyticsManager.shared.trackOptionsMenuClosed(noteId: item.firebaseId ?? item.id)
            }
        }
        .onChange(of: showingOptions) { isShowing in
            if !isShowing {
                // Track options menu closed when dismissed
                AnalyticsManager.shared.trackOptionsMenuClosed(noteId: item.firebaseId ?? item.id)
            }
        }
        .alert("Delete Note?", isPresented: $showingDelete) {
            Button("Delete", role: .destructive) { 
                // Track delete confirmed
                AnalyticsManager.shared.trackDeleteConfirmed(noteId: item.firebaseId ?? item.id)
                deleteNote() 
            }
            Button("Cancel", role: .cancel) { 
                // Track delete cancelled
                AnalyticsManager.shared.trackDeleteCancelled(noteId: item.firebaseId ?? item.id)
            }
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
        .dismissKeyboardOnDrag()
        .onAppear {
            // Track note opened (only once)
            if !hasTrackedOpen {
                AnalyticsManager.shared.trackNoteOpened(noteId: item.firebaseId ?? item.id, openMethod: "list_tap")
                hasTrackedOpen = true
                noteOpenTime = Date()
            }
            
            // Load content immediately without delay for better performance
            Task {
                loadCategories()
            }
            
            // Load content immediately for snappy performance
            Task { @MainActor in
                // Load RTF data immediately without delays
                var finalText = editedText
                if let rtfData = item.rtfData {
                    do {
                        let loadedRTF = try NSAttributedString(
                            data: rtfData,
                            options: [.documentType: NSAttributedString.DocumentType.rtf],
                            documentAttributes: nil
                        )
                        
                        // CRITICAL: Convert ASCII markers back to interactive checkbox attachments
                        print("🔧 NoteEditor: Converting loaded RTF checkboxes for display")
                        finalText = SparkItem.prepareForDisplay(loadedRTF, drawingManager: drawingManager)
                        print("🔧 NoteEditor: Checkbox conversion complete")
                        
                    } catch {
                        print("❌ NoteEditor: Failed to load RTF, using formatted text: \(error)")
                        finalText = Self.createFormattedText(from: item.content)
                    }
                }
                
                // Update text and context immediately
                editedText = finalText
                richTextContext.setAttributedString(finalText)
                
                // Hide skeleton immediately
                withAnimation(.easeOut(duration: 0.1)) {
                    showingSkeleton = false
                }
                
                // Focus text field without delay
                isTextFocused = true
            }
        }
        .onDisappear {
            // Clean up timer and save
            autoSaveTimer?.invalidate()
            autoSaveTimer = nil
            
            // Optimize dismissal by deferring save to background
            DispatchQueue.global(qos: .userInitiated).async {
                // Save when navigating away
                updateContent(editedText)
            }
        }
    }
    
    // MARK: - Actions
    
    private func updateTitle(_ newTitle: String) {
        // Don't save if note is being deleted
        guard !isBeingDeleted else { return }
        
        item.title = newTitle
        if let firebaseId = item.firebaseId {
            Task {
                try? await dataManager.firebaseManager.updateNoteTitle(noteId: firebaseId, title: newTitle)
            }
        }
    }
    
    private func updateContent(_ attributedText: NSAttributedString) {
        // Don't save if note is being deleted
        guard !isBeingDeleted else { return }
        
        let plainText = attributedText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plainText.isEmpty else { return }
        
        // Track content changes
        AnalyticsManager.shared.trackContentChanged(noteId: item.firebaseId ?? item.id, contentLength: plainText.count, changeType: "editing")
        
        // Convert the attributed string to RTF data to preserve formatting
        do {
            // Use trait preservation method for better RTF compatibility
            let rtfCompatibleString = SparkItem.prepareForRTFSave(attributedText, drawingManager: drawingManager)
            let rtfData = try rtfCompatibleString.data(
                from: NSRange(location: 0, length: rtfCompatibleString.length),
                documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
            )
            
            // Track RTF save
            AnalyticsManager.shared.trackRTFContentSaved(noteId: item.firebaseId ?? item.id, rtfDataSize: rtfData.count)
            
            dataManager.updateItemWithRTF(item, rtfData: rtfData)
        } catch {
            // Track content load failure
            AnalyticsManager.shared.trackContentLoadFailed(noteId: item.firebaseId ?? item.id, errorType: "rtf_conversion_failed")
            
            print("❌ NoteEditor: Failed to convert to RTF, falling back to plain text: \(error)")
            dataManager.updateItem(item, newContent: plainText)
        }
    }
    
    private func updateCategories(_ categoryIds: [String]) {
        // Don't save if note is being deleted
        guard !isBeingDeleted else { return }
        
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
        // Track note sharing
        AnalyticsManager.shared.trackNoteShared(noteId: item.firebaseId ?? item.id)
        
        let shareText = item.title.isEmpty ? item.content : "\(item.title)\n\n\(item.content)"
        let activityController = UIActivityViewController(activityItems: [shareText], applicationActivities: nil)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {
            rootViewController.present(activityController, animated: true)
        }
    }
    
    private func deleteNote() {
        // Set flag to prevent any further auto-saves
        isBeingDeleted = true
        
        // Cancel any pending auto-save timers
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
        
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
    
    // MARK: - Helper Functions
    
    /// Create properly formatted NSAttributedString with Space Grotesk font
    private static func createFormattedText(from content: String) -> NSAttributedString {
        let font = UIFont(name: "SpaceGrotesk-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.paragraphSpacing = 8
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraphStyle
        ]
        
        return NSAttributedString(string: content, attributes: attributes)
    }
}

// MARK: - Rich Formatting Toolbar
struct RichFormattingToolbar: View {
    @ObservedObject var context: RichTextContext
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let safeWidth = availableWidth.isFinite && availableWidth > 0 ? availableWidth : 320
            
            // Calculate equal spacing for all buttons including dismiss
            let totalPadding: CGFloat = 32 // 16pt on each side
            let totalButtons: CGFloat = 9 // 8 formatting buttons + 1 dismiss button
            let totalSpacing = totalButtons - 1 // spaces between buttons
            let buttonSpacing: CGFloat = 6 // Consistent spacing between all buttons
            let usedSpacing = totalSpacing * buttonSpacing
            let availableForButtons = safeWidth - totalPadding - usedSpacing
            let buttonWidth = max(32, availableForButtons / totalButtons)
            
            HStack(spacing: buttonSpacing) {
                // Bold button
                Button(action: { context.toggleBold() }) {
                    Text("B")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(context.isBoldActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isBoldActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isBoldActive)
                
                // Italic button
                Button(action: { context.toggleItalic() }) {
                    Text("I")
                        .font(.system(size: 16, weight: .medium))
                        .italic()
                        .foregroundColor(context.isItalicActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isItalicActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isItalicActive)
                
                // Strikethrough button
                Button(action: { context.toggleStrikethrough() }) {
                    Text("S")
                        .font(.system(size: 16, weight: .medium))
                        .strikethrough()
                        .foregroundColor(context.isStrikethroughActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isStrikethroughActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isStrikethroughActive)
                
                // Code button
                Button(action: { context.toggleCodeBlock() }) {
                    Text("</>")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(context.isCodeBlockActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isCodeBlockActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isCodeBlockActive)
                
                // List button
                Button(action: { context.toggleBulletList() }) {
                    Image(systemName: GentleLightning.Icons.formatList)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isBulletListActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isBulletListActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isBulletListActive)
                
                // Checkbox button
                Button(action: { context.toggleCheckbox() }) {
                    Image(systemName: "circle.dotted")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isCheckboxActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isCheckboxActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isCheckboxActive)
                
                // Marker/Drawing button
                Button(action: { context.toggleDrawing() }) {
                    Image(systemName: "pencil.tip")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(context.isDrawingActive ? .white : .primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(context.isDrawingActive ? Color.black : Color.clear)
                        .cornerRadius(8)
                }
                .animation(.easeInOut(duration: 0.1), value: context.isDrawingActive)
                
                // Indent In button
                Button(action: { context.indentIn() }) {
                    Image(systemName: "increase.indent")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(Color.clear)
                        .cornerRadius(8)
                }
                
                // Dismiss keyboard button
                Button(action: { 
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: buttonWidth, height: 32)
                        .background(Color.clear)
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Rectangle()
                    .fill(Color(UIColor.systemBackground))
                    .shadow(color: Color.black.opacity(0.1), radius: 1, x: 0, y: -1)
            )
        }
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
            .navigationTitle(showingCreateForm ? "" : "Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(GentleLightning.Typography.body)
                        .foregroundColor(.black)
                }
            }
        }
        .dismissKeyboardOnDrag()
    }
    
    private func toggleCategory(_ category: Category) {
        let categoryId = category.firebaseId ?? category.id
        
        if selectedCategories.contains(categoryId) {
            // Track category deselection
            AnalyticsManager.shared.trackCategoryDeselected(categoryId: categoryId, categoryName: category.name)
            selectedCategories.removeAll { $0 == categoryId }
        } else {
            // Track category selection
            AnalyticsManager.shared.trackCategorySelected(categoryId: categoryId, categoryName: category.name)
            selectedCategories.append(categoryId)
        }
        
        onCategoryUpdate(selectedCategories)
    }
    
    private func loadAvailableColors() {
        Task {
            do {
                let colors = try await CategoryService.shared.getAvailableColors()
                await MainActor.run {
                    availableColors = colors.isEmpty ? CategoryService.availableColors : colors
                    selectedColorKey = availableColors.first?.key ?? ""
                }
            } catch {
                // Fallback to all available colors if there's an error (e.g., permissions)
                // Don't show error to user since CategoryService already handles this gracefully
                await MainActor.run {
                    availableColors = CategoryService.availableColors
                    selectedColorKey = availableColors.first?.key ?? ""
                }
            }
        }
    }
    
    private func createCategory(name: String, colorKey: String) {
        isLoading = true
        Task {
            do {
                let newCategory = try await CategoryService.shared.createCustomCategory(name: name, colorKey: colorKey)
                
                // Track category creation
                AnalyticsManager.shared.trackCategoryCreated(categoryName: name, colorKey: colorKey)
                
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
            
            // Tag Name Input
            TextField("Tag Name", text: $categoryName)
                .font(GentleLightning.Typography.bodyInput)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal, 20)
            
            // Color Selection
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                ForEach(availableColors, id: \.key) { colorInfo in
                    Button(action: { selectedColorKey = colorInfo.key }) {
                        Circle()
                            .fill(Color(hex: colorInfo.hex) ?? Color.gray)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Circle()
                                    .stroke(GentleLightning.Colors.accentNeutral, lineWidth: selectedColorKey == colorInfo.key ? 3 : 0)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            
            // Create Button - positioned higher, closer to keyboard
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
            
            // Add spacer to push content up, closer to keyboard
            Spacer()
        }
    }
}

// MARK: - Note Editor Skeleton Loading View
struct NoteEditorSkeleton: View {
    @State private var animateShimmer = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Title skeleton
            VStack(alignment: .leading, spacing: 8) {
                SkeletonLine(width: 0.4, height: 24)
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                
                SkeletonLine(width: 0.25, height: 24)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            }
            
            // Content skeleton
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<8, id: \.self) { index in
                    SkeletonLine(
                        width: index == 3 ? 0.6 : (index == 7 ? 0.3 : 0.9),
                        height: 18
                    )
                    .padding(.horizontal, 16)
                }
            }
            .padding(.vertical, 20)
            
            Spacer()
        }
        .background(Color(UIColor.systemBackground))
    }
}

// MARK: - Skeleton Line Component
struct SkeletonLine: View {
    let width: CGFloat
    let height: CGFloat
    @State private var animateShimmer = false
    
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 4)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.gray.opacity(0.2),
                            Color.gray.opacity(0.1),
                            Color.gray.opacity(0.2)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .mask(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(stops: [
                                    .init(color: .clear, location: animateShimmer ? 0.8 : -0.3),
                                    .init(color: .white, location: animateShimmer ? 0.9 : -0.2),
                                    .init(color: .clear, location: animateShimmer ? 1.0 : -0.1)
                                ]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .frame(width: {
                    let availableWidth = geometry.size.width
                    let safeWidth = availableWidth.isFinite && availableWidth > 0 ? availableWidth : 320
                    return safeWidth * width
                }(), height: height)
        }
        .frame(height: height)
        .onAppear {
            withAnimation(
                Animation.linear(duration: 1.5)
                    .repeatForever(autoreverses: false)
            ) {
                animateShimmer = true
            }
        }
    }
}


