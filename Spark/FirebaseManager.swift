import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine

// MARK: - Firebase Note Model
struct FirebaseNote: Identifiable, Codable {
    @DocumentID var id: String?
    let userId: String
    let content: String
    let isTask: Bool
    let categories: [String]
    let createdAt: Date
    let updatedAt: Date
    let pineconeId: String? // Reference to vector in Pinecone
    
    var wrappedContent: String { content }
}

// MARK: - Firebase Manager
class FirebaseManager: ObservableObject {
    static let shared = FirebaseManager()
    
    private let db = Firestore.firestore()
    private let auth = Auth.auth()
    
    @Published var user: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    
    private var listenerRegistration: ListenerRegistration?
    
    init() {
        // Listen for auth state changes
        auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.user = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    // MARK: - Authentication
    func signInAnonymously() async throws {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        let result = try await auth.signInAnonymously()
        DispatchQueue.main.async {
            self.user = result.user
            self.isAuthenticated = true
            self.isLoading = false
        }
    }
    
    func signOut() throws {
        try auth.signOut()
        DispatchQueue.main.async {
            self.user = nil
            self.isAuthenticated = false
        }
    }
    
    // MARK: - Notes Operations
    func createNote(content: String, isTask: Bool, categories: [String] = []) async throws -> String {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let note = FirebaseNote(
            userId: userId,
            content: content,
            isTask: isTask,
            categories: categories,
            createdAt: Date(),
            updatedAt: Date(),
            pineconeId: nil // Will be updated after Pinecone insertion
        )
        
        let docRef = try await db.collection("notes").addDocument(from: note)
        
        // Track analytics
        AnalyticsManager.shared.trackItemCreated(isTask: isTask, contentLength: content.count)
        
        return docRef.documentID
    }
    
    func updateNotePineconeId(noteId: String, pineconeId: String) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "pineconeId": pineconeId,
            "updatedAt": Date()
        ])
    }
    
    func fetchNotes(limit: Int = 50) async throws -> [FirebaseNote] {
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let snapshot = try await db.collection("notes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: FirebaseNote.self)
        }
    }
    
    func deleteNote(noteId: String) async throws {
        try await db.collection("notes").document(noteId).delete()
        
        // Track analytics
        AnalyticsManager.shared.trackItemDeleted(isTask: false) // We don't have task info here
    }
    
    func toggleNoteCompletion(noteId: String, isCompleted: Bool) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "isCompleted": isCompleted,
            "updatedAt": Date()
        ])
        
        if isCompleted {
            AnalyticsManager.shared.trackItemCompleted(isTask: true)
        }
    }
    
    // MARK: - Real-time Listener
    func startListening(completion: @escaping ([FirebaseNote]) -> Void) {
        guard let userId = user?.uid else { return }
        
        listenerRegistration = db.collection("notes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { snapshot, error in
                guard let documents = snapshot?.documents else {
                    print("Error fetching notes: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                let notes = documents.compactMap { doc -> FirebaseNote? in
                    try? doc.data(as: FirebaseNote.self)
                }
                
                DispatchQueue.main.async {
                    completion(notes)
                }
            }
    }
    
    func stopListening() {
        listenerRegistration?.remove()
        listenerRegistration = nil
    }
    
    deinit {
        stopListening()
    }
}

// MARK: - Firebase Errors
enum FirebaseError: Error, LocalizedError {
    case notAuthenticated
    case documentNotFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "User not authenticated"
        case .documentNotFound:
            return "Document not found"
        case .invalidData:
            return "Invalid data format"
        }
    }
}