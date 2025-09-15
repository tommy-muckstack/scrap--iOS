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
struct ScrapApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var themeManager = ThemeManager.shared
    
    init() {
        print("ScrapApp: Initializing app...")
        
        // Initialize Firebase
        FirebaseApp.configure()
        print("ScrapApp: Firebase configured")
        
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
        print("SparkApp: Analytics initialized")
        
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
            } else {
                AuthenticationView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.5), value: firebaseManager.isAuthenticated)
        .animation(.easeInOut(duration: 0.5), value: hasInitialized)
    }
}