//
//  AppStoreReviewManager.swift
//  Scrap
//
//  Conservative App Store review request management with Amplitude tracking
//

import SwiftUI
import StoreKit

#if canImport(AppStore)
import AppStore
#endif

// MARK: - App Store Review Manager
@MainActor
class AppStoreReviewManager {
    static let shared = AppStoreReviewManager()
    
    // UserDefaults keys
    nonisolated private let launchCountKey = "app_launch_count"
    nonisolated private let hasRequestedReviewKey = "has_requested_review"
    nonisolated private let lastReviewRequestVersionKey = "last_review_request_version"
    nonisolated private let lastReviewPromptDateKey = "last_review_prompt_date"
    nonisolated private let reviewPromptCountKey = "review_prompt_count"
    nonisolated private let userDismissedReviewKey = "user_dismissed_review"
    
    // MARK: - Configuration - CONSERVATIVE SETTINGS
    nonisolated private let minimumLaunchCount = 5
    nonisolated private let appStoreId = "TBD" // Update this when app is submitted
    
    // Conservative cooldown periods (in days) - Be respectful to users
    nonisolated private let minimumDaysBetweenPrompts = 90      // Wait 3 months between prompts
    nonisolated private let minimumDaysAfterDismiss = 180       // Wait 6 months if user dismissed
    nonisolated private let minimumDaysAfterNewVersion = 30     // Wait 1 month after app update
    
    // Conservative frequency limits
    nonisolated private let maxPromptsPerVersion = 1            // Only ask once per version
    nonisolated private let maxPromptsPerYear = 1               // Max 1 prompt per year (very conservative)
    
    nonisolated private init() {}
    
    // MARK: - Public Methods
    
