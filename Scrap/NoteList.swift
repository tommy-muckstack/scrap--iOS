import SwiftUI

// MARK: - Simple Note List
struct NoteList: View {
    @ObservedObject var dataManager: FirebaseDataManager
    @Binding var navigationPath: NavigationPath
    
    var body: some View {
        LazyVStack(spacing: 12) {
            ForEach(dataManager.items) { item in
                NoteRow(item: item, dataManager: dataManager) {
                    navigationPath.append(item)
                }
                .id(item.id) // Use stable ID for better performance
                .animation(.default, value: item.id)
            }
        }
    }
}

// MARK: - Simple Note Row
struct NoteRow: View {
    @ObservedObject var item: SparkItem
    let dataManager: FirebaseDataManager
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Title and content
                VStack(alignment: .leading, spacing: 4) {
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    
                    Text(item.content)
                        .font(item.title.isEmpty ? GentleLightning.Typography.body : GentleLightning.Typography.secondary)
                        .foregroundColor(item.title.isEmpty ? GentleLightning.Colors.textPrimary : GentleLightning.Colors.textSecondary)
                        .lineLimit(item.title.isEmpty ? nil : 3)
                        .multilineTextAlignment(.leading)
                }
                
                // Category pills
                if !item.categoryIds.isEmpty {
                    CategoryPills(categoryIds: item.categoryIds)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(GentleLightning.Colors.surface)
            )
        }
        .buttonStyle(PlainButtonStyle())
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

// MARK: - Category Pills Display
struct CategoryPills: View {
    let categoryIds: [String]
    
    var body: some View {
        if categoryIds.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                // For now, just show category count to avoid async loading
                Text("\(categoryIds.count) categor\(categoryIds.count == 1 ? "y" : "ies")")
                    .font(GentleLightning.Typography.metadata)
                    .foregroundColor(GentleLightning.Colors.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(GentleLightning.Colors.accentNeutral.opacity(0.1))
                    )
                Spacer()
            }
        }
    }
}