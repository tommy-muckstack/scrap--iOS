import SwiftUI

// MARK: - Enhanced Note List with Delightful Animations
struct NoteList: View {
    @ObservedObject var dataManager: FirebaseDataManager
    @Binding var navigationPath: NavigationPath
    @State private var isVisible = false
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(Array(dataManager.filteredItems.enumerated()), id: \.element.id) { index, item in
                NoteRow(item: item, dataManager: dataManager) {
                    // Track note opened for analytics
                    AnalyticsManager.shared.trackNoteOpened(noteId: item.firebaseId ?? item.id, openMethod: "list_tap")
                    navigationPath.append(item)
                }
                .scaleEffect(isVisible ? 1.0 : 0.8)
                .opacity(isVisible ? 1.0 : 0.0)
                .offset(y: isVisible ? 0 : 20)
                .animation(
                    GentleLightning.Animation.delightful
                        .delay(Double(index) * 0.1), // Staggered entrance animation
                    value: isVisible
                )
                .animation(GentleLightning.Animation.silky, value: item.content) // Smooth content updates
                .animation(GentleLightning.Animation.bouncy, value: item.title) // Bouncy title updates
            }
        }
        .onAppear {
            // Trigger staggered entrance animation when the list appears
            withAnimation {
                isVisible = true
            }
        }
        .onDisappear {
            // Reset animation state when list disappears
            isVisible = false
        }
    }
}

// MARK: - Enhanced Note Row with Delightful Animations
struct NoteRow: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    let onTap: () -> Void
    @State private var isPressed = false
    @State private var isHovering = false
    
    var body: some View {
        Button(action: {
            // Add haptic feedback for delightful interaction
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                // Title and content with enhanced typography animations
                VStack(alignment: .leading, spacing: 4) {
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .scaleEffect(isPressed ? 0.98 : 1.0)
                            .animation(GentleLightning.Animation.delightful, value: isPressed)
                    }
                    
                    Text(item.content)
                        .font(item.title.isEmpty ? GentleLightning.Typography.body : GentleLightning.Typography.secondary)
                        .foregroundColor(item.title.isEmpty ? GentleLightning.Colors.textPrimary : GentleLightning.Colors.textSecondary)
                        .lineLimit(item.title.isEmpty ? nil : 3)
                        .multilineTextAlignment(.leading)
                        .opacity(isPressed ? 0.8 : 1.0)
                        .animation(GentleLightning.Animation.silky, value: isPressed)
                }
                
                // Category pills with enhanced animations
                if !item.categoryIds.isEmpty {
                    CategoryPills(categoryIds: item.categoryIds)
                        .scaleEffect(isPressed ? 0.95 : 1.0)
                        .animation(GentleLightning.Animation.bouncy, value: isPressed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GentleLightning.Colors.surface)
                    .shadow(
                        color: GentleLightning.Colors.shadowLight,
                        radius: isHovering ? 8 : 2,
                        x: 0,
                        y: isHovering ? 4 : 1
                    )
                    .animation(GentleLightning.Animation.delightful, value: isHovering)
            )
            .scaleEffect(isPressed ? 0.96 : (isHovering ? 1.02 : 1.0))
            .rotationEffect(.degrees(isPressed ? -0.5 : 0))
            .animation(GentleLightning.Animation.elastic, value: isPressed)
            .animation(GentleLightning.Animation.delightful, value: isHovering)
        }
        .buttonStyle(PlainButtonStyle())
        .onLongPressGesture(
            minimumDuration: 0,
            maximumDistance: .infinity,
            pressing: { pressing in
                withAnimation(GentleLightning.Animation.delightful) {
                    isPressed = pressing
                }
            },
            perform: {}
        )
        .onHover { hovering in
            withAnimation(GentleLightning.Animation.silky) {
                isHovering = hovering
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete") {
                // Add haptic feedback for deletion
                let notificationFeedback = UINotificationFeedbackGenerator()
                notificationFeedback.notificationOccurred(.warning)
                
                // Enhanced delete animation with scale out effect
                withAnimation(GentleLightning.Animation.elastic) {
                    dataManager.deleteItem(item)
                }
            }
            .tint(.red)
        }
    }
}

// MARK: - Enhanced Category Pills with Delightful Animations
struct CategoryPills: View {
    let categoryIds: [String]
    @State private var isVisible = false
    @State private var isPulsing = false
    
    var body: some View {
        if categoryIds.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                // Enhanced category indicator with pulsing animation
                Text("\(categoryIds.count) categor\(categoryIds.count == 1 ? "y" : "ies")")
                    .font(GentleLightning.Typography.metadata)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(GentleLightning.Colors.accentNeutral.opacity(isPulsing ? 0.2 : 0.1))
                            .overlay(
                                Capsule()
                                    .stroke(GentleLightning.Colors.accentNeutral.opacity(0.3), lineWidth: 1)
                                    .scaleEffect(isPulsing ? 1.1 : 1.0)
                                    .opacity(isPulsing ? 0.5 : 1.0)
                            )
                    )
                    .scaleEffect(isVisible ? 1.0 : 0.8)
                    .opacity(isVisible ? 1.0 : 0.0)
                    .animation(GentleLightning.Animation.delightful.delay(0.2), value: isVisible)
                    .animation(GentleLightning.Animation.elastic, value: isPulsing)
                
                // Add a subtle animated dot indicator for multiple categories
                if categoryIds.count > 1 {
                    HStack(spacing: 2) {
                        ForEach(0..<min(categoryIds.count, 3), id: \.self) { index in
                            Circle()
                                .fill(GentleLightning.Colors.accentNeutral)
                                .frame(width: 4, height: 4)
                                .scaleEffect(isVisible ? 1.0 : 0.0)
                                .animation(
                                    GentleLightning.Animation.bouncy
                                        .delay(Double(index) * 0.1 + 0.3),
                                    value: isVisible
                                )
                        }
                        
                        if categoryIds.count > 3 {
                            Text("...")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .opacity(isVisible ? 1.0 : 0.0)
                                .animation(GentleLightning.Animation.silky.delay(0.6), value: isVisible)
                        }
                    }
                }
                
                Spacer()
            }
            .onAppear {
                withAnimation {
                    isVisible = true
                }
                
                // Start subtle pulsing animation for visual interest
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(GentleLightning.Animation.delightful.repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .onDisappear {
                isVisible = false
                isPulsing = false
            }
        }
    }
}