import Foundation

struct SupportMessage: Identifiable {
    enum Role {
        case user
        case assistant
    }
    let id = UUID()
    let role: Role
    let content: String
    let timestamp: Date
} 