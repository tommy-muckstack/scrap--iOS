import Foundation
import FirebaseFirestore
import FirebaseAuth
import Combine
import GoogleSignIn
import UIKit

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
    
    func signInWithGoogle() async throws {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            throw FirebaseError.invalidData
        }
        
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw FirebaseError.invalidData
            }
            
            // Configure Google Sign In
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            // Start the Google Sign In flow
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw FirebaseError.invalidData
            }
            
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            // Sign in with Firebase
            let authResult = try await auth.signIn(with: credential)
            
            DispatchQueue.main.async {
                self.user = authResult.user
                self.isAuthenticated = true
                self.isLoading = false
            }
            
            // Track successful Google sign in
            AnalyticsManager.shared.trackEvent("auth_google_signin_success")
            
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            
            // Track failed Google sign in
            AnalyticsManager.shared.trackEvent("auth_google_signin_failed", properties: [
                "error": error.localizedDescription
            ])
            
            throw error
        }
    }
    
    func signOut() throws {
        try auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        
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