import Foundation
import Combine

struct EventLogEntry: Identifiable, Sendable {
    let id = UUID()
    let timestamp: Date
    let type: String
    let message: String
    let severity: String?
}

@MainActor
class EventLogService: ObservableObject, @unchecked Sendable {
    static let shared = EventLogService()
    @Published private(set) var events: [EventLogEntry] = []
    let eventPublisher = PassthroughSubject<EventLogEntry, Never>()

    private init() {}

    func addEvent(type: String, message: String, severity: String? = nil) {
        let entry = EventLogEntry(timestamp: Date(), type: type, message: message, severity: severity)
        events.append(entry)
        eventPublisher.send(entry)
        // Optionally trim to last N events
        if events.count > 1000 { events.removeFirst(events.count - 1000) }
    }

    func recentEvents(limit: Int = 10) -> [EventLogEntry] {
        return Array(events.suffix(limit))
    }
} 