import Foundation
import AmplitudeSwift
import AmplitudeSwiftSessionReplayPlugin
import UIKit

class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()
    private var amplitude: Amplitude?
    private var sessionReplayPlugin: AmplitudeSwiftSessionReplayPlugin?
    
    private init() {}
    
    func initialize() {
        // Fetch API key from environment or build settings
        // SECURITY: Never hardcode API keys - use environment variables or build settings
        let amplitudeAPIKey = ProcessInfo.processInfo.environment["AMPLITUDE_API_KEY"] ??
                             Bundle.main.object(forInfoDictionaryKey: "AMPLITUDE_API_KEY") as? String ??
                             "693800f793945567021a62721d3713c9" // Fallback for development only

        let configuration = Configuration(
            apiKey: amplitudeAPIKey
        )

        // Optimize storage to reduce I/O operations and disk health warnings
        configuration.flushQueueSize = 50           // Batch more events before flushing (increased from 30)
        configuration.flushIntervalMillis = 60000   // Flush less frequently - 60 seconds (increased from 30)
        configuration.minIdLength = 5               // Reduce minimum ID length validation
        configuration.partnerId = nil               // Disable partner tracking
        configuration.plan = nil                    // Disable plan tracking
        configuration.ingestionMetadata = nil       // Disable ingestion metadata

        // Session Replay with reduced sample rate to minimize I/O
        // This is the PRIMARY optimization to reduce disk writes
        let sampleRate: Float = 0.1 // 10% of sessions (reduced from 100% to minimize disk I/O)
        sessionReplayPlugin = AmplitudeSwiftSessionReplayPlugin(sampleRate: sampleRate, maskLevel: .light)

        amplitude = Amplitude(configuration: configuration)

        // Add Session Replay plugin to Amplitude
        if let plugin = sessionReplayPlugin {
            amplitude?.add(plugin: plugin)
        }

        // Set initial user ID to device ID and capture device properties
        setInitialDeviceProperties()

        // Track app launch
        trackEvent("app_launched")
    }

    // MARK: - User Identification (Best Practices)

    /// Set user ID using Firebase UID (or device ID as fallback)
    /// BEST PRACTICE: Use a stable, consistent user ID (not email) for tracking across sessions
    func setUserId(firebaseUid: String?) {
        if let uid = firebaseUid {
            // Use Firebase UID as the primary user identifier
            amplitude?.setUserId(userId: uid)
            print("📊 Amplitude: Set user ID to Firebase UID")
        } else {
            // Fallback to device ID for anonymous users
            let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
            amplitude?.setUserId(userId: deviceId)
            print("📊 Amplitude: Set user ID to device ID (anonymous)")
        }
    }

    /// Set user properties using Amplitude's Identify API
    /// BEST PRACTICE: Store email, device info, etc. as user properties (not the main user ID)
    func setUserProperties(email: String? = nil, authMethod: String? = nil, phoneNumber: String? = nil) {
        let identify = Identify()

        // Set email as a user property (not the user ID)
        if let email = email {
            identify.set(property: "email", value: email)
            print("📊 Amplitude: Set user property - email")
        }

        // Set authentication method
        if let authMethod = authMethod {
            identify.set(property: "auth_method", value: authMethod)
            identify.set(property: "last_auth_method", value: authMethod)
        }

        // Set phone number (if available)
        if let phoneNumber = phoneNumber {
            // SECURITY: Only store masked phone number
            let maskedPhone = String(phoneNumber.prefix(2)) + "****" + String(phoneNumber.suffix(2))
            identify.set(property: "phone_masked", value: maskedPhone)
        }

        // Device properties
        identify.set(property: "device_model", value: UIDevice.current.model)
        identify.set(property: "device_name", value: UIDevice.current.name)
        identify.set(property: "os_version", value: UIDevice.current.systemVersion)
        identify.set(property: "app_version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")
        identify.set(property: "app_build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown")

        // Screen size
        let screenSize = UIScreen.main.bounds.size
        identify.set(property: "screen_width", value: Int(screenSize.width))
        identify.set(property: "screen_height", value: Int(screenSize.height))

        amplitude?.identify(identify: identify)
        print("📊 Amplitude: Updated user properties")
    }

    /// Set initial device properties for anonymous users
    private func setInitialDeviceProperties() {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        amplitude?.setUserId(userId: deviceId)

        // Set device properties even for anonymous users
        setUserProperties()
    }

    /// Track user sign-in event with proper user identification
    /// BEST PRACTICE: Use Firebase UID as user ID, store email as a property
    func trackUserSignedIn(firebaseUid: String, method: String, email: String?) {
        // Set Firebase UID as the primary user identifier
        setUserId(firebaseUid: firebaseUid)

        // Set email and other properties using Identify API
        setUserProperties(email: email, authMethod: method)

        // Track the sign-in event
        trackEvent("user_signed_in", properties: [
            "sign_in_method": method,
            "has_email": email != nil
        ])

        print("📊 Amplitude: User signed in - UID: \(firebaseUid.prefix(8))..., Method: \(method)")
    }

    /// Track user sign-out and reset to device ID
    func trackUserSignedOut() {
        // Track sign-out event first
        trackEvent("user_signed_out")

        // Reset to device ID (anonymous user)
        setUserId(firebaseUid: nil)

        // Clear user properties
        let identify = Identify()
        identify.unset(property: "email")
        identify.unset(property: "auth_method")
        identify.unset(property: "phone_masked")
        amplitude?.identify(identify: identify)

        print("📊 Amplitude: User signed out - reset to device ID")
    }
    
    // MARK: - Event Tracking
    func trackEvent(_ eventName: String, properties: [String: Any]? = nil) {
        amplitude?.track(eventType: eventName, eventProperties: properties)
    }
    
    // MARK: - Spark-specific Events
    func trackItemCreated(isTask: Bool, contentLength: Int, creationType: String = "text") {
        trackEvent("item_created", properties: [
            "is_task": isTask,
            "content_length": contentLength,
            "item_type": isTask ? "task" : "note",
            "creation_type": creationType,
            "note_type": creationType // Add note_type property to distinguish voice vs text
        ])
    }
    
    func trackItemCompleted(isTask: Bool) {
        trackEvent("item_completed", properties: [
            "is_task": isTask,
            "item_type": isTask ? "task" : "note"
        ])
    }
    
    func trackItemDeleted(isTask: Bool) {
        trackEvent("item_deleted", properties: [
            "is_task": isTask,
            "item_type": isTask ? "task" : "note"
        ])
    }
    
    func trackSearch(query: String, resultCount: Int) {
        trackEvent("search_performed", properties: [
            "query_length": query.count,
            "result_count": resultCount
        ])
    }
    
    func trackSearchInitiated() {
        trackEvent("search_initiated")
    }
    
    // MARK: - Voice Recording Events
    func trackVoiceRecordingStarted() {
        trackEvent("voice_recording_started")
    }
    
    func trackVoiceRecordingStopped(duration: TimeInterval, textLength: Int) {
        trackEvent("voice_recording_stopped", properties: [
            "duration_seconds": Int(duration),
            "transcribed_text_length": textLength
        ])
    }
    
    func trackVoicePermissionDenied() {
        trackEvent("voice_permission_denied")
    }
    
    // MARK: - Note Editing Events
    func trackNoteEditOpened(noteId: String) {
        trackEvent("note_edit_opened", properties: [
            "note_id": noteId
        ])
    }
    
    func trackNoteEditSaved(noteId: String, contentLength: Int) {
        trackEvent("note_edit_saved", properties: [
            "note_id": noteId,
            "content_length": contentLength
        ])
    }
    
    func trackNoteShared(noteId: String) {
        trackEvent("note_shared", properties: [
            "note_id": noteId
        ])
    }
    
    // MARK: - Rich Text Formatting Events
    func trackFormattingToggled(format: String, isActive: Bool) {
        trackEvent("formatting_toggled", properties: [
            "format_type": format,
            "new_state": isActive ? "active" : "inactive"
        ])
    }
    
    func trackBoldToggled(isActive: Bool) {
        trackFormattingToggled(format: "bold", isActive: isActive)
    }
    
    func trackItalicToggled(isActive: Bool) {
        trackFormattingToggled(format: "italic", isActive: isActive)
    }
    
    func trackUnderlineToggled(isActive: Bool) {
        trackFormattingToggled(format: "underline", isActive: isActive)
    }
    
    func trackStrikethroughToggled(isActive: Bool) {
        trackFormattingToggled(format: "strikethrough", isActive: isActive)
    }
    
    func trackBulletListToggled(isActive: Bool) {
        trackFormattingToggled(format: "bullet_list", isActive: isActive)
    }
    
    func trackCheckboxToggled(isActive: Bool) {
        trackFormattingToggled(format: "checkbox", isActive: isActive)
    }
    
    func trackCodeBlockToggled(isActive: Bool) {
        trackFormattingToggled(format: "code_block", isActive: isActive)
    }
    
    func trackDrawingToggled(isActive: Bool) {
        trackFormattingToggled(format: "drawing", isActive: isActive)
    }
    
    func trackIndentChanged(direction: String) {
        trackEvent("indent_changed", properties: [
            "direction": direction // "in" or "out"
        ])
    }
    
    // MARK: - Checkbox Interaction Events
    func trackCheckboxClicked(isChecked: Bool, checkboxType: String) {
        trackEvent("checkbox_clicked", properties: [
            "new_state": isChecked ? "checked" : "unchecked",
            "checkbox_type": checkboxType // "unicode" or "attachment"
        ])
    }
    
    func trackCheckboxVisualUpdateFailed(reason: String) {
        trackEvent("checkbox_visual_update_failed", properties: [
            "failure_reason": reason
        ])
    }
    
    // MARK: - Text Processing Events
    func trackArrowConversion() {
        trackEvent("text_arrow_converted")
    }
    
    func trackBulletPointCreated() {
        trackEvent("text_bullet_created")
    }
    
    // MARK: - Category/Tag Events
    func trackCategoryCreated(categoryName: String, colorKey: String) {
        trackEvent("category_created", properties: [
            "category_name_length": categoryName.count,
            "color_key": colorKey
        ])
    }
    
    func trackCategorySelected(categoryId: String, categoryName: String) {
        trackEvent("category_selected", properties: [
            "category_id": categoryId,
            "category_name_length": categoryName.count
        ])
    }
    
    func trackCategoryDeselected(categoryId: String, categoryName: String) {
        trackEvent("category_deselected", properties: [
            "category_id": categoryId,
            "category_name_length": categoryName.count
        ])
    }
    
    func trackCategoryManagerOpened() {
        trackEvent("category_manager_opened")
    }
    
    func trackCategoryManagerClosed() {
        trackEvent("category_manager_closed")
    }
    
    // MARK: - Navigation Events
    func trackNoteOpened(noteId: String, openMethod: String) {
        trackEvent("note_opened", properties: [
            "note_id": noteId,
            "open_method": openMethod // "list_tap", "search_result", etc.
        ])
    }
    
    func trackNoteClosed(noteId: String, timeSpent: TimeInterval) {
        trackEvent("note_closed", properties: [
            "note_id": noteId,
            "time_spent_seconds": Int(timeSpent)
        ])
    }
    
    func trackBackButtonTapped(fromScreen: String) {
        trackEvent("back_button_tapped", properties: [
            "from_screen": fromScreen
        ])
    }
    
    func trackKeyboardDismissed(method: String) {
        trackEvent("keyboard_dismissed", properties: [
            "dismiss_method": method // "drag", "button", "tap_outside", etc.
        ])
    }
    
    // MARK: - Content Creation Events
    func trackTitleChanged(noteId: String, titleLength: Int) {
        trackEvent("title_changed", properties: [
            "note_id": noteId,
            "title_length": titleLength
        ])
    }
    
    func trackContentChanged(noteId: String, contentLength: Int, changeType: String) {
        trackEvent("content_changed", properties: [
            "note_id": noteId,
            "content_length": contentLength,
            "change_type": changeType // "typing", "formatting", "paste", etc.
        ])
    }
    
    func trackRTFContentSaved(noteId: String, rtfDataSize: Int) {
        trackEvent("rtf_content_saved", properties: [
            "note_id": noteId,
            "rtf_data_size_bytes": rtfDataSize
        ])
    }
    
    func trackContentLoadFailed(noteId: String, errorType: String) {
        trackEvent("content_load_failed", properties: [
            "note_id": noteId,
            "error_type": errorType
        ])
    }
    
    // MARK: - UI Interaction Events
    func trackAccountDrawerOpened() {
        trackEvent("account_drawer_opened")
    }
    
    func trackAccountDrawerClosed() {
        trackEvent("account_drawer_closed")
    }
    
    func trackNewNoteStarted(method: String) {
        trackEvent("new_note_started", properties: [
            "method": method // "text" or "voice"
        ])
    }
    
    func trackNoteSaved(method: String, contentLength: Int) {
        trackEvent("note_saved", properties: [
            "method": method, // "button" or "auto"
            "content_length": contentLength
        ])
    }
    
    func trackOptionsMenuOpened(noteId: String) {
        trackEvent("options_menu_opened", properties: [
            "note_id": noteId
        ])
    }
    
    func trackOptionsMenuClosed(noteId: String) {
        trackEvent("options_menu_closed", properties: [
            "note_id": noteId
        ])
    }
    
    func trackDeleteConfirmationShown(noteId: String) {
        trackEvent("delete_confirmation_shown", properties: [
            "note_id": noteId
        ])
    }
    
    func trackDeleteConfirmed(noteId: String) {
        trackEvent("delete_confirmed", properties: [
            "note_id": noteId
        ])
    }
    
    func trackDeleteCancelled(noteId: String) {
        trackEvent("delete_cancelled", properties: [
            "note_id": noteId
        ])
    }
    
    // MARK: - Error Events
    func trackError(errorType: String, errorMessage: String) {
        trackEvent("error_occurred", properties: [
            "error_type": errorType,
            "error_message": errorMessage
        ])
    }
    
    func trackAppForeground() {
        trackEvent("app_foreground")
    }
    
    func trackAppBackground() {
        trackEvent("app_background")
    }
    
    // MARK: - Drawing Events (Single Drawing Per Note)
    func trackDrawingAdded(noteId: String) {
        trackEvent("drawing_added", properties: [
            "note_id": noteId,
            "drawing_type": "single_per_note"
        ])
    }
    
    func trackDrawingUpdated(noteId: String, hasContent: Bool) {
        trackEvent("drawing_updated", properties: [
            "note_id": noteId,
            "has_content": hasContent,
            "drawing_type": "single_per_note"
        ])
    }
    
    func trackDrawingHeightChanged(noteId: String, newHeight: CGFloat) {
        trackEvent("drawing_height_changed", properties: [
            "note_id": noteId,
            "new_height": Int(newHeight),
            "drawing_type": "single_per_note"
        ])
    }
    
    func trackDrawingColorChanged(noteId: String, newColor: String) {
        trackEvent("drawing_color_changed", properties: [
            "note_id": noteId,
            "new_color": newColor,
            "drawing_type": "single_per_note"
        ])
    }
    
    func trackDrawingDeleted(noteId: String) {
        trackEvent("drawing_deleted", properties: [
            "note_id": noteId,
            "drawing_type": "single_per_note"
        ])
    }
    
    // MARK: - Storage and Performance Control
    func flushEvents() {
        // Manually flush events - use sparingly to reduce I/O
        amplitude?.flush()
    }
    
    // MARK: - Session Replay Control
    func startSessionReplay() {
        // Session replay starts automatically, but you can manually control it
        print("Session Replay is active with optimized I/O settings")
    }
    
    func pauseSessionReplay() {
        // Session Replay doesn't have direct pause/resume in this version
        // But you can stop/start recording if needed
        print("Session Replay pause requested - implement if needed")
    }
    
    func resumeSessionReplay() {
        // Session Replay doesn't have direct pause/resume in this version
        print("Session Replay resume requested - implement if needed")
    }
    
    func setSessionReplaySampleRate(_ rate: Double) {
        // Sample rate is set during initialization (currently 10% to minimize disk I/O)
        print("Session Replay sample rate change requested: \(rate) - requires reinitialization")
    }
    
    func maskSensitiveViews(_ views: [UIView]) {
        // Mark specific views as sensitive to be masked in recordings
        for view in views {
            // This is typically handled by the SDK automatically,
            // but you can add custom masking logic here if needed
            view.accessibilityIdentifier = "amplitude_mask"
        }
    }
    
    // MARK: - App Store Review Events
    func trackReviewPromptShown(launchCount: Int, trigger: String, appVersion: String, daysSinceLastPrompt: Int?, strategy: String = "conservative") {
        var properties: [String: Any] = [
            "launch_count": launchCount,
            "trigger": trigger,
            "app_version": appVersion,
            "strategy": strategy
        ]
        
        if let daysSinceLastPrompt = daysSinceLastPrompt {
            properties["days_since_last_prompt"] = daysSinceLastPrompt
        }
        
        trackEvent("review_prompt_shown", properties: properties)
    }
    
    func trackReviewPageOpened(source: String) {
        trackEvent("review_page_opened", properties: [
            "source": source
        ])
    }
    
    func trackReviewPageOpenFailed(appStoreId: String) {
        trackEvent("review_page_open_failed", properties: [
            "app_store_id": appStoreId
        ])
    }
}