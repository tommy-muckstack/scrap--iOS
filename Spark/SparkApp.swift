import SwiftUI
import Firebase
import GoogleSignIn
import UIKit

@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("AppDelegate: didFinishLaunchingWithOptions called")
        return true
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("AppDelegate: Handling URL: \(url)")
        let handled = GIDSignIn.sharedInstance.handle(url)
        print("AppDelegate: Google Sign-In handled URL: \(handled)")
        return handled
    }
    
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("AppDelegate: continue userActivity called")
        return true
    }
}

@main
struct SparkApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    
    init() {
        print("SparkApp: Initializing app...")
        
        // Initialize Firebase
        FirebaseApp.configure()
        print("SparkApp: Firebase configured")
        
        // Configure Google Sign In
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            print("SparkApp: Configuring Google Sign-In with client ID: \(clientId)")
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
            print("SparkApp: Google Sign-In configured successfully")
        } else {
            print("SparkApp: ERROR - Failed to configure Google Sign-In")
        }
        
        // Initialize analytics when app launches
        AnalyticsManager.shared.initialize()
        print("SparkApp: Analytics initialized")
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
                    print("SwiftUI: Handling URL: \(url)")
                    let handled = GIDSignIn.sharedInstance.handle(url)
                    print("SwiftUI: Google Sign-In handled URL: \(handled)")
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
                        
                        Text("Scrap")
                            .font(GentleLightning.Typography.hero)
                            .foregroundColor(GentleLightning.Colors.textPrimary)
                        
                        ProgressView()
                            .scaleEffect(1.2)
                            .tint(GentleLightning.Colors.accentNeutral)
                    }
                }
                .onAppear {
                    // Give Firebase time to initialize auth state
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                hasInitialized = true
                            }
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