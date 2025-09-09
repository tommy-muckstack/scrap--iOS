import Foundation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
import Combine
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit

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
    private var authStateListener: AuthStateDidChangeListenerHandle?
    private var currentNonce: String?
    
    init() {
        // Listen for auth state changes
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.user = user
                self.isAuthenticated = user != nil
                
                // Update analytics user ID when auth state changes
                if let user = user, let email = user.email {
                    AnalyticsManager.shared.setUserIdToEmail(email)
                } else {
                    AnalyticsManager.shared.setUserIdToDeviceId()
                }
            }
        }
    }
    
    // MARK: - Authentication
    
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
            
            // Track successful Google sign in with analytics user ID update
            AnalyticsManager.shared.trackUserSignedIn(method: "google", email: authResult.user.email)
            
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
    
    func signInWithApple(authorization: ASAuthorization) async throws {
        DispatchQueue.main.async {
            self.isLoading = true
        }
        
        do {
            guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                throw FirebaseError.invalidData
            }
            
            guard let nonce = currentNonce else {
                throw FirebaseError.invalidData
            }
            
            guard let appleIDToken = appleIDCredential.identityToken else {
                throw FirebaseError.invalidData
            }
            
            guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                throw FirebaseError.invalidData
            }
            
            // Create Firebase credential
            let credential = OAuthProvider.credential(withProviderID: "apple.com",
                                                    idToken: idTokenString,
                                                    rawNonce: nonce)
            
            // Sign in with Firebase
            let authResult = try await auth.signIn(with: credential)
            
            // Save user display name if it's their first time
            if let fullName = appleIDCredential.fullName {
                let displayName = PersonNameComponentsFormatter.localizedString(
                    from: fullName,
                    style: .default
                )
                
                if !displayName.isEmpty {
                    let changeRequest = authResult.user.createProfileChangeRequest()
                    changeRequest.displayName = displayName
                    try await changeRequest.commitChanges()
                }
            }
            
            DispatchQueue.main.async {
                self.user = authResult.user
                self.isAuthenticated = true
                self.isLoading = false
            }
            
            // Track successful Apple sign in with analytics user ID update
            AnalyticsManager.shared.trackUserSignedIn(method: "apple", email: authResult.user.email)
            
        } catch {
            DispatchQueue.main.async {
                self.isLoading = false
            }
            
            // Track failed Apple sign in
            AnalyticsManager.shared.trackEvent("auth_apple_signin_failed", properties: [
                "error": error.localizedDescription
            ])
            
            throw error
        }
    }
    
    func generateNonce() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return nonce
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                let errorCode = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if errorCode != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(errorCode)")
                }
                return random
            }
            
            randoms.forEach { random in
                if remainingLength == 0 {
                    return
                }
                
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }
    
    func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        let hashString = hashedData.compactMap {
            String(format: "%02x", $0)
        }.joined()
        
        return hashString
    }
    
    func signOut() throws {
        // Track sign out before clearing user data
        AnalyticsManager.shared.trackUserSignedOut()
        
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
        if let authStateListener = authStateListener {
            auth.removeStateDidChangeListener(authStateListener)
        }
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