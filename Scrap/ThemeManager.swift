import SwiftUI
import Foundation

// MARK: - Theme Manager
class ThemeManager: ObservableObject {
    @Published var isDarkMode: Bool = false
    @Published var groupNotesByTag: Bool = false
    @Published var useVoiceInput: Bool = true // true = microphone, false = plus button

    static let shared = ThemeManager()

    private let userOverrideKey = "userOverrideDarkMode"
    private let hasUserOverrideKey = "hasUserOverrideDarkMode"
    private let groupNotesByTagKey = "groupNotesByTag"
    private let useVoiceInputKey = "useVoiceInput"
    
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

        // Load voice input preference (defaults to true)
        if UserDefaults.standard.object(forKey: useVoiceInputKey) != nil {
            useVoiceInput = UserDefaults.standard.bool(forKey: useVoiceInputKey)
        } else {
            useVoiceInput = true // Default to voice input
        }
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

    func toggleVoiceInput() {
        print("🎙️ ThemeManager: Toggling useVoiceInput from \(useVoiceInput) to \(!useVoiceInput)")
        withAnimation(.easeInOut(duration: 0.3)) {
            useVoiceInput.toggle()
            saveVoiceInputPreference()
            print("🎙️ ThemeManager: Successfully toggled useVoiceInput to \(useVoiceInput)")
        }
    }

    func setVoiceInput(_ enabled: Bool) {
        withAnimation(.easeInOut(duration: 0.3)) {
            useVoiceInput = enabled
            saveVoiceInputPreference()
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

    private func saveVoiceInputPreference() {
        UserDefaults.standard.set(useVoiceInput, forKey: useVoiceInputKey)
    }

    /// Reset to follow system settings again (useful for debugging or settings reset)
    func resetToSystemSettings() {
        UserDefaults.standard.removeObject(forKey: hasUserOverrideKey)
        UserDefaults.standard.removeObject(forKey: userOverrideKey)
        UserDefaults.standard.removeObject(forKey: groupNotesByTagKey)
        UserDefaults.standard.removeObject(forKey: useVoiceInputKey)
        withAnimation(.easeInOut(duration: 0.3)) {
            isDarkMode = UITraitCollection.current.userInterfaceStyle == .dark
            groupNotesByTag = false
            useVoiceInput = true
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