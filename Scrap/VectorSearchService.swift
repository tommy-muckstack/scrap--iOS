import Foundation
import FirebaseAuth

// MARK: - Vector Search Service
class VectorSearchService: ObservableObject {
    static let shared = VectorSearchService()
    
    private let chromaService = ChromaService.shared
    private let embeddingService = EmbeddingService.shared
    
    @Published var isSearching = false
    @Published var searchError: String?
    
    private init() {}
    
    // MARK: - Note Vector Operations
    
    /// Add or update a note's vector embedding in ChromaDB
    func indexNote(_ note: FirebaseNote) async throws {
        print("🔍 VectorSearchService: Starting indexNote for note ID: \(note.id ?? "unknown")")
        print("🔍 VectorSearchService: Note content length: \(note.content.count) chars")
        
        guard let userId = Auth.auth().currentUser?.uid else {
            print("❌ VectorSearchService: User not authenticated - cannot index note")
            throw VectorSearchError.notAuthenticated
        }
        
        print("🔍 VectorSearchService: User authenticated: \(userId)")
        print("🔍 VectorSearchService: Indexing note \(note.id ?? "unknown") for vector search...")
        
        do {
            // Combine title and content for better search indexing
            let searchableContent = [note.title, note.content]
                .compactMap { $0 }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            
            print("🔍 VectorSearchService: Generating embedding for combined title+content (\(searchableContent.count) chars)...")
            let embedding = try await embeddingService.generateEmbedding(for: searchableContent)
            print("🔍 VectorSearchService: Generated embedding with \(embedding.count) dimensions")
            
            // Create metadata for ChromaDB
            let metadata = ChromaMetadata(
                firebaseId: note.id ?? "",
                userId: userId,
                isTask: note.isTask,
                categories: note.categoryIds ?? [],
                createdAt: ISO8601DateFormatter().string(from: note.createdAt)
            )
            print("🔍 VectorSearchService: Created metadata for ChromaDB")
            
            // Store in ChromaDB with note ID as the vector ID
            print("🔍 VectorSearchService: Adding document to ChromaDB...")
            try await chromaService.addDocument(
                id: note.id ?? UUID().uuidString,
                content: searchableContent,
                embedding: embedding,
                metadata: metadata
            )
            
            print("✅ VectorSearchService: Successfully indexed note \(note.id ?? "unknown")")
        } catch {
            print("❌ VectorSearchService: Failed to index note \(note.id ?? "unknown"): \(error)")
            throw error
        }
    }
    
    /// Remove a note from vector search
    func removeNoteFromIndex(_ noteId: String) async throws {
        print("🗑️ VectorSearchService: Removing note \(noteId) from vector index...")
        try await chromaService.deleteDocument(id: noteId)
        print("✅ VectorSearchService: Successfully removed note \(noteId) from index")
    }
    
    // MARK: - Semantic Search
    
    /// Perform semantic search across user's notes
    @MainActor
    func semanticSearch(query: String, limit: Int = 10, categories: [String]? = nil) async throws -> [SearchResult] {
        guard let userId = Auth.auth().currentUser?.uid else {
            throw VectorSearchError.notAuthenticated
        }
        
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VectorSearchError.emptyQuery
        }
        
        isSearching = true
        searchError = nil
        
        defer { 
            isSearching = false
        }
        
