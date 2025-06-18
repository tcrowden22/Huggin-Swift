import Foundation
import SwiftUI

public enum AlertSeverity {
    case info
    case warning
    case error
    case critical
    
    var color: Color {
        switch self {
        case .info: return .blue
        case .warning: return .yellow
        case .error: return .orange
        case .critical: return .red
        }
    }
    
    var label: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .critical: return "Critical"
        }
    }
}

public struct SystemAlert: Identifiable {
    public let id: UUID
    public let title: String
    public let message: String
    public let severity: AlertSeverity
    public let timestamp: Date
    
    public init(title: String, message: String, severity: AlertSeverity) {
        self.id = UUID()
        self.title = title
        self.message = message
        self.severity = severity
        self.timestamp = Date()
    }
} 