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
        let configuration = Configuration(
            apiKey: "693800f793945567021a62721d3713c9"
        )
        
        // Configure Session Replay
        let sampleRate: Float = 1.0 // 100% sample rate
        sessionReplayPlugin = AmplitudeSwiftSessionReplayPlugin(sampleRate: sampleRate)
        
        amplitude = Amplitude(configuration: configuration)
        
        // Add Session Replay plugin to Amplitude
        if let plugin = sessionReplayPlugin {
            amplitude?.add(plugin: plugin)
        }
        
        // Set initial user ID to device ID
        setUserIdToDeviceId()
        
        // Track app launch
        trackEvent("app_launched")
    }
    
    // MARK: - User Identification
    func setUserIdToDeviceId() {
        let deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        amplitude?.setUserId(userId: deviceId)
    }
    
    func setUserIdToEmail(_ email: String) {
        amplitude?.setUserId(userId: email)
    }
    
    func trackUserSignedIn(method: String, email: String?) {
        // Update user ID to email if available
        if let email = email {
            setUserIdToEmail(email)
        }
        
        trackEvent("user_signed_in", properties: [
            "sign_in_method": method
        ])
    }
    
    func trackUserSignedOut() {
        // Reset user ID back to device ID
        setUserIdToDeviceId()
        
        trackEvent("user_signed_out")
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
            "creation_type": creationType
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
    
    // MARK: - Text Processing Events
    func trackArrowConversion() {
        trackEvent("text_arrow_converted")
    }
    
    func trackBulletPointCreated() {
        trackEvent("text_bullet_created")
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
    
    // MARK: - Session Replay Control
    func startSessionReplay() {
        // Session replay starts automatically, but you can manually control it
        amplitude?.flush()
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
        // Sample rate is set during initialization
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
}