    /// Call this method in your App's init() or main view's onAppear
    func incrementLaunchCountAndRequestReview() {
        incrementLaunchCount()
        
        // Delay review request to ensure window scene is available
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                requestReviewIfAppropriate()
            }
        }
    }
    
    /// Manually request review (for settings page) - bypasses some cooldowns
    func requestReview(bypassCooldown: Bool = false) {
        requestReviewIfAppropriate(force: true, bypassCooldown: bypassCooldown)
    }
    
    /// Check if we can show review prompt right now (for testing)
    func canShowReviewPrompt() -> (canShow: Bool, reason: String) {
        let launchCount = getCurrentLaunchCount()
        let hasRequestedReview = UserDefaults.standard.bool(forKey: hasRequestedReviewKey)
        let currentVersion = getCurrentAppVersion()
        let lastRequestVersion = UserDefaults.standard.string(forKey: lastReviewRequestVersionKey)
        let lastPromptDate = UserDefaults.standard.object(forKey: lastReviewPromptDateKey) as? Date
        _ = UserDefaults.standard.integer(forKey: reviewPromptCountKey)
        let userDismissed = UserDefaults.standard.bool(forKey: userDismissedReviewKey)
        
        // Check launch count
        if launchCount < minimumLaunchCount {
            return (false, "Launch count (\(launchCount)) below minimum (\(minimumLaunchCount))")
        }
        
        // Check version-based limits
        if hasRequestedReview && lastRequestVersion == currentVersion && maxPromptsPerVersion <= 1 {
            return (false, "Already requested review for current version (\(currentVersion))")
        }
        
        // Check yearly limits - CONSERVATIVE: Only 1 per year
        let yearlyCount = getYearlyPromptCount()
        if yearlyCount >= maxPromptsPerYear {
            return (false, "Reached yearly limit (\(yearlyCount)/\(maxPromptsPerYear)) - being conservative")
        }
        
        // Check cooldown periods
        if let lastDate = lastPromptDate {
            let daysSinceLastPrompt = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
            
            // Different cooldowns based on user behavior - CONSERVATIVE approach
            let requiredCooldown: Int
            if userDismissed {
                requiredCooldown = minimumDaysAfterDismiss // 6 months after dismiss
            } else if lastRequestVersion != currentVersion {
                requiredCooldown = minimumDaysAfterNewVersion // 1 month after new version
            } else {
                requiredCooldown = minimumDaysBetweenPrompts // 3 months standard
            }
            
            if daysSinceLastPrompt < requiredCooldown {
                let remainingDays = requiredCooldown - daysSinceLastPrompt
                let cooldownType = userDismissed ? "dismiss (6 months)" : (lastRequestVersion != currentVersion ? "new version (1 month)" : "standard (3 months)")
                return (false, "Conservative cooldown active: \(remainingDays) days remaining (\(cooldownType) cooldown)")
            }
        }
        
        return (true, "All conservative conditions met")
    }
    
    /// Simulate user dismissing the prompt (for testing - iOS doesn't provide this callback)
    func simulateUserDismissed() {
        UserDefaults.standard.set(true, forKey: userDismissedReviewKey)
        print("🚫 Simulated user dismissing review prompt - 6 month cooldown activated")
    }
    
    /// Reset dismissal status (user can be asked again)
    func resetDismissalStatus() {
        UserDefaults.standard.removeObject(forKey: userDismissedReviewKey)
        print("🔄 Reset dismissal status")
    }
    
    /// Open App Store review page directly
    func openAppStoreReviewPage() {
        guard appStoreId != "TBD", let url = URL(string: "https://apps.apple.com/app/id\(appStoreId)?action=write-review") else {
            print("❌ App Store ID not configured yet for Scrap app")
            return
        }
        
        // Track that user opened App Store review page
        Task { @MainActor in
            AnalyticsManager.shared.trackReviewPageOpened(source: "manual_button")
        }
        
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if success {
                    print("✅ Successfully opened App Store review page")
                } else {
                    print("❌ Failed to open App Store review page")
                    AnalyticsManager.shared.trackReviewPageOpenFailed(appStoreId: self.appStoreId)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func incrementLaunchCount() {
        let currentCount = UserDefaults.standard.integer(forKey: launchCountKey)
        let newCount = currentCount + 1
        UserDefaults.standard.set(newCount, forKey: launchCountKey)
        
        print("📱 Scrap app launch count: \(newCount)")
    }
    
    private func getCurrentLaunchCount() -> Int {
        return UserDefaults.standard.integer(forKey: launchCountKey)
    }
    
    private func requestReviewIfAppropriate(force: Bool = false, bypassCooldown: Bool = false) {
        // Only show reviews on iOS 14+ to use SKStoreReviewController
        guard #available(iOS 14.0, *) else {
            print("⏭️ Skipping review request - iOS 14+ required for SKStoreReviewController")
            return
        }
        
        let checkResult = canShowReviewPrompt()
        
        if !force && !checkResult.canShow {
            print("⏭️ Skipping review request (conservative) - \(checkResult.reason)")
            return
        }
        
        if force && !bypassCooldown && !checkResult.canShow {
            print("⏭️ Manual review request blocked (conservative) - \(checkResult.reason)")
            return
        }
        
        // Find the active window scene
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .filter({ $0.activationState == .foregroundActive })
            .first else {
            print("❌ No active window scene found for review request")
            return
        }
        
        let launchCount = getCurrentLaunchCount()
        let currentVersion = getCurrentAppVersion()
        
        // Track that we're showing the review prompt
        let trigger = force ? (bypassCooldown ? "manual_bypass_cooldown" : "manual_request") : "automatic_after_\(launchCount)_launches"
        Task { @MainActor in
            AnalyticsManager.shared.trackReviewPromptShown(
                launchCount: launchCount,
                trigger: trigger,
                appVersion: currentVersion,
                daysSinceLastPrompt: getDaysSinceLastPrompt(),
                strategy: "conservative"
            )
        }
        
        // Request the review
        print("⭐ Requesting App Store review (conservative approach) - Launch count: \(launchCount)")
        
        // Request review using SKStoreReviewController
        if #available(iOS 14.0, *) {
            SKStoreReviewController.requestReview(in: windowScene)
        }
        
        // Update tracking data
        UserDefaults.standard.set(true, forKey: hasRequestedReviewKey)
        UserDefaults.standard.set(currentVersion, forKey: lastReviewRequestVersionKey)
        UserDefaults.standard.set(Date(), forKey: lastReviewPromptDateKey)
        
        // Increment prompt count
        let currentPromptCount = UserDefaults.standard.integer(forKey: reviewPromptCountKey)
        UserDefaults.standard.set(currentPromptCount + 1, forKey: reviewPromptCountKey)
        
        // Reset dismissal status (fresh start for this prompt)
        UserDefaults.standard.removeObject(forKey: userDismissedReviewKey)
    }
    
    private func getCurrentAppVersion() -> String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    private func getDaysSinceLastPrompt() -> Int? {
        guard let lastDate = UserDefaults.standard.object(forKey: lastReviewPromptDateKey) as? Date else {
            return nil
        }
        return Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day
    }
    
    private func getYearlyPromptCount() -> Int {
        // For simplicity, using total prompt count
        // In a real implementation, you'd filter by date
        return UserDefaults.standard.integer(forKey: reviewPromptCountKey)
    }
    
    // MARK: - Debug Methods
    
    /// Reset all review tracking (useful for testing)
    func resetReviewTracking() {
        UserDefaults.standard.removeObject(forKey: launchCountKey)
        UserDefaults.standard.removeObject(forKey: hasRequestedReviewKey)
        UserDefaults.standard.removeObject(forKey: lastReviewRequestVersionKey)
        UserDefaults.standard.removeObject(forKey: lastReviewPromptDateKey)
        UserDefaults.standard.removeObject(forKey: reviewPromptCountKey)
        UserDefaults.standard.removeObject(forKey: userDismissedReviewKey)
        print("🔄 Reset all conservative review tracking data for Scrap")
    }
    
    /// Get current tracking status for debugging
    func getTrackingStatus() -> String {
        let launchCount = getCurrentLaunchCount()
        let hasRequestedReview = UserDefaults.standard.bool(forKey: hasRequestedReviewKey)
        let lastRequestVersion = UserDefaults.standard.string(forKey: lastReviewRequestVersionKey) ?? "none"
        let currentVersion = getCurrentAppVersion()
        let lastPromptDate = UserDefaults.standard.object(forKey: lastReviewPromptDateKey) as? Date
        let promptCount = UserDefaults.standard.integer(forKey: reviewPromptCountKey)
        let userDismissed = UserDefaults.standard.bool(forKey: userDismissedReviewKey)
        let daysSinceLastPrompt = getDaysSinceLastPrompt()
        let canShow = canShowReviewPrompt()
        
        let lastPromptDateString = lastPromptDate?.formatted(date: .abbreviated, time: .omitted) ?? "never"
        let daysSinceString = daysSinceLastPrompt.map { "\($0) days ago" } ?? "never"
        
        return """
        📊 Scrap Conservative Review Tracking Status:
        Launch Count: \(launchCount) (min: \(minimumLaunchCount))
        Has Requested Review: \(hasRequestedReview)
        Current App Version: \(currentVersion)
        Last Request Version: \(lastRequestVersion)
        Last Prompt Date: \(lastPromptDateString) (\(daysSinceString))
        Total Prompts Shown: \(promptCount)
        User Dismissed Last: \(userDismissed)
        App Store ID: \(appStoreId)
        
        🎯 Can Show Prompt: \(canShow.canShow)
        Reason: \(canShow.reason)
        
        ⏱️ CONSERVATIVE Settings Active:
        - Standard Cooldown: \(minimumDaysBetweenPrompts) days (3 months)
        - After Dismiss: \(minimumDaysAfterDismiss) days (6 months)
        - New Version: \(minimumDaysAfterNewVersion) days (1 month)
        - Max Per Version: \(maxPromptsPerVersion)
        - Max Per Year: \(maxPromptsPerYear) (very conservative)
        
        👤 User Experience: Respectful & Non-Intrusive
        """
    }
}