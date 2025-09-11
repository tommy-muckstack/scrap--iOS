import SwiftUI
import Foundation

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var isDarkMode: Bool = false
    
    static let shared = ThemeManager()
    
    private init() {
        // Load saved preference or use system default
        if let savedPreference = UserDefaults.standard.object(forKey: "isDarkMode") as? Bool {
            isDarkMode = savedPreference
        } else {
            // Default to system appearance
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        }
    }
    
    func toggleDarkMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode.toggle()
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }
    
    func setDarkMode(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode = enabled
            UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        }
    }
}

// MARK: - Environment Key for Theme
struct ThemeKey: EnvironmentKey {
    static let defaultValue = ThemeManager.shared
}

extension EnvironmentValues {
    var themeManager: ThemeManager {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}