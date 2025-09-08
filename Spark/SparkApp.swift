import SwiftUI
import Firebase
import GoogleSignIn

@main
struct SparkApp: App {
    init() {
        // Initialize Firebase
        FirebaseApp.configure()
        
        // Configure Google Sign In
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
        
        // Initialize analytics when app launches
        AnalyticsManager.shared.initialize()
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(ColorScheme.light)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    AnalyticsManager.shared.trackAppForeground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    AnalyticsManager.shared.trackAppBackground()
                }
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

// MARK: - Root View with Authentication Flow
struct RootView: View {
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    @State private var hasInitialized = false
    
    var body: some View {
        Group {
            if !hasInitialized {
                // Loading screen while Firebase initializes
                ZStack {
                    Color.white
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        GentleLightning.Colors.accentIdea,
                                        GentleLightning.Colors.accentNeutral
                                    ],
                                    center: .center,
                                    startRadius: 30,
                                    endRadius: 60
                                )
                            )
                            .frame(width: 120, height: 120)
                            .overlay(
                                Image(systemName: "sparkles")
                                    .font(.system(size: 48, weight: .medium))
                                    .foregroundColor(.white)
                            )
                        
                        Text("Spark")
                            .font(GentleLightning.Typography.hero)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                        
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(GentleLightning.Colors.accentNeutral)
                    }
                }
                .onAppear {
                    // Give Firebase time to initialize auth state
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.easeInOut(duration: 0.5)) {
                            hasInitialized = true
                        }
                    }
                }
            } else if firebaseManager.isAuthenticated {
                ContentView()
                    .transition(.opacity)
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: firebaseManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: hasInitialized)
    }
}