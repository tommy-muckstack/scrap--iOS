import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Spark Item (Main Note Model)
class SparkItem: ObservableObject, Identifiable, Hashable {
    let id: String
    @Published var content: String
    @Published var title: String
    @Published var categoryIds: [String]
    @Published var isTask: Bool
    @Published var isCompleted: Bool
    let createdAt: Date
    var firebaseId: String?
    
    init(content: String, title: String = "", categoryIds: [String] = [], isTask: Bool = false, id: String = UUID().uuidString) {
        self.id = id
        self.content = content
        self.title = title
        self.categoryIds = categoryIds
        self.isTask = isTask
        self.isCompleted = false
        self.createdAt = Date()
    }
    
    init(from firebaseNote: FirebaseNote) {
        self.id = firebaseNote.id ?? UUID().uuidString
        self.content = firebaseNote.content
        self.title = firebaseNote.title ?? ""
        self.categoryIds = firebaseNote.categoryIds ?? []
        self.isTask = firebaseNote.isTask
        self.isCompleted = false
        self.createdAt = firebaseNote.createdAt
        self.firebaseId = firebaseNote.id
    }
    
    var displayTitle: String {
        title.isEmpty ? (content.isEmpty ? "Untitled Note" : String(content.prefix(30))) : title
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SparkItem, rhs: SparkItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Category Model
class Category: ObservableObject, Identifiable, Hashable {
    let id: String
    @Published var name: String
    @Published var color: String
    let createdAt: Date
    @Published var usageCount: Int
    var firebaseId: String?
    
    init(name: String, color: String = Category.defaultColor(), id: String = UUID().uuidString) {
        self.id = id
        self.name = name
        self.color = color
        self.createdAt = Date()
        self.usageCount = 0
    }
    
    init(from firebaseCategory: FirebaseCategory) {
        self.id = firebaseCategory.id ?? UUID().uuidString
        self.name = firebaseCategory.name
        self.color = firebaseCategory.color
        self.createdAt = firebaseCategory.createdAt
        self.usageCount = firebaseCategory.usageCount
        self.firebaseId = firebaseCategory.id
    }
    
    var uiColor: Color {
        Color(hex: color) ?? Color.gray
    }
    
    static func defaultColor() -> String {
        let colors = [
            "#6B73FF", "#9F7AEA", "#4FD1C7", "#68D391", "#F6AD55",
            "#FC8181", "#63B3ED", "#D69E2E", "#ED64A6", "#A0AEC0"
        ]
        return colors.randomElement() ?? colors[0]
    }
    
    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Category, rhs: Category) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Firebase Models
struct FirebaseNote: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let content: String
    let title: String?
    let categoryIds: [String]?
    let isTask: Bool
    let categories: [String] // Legacy field
    let createdAt: Date
    let updatedAt: Date
    let pineconeId: String?
    let creationType: String
    
    var wrappedContent: String { content }
}

struct FirebaseCategory: Codable {
    let id: String?
    let name: String
    let color: String
    let createdAt: Date
    let usageCount: Int
    
    enum CodingKeys: String, CodingKey {
        case id, name, color, usageCount
        case createdAt = "created_at"
    }
}

// MARK: - Color Extension
extension Color {
    init?(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            return nil
        }
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}