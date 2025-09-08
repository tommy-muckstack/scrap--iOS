import Foundation
import AmplitudeSwift

class AnalyticsManager: ObservableObject {
    static let shared = AnalyticsManager()
    private var amplitude: Amplitude?
    
    private init() {}
    
    func initialize() {
        amplitude = Amplitude(
            configuration: Configuration(
                apiKey: "693800f793945567021a62721d3713c9"
            )
        )
        
        // Track app launch
        trackEvent("app_launched")
    }
    
    // MARK: - Event Tracking
    func trackEvent(_ eventName: String, properties: [String: Any]? = nil) {
        amplitude?.track(eventType: eventName, eventProperties: properties)
    }
    
    // MARK: - Spark-specific Events
    func trackItemCreated(isTask: Bool, contentLength: Int) {
        trackEvent("item_created", properties: [
            "is_task": isTask,
            "content_length": contentLength,
            "item_type": isTask ? "task" : "note"
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
    
    func trackAppForeground() {
        trackEvent("app_foreground")
    }
    
    func trackAppBackground() {
        trackEvent("app_background")
    }
}