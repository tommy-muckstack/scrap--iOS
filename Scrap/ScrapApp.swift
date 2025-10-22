import SwiftUI
import Firebase
import FirebaseAuth
import GoogleSignIn
import UIKit
import StoreKit

// MARK: - Notification Names
extension Notification.Name {
    static let focusInputField = Notification.Name("focusInputField")
    static let categoriesUpdated = Notification.Name("categoriesUpdated")
}

@objc class AppDelegate: NSObject, UIApplicationDelegate {
    @objc func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        print("🚀 AppDelegate: didFinishLaunchingWithOptions called")
        return true
    }

    @objc func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        print("🔗 AppDelegate: Handling URL: \(url)")
        let handled = GIDSignIn.sharedInstance.handle(url)
        print("🔗 AppDelegate: Google Sign-In handled URL: \(handled)")
        return handled
    }

    @objc func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        print("🔗 AppDelegate: continue userActivity called")
        return true
    }
}

@main
struct ScrapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        print("ScrapApp: Initializing app...")

        // Enable CoreGraphics debugging for NaN error tracking
        #if DEBUG
        CoreGraphicsDebugger.enableDebugMode()
        #endif

        // Initialize Firebase
        FirebaseApp.configure()
        print("ScrapApp: Firebase configured")

        // Let Firebase Auth auto-detect capabilities and use appropriate method
        // With aps-environment entitlement + delegate methods, Firebase will use APNs or fall back to reCAPTCHA
        print("✅ ScrapApp: Firebase Auth will auto-detect phone verification method")
        
        // Reduce Firebase logging verbosity in debug builds
        #if DEBUG
        FirebaseConfiguration.shared.setLoggerLevel(.warning)
        #endif
        
        // Configure Google Sign In
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            print("ScrapApp: Configuring Google Sign-In with client ID: \(clientId)")
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
            print("ScrapApp: Google Sign-In configured successfully")
        } else {
            print("ScrapApp: ERROR - Failed to configure Google Sign-In")
        }
        
        // Initialize analytics when app launches
        AnalyticsManager.shared.initialize()
        print("ScrapApp: Analytics initialized")
        
        // Configure navigation bar appearance for smaller buttons and no separator
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor.systemBackground
        appearance.shadowColor = UIColor.clear // Remove separator line
        appearance.shadowImage = UIImage() // Ensure no shadow image
        
        // Make back button smaller
        UIBarButtonItem.appearance().setTitleTextAttributes([
            .font: UIFont.systemFont(ofSize: 14)
        ], for: .normal)
        
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(themeManager)
                .preferredColorScheme(themeManager.isDarkMode ? .dark : .light)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    AnalyticsManager.shared.trackAppForeground()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
                    AnalyticsManager.shared.trackAppBackground()
                }
                .onOpenURL { url in
                    print("SwiftUI: Handling URL: \(url)")
                    
                    // Handle widget deep links for note creation
                    if url.scheme == "com.muckstack.scrap" && url.host == "create-note" {
                        print("SwiftUI: Widget create-note URL detected")
                        // Post notification to focus InputField
                        NotificationCenter.default.post(name: .focusInputField, object: nil)
                        return
                    }
                    
                    // Handle Google Sign-In URLs
                    let handled = GIDSignIn.sharedInstance.handle(url)
                    print("SwiftUI: Google Sign-In handled URL: \(handled)")
                }
        }
    }
}

// MARK: - Root View with Authentication Flow
struct RootView: View {
    @ObservedObject private var firebaseManager = FirebaseManager.shared
    @EnvironmentObject private var themeManager: ThemeManager
    @State private var hasInitialized = false
    
    var body: some View {
        ZStack {
            if !hasInitialized {
                // Loading screen while Firebase initializes
                ZStack {
                    GentleLightning.Colors.background(isDark: themeManager.isDarkMode)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image("AppLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 120, height: 120)
                        
                        Text("Scrap")
                            .font(.custom("SpaceGrotesk-Bold", size: 48))
                            .foregroundColor(GentleLightning.Colors.textPrimary(isDark: themeManager.isDarkMode))
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
                    .onAppear {
                        // Increment launch count and potentially request review
                        AppStoreReviewManager.shared.incrementLaunchCountAndRequestReview()
                    }
            } else {
                AuthenticationView()
                    .transition(.opacity)
                    .preferredColorScheme(.light) // Force light mode for authentication
            }
        }
        .animation(.easeInOut(duration: 0.5), value: firebaseManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: hasInitialized)
    }
}