        do {
            print("🔍 VectorSearchService: Performing semantic search for: '\(query)'")
            print("🔍 VectorSearchService: ChromaDB connected: \(chromaService.isConnected)")
            
            // Generate embedding for the search query
            print("🔍 VectorSearchService: Generating embedding for query: '\(query)'...")
            let queryEmbedding = try await embeddingService.generateEmbedding(for: query)
            print("🔍 VectorSearchService: Generated embedding with \(queryEmbedding.count) dimensions")
            
            // Debug: Show a few embedding values for diagnostic purposes
            if queryEmbedding.count >= 5 {
                print("🔍 VectorSearchService: First 5 embedding values: \(Array(queryEmbedding.prefix(5)))")
            }
            
            print("🔍 VectorSearchService: Searching for user: \(userId)")
            
            // Build filter for categories if specified
            var filter: [String: Any]? = nil
            if let categories = categories, !categories.isEmpty {
                filter = ["categories": ["$in": categories]]
            }
            
            // Query ChromaDB
            let results = try await chromaService.queryDocuments(
                embedding: queryEmbedding,
                userId: userId,
                limit: limit,
                filter: filter
            )
            
            // Debug: Log raw ChromaDB response
            print("🔍 VectorSearchService: Raw ChromaDB response:")
            print("   - IDs count: \(results.ids.count > 0 ? results.ids[0].count : 0)")
            print("   - Documents count: \(results.documents.count > 0 ? results.documents[0].count : 0)")
            print("   - Distances count: \(results.distances.count > 0 ? results.distances[0].count : 0)")
            print("   - Metadatas count: \(results.metadatas.count > 0 ? results.metadatas[0].count : 0)")
            
            if results.documents.count > 0 && results.documents[0].count > 0 {
                print("   - First document preview: \(String(results.documents[0][0].prefix(100)))")
                if results.distances.count > 0 && results.distances[0].count > 0 {
                    print("   - First document distance: \(results.distances[0][0])")
                }
            }
            
            // Enhanced diagnostic for empty results
            if results.ids.count == 0 || (results.ids.count > 0 && results.ids[0].count == 0) {
                print("⚠️ VectorSearchService: ChromaDB returned ZERO results for query: '\(query)'")
                print("   - This suggests either:")
                print("     1. No notes have been indexed in ChromaDB")
                print("     2. User filter is too restrictive") 
                print("     3. ChromaDB collection is empty")
                print("     4. Network/connectivity issues with ChromaDB")
                print("   - Checking ChromaDB connection status: \(chromaService.isConnected)")
                print("   - User ID filter: \(userId)")
            }
            
            // Convert to SearchResult objects
            let searchResults = convertToSearchResults(results)
            
            print("✅ VectorSearchService: Found \(searchResults.count) results for query: '\(query)'")
            
            return searchResults
            
        } catch {
            searchError = error.localizedDescription
            print("💥 VectorSearchService: Search failed: \(error)")
            throw error
        }
    }
    
    // MARK: - Q&A Functionality
    
    /// Answer questions based on user's notes using RAG (Retrieval-Augmented Generation)
    func answerQuestion(_ question: String, limit: Int = 5) async throws -> QAResult {
        guard Auth.auth().currentUser?.uid != nil else {
            throw VectorSearchError.notAuthenticated
        }
        
        print("❓ VectorSearchService: Answering question: '\(question)'")
        
        // First, find relevant notes using semantic search
        let relevantNotes = try await semanticSearch(query: question, limit: limit)
        
        guard !relevantNotes.isEmpty else {
            throw VectorSearchError.noRelevantNotes
        }
        
        // Combine the top relevant note contents as context
        let context = relevantNotes.prefix(3).map { result in
            "Note: \(result.content)"
        }.joined(separator: "\n\n")
        
        // Use OpenAI to generate an answer based on the context
        let answer = try await generateAnswerFromContext(question: question, context: context)
        
        return QAResult(
            question: question,
            answer: answer,
            sourceNotes: relevantNotes.prefix(3).map { $0.firebaseId },
            confidence: calculateConfidence(for: relevantNotes)
        )
    }
    
    // MARK: - Note Summarization
    
    /// Generate a summary of user's notes, optionally filtered by categories
    func summarizeNotes(categories: [String]? = nil, limit: Int = 20) async throws -> String {
        guard Auth.auth().currentUser?.uid != nil else {
            throw VectorSearchError.notAuthenticated
        }
        
        print("📝 VectorSearchService: Generating summary of user's notes...")
        
        // Get a diverse set of notes for summarization
        // Use a broad query to get representative content
        let searchQuery = categories?.joined(separator: " ") ?? "notes thoughts ideas tasks"
        let relevantNotes = try await semanticSearch(query: searchQuery, limit: limit, categories: categories)
        
        guard !relevantNotes.isEmpty else {
            throw VectorSearchError.noRelevantNotes
        }
        
        // Combine note contents for summarization
        let notesContent = relevantNotes.map { "• \($0.content)" }.joined(separator: "\n")
        
        // Generate summary using OpenAI
        let summary = try await generateSummary(from: notesContent)
        
        print("✅ VectorSearchService: Generated summary from \(relevantNotes.count) notes")
        
        return summary
    }
    
    // MARK: - Health Check
    
    /// Test ChromaDB connectivity
    func testConnection() async throws -> Bool {
        print("🔍 VectorSearchService: Testing ChromaDB connection...")
        let isHealthy = try await chromaService.healthCheck()
        print("🔍 VectorSearchService: ChromaDB health check result: \(isHealthy)")
        return isHealthy
    }
    
    /// Re-index all existing notes (useful for backfilling)
    func reindexAllNotes(_ notes: [FirebaseNote]) async {
        print("🔍 VectorSearchService: Re-indexing \(notes.count) existing notes...")
        
        for note in notes {
            do {
                try await indexNote(note)
                print("✅ VectorSearchService: Re-indexed note \(note.id ?? "unknown")")
            } catch {
                print("⚠️ VectorSearchService: Failed to re-index note \(note.id ?? "unknown"): \(error)")
            }
        }
        
        print("🎉 VectorSearchService: Re-indexing complete!")
    }
    
    /// Test semantic search with different terms to debug "foliage" vs "leaves" issue
    func testSemanticSearchDebug() async {
        print("🧪 VectorSearchService: Testing semantic search with various terms...")
        print("🧪 This test will help diagnose why 'foliage' might not find notes containing 'leaves'")
        
        let testTerms = [
            ("foliage", "Should find notes about leaves, plants, greenery"),
            ("leaves", "Should find notes with direct 'leaves' mentions"), 
            ("plants", "Should find botanical content"),
            ("nature", "Should find outdoor/natural content"),
            ("green", "Should find color or nature references"),
            ("trees", "Should find forestry content"),
            ("garden", "Should find gardening/plant content"),
            ("botanical", "Should find plant science content")
        ]
        
        for (term, expectation) in testTerms {
            print("\n🧪 Testing search term: '\(term)'")
            print("   Expected: \(expectation)")
            do {
                let results = try await semanticSearch(query: term, limit: 5)
                print("   Results found: \(results.count)")
                
                if results.isEmpty {
                    print("   ❌ No results found - might indicate indexing issue")
                } else {
                    for (i, result) in results.enumerated() {
                        let preview = String(result.content.prefix(80)).replacingOccurrences(of: "\n", with: " ")
                        print("   [\(i+1)] \(Int(result.similarity * 100))% match - \(preview)...")
                        
                        // Special check for foliage -> leaves connection
                        if term == "foliage" && result.content.lowercased().contains("leaves") {
                            print("       ✅ Found semantic connection: foliage query found 'leaves' content!")
                        } else if term == "leaves" && result.content.lowercased().contains("foliage") {
                            print("       ✅ Found semantic connection: leaves query found 'foliage' content!")
                        }
                    }
                }
            } catch {
                print("   ❌ Error: \(error)")
            }
        }
        
        print("\n🧪 Semantic search debug test complete!")
    }
    
    // MARK: - Private Helper Methods
    
    private func convertToSearchResults(_ chromaResults: ChromaQueryResult) -> [SearchResult] {
        var results: [SearchResult] = []
        
        print("🔍 VectorSearchService: Converting \(chromaResults.ids[0].count) raw results to SearchResults")
        
        for i in 0..<chromaResults.ids[0].count {
            let id = chromaResults.ids[0][i]
            let content = chromaResults.documents[0][i]
            let distance = chromaResults.distances[0][i]
            let metadata = chromaResults.metadatas[0][i]
            
            // Convert distance to similarity score (0-1, higher is better)
            print("🔍 VectorSearchService: Result \(i):")
            print("   - ID: \(id)")
            print("   - Content preview: \(String(content.prefix(60)))...")
            print("   - Raw distance: \(distance)")
            
            // Use inverse relationship for all distances since ChromaDB returns euclidean-style distances
            // Scale to give meaningful percentages: smaller distances = higher similarity
            let similarity = 1.0 / (1.0 + distance)
            
            print("   - Calculated similarity: \(similarity) (\(Int(similarity * 100))%)")
            
            // Log semantic quality assessment
            if similarity > 0.85 {
                print("   - Quality: EXCELLENT match")
            } else if similarity > 0.70 {
                print("   - Quality: GOOD match") 
            } else if similarity > 0.50 {
                print("   - Quality: MODERATE match")
            } else if similarity > 0.30 {
                print("   - Quality: WEAK match")
            } else {
                print("   - Quality: VERY WEAK match")
            }
            
            let result = SearchResult(
                firebaseId: metadata.firebaseId,
                content: content,
                similarity: similarity,
                isTask: metadata.isTask ?? false,
                categories: metadata.categories ?? [],
                createdAt: ISO8601DateFormatter().date(from: metadata.createdAt) ?? Date()
            )
            
            results.append(result)
        }
        
        // Sort by similarity (highest first) for better user experience
        results.sort { $0.similarity > $1.similarity }
        
        print("🔍 VectorSearchService: Final results summary:")
        print("   - Total results before filtering: \(results.count)")
        if let bestMatch = results.first {
            print("   - Best match similarity: \(Int(bestMatch.similarity * 100))%")
        }
        if let worstMatch = results.last {
            print("   - Worst match similarity: \(Int(worstMatch.similarity * 100))%")
        }
        
        // Apply minimum similarity threshold to filter out very weak results
        // This may be why "foliage" -> "leaves" isn't showing up if the similarity is too low
        let minimumSimilarityThreshold = 0.15 // 15% - fairly permissive threshold
        let filteredResults = results.filter { $0.similarity >= minimumSimilarityThreshold }
        
        if filteredResults.count != results.count {
            print("🔍 VectorSearchService: Filtered out \(results.count - filteredResults.count) results below \(Int(minimumSimilarityThreshold * 100))% similarity threshold")
        }
        
        print("🔍 VectorSearchService: Final filtered results: \(filteredResults.count)")
        
        return filteredResults
    }
    
    private func generateAnswerFromContext(question: String, context: String) async throws -> String {
        return try await OpenAIService.shared.answerQuestion(question: question, context: context)
    }
    
    private func generateSummary(from content: String) async throws -> String {
        return try await OpenAIService.shared.summarizeContent(content)
    }
    
    private func calculateConfidence(for results: [SearchResult]) -> Double {
        guard !results.isEmpty else { return 0.0 }
        
        // Calculate confidence based on top result's similarity
        let topSimilarity = results.first?.similarity ?? 0.0
        
        // Scale to confidence percentage
        return min(topSimilarity * 100, 95.0) // Cap at 95%
    }
}

// NOTE: SearchResult model moved to ContentView.swift for better accessibility

// MARK: - Q&A Result Model
struct QAResult {
    let question: String
    let answer: String
    let sourceNotes: [String] // Firebase note IDs
    let confidence: Double
    
    var confidencePercentage: Int {
        Int(confidence)
    }
}

// MARK: - Vector Search Errors
enum VectorSearchError: Error, LocalizedError {
    case notAuthenticated
    case emptyQuery
    case noRelevantNotes
    case searchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .emptyQuery:
            return "Search query cannot be empty"
        case .noRelevantNotes:
            return "No relevant notes found"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        }
    }
}