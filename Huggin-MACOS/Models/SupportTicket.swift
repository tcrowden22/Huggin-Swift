import Foundation

struct BasicSupportTicket: Identifiable {
    let id: UUID
    let title: String
    let description: String
    var status: BasicTicketStatus
    let createdAt: Date
    var updatedAt: Date
    
    enum BasicTicketStatus: String {
        case open = "Open"
        case inProgress = "In Progress"
        case resolved = "Resolved"
        case closed = "Closed"
    }}

class SupportTicketStore: ObservableObject {
    @Published var tickets: [BasicSupportTicket] = []
    
    func addTicket(_ ticket: BasicSupportTicket) {
        tickets.append(ticket)
        // TODO: Persist to storage
    }
    
    func updateTicket(_ ticket: BasicSupportTicket) {
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
            // TODO: Persist to storage
        }
    }
}

struct DeviceInfo {
    let hostname: String
    let serial: String
    let os: String
    let uptime: String
    let battery: String
    let memory: String
}

struct TimelineEvent: Identifiable {
    let id = UUID()
    let title: String
    let time: String
    let detail: String?
    init(title: String, time: String, detail: String? = nil) {
        self.title = title
        self.time = time
        self.detail = detail
    }
}

struct BasicChatMessage: Identifiable {
    let id = UUID()
    let sender: String
    let text: String
    let time: String
} 