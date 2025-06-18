import Foundation

enum SystemEventType: String {
    case cpu = "CPU"
    case memory = "Memory"
    case disk = "Disk"
    case network = "Network"
    case battery = "Battery"
    case system = "System"
}

struct SystemEvent: Identifiable {
    let id = UUID()
    let type: SystemEventType
    let message: String
    let timestamp: Date
    let severity: String
    
    init(type: SystemEventType, message: String, timestamp: Date, severity: String = "warning") {
        self.type = type
        self.message = message
        self.timestamp = timestamp
        self.severity = severity
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }
} 