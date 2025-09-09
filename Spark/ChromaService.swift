import Foundation

// MARK: - Chroma Models
struct ChromaCollection: Codable {
    let name: String
    let metadata: [String: String]?
}

struct ChromaDocument: Codable {
    let ids: [String]
    let embeddings: [[Double]]
    let metadatas: [[String: Any]]
    let documents: [String]
}

struct ChromaQueryResult: Codable {
    let ids: [[String]]
    let distances: [[Double]]
    let metadatas: [[ChromaMetadata]]
    let documents: [[String]]
}

struct ChromaMetadata: Codable {
    let firebaseId: String
    let userId: String
    let isTask: Bool
    let categories: [String]
    let createdAt: String
}

// MARK: - Chroma Service
class ChromaService: ObservableObject {
    static let shared = ChromaService()
    
    private let baseURL: String
    private let collectionName = "spark_notes"
    private let session = URLSession.shared
    
    @Published var isConnected = false
    @Published var error: String?
    
    init() {
        // Railway Chroma deployment URL
        self.baseURL = "https://spark-ios-production.up.railway.app"
        
        Task {
            await initializeCollection()
        }
    }
    
    // MARK: - Collection Management
    private func initializeCollection() async {
        do {
            // Check if collection exists, create if not
            let collections = try await getCollections()
            if !collections.contains(where: { $0.name == collectionName }) {
                try await createCollection()
            }
            
            DispatchQueue.main.async {
                self.isConnected = true
                self.error = nil
            }
        } catch {
            DispatchQueue.main.async {
                self.isConnected = false
                self.error = "Failed to connect to Chroma: \(error.localizedDescription)"
            }
        }
    }
    
    private func getCollections() async throws -> [ChromaCollection] {
        let url = URL(string: "\(baseURL)/api/v1/collections")!
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChromaError.networkError("Failed to get collections")
        }
        
        return try JSONDecoder().decode([ChromaCollection].self, from: data)
    }
    
    private func createCollection() async throws {
        let url = URL(string: "\(baseURL)/api/v1/collections")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let collection = ChromaCollection(
            name: collectionName,
            metadata: ["description": "Spark notes vector storage"]
        )
        
        request.httpBody = try JSONEncoder().encode(collection)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChromaError.networkError("Failed to create collection")
        }
    }
    
    // MARK: - Vector Operations
    func addDocument(
        id: String,
        content: String,
        embedding: [Double],
        metadata: ChromaMetadata
    ) async throws {
        
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionName)/add")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert metadata to [String: Any]
        let metadataDict: [String: Any] = [
            "firebaseId": metadata.firebaseId,
            "userId": metadata.userId,
            "isTask": metadata.isTask,
            "categories": metadata.categories,
            "createdAt": metadata.createdAt
        ]
        
        let document = ChromaDocument(
            ids: [id],
            embeddings: [embedding],
            metadatas: [metadataDict],
            documents: [content]
        )
        
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "ids": document.ids,
            "embeddings": document.embeddings,
            "metadatas": document.metadatas,
            "documents": document.documents
        ])
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChromaError.networkError("Failed to add document")
        }
    }
    
    func queryDocuments(
        embedding: [Double],
        userId: String,
        limit: Int = 10,
        filter: [String: Any]? = nil
    ) async throws -> ChromaQueryResult {
        
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionName)/query")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build query with user filter
        var queryFilter: [String: Any] = ["userId": ["$eq": userId]]
        if let additionalFilter = filter {
            queryFilter.merge(additionalFilter) { _, new in new }
        }
        
        let queryData: [String: Any] = [
            "query_embeddings": [embedding],
            "n_results": limit,
            "where": queryFilter,
            "include": ["metadatas", "documents", "distances"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: queryData)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChromaError.networkError("Failed to query documents")
        }
        
        return try JSONDecoder().decode(ChromaQueryResult.self, from: data)
    }
    
    func deleteDocument(id: String) async throws {
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionName)/delete")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let deleteData: [String: Any] = [
            "ids": [id]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: deleteData)
        
        let (_, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ChromaError.networkError("Failed to delete document")
        }
    }
    
    // MARK: - Health Check
    func healthCheck() async throws -> Bool {
        let url = URL(string: "\(baseURL)/api/v1/heartbeat")!
        let (_, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return false
        }
        
        return httpResponse.statusCode == 200
    }
}

// MARK: - Chroma Errors
enum ChromaError: Error, LocalizedError {
    case networkError(String)
    case encodingError(String)
    case decodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .decodingError(let message):
            return "Decoding error: \(message)"
        }
    }
}

// MARK: - OpenAI Embedding Service (for generating embeddings)
class EmbeddingService {
    static let shared = EmbeddingService()
    
    private let openAIKey = "YOUR_OPENAI_API_KEY" // TODO: Add to environment
    private let session = URLSession.shared
    
    func generateEmbedding(for text: String) async throws -> [Double] {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(openAIKey)", forHTTPHeaderField: "Authorization")
        
        let requestBody: [String: Any] = [
            "model": "text-embedding-3-small",
            "input": text
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw EmbeddingError.apiError("Failed to generate embedding")
        }
        
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let dataArray = json["data"] as! [[String: Any]]
        let embedding = dataArray[0]["embedding"] as! [Double]
        
        return embedding
    }
}

enum EmbeddingError: Error, LocalizedError {
    case apiError(String)
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Embedding API error: \(message)"
        }
    }
}