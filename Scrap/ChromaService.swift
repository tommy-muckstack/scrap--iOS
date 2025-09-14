import Foundation

// MARK: - Chroma Models
struct ChromaCollection: Codable {
    let id: String?
    let name: String
    let metadata: [String: String]?
}

struct ChromaDocument {
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
    let isTask: Bool?
    let categories: [String]?
    let createdAt: String
    
    // Custom initializer to provide defaults
    init(firebaseId: String, userId: String, isTask: Bool, categories: [String], createdAt: String) {
        self.firebaseId = firebaseId
        self.userId = userId
        self.isTask = isTask
        self.categories = categories
        self.createdAt = createdAt
    }
}

// MARK: - Chroma Service
class ChromaService: ObservableObject {
    static let shared = ChromaService()
    
    private let baseURL: String
    private let collectionName = "spark_notes"
    private let session = URLSession.shared
    
    @Published var isConnected = false
    @Published var error: String?
    
    private var collectionId: String?
    
    init() {
        // Railway Chroma deployment URL
        self.baseURL = "https://spark-ios-production.up.railway.app"
        
        Task {
            await initializeCollection()
        }
    }
    
    // MARK: - Collection Management
    @MainActor
    private func initializeCollection() async {
        do {
            print("🔍 ChromaService: Initializing collection at \(baseURL)")
            
            // Check if collection exists, create if not
            let collections = try await getCollections()
            print("🔍 ChromaService: Found \(collections.count) collections")
            
            // Debug: Print all collections
            for collection in collections {
                print("🔍 ChromaService: Collection - ID: \(collection.id ?? "nil"), Name: \(collection.name)")
            }
            
            if let existingCollection = collections.first(where: { $0.name == collectionName }) {
                print("🔍 ChromaService: Collection '\(collectionName)' already exists")
                self.collectionId = existingCollection.id
                print("🔍 ChromaService: Using collection ID: \(existingCollection.id ?? "nil")")
            } else {
                print("🔍 ChromaService: Creating collection '\(collectionName)'")
                try await createCollection()
                // After creating, get the collection to find its ID
                let updatedCollections = try await getCollections()
                if let newCollection = updatedCollections.first(where: { $0.name == collectionName }) {
                    self.collectionId = newCollection.id
                    print("🔍 ChromaService: Created collection with ID: \(newCollection.id ?? "nil")")
                }
            }
            
            self.isConnected = true
            self.error = nil
            print("✅ ChromaService: Successfully connected to ChromaDB")
        } catch {
            self.isConnected = false
            self.error = "Failed to connect to Chroma: \(error.localizedDescription)"
            print("💥 ChromaService: Failed to initialize: \(error)")
        }
    }
    
    private func getCollections() async throws -> [ChromaCollection] {
        let url = URL(string: "\(baseURL)/api/v1/collections")!
        let (data, response) = try await session.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChromaError.networkError("Invalid response format")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = "HTTP \(httpResponse.statusCode)"
            if let errorData = String(data: data, encoding: .utf8) {
                print("🔍 ChromaService getCollections error response: \(errorData)")
            }
            throw ChromaError.networkError("Failed to get collections: \(errorMessage)")
        }
        
        return try JSONDecoder().decode([ChromaCollection].self, from: data)
    }
    
    private func createCollection() async throws {
        let url = URL(string: "\(baseURL)/api/v1/collections")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let collection = ChromaCollection(
            id: nil, // Let server assign ID
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
        
        guard let collectionId = collectionId else {
            throw ChromaError.networkError("Collection not initialized")
        }
        
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionId)/add")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert metadata to [String: Any]
        let metadataDict: [String: Any] = [
            "firebaseId": metadata.firebaseId,
            "userId": metadata.userId,
            "isTask": metadata.isTask ?? false,
            "categories": metadata.categories ?? [],
            "createdAt": metadata.createdAt
        ]
        
        let document = ChromaDocument(
            ids: [id],
            embeddings: [embedding],
            metadatas: [metadataDict],
            documents: [content]
        )
        
        let requestBody: [String: Any] = [
            "ids": document.ids,
            "embeddings": document.embeddings,
            "metadatas": document.metadatas,
            "documents": document.documents
        ]
        
        print("🔍 ChromaService: Adding document with ID: \(id)")
        print("🔍 ChromaService: Content length: \(content.count)")
        print("🔍 ChromaService: Embedding dimensions: \(embedding.count)")
        print("🔍 ChromaService: Metadata: \(metadataDict)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChromaError.networkError("Invalid response format")
        }
        
        if httpResponse.statusCode != 200 && httpResponse.statusCode != 201 {
            let errorMessage = "HTTP \(httpResponse.statusCode)"
            if let errorData = String(data: data, encoding: .utf8) {
                print("🔍 ChromaService addDocument error response: \(errorData)")
            }
            throw ChromaError.networkError("Failed to add document: \(errorMessage)")
        }
        
        print("✅ ChromaService: Successfully added document to ChromaDB")
    }
    
    func queryDocuments(
        embedding: [Double],
        userId: String,
        limit: Int = 10,
        filter: [String: Any]? = nil
    ) async throws -> ChromaQueryResult {
        
        guard let collectionId = collectionId else {
            throw ChromaError.networkError("Collection not initialized")
        }
        
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionId)/query")!
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
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChromaError.networkError("Invalid response format")
        }
        
        guard httpResponse.statusCode == 200 else {
            let errorMessage = "HTTP \(httpResponse.statusCode)"
            if let errorData = String(data: data, encoding: .utf8) {
                print("🔍 ChromaService query error response: \(errorData)")
            }
            throw ChromaError.networkError("Failed to query documents: \(errorMessage)")
        }
        
        return try JSONDecoder().decode(ChromaQueryResult.self, from: data)
    }
    
    func deleteDocument(id: String) async throws {
        guard let collectionId = collectionId else {
            throw ChromaError.networkError("Collection not initialized")
        }
        
        let url = URL(string: "\(baseURL)/api/v1/collections/\(collectionId)/delete")!
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
    
    private let apiKey: String
    private let session = URLSession.shared
    
    private init() {
        // Get API key from multiple sources (same as SparkServices)
        var key = ""
        
        // 1. Try environment variable first
        key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? ""
        
        // 2. Try Info.plist if environment variable is empty
        if key.isEmpty {
            key = Bundle.main.object(forInfoDictionaryKey: "OPENAI_API_KEY") as? String ?? ""
        }
        
        self.apiKey = key
        
        if apiKey.isEmpty {
            print("⚠️ OpenAI API key not found for embedding service")
        } else {
            print("✅ OpenAI API key configured for embedding service")
        }
    }
    
    func generateEmbedding(for text: String) async throws -> [Double] {
        let url = URL(string: "https://api.openai.com/v1/embeddings")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard !apiKey.isEmpty else {
            throw EmbeddingError.missingAPIKey
        }
        
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
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
    case missingAPIKey
    
    var errorDescription: String? {
        switch self {
        case .apiError(let message):
            return "Embedding API error: \(message)"
        case .missingAPIKey:
            return "OpenAI API key not configured"
        }
    }
}