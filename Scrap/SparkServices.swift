import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

// MARK: - OpenAI Service for Title Generation
class OpenAIService {
    static let shared = OpenAIService()
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    private init() {
        // Get API key from multiple sources
        var key = ""
        
        // 1. Try environment variable first
        key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        
        // 2. Try Info.plist if environment variable is empty
        if key.isEmpty {
            key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
        }
        
        // Note: API key should be configured via environment variable or Info.plist
        
        self.apiKey = key
        
        if apiKey.isEmpty {
            print("⚠️ OpenAI API key not found. Please configure OPENAI_API_KEY")
        } else {
            print("✅ OpenAI API key configured successfully")
        }
    }
    
    // MARK: - Generate Title
    func generateTitle(for content: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OpenAIError.emptyContent
        }
        
        let request = createTitleRequest(for: content)
        
        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("🔴 OpenAI API Error: Status \(httpResponse.statusCode)")
                if let errorString = String(data: data, encoding: .utf8) {
                    print("🔴 Error response: \(errorString)")
                }
                throw OpenAIError.apiError(httpResponse.statusCode)
            }
            
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let title = response.choices.first?.message.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) else {
                throw OpenAIError.noTitle
            }
            
            // Clean up the title (remove quotes, ensure reasonable length)
            let cleanTitle = cleanTitle(title)
            
            print("✅ Generated title: '\(cleanTitle)' for content: '\(content.prefix(50))...'")
            
            return cleanTitle
            
        } catch {
            print("💥 OpenAI title generation failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Q&A and Summarization
    
    func answerQuestion(question: String, context: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        let request = createQARequest(question: question, context: context)
        
        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("🔴 OpenAI API Error: Status \(httpResponse.statusCode)")
                throw OpenAIError.apiError(httpResponse.statusCode)
            }
            
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let answer = response.choices.first?.message.content else {
                throw OpenAIError.noResponse
            }
            
            print("✅ Generated answer for question: '\(question.prefix(50))...'")
            return answer.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("💥 OpenAI Q&A failed: \(error)")
            throw error
        }
    }
    
    func summarizeContent(_ content: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw OpenAIError.missingAPIKey
        }
        
        let request = createSummaryRequest(for: content)
        
        do {
            let (data, urlResponse) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = urlResponse as? HTTPURLResponse else {
                throw OpenAIError.invalidResponse
            }
            
            guard httpResponse.statusCode == 200 else {
                print("🔴 OpenAI API Error: Status \(httpResponse.statusCode)")
                throw OpenAIError.apiError(httpResponse.statusCode)
            }
            
            let response = try JSONDecoder().decode(OpenAIResponse.self, from: data)
            
            guard let summary = response.choices.first?.message.content else {
                throw OpenAIError.noResponse
            }
            
            print("✅ Generated summary from content (\(content.count) chars)")
            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
            
        } catch {
            print("💥 OpenAI summarization failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func createTitleRequest(for content: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Create a concise, descriptive title (max 6 words) for this note content. 
        The title should capture the main topic or purpose. 
        Return only the title, no quotes or extra text.
        
        Content: \(content.prefix(500))
        """
        
        let payload = OpenAIRequest(
            model: "gpt-3.5-turbo",
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            maxTokens: 20,
            temperature: 0.7
        )
        
        request.httpBody = try? JSONEncoder().encode(payload)
        return request
    }
    
    private func cleanTitle(_ title: String) -> String {
        var cleaned = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        
        // Remove common prefixes that OpenAI sometimes adds despite instructions
        let prefixesToRemove = ["Title:", "Title :", "Title-", "Title –", "Title-", "Note:", "Note :", "Subject:", "Subject :", "Topic:", "Topic :"]
        for prefix in prefixesToRemove {
            if cleaned.hasPrefix(prefix) {
                cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break // Only remove the first match
            }
        }
        
        // Ensure reasonable length
        if cleaned.count > 50 {
            cleaned = String(cleaned.prefix(50)) + "..."
        }
        
        // Fallback if title is too short
        if cleaned.count < 3 {
            cleaned = "Note"
        }
        
        return cleaned
    }
    
    private func createQARequest(question: String, context: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Based on the following notes from the user, answer their question accurately and concisely.
        If the notes don't contain relevant information, say so politely.
        
        User's Notes:
        \(context)
        
        Question: \(question)
        
        Answer:
        """
        
        let payload = OpenAIRequest(
            model: "gpt-3.5-turbo",
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            maxTokens: 300,
            temperature: 0.3
        )
        
        request.httpBody = try? JSONEncoder().encode(payload)
        return request
    }
    
    private func createSummaryRequest(for content: String) -> URLRequest {
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Please create a comprehensive summary of these notes. Organize the information into key themes, 
        important points, and actionable items. Make it clear and well-structured.
        
        Notes to summarize:
        \(content)
        
        Summary:
        """
        
        let payload = OpenAIRequest(
            model: "gpt-3.5-turbo",
            messages: [
                OpenAIMessage(role: "user", content: prompt)
            ],
            maxTokens: 500,
            temperature: 0.5
        )
        
        request.httpBody = try? JSONEncoder().encode(payload)
        return request
    }
}

// MARK: - Category Service
class CategoryService {
    static let shared = CategoryService()
    private let db = Firestore.firestore()
    
    private init() {}
    
    // MARK: - CRUD Operations
    
    func loadCategories() async throws -> [Category] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw CategoryError.notAuthenticated
        }
        
        let snapshot = try await db.collection("users")
            .document(userId)
            .collection("categories")
            .order(by: "usageCount", descending: true)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            let data = doc.data()
            guard let name = data["name"] as? String,
                  let color = data["color"] as? String,
                  let timestamp = data["created_at"] as? Timestamp,
                  let usageCount = data["usageCount"] as? Int else {
                return nil
            }
            
            let firebaseCategory = FirebaseCategory(
                id: doc.documentID,
                name: name,
                color: color,
                createdAt: timestamp.dateValue(),
                usageCount: usageCount
            )
            
            return Category(from: firebaseCategory)
        }
    }
    
    func saveCategory(_ category: Category) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw CategoryError.notAuthenticated
        }
        
        let categoryData: [String: Any] = [
            "name": category.name,
            "color": category.color,
            "created_at": Timestamp(date: category.createdAt),
            "usageCount": category.usageCount
        ]
        
        if let firebaseId = category.firebaseId {
            // Update existing category
            try await db.collection("users")
                .document(userId)
                .collection("categories")
                .document(firebaseId)
                .updateData(categoryData)
        } else {
            // Create new category
            let docRef = try await db.collection("users")
                .document(userId)
                .collection("categories")
                .addDocument(data: categoryData)
            
            category.firebaseId = docRef.documentID
        }
    }
    
    func deleteCategory(_ category: Category) async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let firebaseId = category.firebaseId else {
            throw CategoryError.notAuthenticated
        }
        
        try await db.collection("users")
            .document(userId)
            .collection("categories")
            .document(firebaseId)
            .delete()
    }
    
    func updateCategoryUsage(_ categoryId: String) async {
        guard let userId = Auth.auth().currentUser?.uid else {
            return
        }
        
        do {
            try await db.collection("users")
                .document(userId)
                .collection("categories")
                .document(categoryId)
                .updateData([
                    "usageCount": FieldValue.increment(Int64(1))
                ])
        } catch {
            print("Failed to update category usage: \(error)")
        }
    }
    
    func incrementUsage(for categoryId: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw CategoryError.notAuthenticated
        }
        
        try await db.collection("users")
            .document(userId)
            .collection("categories")
            .document(categoryId)
            .updateData([
                "usageCount": FieldValue.increment(Int64(1))
            ])
    }
    
    // MARK: - Search & Filter
    
    func searchCategories(_ query: String, in categories: [Category]) -> [Category] {
        guard !query.isEmpty else { return categories }
        
        return categories.filter { category in
            category.name.localizedCaseInsensitiveContains(query)
        }
    }
    
    func getOrCreateCategory(name: String, color: String? = nil) async throws -> Category {
        // First check if category already exists
        let existingCategories = try await loadCategories()
        
        if let existing = existingCategories.first(where: { $0.name.lowercased() == name.lowercased() }) {
            return existing
        }
        
        // Create new category
        let category = Category(
            name: name,
            color: color ?? Category.defaultColor()
        )
        
        try await saveCategory(category)
        return category
    }
    
    // MARK: - 5-Color Category System
    
    static let availableColors = [
        ("red", "#DC2626", "Red"),
        ("yellow", "#EAB308", "Yellow"),
        ("green", "#16A34A", "Green"),
        ("blue", "#2563EB", "Blue"),
        ("purple", "#7C3AED", "Purple")
    ]
    
    func getUserCategories() async throws -> [Category] {
        return try await loadCategories()
    }
    
    func canCreateCategory(withColor colorKey: String) async throws -> Bool {
        let existingCategories = try await loadCategories()
        return !existingCategories.contains { category in
            // Check if this color is already used
            let colorHex = CategoryService.availableColors.first { $0.0 == colorKey }?.1 ?? ""
            return category.color == colorHex
        }
    }
    
    func getAvailableColors() async throws -> [(key: String, hex: String, name: String)] {
        do {
            let existingCategories = try await loadCategories()
            let usedColors = Set(existingCategories.map { $0.color })
            
            return CategoryService.availableColors.filter { colorInfo in
                !usedColors.contains(colorInfo.1)
            }
        } catch {
            // If we can't load existing categories (authentication issue, etc.),
            // return all available colors as a fallback
            print("Warning: Failed to load existing categories, returning all colors: \(error)")
            return CategoryService.availableColors
        }
    }
    
    func createCustomCategory(name: String, colorKey: String) async throws -> Category {
        // Validate input
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CategoryError.invalidData
        }
        
        guard let colorInfo = CategoryService.availableColors.first(where: { $0.0 == colorKey }) else {
            throw CategoryError.invalidData
        }
        
        // Check if color is available
        guard try await canCreateCategory(withColor: colorKey) else {
            throw CategoryError.colorAlreadyUsed
        }
        
        // Check if we've reached the limit
        let existingCategories = try await loadCategories()
        guard existingCategories.count < 5 else {
            throw CategoryError.limitReached
        }
        
        // Create the category
        let category = Category(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: colorInfo.1)
        try await saveCategory(category)
        
        return category
    }
}

// MARK: - OpenAI Models

struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let maxTokens: Int
    let temperature: Double
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

// MARK: - Errors

enum OpenAIError: Error, LocalizedError {
    case missingAPIKey
    case emptyContent
    case invalidResponse
    case apiError(Int)
    case noTitle
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key not configured"
        case .emptyContent:
            return "Content is empty"
        case .invalidResponse:
            return "Invalid response from OpenAI"
        case .apiError(let code):
            return "OpenAI API error: \(code)"
        case .noTitle:
            return "No title generated"
        case .noResponse:
            return "No response generated"
        }
    }
}

enum CategoryError: Error, LocalizedError {
    case notAuthenticated
    case invalidData
    case networkError
    case colorAlreadyUsed
    case limitReached
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .invalidData:
            return "Invalid category data"
        case .networkError:
            return "Network error occurred"
        case .colorAlreadyUsed:
            return "This color is already used by another category"
        case .limitReached:
            return "Maximum of 5 categories allowed"
        }
    }
}