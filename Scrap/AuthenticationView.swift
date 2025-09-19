import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import AuthenticationServices

// MARK: - FloatingLabelTextField Component (HuddleUp implementation with Scrap design system)
struct FloatingLabelTextField: View {
    // MARK: - Properties
    let placeholder: String
    @Binding var text: String
    let keyboardType: UIKeyboardType
    let contentType: UITextContentType?
    let isSecure: Bool
    let colors: FloatingLabelColors
    let fonts: FloatingLabelFonts
    let animation: FloatingLabelAnimation
    
    // State management
    @FocusState private var isFocused: Bool
    @State private var isAnimated: Bool = false
    @State private var showPassword: Bool = false
    
    // MARK: - Computed Properties
    private var shouldShowFloatingLabel: Bool {
        isFocused || !text.isEmpty
    }
    
    private var borderColor: Color {
        if isFocused {
            return colors.focusedBorder
        } else {
            return colors.defaultBorder
        }
    }
    
    private var labelColor: Color {
        if isFocused {
            return colors.focusedLabel
        } else if shouldShowFloatingLabel {
            return colors.floatingLabel
        } else {
            return colors.placeholder
        }
    }
    
    // MARK: - Initializers
    init(
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        contentType: UITextContentType? = nil,
        isSecure: Bool = false,
        colors: FloatingLabelColors = .scrapDefault,
        fonts: FloatingLabelFonts = .scrapDefault,
        animation: FloatingLabelAnimation = .default
    ) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
        self.contentType = contentType
        self.isSecure = isSecure
        self.colors = colors
        self.fonts = fonts
        self.animation = animation
    }
    
    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                // Background and border
                RoundedRectangle(cornerRadius: 12)
                    .fill(colors.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(borderColor, lineWidth: isFocused ? 2 : 1)
                    )
                    .frame(height: 56)
                    .onTapGesture {
                        isFocused = true
                    }
                
                // Input field
                VStack {
                    if shouldShowFloatingLabel {
                        Spacer()
                            .frame(height: 20)
                    } else {
                        Spacer()
                    }
                    
                    HStack {
                        if isSecure && !showPassword {
                            SecureField("", text: $text)
                                .font(fonts.input)
                                .foregroundColor(colors.inputText)
                                .focused($isFocused)
                                .textContentType(contentType)
                        } else {
                            TextField("", text: $text)
                                .font(fonts.input)
                                .foregroundColor(colors.inputText)
                                .keyboardType(keyboardType)
                                .textContentType(contentType)
                                .focused($isFocused)
                                .autocorrectionDisabled()
                        }
                        
                        // Show/Hide password toggle for secure fields
                        if isSecure {
                            Button(action: {
                                // Toggle password visibility while maintaining focus
                                let wasFocused = isFocused
                                showPassword.toggle()
                                if wasFocused {
                                    // Ensure focus is maintained after the toggle
                                    DispatchQueue.main.async {
                                        isFocused = true
                                    }
                                }
                            }) {
                                Text(showPassword ? "HIDE" : "SHOW")
                                    .font(fonts.floatingLabel)
                                    .foregroundColor(colors.focusedLabel)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    
                    if shouldShowFloatingLabel {
                        Spacer()
                            .frame(height: 8)
                    } else {
                        Spacer()
                    }
                }
                .padding(.horizontal, 16)
                
                // Floating label
                Text(placeholder)
                    .font(shouldShowFloatingLabel ? fonts.floatingLabel : fonts.placeholder)
                    .foregroundColor(labelColor)
                    .background(
                        // Background to hide border line
                        Rectangle()
                            .fill(colors.background)
                            .padding(.horizontal, -4)
                            .opacity(shouldShowFloatingLabel ? 1 : 0)
                    )
                    .padding(.horizontal, shouldShowFloatingLabel ? 12 : 16)
                    .padding(.top, shouldShowFloatingLabel ? -8 : 18)
                    .scaleEffect(shouldShowFloatingLabel ? 1 : 1, anchor: .topLeading)
                    .animation(
                        .easeOut(duration: 0.15),
                        value: shouldShowFloatingLabel
                    )
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(placeholder)
        .accessibilityValue(text.isEmpty ? "Empty" : text)
        .accessibilityHint(isFocused ? "Currently editing" : "Double tap to edit")
    }
}

// MARK: - Configuration Structs for Scrap
struct FloatingLabelColors {
    let background: Color
    let inputText: Color
    let placeholder: Color
    let floatingLabel: Color
    let focusedLabel: Color
    let defaultBorder: Color
    let focusedBorder: Color
    
    static let scrapDefault = FloatingLabelColors(
        background: GentleLightning.Colors.surface,
        inputText: GentleLightning.Colors.textPrimary,
        placeholder: GentleLightning.Colors.textSecondary,
        floatingLabel: GentleLightning.Colors.textPrimary,
        focusedLabel: GentleLightning.Colors.accentNeutral,
        defaultBorder: GentleLightning.Colors.textSecondary.opacity(0.2),
        focusedBorder: GentleLightning.Colors.accentNeutral
    )
}

struct FloatingLabelFonts {
    let input: Font
    let placeholder: Font
    let floatingLabel: Font
    
    static let scrapDefault = FloatingLabelFonts(
        input: GentleLightning.Typography.bodyInput,
        placeholder: GentleLightning.Typography.bodyInput,
        floatingLabel: GentleLightning.Typography.caption
    )
}

struct FloatingLabelAnimation {
    let duration: TimeInterval
    let curve: Animation
    
    static let `default` = FloatingLabelAnimation(
        duration: 0.2,
        curve: .easeInOut(duration: 0.2)
    )
}

// MARK: - Convenience Initializers for FloatingLabelTextField
extension FloatingLabelTextField {
    // Email field
    static func email(placeholder: String, text: Binding<String>) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            keyboardType: .emailAddress,
            contentType: .emailAddress
        )
    }
    
    // Password field
    static func password(placeholder: String, text: Binding<String>) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            contentType: .password,
            isSecure: true
        )
    }
    
    // New password field
    static func newPassword(placeholder: String, text: Binding<String>) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            contentType: .newPassword,
            isSecure: true
        )
    }
    
    // Name field
    static func name(placeholder: String, text: Binding<String>) -> FloatingLabelTextField {
        FloatingLabelTextField(
            placeholder: placeholder,
            text: text,
            keyboardType: .namePhonePad,
            contentType: .name
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
            // Background - always light mode for login
            GentleLightning.Colors.background(isDark: false)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top section with logo and welcome text
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        // App logo
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 80, height: 80)
                            .environment(\.colorScheme, .light) // Force light mode logo
                        
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    
                    // Welcome text below logo (left aligned)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Scrap")
                            .font(.custom("SpaceGrotesk-Bold", size: 48))
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        
                        Text("The world's simplest notepad")
                            .font(GentleLightning.Typography.title)
                            .foregroundColor(GentleLightning.Colors.textSecondary(isDark: false))
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
                                    .fill(GentleLightning.Colors.background)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle()
                                            .stroke(GentleLightning.Colors.shadowLight, lineWidth: 1)
                                    )
                                Text("G")
                                    .font(GentleLightning.Typography.caption)
                                    .foregroundColor(Color(red: 0.26, green: 0.52, blue: 0.96))
                            }
                            
                            Text("Continue with Google")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
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
                                .font(GentleLightning.Typography.bodyInput)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
                            
                            Text("Continue with Apple")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
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
                                .font(GentleLightning.Typography.bodyInput)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
                            
                            Text("Continue with Email")
                                .font(GentleLightning.Typography.body)
                                .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
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
                            .foregroundColor(GentleLightning.Colors.error)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                    
                    // Privacy links
                    HStack(spacing: 4) {
                        Link("Terms of Service", destination: URL(string: "https://muckstack.com/scrap/terms")!)
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Text("|")
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                        
                        Link("Privacy Policy", destination: URL(string: "https://muckstack.com/scrap/privacy")!)
                            .font(GentleLightning.Typography.small)
                            .foregroundColor(GentleLightning.Colors.textSecondary)
                    }
                    .padding(.top, 16)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    // Dismiss keyboard when user drags down (mainly for EmailAuthView sheet)
                    if value.translation.height > 50 && value.velocity.height > 0 {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        print("🔽 AuthenticationView: Dismissed keyboard via pull-down gesture")
                    }
                }
        )
        .sheet(isPresented: $showingEmailEntry) {
            EmailAuthView()
        }
        .onAppear {
            // Pause session replay for privacy during authentication
            AnalyticsManager.shared.pauseSessionReplay()
        }
        .onDisappear {
            // Resume session replay after authentication
            AnalyticsManager.shared.resumeSessionReplay()
        }
        .preferredColorScheme(.light) // Force light mode for login screen
    }
    
    // MARK: - Authentication Actions
    
    private func signInWithGoogle() async {
        do {
            errorMessage = nil
            try await firebaseManager.signInWithGoogle()
        } catch {
            // Don't show error message if user canceled
            if (error as NSError).code != -5 { // GIDSignInError.canceled
                await MainActor.run {
                    self.errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
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
    
    @State private var showingPasswordFields = false
    @State private var isSignUp = false
    @State private var lastValidatedEmail = ""
    @State private var error: String?
    
    @FocusState private var isEmailFocused: Bool
    @FocusState private var isPasswordFocused: Bool
    @FocusState private var isConfirmPasswordFocused: Bool
    @FocusState private var isFullNameFocused: Bool
    
    var body: some View {
        NavigationStack {
            ZStack {
                GentleLightning.Colors.background(isDark: false) // Email auth always uses light mode for now
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
                                        .font(GentleLightning.Typography.title)
                                        .foregroundColor(.white)
                                )
                            
                            Text(getHeaderTitle())
                                .font(.custom("SpaceGrotesk-Bold", size: 48))
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
                            // Email field - always visible and editable
                            VStack(alignment: .leading, spacing: 4) {
                                FloatingLabelTextField.email(
                                    placeholder: "Email Address",
                                    text: $email
                                )
                                .focused($isEmailFocused)
                                .onChange(of: email) { _ in
                                    // If email changed after password fields were shown, reset the flow
                                    if showingPasswordFields && email != lastValidatedEmail {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            showingPasswordFields = false
                                            password = ""
                                            confirmPassword = ""
                                            fullName = ""
                                            error = nil
                                        }
                                    }
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
                            
                            // Action Button (like HuddleUp)
                            Button(action: handleAction) {
                                HStack {
                                    if firebaseManager.isLoading {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    }
                                    Text(getActionButtonText())
                                        .font(GentleLightning.Typography.body)
                                        .foregroundColor(.white)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background(
                                    RoundedRectangle(cornerRadius: GentleLightning.Layout.Radius.large)
                                        .fill(isActionButtonEnabled ? GentleLightning.Colors.accentNeutral : GentleLightning.Colors.textSecondary.opacity(0.3))
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(!isActionButtonEnabled)
                            .padding(.top, 20)
                            
                            // Back button (only shown when password fields are visible)
                            if showingPasswordFields {
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        showingPasswordFields = false
                                        password = ""
                                        confirmPassword = ""
                                        fullName = ""
                                        lastValidatedEmail = ""
                                        error = nil
                                    }
                                }) {
                                    Text("← Use different email")
                                        .font(GentleLightning.Typography.caption)
                                        .foregroundColor(GentleLightning.Colors.accentNeutral)
                                }
                                .padding(.top, 12)
                            }
                            
                            
                            // Error message
                            if let error = error {
                                Text(error)
                                    .font(GentleLightning.Typography.small)
                                    .foregroundColor(GentleLightning.Colors.error)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                                    .transition(.opacity)
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer(minLength: 40)
                    }
                }
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            // Dismiss keyboard when user drags down
                            if value.translation.height > 50 && value.velocity.height > 0 {
                                isEmailFocused = false
                                isPasswordFocused = false
                                isConfirmPasswordFocused = false
                                isFullNameFocused = false
                                print("🔽 EmailAuthView: Dismissed keyboard via pull-down gesture")
                            }
                        }
                )
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
            // Pause session replay for privacy during authentication
            AnalyticsManager.shared.pauseSessionReplay()
        }
        .onDisappear {
            // Resume session replay after authentication
            AnalyticsManager.shared.resumeSessionReplay()
        }
        .preferredColorScheme(.light) // Force light mode for email auth
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
            return "Enter your email to sign in or create account"
        }
    }
    
    private func getActionButtonText() -> String {
        if showingPasswordFields {
            return isSignUp ? "Create Account" : "Sign In"
        } else {
            return "Continue"
        }
    }
    
    private var isActionButtonEnabled: Bool {
        if firebaseManager.isLoading {
            return false
        }
        
        if !showingPasswordFields {
            return isValidEmail(email)
        }
        
        let emailValid = isValidEmail(email)
        let passwordValid = !password.isEmpty && password.count >= 6
        
        if isSignUp {
            let nameValid = !fullName.isEmpty
            let passwordMatch = password == confirmPassword
            return emailValid && passwordValid && nameValid && passwordMatch
        } else {
            return emailValid && passwordValid
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
    
    private func proceedWithEmail() {
        // Always start with sign-up mode - if email exists, we'll handle that error during account creation
        isSignUp = true
        lastValidatedEmail = email.lowercased()
        
        withAnimation(.easeInOut(duration: 0.3)) {
            showingPasswordFields = true
        }
    }
    
    private func handleAction() {
        if !showingPasswordFields {
            proceedWithEmail()
        } else {
            handleAuth()
        }
    }
    
    private func handleAuth() {
        Task {
            if isSignUp {
                let displayName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
                await signUpUser(email: email, password: password, displayName: displayName)
            } else {
                await signInUser(email: email, password: password)
            }
        }
    }
    
    private func signUpUser(email: String, password: String, displayName: String) async {
        error = nil
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            
            // Update profile with display name
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()
            
            AnalyticsManager.shared.trackUserSignedIn(method: "email_signup", email: result.user.email)
            dismiss()
        } catch {
            await MainActor.run {
                if error.localizedDescription.contains("already in use") || error.localizedDescription.contains("email-already-in-use") {
                    // Email already exists, switch to sign in mode
                    self.isSignUp = false
                    self.fullName = "" // Clear name field since we're now signing in
                    self.confirmPassword = "" // Clear confirm password since we're now signing in
                    self.error = "This email is already registered. Please enter your password to sign in."
                } else {
                    let errorMessage: String
                    if error.localizedDescription.contains("network") {
                        errorMessage = "Network error. Please check your connection."
                    } else if error.localizedDescription.contains("weak-password") {
                        errorMessage = "Password is too weak. Use at least 6 characters."
                    } else {
                        errorMessage = "Failed to create account. Please try again."
                    }
                    self.error = errorMessage
                }
            }
            
            AnalyticsManager.shared.trackEvent("auth_signup_failed", properties: [
                "error": error.localizedDescription,
                "method": "email"
            ])
        }
    }
    
    private func signInUser(email: String, password: String) async {
        error = nil
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            AnalyticsManager.shared.trackUserSignedIn(method: "email_signin", email: result.user.email)
            dismiss()
        } catch {
            await MainActor.run {
                if error.localizedDescription.contains("no user record") || 
                   error.localizedDescription.contains("user-not-found") ||
                   error.localizedDescription.contains("wrong password") ||
                   error.localizedDescription.contains("invalid-credential") {
                    self.error = "Invalid email or password. Check your credentials or create a new account."
                } else if error.localizedDescription.contains("network") {
                    self.error = "Network error. Please check your connection."
                } else if error.localizedDescription.contains("too-many-requests") {
                    self.error = "Too many attempts. Please try again later."
                } else {
                    self.error = "Failed to sign in. Please try again."
                }
            }
            
            AnalyticsManager.shared.trackEvent("auth_signin_failed", properties: [
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