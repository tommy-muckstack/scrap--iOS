import Foundation
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseCore
import Combine
import GoogleSignIn
import UIKit
import AuthenticationServices
import CryptoKit


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
    
    // Screenshot demo mode
    private var isScreenshotMode: Bool {
        return ProcessInfo.processInfo.environment["SCREENSHOT_MODE"] == "true"
    }
    
    init() {
        // Check for screenshot mode
        if isScreenshotMode {
            print("🎬 FirebaseManager: Screenshot mode enabled - bypassing authentication")
            Task { @MainActor in
                self.isAuthenticated = true
                // Set a mock user for screenshot mode
                AnalyticsManager.shared.setUserIdToDeviceId()
            }
            return
        }
        
        // Listen for auth state changes
        authStateListener = auth.addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
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
    
    @MainActor
    func signInWithGoogle() async throws {
        print("FirebaseManager: Starting Google Sign-In")
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first,
              let rootViewController = window.rootViewController else {
            print("FirebaseManager: Failed to get root view controller")
            throw FirebaseError.invalidData
        }
        
        print("FirebaseManager: Got root view controller: \(rootViewController)")
        
        self.isLoading = true
        
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                print("FirebaseManager: Failed to get Firebase client ID")
                throw FirebaseError.invalidData
            }
            
            print("FirebaseManager: Using client ID: \(clientID)")
            
            // Configure Google Sign In
            let config = GIDConfiguration(clientID: clientID)
            GIDSignIn.sharedInstance.configuration = config
            
            print("FirebaseManager: Google Sign-In configured")
            
            // Start the Google Sign In flow on main thread
            print("FirebaseManager: Starting Google Sign-In flow...")
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)
            print("FirebaseManager: Google Sign-In completed successfully")
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw FirebaseError.invalidData
            }
            
            let accessToken = result.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            // Sign in with Firebase
            let authResult = try await auth.signIn(with: credential)
            
            self.user = authResult.user
            self.isAuthenticated = true
            self.isLoading = false
            
            // Track successful Google sign in with analytics user ID update
            AnalyticsManager.shared.trackUserSignedIn(method: "google", email: authResult.user.email)
            
        } catch {
            self.isLoading = false
            
            // Track failed Google sign in
            AnalyticsManager.shared.trackEvent("auth_google_signin_failed", properties: [
                "error": error.localizedDescription
            ])
            
            throw error
        }
    }
    
    @MainActor
    func signInWithApple(authorization: ASAuthorization) async throws {
        self.isLoading = true
        
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
            let credential = OAuthProvider.credential(
                providerID: AuthProviderID.apple,
                idToken: idTokenString,
                rawNonce: nonce
            )
            
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
            
            self.user = authResult.user
            self.isAuthenticated = true
            self.isLoading = false
            
            // Track successful Apple sign in with analytics user ID update
            AnalyticsManager.shared.trackUserSignedIn(method: "apple", email: authResult.user.email)
            
        } catch {
            self.isLoading = false
            
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
        
        Task { @MainActor in
            self.user = nil
            self.isAuthenticated = false
        }
    }
    
    func deleteAccount() async throws {
        guard let user = user else {
            throw FirebaseError.notAuthenticated
        }
        
        let userId = user.uid
        
        // Track account deletion start
        AnalyticsManager.shared.trackEvent("account_deletion_started", properties: [
            "user_id": userId
        ])
        
        // First, delete all user's notes
        let snapshot = try await db.collection("notes")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        
        // Delete all notes in batch
        let batch = db.batch()
        for document in snapshot.documents {
            batch.deleteDocument(document.reference)
        }
        try await batch.commit()
        
        // Track notes deletion
        AnalyticsManager.shared.trackEvent("account_notes_deleted", properties: [
            "user_id": userId,
            "notes_deleted": snapshot.documents.count
        ])
        
        // Delete the user account - this may require recent authentication
        do {
            try await user.delete()
            
            // Track successful account deletion
            AnalyticsManager.shared.trackEvent("account_deleted_successfully", properties: [
                "user_id": userId,
                "notes_deleted": snapshot.documents.count
            ])
        } catch {
            // If account deletion fails, we still want to sign out the user
            // This often happens when the user needs to re-authenticate
            print("Failed to delete Firebase user account: \(error.localizedDescription)")
            
            // Track partial deletion (notes deleted but account deletion failed)
            AnalyticsManager.shared.trackEvent("account_deletion_partial", properties: [
                "user_id": userId,
                "notes_deleted": snapshot.documents.count,
                "error": error.localizedDescription
            ])
            
            // Still proceed with sign out to at least log the user out locally
        }
        
        // Always sign out from Google regardless of account deletion success
        GIDSignIn.sharedInstance.signOut()
        
        // Always clear local state and sign out from Firebase Auth
        try? auth.signOut()
        
        await MainActor.run {
            self.user = nil
            self.isAuthenticated = false
        }
        
        // Track final sign out
        AnalyticsManager.shared.trackEvent("account_deletion_completed", properties: [
            "user_id": userId
        ])
    }
    
    // MARK: - Notes Operations
    func createNote(content: String, title: String? = nil, categoryIds: [String] = [], isTask: Bool, categories: [String] = [], creationType: String = "text", rtfData: Data? = nil) async throws -> String {
        
        guard let userId = user?.uid else {
            print("❌ FirebaseManager: User not authenticated!")
            throw FirebaseError.notAuthenticated
        }
        
        print("✅ FirebaseManager: User authenticated with ID: \(userId)")
        
        // Convert RTF data to base64 string for Firebase storage
        let rtfContentString = rtfData?.base64EncodedString()
        
        let note = FirebaseNote(
            userId: userId,
            content: content,
            title: title,
            categoryIds: categoryIds,
            isTask: isTask,
            categories: categories, // Legacy field for backward compatibility
            createdAt: Date(),
            updatedAt: Date(),
            pineconeId: nil, // Will be updated after Pinecone insertion
            creationType: creationType,
            rtfContent: rtfContentString // Store RTF from the start
        )
        
        print("📝 FirebaseManager: Created note object: \(note)")
        
        do {
            let docRef = try db.collection("notes").addDocument(from: note)
            print("🎉 FirebaseManager: Successfully saved note with ID: \(docRef.documentID)")
            
            // Update note with actual document ID for vector search
            var noteWithId = note
            noteWithId.id = docRef.documentID
            
            // Index note for vector search (async, don't block save)
            Task {
                do {
                    try await VectorSearchService.shared.indexNote(noteWithId)
                    print("✅ FirebaseManager: Successfully indexed note \(docRef.documentID)")
                } catch {
                    print("⚠️ FirebaseManager: Failed to index note for vector search: \(error)")
                    // Don't throw - vector indexing failure shouldn't block note saving
                }
            }
            
            // Track analytics
            AnalyticsManager.shared.trackItemCreated(isTask: isTask, contentLength: content.count, creationType: creationType)
            
            return docRef.documentID
        } catch let error {
            print("💥 FirebaseManager: Failed to save note to Firestore: \(error)")
            throw error
        }
    }
    
    func updateNote(noteId: String, newContent: String) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "content": newContent,
            "updatedAt": Date()
        ])
        
        // Update vector search index (async, don't block update)
        Task {
            do {
                // Fetch the updated note to get complete data for re-indexing
                let noteDoc = try await db.collection("notes").document(noteId).getDocument()
                if let note = try? noteDoc.data(as: FirebaseNote.self) {
                    try await VectorSearchService.shared.indexNote(note)
                }
            } catch {
                print("⚠️ FirebaseManager: Failed to update vector index after note update: \(error)")
            }
        }
    }
    
    func updateNoteWithRTF(noteId: String, rtfData: Data) async throws {
        // Store RTF data as base64 string for Firebase compatibility
        let base64RTF = rtfData.base64EncodedString()
        try await db.collection("notes").document(noteId).updateData([
            "rtfContent": base64RTF,
            "updatedAt": Date()
        ])
        
        // Update vector search index (async, don't block update)
        Task {
            do {
                // Fetch the updated note to get complete data for re-indexing
                let noteDoc = try await db.collection("notes").document(noteId).getDocument()
                if let note = try? noteDoc.data(as: FirebaseNote.self) {
                    try await VectorSearchService.shared.indexNote(note)
                }
            } catch {
                print("⚠️ FirebaseManager: Failed to update vector index after RTF update: \(error)")
            }
        }
    }
    
    func updateNotePineconeId(noteId: String, pineconeId: String) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "pineconeId": pineconeId,
            "updatedAt": Date()
        ])
    }
    
    func updateNoteTitle(noteId: String, title: String) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "title": title,
            "updatedAt": Date()
        ])
        
        // Update vector search index (async, don't block update)
        Task {
            do {
                // Fetch the updated note to get complete data for re-indexing
                let noteDoc = try await db.collection("notes").document(noteId).getDocument()
                if let note = try? noteDoc.data(as: FirebaseNote.self) {
                    try await VectorSearchService.shared.indexNote(note)
                }
            } catch {
                print("⚠️ FirebaseManager: Failed to update vector index after title update: \(error)")
            }
        }
    }
    
    func updateNoteCategories(noteId: String, categoryIds: [String]) async throws {
        try await db.collection("notes").document(noteId).updateData([
            "categoryIds": categoryIds,
            "updatedAt": Date()
        ])
    }
    
    func fetchNotes(limit: Int = 50) async throws -> [FirebaseNote] {
        // Return demo data in screenshot mode
        if isScreenshotMode {
            return getScreenshotDemoNotes()
        }
        
        guard let userId = user?.uid else {
            throw FirebaseError.notAuthenticated
        }
        
        let snapshot = try await db.collection("notes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .limit(to: limit)
            .getDocuments()
        
        return snapshot.documents.compactMap { doc in
            try? doc.data(as: FirebaseNote.self)
        }
    }
    
    func deleteNote(noteId: String) async throws {
        try await db.collection("notes").document(noteId).delete()
        
        // Remove from vector search index (async, don't block delete)
        Task {
            do {
                try await VectorSearchService.shared.removeNoteFromIndex(noteId)
            } catch {
                print("⚠️ FirebaseManager: Failed to remove note from vector index: \(error)")
            }
        }
        
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
        // Return demo data immediately in screenshot mode
        if isScreenshotMode {
            Task { @MainActor in
                completion(getScreenshotDemoNotes())
            }
            return
        }
        
        guard let userId = user?.uid else { 
            return 
        }
        
        listenerRegistration = db.collection("notes")
            .whereField("userId", isEqualTo: userId)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    print("Error fetching notes: \(error.localizedDescription)")
                    return
                }
                
                guard let documents = snapshot?.documents else {
                    return
                }
                
                let notes = documents.compactMap { doc -> FirebaseNote? in
                    try? doc.data(as: FirebaseNote.self)
                }
                
                Task { @MainActor in
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
    
    // MARK: - Screenshot Demo Data
    private func getScreenshotDemoNotes() -> [FirebaseNote] {
        let now = Date()
        let calendar = Calendar.current
        
        return [
            FirebaseNote(
                id: "demo1",
                userId: "demo-user",
                content: "Morning reflection: Woke up feeling grateful for the small moments of peace in my daily routine. There's something beautiful about watching the sunrise while having my first cup of coffee.",
                title: "Gratitude Practice",
                categoryIds: [],
                isTask: false,
                categories: [],
                createdAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .hour, value: -2, to: now) ?? now,
                pineconeId: nil,
                creationType: "text",
                rtfContent: nil
            ),
            FirebaseNote(
                id: "demo2",
                userId: "demo-user",
                content: "Read an inspiring quote today: 'The only way to do great work is to love what you do.' This really resonates with my current career transition.",
                title: "Daily Inspiration",
                categoryIds: [],
                isTask: false,
                categories: [],
                createdAt: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .hour, value: -5, to: now) ?? now,
                pineconeId: nil,
                creationType: "text",
                rtfContent: nil
            ),
            FirebaseNote(
                id: "demo3",
                userId: "demo-user",
                content: "Breakthrough insight during meditation: I've been holding onto perfectionism as a form of self-protection, but it's actually preventing me from taking meaningful risks and growing.",
                title: "Self-Discovery",
                categoryIds: [],
                isTask: false,
                categories: [],
                createdAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .day, value: -1, to: now) ?? now,
                pineconeId: nil,
                creationType: "voice",
                rtfContent: nil
            ),
            FirebaseNote(
                id: "demo4",
                userId: "demo-user",
                content: "Goals for next month: Start a daily journaling practice, read two books on emotional intelligence, and have honest conversations with close friends about my personal growth journey.",
                title: "Monthly Goals",
                categoryIds: [],
                isTask: false,
                categories: [],
                createdAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .day, value: -2, to: now) ?? now,
                pineconeId: nil,
                creationType: "text",
                rtfContent: nil
            ),
            FirebaseNote(
                id: "demo5",
                userId: "demo-user",
                content: "Powerful realization: My anxiety often stems from trying to control outcomes that are beyond my influence. Learning to focus on my actions and responses instead.",
                title: "Mindfulness Notes",
                categoryIds: [],
                isTask: false,
                categories: [],
                createdAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                updatedAt: calendar.date(byAdding: .day, value: -3, to: now) ?? now,
                pineconeId: nil,
                creationType: "voice",
                rtfContent: nil
            )
        ]
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