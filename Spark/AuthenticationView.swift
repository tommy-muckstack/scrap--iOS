import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

struct AuthenticationView: View {
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    @State private var showingEmailEntry = false
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // Background
            Color.white
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top section with logo and welcome text
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        // Spark logo/icon in top left
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        GentleLightning.Colors.accentIdea,
                                        GentleLightning.Colors.accentNeutral
                                    ],
                                    center: .center,
                                    startRadius: 20,
                                    endRadius: 50
                                )
                            )
                            .frame(width: 80, height: 80)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(.white)
                            )
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    
                    // Welcome text below logo (left aligned)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to Spark")
                            .font(GentleLightning.Typography.hero)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text("Capture thoughts. Spark ideas.")
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    
                    Spacer()
                }
                
                // Bottom section with authentication buttons
                VStack(spacing: 12) {
                    // Continue with Google
                    Button(action: {
                        Task {
                            await signInWithGoogle()
                        }
                    }) {
                        HStack(spacing: 12) {
                            // Google G logo
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(GentleLightning.Colors.shadowLight, lineWidth: 1)
                                    )
                                Text("G")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            }
                            
                            Text("Continue with Google")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                .fill(GentleLightning.Colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                        .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(firebaseManager.isLoading)
                    
                    // Sign in with Apple
                    Button(action: {
                        performAppleSignIn()
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "applelogo")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                            
                            Text("Continue with Apple")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                .fill(GentleLightning.Colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                        .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(firebaseManager.isLoading)
                    
                    // Email/Password option
                    Button(action: {
                        showingEmailEntry = true
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                            
                            Text("Continue with Email")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(
                            RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                .fill(GentleLightning.Colors.surface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                        .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                )
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(firebaseManager.isLoading)
                    
                    
                    // Loading indicator
                    if firebaseManager.isLoading {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(GentleLightning.Colors.accentNeutral)
                            Text("Signing in...")
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                        }
                        .padding(.top, 8)
                    }
                    
                    // Error message
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    
                    // Privacy links
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://spark-app.com/terms")!)
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Text("|")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Link("Privacy Policy", destination: URL(string: "https://spark-app.com/privacy")!)
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .sheet(isPresented: $showingEmailEntry) {
            EmailAuthView()
        }
    }
    
    // MARK: - Authentication Actions
    
    private func signInWithGoogle() async {
        do {
            errorMessage = nil
            try await firebaseManager.signInWithGoogle()
        } catch {
            await MainActor.run {
                self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
            }
            print("Google Sign-In failed: \(error.localizedDescription)")
        }
    }
    
    
    private func performAppleSignIn() {
        errorMessage = nil
        
        let nonce = firebaseManager.generateNonce()
        
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let request = appleIDProvider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = firebaseManager.sha256(nonce)
        
        let authController = ASAuthorizationController(authorizationRequests: [request])
        
        appleSignInCoordinator = AppleSignInCoordinator { result in
            Task {
                switch result {
                case .success(let authorization):
                    do {
                        try await firebaseManager.signInWithApple(authorization: authorization)
                    } catch {
                        await MainActor.run {
                            self.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                        }
                    }
                case .failure(let error):
                    await MainActor.run {
                        if (error as NSError).code != ASAuthorizationError.canceled.rawValue {
                            self.errorMessage = "Apple Sign-In failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
        }
        
        authController.delegate = appleSignInCoordinator
        authController.presentationContextProvider = appleSignInCoordinator
        authController.performRequests()
    }
}

// MARK: - Email Authentication View
struct EmailAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    
    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var error: String?
    
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.white
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [
                                            GentleLightning.Colors.accentIdea,
                                            GentleLightning.Colors.accentNeutral
                                        ],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 40
                                    )
                                )
                                .frame(width: 60, height: 60)
                                .overlay(
                                    Image(systemName: "envelope")
                                        .font(.system(size: 24, weight: .medium))
                                        .foregroundColor(.white)
                                )
                            
                            Text(isSignUp ? "Create Account" : "Sign In")
                                .font(GentleLightning.Typography.hero)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                            
                            Text("Enter your email to continue")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 16) {
                            // Email field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Email")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(GentleLightning.Colors.textPrimary)
                                
                                TextField("Enter your email", text: $email)
                                    .font(GentleLightning.Typography.bodyInput)
                                    .foregroundColor(GentleLightning.Colors.textPrimary)
                                    .keyboardType(.emailAddress)
                                    .textContentType(.emailAddress)
                                    .autocapitalization(.none)
                                    .focused($isEmailFocused)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                            .fill(GentleLightning.Colors.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                                    .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            // Password field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Password")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(GentleLightning.Colors.textPrimary)
                                
                                SecureField("Enter your password", text: $password)
                                    .font(GentleLightning.Typography.bodyInput)
                                    .foregroundColor(GentleLightning.Colors.textPrimary)
                                    .textContentType(isSignUp ? .newPassword : .password)
                                    .focused($isPasswordFocused)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                            .fill(GentleLightning.Colors.surface)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                                    .stroke(GentleLightning.Colors.textSecondary.opacity(0.2), lineWidth: 1)
                                            )
                                    )
                            }
                            
                            // Submit button
                            Button(action: {
                                Task {
                                    await handleSubmit()
                                }
                            }) {
                                HStack {
                                    if firebaseManager.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Text(isSignUp ? "Create Account" : "Sign In")
                                            .font(Font.custom("Office Notes", size: 16))
                                            .foregroundColor(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                                        .fill(isFormValid ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.textSecondary.opacity(0.3))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!isFormValid || firebaseManager.isLoading)
                            
                            // Toggle sign up/in
                            HStack {
                                Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(GentleLightning.Colors.textSecondary)
                                
                                Button(isSignUp ? "Sign In" : "Sign Up") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isSignUp.toggle()
                                        error = nil
                                    }
                                }
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.accentNeutral)
                            }
                            
                            // Error message
                            if let error = error {
                                Text(error)
                                    .font(GentleLightning.Typography.small)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 8)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                }
            }
            .navigationTitle("Email Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(GentleLightning.Colors.accentNeutral)
                }
            }
        }
        .onAppear {
            isEmailFocused = true
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && password.count >= 6 && email.contains("@")
    }
    
    private func handleSubmit() async {
        guard isFormValid else { return }
        
        error = nil
        
        do {
            if isSignUp {
                // Create new user
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                AnalyticsManager.shared.trackUserSignedIn(method: "email_signup", email: result.user.email)
            } else {
                // Sign in existing user
                let result = try await Auth.auth().signIn(withEmail: email, password: password)
                AnalyticsManager.shared.trackUserSignedIn(method: "email_signin", email: result.user.email)
            }
            
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Apple Sign In Coordinator
private class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let completion: (Result<ASAuthorization, Error>) -> Void
    
    init(completion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.completion = completion
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        completion(.success(authorization))
    }
    
    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        completion(.failure(error))
    }
    
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return ASPresentationAnchor()
        }
        return window
    }
}

#Preview {
    AuthenticationView()
}