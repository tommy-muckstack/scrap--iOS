import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

struct AuthenticationView: View {
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    @State private var showingEmailEntry = false
    @State private var currentNonce: String?
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    
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
                                .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                .fill(GentleLightning.Colors.surface)
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
                                .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                .fill(GentleLightning.Colors.surface)
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
                                .stroke(GentleLightning.Colors.textSecondary.opacity(0.3), lineWidth: 1)
                                .fill(GentleLightning.Colors.surface)
                                .shadow(color: GentleLightning.Colors.shadowLight, radius: 8, x: 0, y: 2)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(firebaseManager.isLoading)
                    
                    // Or separator
                    HStack {
                        Rectangle()
                            .fill(GentleLightning.Colors.textSecondary.opacity(0.2))
                            .frame(height: 1)
                        
                        Text("Or")
                            .font(.custom("Satoshi-Regular", size: 14))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                            .padding(.horizontal, 16)
                        
                        Rectangle()
                            .fill(GentleLightning.Colors.textSecondary.opacity(0.2))
                            .frame(height: 1)
                    }
                    .padding(.vertical, 8)
                    
                    // Continue as Guest
                    Button(action: {
                        Task {
                            await signInAsGuest()
                        }
                    }) {
                        Text("Continue as Guest")
                            .font(.custom("Satoshi-Medium", size: 16))
                            .foregroundColor(GentleLightning.Colors.accentNeutral)
                            .underline()
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
                                .font(.custom("Satoshi-Regular", size: 14))
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                        }
                        .padding(.top, 8)
                    }
                    
                    // Privacy links
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://spark-app.com/terms")!)
                            .font(.custom("Satoshi-Regular", size: 12))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Text("|")
                            .font(.custom("Satoshi-Regular", size: 12))
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Link("Privacy Policy", destination: URL(string: "https://spark-app.com/privacy")!)
                            .font(.custom("Satoshi-Regular", size: 12))
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
        // TODO: Implement Google Sign In
        // For now, fallback to anonymous
        await signInAsGuest()
    }
    
    private func signInAsGuest() async {
        do {
            try await firebaseManager.signInAnonymously()
            AnalyticsManager.shared.trackEvent("auth_anonymous_signin")
        } catch {
            print("Failed to sign in anonymously: \(error)")
        }
    }
    
    private func performAppleSignIn() {
        // TODO: Implement Apple Sign In
        // For now, fallback to anonymous
        Task {
            await signInAsGuest()
        }
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
                                    .font(.custom("Satoshi-Medium", size: 14))
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
                                    .font(.custom("Satoshi-Medium", size: 14))
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
                                            .font(.custom("Satoshi-Medium", size: 16))
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
                                    .font(.custom("Satoshi-Regular", size: 14))
                                    .foregroundColor(GentleLightning.Colors.textSecondary)
                                
                                Button(isSignUp ? "Sign In" : "Sign Up") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        isSignUp.toggle()
                                        error = nil
                                    }
                                }
                                .font(.custom("Satoshi-Medium", size: 14))
                                .foregroundColor(GentleLightning.Colors.accentNeutral)
                            }
                            
                            // Error message
                            if let error = error {
                                Text(error)
                                    .font(.custom("Satoshi-Regular", size: 12))
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
                AnalyticsManager.shared.trackEvent("auth_email_signup")
            } else {
                // Sign in existing user
                let result = try await Auth.auth().signIn(withEmail: email, password: password)
                AnalyticsManager.shared.trackEvent("auth_email_signin")
            }
            
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Apple Sign In Coordinator
private class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
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
}

#Preview {
    AuthenticationView()
}