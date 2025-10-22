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
    @State private var appleSignInCoordinator: AppleSignInCoordinator?
    @State private var errorMessage: String?
    
    var body: some View {
        GeometryReader { geometry in
            let isCompact = geometry.size.height < 700 // iPhone SE and similar
            let logoSize: CGFloat = isCompact ? 56 : 80
            let titleSize: CGFloat = isCompact ? 36 : 48
            let topPadding: CGFloat = isCompact ? 20 : 40
            let titleTopPadding: CGFloat = isCompact ? 12 : 20
            let horizontalPadding: CGFloat = 24
            let bottomPadding: CGFloat = isCompact ? 16 : 24

            ZStack {
                // Background - always light mode for login
                GentleLightning.Colors.background(isDark: false)
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        // Top section with logo and welcome text
                        VStack(alignment: .leading, spacing: 0) {
                            HStack {
                                // App logo
                                Image("AppLogo")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: logoSize, height: logoSize)
                                    .environment(\.colorScheme, .light) // Force light mode logo

                                Spacer()
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, topPadding)

                            // Welcome text below logo (left aligned)
                            VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
                                Text("Scrap")
                                    .font(.custom("SpaceGrotesk-Bold", size: titleSize))
                                    .foregroundColor(GentleLightning.Colors.textPrimary(isDark: false))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)

                                Text("The world's simplest notepad.")
                                    .font(GentleLightning.Typography.title)
                                    .foregroundColor(GentleLightning.Colors.textSecondary(isDark: false))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                            }
                            .padding(.horizontal, horizontalPadding)
                            .padding(.top, titleTopPadding)
                        }

                        // Spacer for flexible spacing
                        Spacer()
                            .frame(minHeight: isCompact ? 20 : 40)

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
                            Image("GoogleIconLight")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                            
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
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bottomPadding)
                    }
                    .frame(minHeight: geometry.size.height)
                }
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