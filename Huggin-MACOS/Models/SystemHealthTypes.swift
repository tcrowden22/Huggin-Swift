import Foundation

enum SystemHealthStatus: String {
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"
    case unknown = "Unknown"
}

struct SystemMetrics {
    var cpuUsage: Double = 0.0
    var memoryUsage: Double = 0.0
    var diskUsage: Double = 0.0
    var networkUsage: Double = 0.0
    var batteryLevel: Double = 0.0
    var isCharging: Bool = false
}

enum SystemHealth {
    case good
    case fair
    case poor
    case unknown
    
    var color: String {
        switch self {
        case .good: return "green"
        case .fair: return "yellow"
        case .poor: return "red"
        case .unknown: return "gray"
        }
    }
    
    var description: String {
        switch self {
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .unknown: return "Unknown"
        }
    }
} 