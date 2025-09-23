import SwiftUI
import Foundation

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var isDarkMode: Bool = false
    @Published var groupNotesByTag: Bool = false
    
    static let shared = ThemeManager()
    
    private let userOverrideKey = "userOverrideDarkMode"
    private let hasUserOverrideKey = "hasUserOverrideDarkMode"
    private let groupNotesByTagKey = "groupNotesByTag"
    
    private init() {
        // Check if user has previously overridden the theme
        if UserDefaults.standard.bool(forKey: hasUserOverrideKey) {
            // User has made a choice, use their preference
            isDarkMode = UserDefaults.standard.bool(forKey: userOverrideKey)
        } else {
            // First time user, honor system settings
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
        }
        
        // Load group notes by tag preference (defaults to false)
        groupNotesByTag = UserDefaults.standard.bool(forKey: groupNotesByTagKey)
    }
    
    func toggleDarkMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode.toggle()
            saveUserPreference()
        }
    }
    
    func setDarkMode(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode = enabled
            saveUserPreference()
        }
    }
    
    func toggleGroupNotesByTag() {
        print("🏷️ ThemeManager: Toggling groupNotesByTag from \(groupNotesByTag) to \(!groupNotesByTag)")
        withAnimation(.easeInOut(duration: 0.3)) {
            groupNotesByTag.toggle()
            saveGroupNotesPreference()
            print("🏷️ ThemeManager: Successfully toggled groupNotesByTag to \(groupNotesByTag)")
        }
    }
    
    func setGroupNotesByTag(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            groupNotesByTag = enabled
            saveGroupNotesPreference()
        }
    }
    
    private func saveUserPreference() {
        // Mark that user has made a choice
        UserDefaults.standard.set(true, forKey: hasUserOverrideKey)
        // Save their preference
        UserDefaults.standard.set(isDarkMode, forKey: userOverrideKey)
    }
    
    private func saveGroupNotesPreference() {
        UserDefaults.standard.set(groupNotesByTag, forKey: groupNotesByTagKey)
    }
    
    /// Reset to follow system settings again (useful for debugging or settings reset)
    func resetToSystemSettings() {
        UserDefaults.standard.removeObject(forKey: hasUserOverrideKey)
        UserDefaults.standard.removeObject(forKey: userOverrideKey)
        UserDefaults.standard.removeObject(forKey: groupNotesByTagKey)
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
            groupNotesByTag = false
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