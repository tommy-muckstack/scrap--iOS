import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

// MARK: - FloatingLabelTextField Component
struct FloatingLabelTextField: View {
    let placeholder: String
    @Binding var text: String
    var isSecureField: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isDisabled: Bool = false
    
    @FocusState private var isFocused: Bool
    @State private var isSecureTextVisible: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                // Background with border
                RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                    .fill(GentleLightning.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.medium)
                            .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
                    )
                    .frame(height: 56)
                
                // Floating Label - positioned more precisely like HuddleUp
                Text(placeholder)
                    .font(shouldShowFloatingLabel ? GentleLightning.Typography.caption : GentleLightning.Typography.bodyInput)
                    .foregroundColor(labelColor)
                    .padding(.leading, 16)
                    .offset(y: shouldShowFloatingLabel ? -18 : 0)
                    .scaleEffect(shouldShowFloatingLabel ? 0.85 : 1.0, anchor: .leading)
                    .animation(.easeInOut(duration: 0.2), value: shouldShowFloatingLabel)
                    .allowsHitTesting(false)
                
                // Text Input
                HStack {
                    if isSecureField && !isSecureTextVisible {
                        SecureField("", text: $text)
                            .font(GentleLightning.Typography.bodyInput)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .keyboardType(keyboardType)
                            .textContentType(textContentType)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(autocapitalization)
                            .focused($isFocused)
                            .disabled(isDisabled)
                    } else {
                        TextField("", text: $text)
                            .font(GentleLightning.Typography.bodyInput)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                            .keyboardType(keyboardType)
                            .textContentType(textContentType)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(autocapitalization)
                            .focused($isFocused)
                            .disabled(isDisabled)
                    }
                    
                    // Show/Hide password toggle
                    if isSecureField {
                        Button(action: {
                            isSecureTextVisible.toggle()
                        }) {
                            Image(systemName: isSecureTextVisible ? "eye.slash" : "eye")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                        }
                        .padding(.trailing, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
        }
        .opacity(isDisabled ? 0.6 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isFocused)
        .animation(.easeInOut(duration: 0.2), value: !text.isEmpty)
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowFloatingLabel: Bool {
        isFocused || !text.isEmpty
    }
    
    private var labelColor: Color {
        if isDisabled {
            return GentleLightning.Colors.textSecondary.opacity(0.5)
        } else if isFocused {
            return GentleLightning.Colors.accentNeutral
        } else if !text.isEmpty {
            return GentleLightning.Colors.textPrimary
        } else {
            return GentleLightning.Colors.textSecondary
        }
    }
    
    private var borderColor: Color {
        if isDisabled {
            return GentleLightning.Colors.textSecondary.opacity(0.1)
        } else if isFocused {
            return GentleLightning.Colors.accentNeutral
        } else {
            return GentleLightning.Colors.textSecondary.opacity(0.2)
        }
    }
}

// MARK: - Convenience Initializers for FloatingLabelTextField
extension FloatingLabelTextField {
    static func email(placeholder: String, text: Binding<String>, isDisabled: Bool = false) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            keyboardType: .emailAddress,
            textContentType: .emailAddress,
            autocapitalization: .never,
            isDisabled: isDisabled
        )
    }
    
    static func password(placeholder: String, text: Binding<String>, isDisabled: Bool = false) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            isSecureField: true,
            textContentType: .password,
            autocapitalization: .never,
            isDisabled: isDisabled
        )
    }
    
    static func newPassword(placeholder: String, text: Binding<String>, isDisabled: Bool = false) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            isSecureField: true,
            textContentType: .newPassword,
            autocapitalization: .never,
            isDisabled: isDisabled
        )
    }
    
    static func name(placeholder: String, text: Binding<String>, isDisabled: Bool = false) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            keyboardType: .default,
            textContentType: .name,
            autocapitalization: .words,
            isDisabled: isDisabled
        )
    }
}

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
                        Text("Scrap")
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
    @State private var confirmPassword = ""
    @State private var fullName = ""
    
    @State private var isCheckingEmail = false
    @State private var showingPasswordFields = false
    @State private var isSignUp = false
    @State private var error: String?
    
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isConfirmPasswordFocused: Bool
    @FocusState private var isFullNameFocused: Bool
    
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
                            
                            Text(getHeaderTitle())
                                .font(GentleLightning.Typography.hero)
                                .foregroundColor(GentleLightning.Colors.textPrimary)
                                .animation(.easeInOut(duration: 0.3), value: showingPasswordFields)
                            
                            Text(getSubtitle())
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textSecondary)
                                .multilineTextAlignment(.center)
                                .animation(.easeInOut(duration: 0.3), value: showingPasswordFields)
                        }
                        .padding(.top, 40)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Email field - always visible
                            FloatingLabelTextField.email(
                                placeholder: "Email Address",
                                text: $email
                            )
                            .focused($isEmailFocused)
                            .disabled(showingPasswordFields)
                            .onChange(of: email) { newValue in
                                if !showingPasswordFields && isValidEmail(newValue) && !isCheckingEmail {
                                    checkEmailExists()
                                }
                            }
                            
                            // Password fields - shown after email validation
                            if showingPasswordFields {
                                VStack(spacing: 16) {
                                    // Full name field (only for sign up)
                                    if isSignUp {
                                        FloatingLabelTextField.name(
                                            placeholder: "Full Name",
                                            text: $fullName
                                        )
                                        .focused($isFullNameFocused)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                    
                                    // Password field
                                    if isSignUp {
                                        FloatingLabelTextField.newPassword(
                                            placeholder: "Password",
                                            text: $password
                                        )
                                        .focused($isPasswordFocused)
                                    } else {
                                        FloatingLabelTextField.password(
                                            placeholder: "Password",
                                            text: $password
                                        )
                                        .focused($isPasswordFocused)
                                    }
                                    
                                    // Confirm password (only for sign up)
                                    if isSignUp {
                                        FloatingLabelTextField.newPassword(
                                            placeholder: "Confirm Password",
                                            text: $confirmPassword
                                        )
                                        .focused($isConfirmPasswordFocused)
                                        .transition(.move(edge: .top).combined(with: .opacity))
                                    }
                                }
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // Submit button
                            if showingPasswordFields {
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
                                            Text(getButtonText())
                                                .font(GentleLightning.Typography.body)
                                                .foregroundColor(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 52)
                                    .background(
                                        RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                            .fill(isFormValid ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.textSecondary.opacity(0.3))
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(!isFormValid || firebaseManager.isLoading)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // Back to email button
                            if showingPasswordFields {
                                Button("← Back to email") {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showingPasswordFields = false
                                        clearPasswordFields()
                                        error = nil
                                        isEmailFocused = true
                                    }
                                }
                                .font(GentleLightning.Typography.caption)
                                .foregroundColor(GentleLightning.Colors.accentNeutral)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            // Email checking indicator
                            if isCheckingEmail {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .tint(GentleLightning.Colors.accentNeutral)
                                    Text("Checking email...")
                                        .font(GentleLightning.Typography.caption)
                                        .foregroundColor(GentleLightning.Colors.textSecondary)
                                }
                                .transition(.opacity)
                            }
                            
                            // Error message
                            if let error = error {
                                Text(error)
                                    .font(GentleLightning.Typography.small)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .transition(.opacity)
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
    
    // MARK: - Helper Methods
    
    private func getHeaderTitle() -> String {
        if showingPasswordFields {
            return isSignUp ? "Create Account" : "Welcome Back"
        } else {
            return "Enter Email"
        }
    }
    
    private func getSubtitle() -> String {
        if showingPasswordFields {
            return isSignUp ? "Just a few details to get started" : "Enter your password to continue"
        } else {
            return "We'll check if you have an account"
        }
    }
    
    private func getButtonText() -> String {
        return isSignUp ? "Create Account" : "Sign In"
    }
    
    private var isFormValid: Bool {
        let hasValidEmail = !email.isEmpty && isValidEmail(email)
        let hasValidPassword = password.count >= 6
        
        if isSignUp {
            let hasValidName = !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let passwordsMatch = password == confirmPassword && !password.isEmpty
            return hasValidEmail && hasValidPassword && hasValidName && passwordsMatch
        } else {
            return hasValidEmail && hasValidPassword
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func clearPasswordFields() {
        password = ""
        confirmPassword = ""
        fullName = ""
    }
    
    private func checkEmailExists() {
        isCheckingEmail = true
        
        Task {
            // Simulate API call to check if email exists
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            
            // Demo implementation - checks against hardcoded list of existing emails
            let existingEmails = [
                "tommy@muckstack.com",
                "test@example.com",
                "user@test.com",
                "demo@spark.com"
            ]
            
            await MainActor.run {
                isCheckingEmail = false
                isSignUp = !existingEmails.contains(email.lowercased())
                
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingPasswordFields = true
                }
                
                // Focus appropriate field
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if isSignUp {
                        isFullNameFocused = true
                    } else {
                        isPasswordFocused = true
                    }
                }
                
                // Track analytics
                AnalyticsManager.shared.trackEvent("email_checked", properties: [
                    "is_new_user": isSignUp,
                    "email_domain": String(email.split(separator: "@").last ?? "")
                ])
            }
        }
    }
    
    private func handleSubmit() async {
        guard isFormValid else { return }
        
        error = nil
        
        do {
            if isSignUp {
                // Create new user
                let result = try await Auth.auth().createUser(withEmail: email, password: password)
                
                // Update profile with display name
                let changeRequest = result.user.createProfileChangeRequest()
                changeRequest.displayName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                try await changeRequest.commitChanges()
                
                AnalyticsManager.shared.trackUserSignedIn(method: "email_signup", email: result.user.email)
            } else {
                // Sign in existing user
                let result = try await Auth.auth().signIn(withEmail: email, password: password)
                AnalyticsManager.shared.trackUserSignedIn(method: "email_signin", email: result.user.email)
            }
            
            dismiss()
        } catch {
            self.error = error.localizedDescription
            
            // Track failed authentication
            AnalyticsManager.shared.trackEvent(isSignUp ? "auth_signup_failed" : "auth_signin_failed", properties: [
                "error": error.localizedDescription,
                "method": "email"
            ])
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