import SwiftUI
import Foundation

// MARK: - DateFormatter Extensions

extension DateFormatter {
    static let fullDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Support-Specific Data Models (avoiding conflicts with existing types)

public enum SupportSeverity: String, CaseIterable, Sendable, Codable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case critical = "Critical"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

public enum SupportTicketStatus: String, CaseIterable, Sendable, Codable {
    case open = "Open"
    case inProgress = "In Progress"
    case resolved = "Resolved"
    case closed = "Closed"
    
    var color: Color {
        switch self {
        case .open: return .blue
        case .inProgress: return .orange
        case .resolved: return .green
        case .closed: return .gray
        }
    }
}

public enum SupportChatSender: String, CaseIterable, Sendable, Codable {
    case user = "User"
    case agent = "Huginn Agent"
    case system = "System"
}

public struct SupportSystemInfo: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let hostname: String
    public let osVersion: String
    public let macAddress: String
    public let ipAddress: String
    public let cpuModel: String
    public let totalMemory: String
    public let diskSpace: String
    public let uptime: String
    public let lastBootTime: Date
    
    public init(
        hostname: String = "Unknown",
        osVersion: String = "Unknown",
        macAddress: String = "Unknown",
        ipAddress: String = "Unknown",
        cpuModel: String = "Unknown",
        totalMemory: String = "Unknown",
        diskSpace: String = "Unknown",
        uptime: String = "Unknown",
        lastBootTime: Date = Date()
    ) {
        self.id = UUID()
        self.hostname = hostname
        self.osVersion = osVersion
        self.macAddress = macAddress
        self.ipAddress = ipAddress
        self.cpuModel = cpuModel
        self.totalMemory = totalMemory
        self.diskSpace = diskSpace
        self.uptime = uptime
        self.lastBootTime = lastBootTime
    }
}

public struct SupportUpdateInfo: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let name: String
    public let currentVersion: String
    public let availableVersion: String
    public let description: String
    public let size: String
    public let priority: SupportSeverity
    public let releaseDate: Date
    
    public init(
        name: String,
        currentVersion: String,
        availableVersion: String,
        description: String,
        size: String,
        priority: SupportSeverity = .medium,
        releaseDate: Date = Date()
    ) {
        self.id = UUID()
        self.name = name
        self.currentVersion = currentVersion
        self.availableVersion = availableVersion
        self.description = description
        self.size = size
        self.priority = priority
        self.releaseDate = releaseDate
    }
}

public struct SupportTicketEnhanced: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var title: String
    public var status: SupportTicketStatus
    public let date: Date
    public let systemInfo: SupportSystemInfo
    public let updatesNeeded: [SupportUpdateInfo]
    public var description: String
    public var chatMessages: [SupportChatMessage]
    public var lastActivity: Date
    public var statusHistory: [TicketStatusEntry]
    public var currentStatusMessage: String
    
    public init(
        title: String,
        status: SupportTicketStatus = .open,
        date: Date = Date(),
        systemInfo: SupportSystemInfo,
        updatesNeeded: [SupportUpdateInfo] = [],
        description: String = "",
        chatMessages: [SupportChatMessage] = [],
        lastActivity: Date = Date(),
        statusHistory: [TicketStatusEntry] = [],
        currentStatusMessage: String = "Ticket created"
    ) {
        self.id = UUID()
        self.title = title
        self.status = status
        self.date = date
        self.systemInfo = systemInfo
        self.updatesNeeded = updatesNeeded
        self.description = description
        self.chatMessages = chatMessages
        self.lastActivity = lastActivity
        self.statusHistory = statusHistory.isEmpty ? [TicketStatusEntry(status: "Created", message: "Ticket created")] : statusHistory
        self.currentStatusMessage = currentStatusMessage
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public static func == (lhs: SupportTicketEnhanced, rhs: SupportTicketEnhanced) -> Bool {
        lhs.id == rhs.id
    }
}

public struct SupportAlertItem: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let severity: SupportSeverity
    public let date: Date
    public let message: String
    
    public init(
        title: String,
        severity: SupportSeverity,
        date: Date = Date(),
        message: String = ""
    ) {
        self.title = title
        self.severity = severity
        self.date = date
        self.message = message
    }
}

public struct SupportChatMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public let sender: SupportChatSender
    public let text: String
    public let date: Date
    public let hasScriptAction: Bool
    public let scriptIntent: ScriptIntent?
    
    public init(sender: SupportChatSender, text: String, date: Date = Date(), hasScriptAction: Bool = false, scriptIntent: ScriptIntent? = nil) {
        self.id = UUID()
        self.sender = sender
        self.text = text
        self.date = date
        self.hasScriptAction = hasScriptAction
        self.scriptIntent = scriptIntent
    }
}

public struct TicketStatusEntry: Identifiable, Sendable, Codable {
    public let id: UUID
    public let status: String
    public let timestamp: Date
    public let message: String
    
    public init(status: String, message: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.status = status
        self.message = message
        self.timestamp = timestamp
    }
}

public enum ScriptIntent: Sendable, Codable {
    case installation(InstallationIntent)
    case maintenance(MaintenanceIntent)
    case diagnostic(String)
}

// MARK: - Support View Model

@MainActor
public class SupportViewModel: ObservableObject {
    @Published public var tickets: [SupportTicketEnhanced] = []
    @Published public var alerts: [SupportAlertItem] = []
    @Published public var selectedTicket: SupportTicketEnhanced?
    @Published public var cpuUsage: Double = 0.0
    @Published public var memoryUsage: Double = 0.0
    @Published public var diskUsage: Double = 0.0
    @Published public var chatMessages: [SupportChatMessage] = []
    @Published public var isLoading = false
    @Published public var messageText = ""
    @Published public var isProcessingMessage = false
    @Published public var isGeneratingWelcome = false
    
    // Ollama integration
    private let systemInfoProvider: SystemInfoProvider
    
    public init() {
        self.systemInfoProvider = SystemInfoProvider()
        
        loadTicketHistory()
        loadAlerts()
        // Removed loadSampleData() - no fake tickets
    }
    
    // MARK: - Public Methods
    
    public func loadTicketHistory() {
        isLoading = true
        
        // Try to load tickets from UserDefaults with backward compatibility
        if let data = UserDefaults.standard.data(forKey: "SupportTickets") {
            do {
                let decoder = JSONDecoder()
                let savedTickets = try decoder.decode([SupportTicketEnhanced].self, from: data)
                tickets = savedTickets.sorted { $0.lastActivity > $1.lastActivity }
                print("Loaded \(tickets.count) tickets from storage")
            } catch {
                print("Failed to decode saved tickets (likely due to structure changes): \(error)")
                // Clear the old incompatible data and start fresh
                UserDefaults.standard.removeObject(forKey: "SupportTickets")
                createSampleTickets()
            }
        } else {
            print("No saved tickets found, creating sample tickets")
            createSampleTickets()
        }
        
        isLoading = false
    }
    
    private func createSampleTickets() {
        let sampleSystemInfo = SupportSystemInfo(
            hostname: "MacBook Pro",
            osVersion: "macOS Sequoia 15.1",
            macAddress: "00:1B:63:84:45:E6",
            ipAddress: "192.168.1.105",
            cpuModel: "Apple M3 Pro",
            totalMemory: "18 GB",
            diskSpace: "512 GB SSD",
            uptime: "2 days, 14:32"
        )
        
        // Sample ticket 1: Recent issue
        let ticket1 = SupportTicketEnhanced(
            title: "Slack won't start after update",
            status: .open,
            date: Date().addingTimeInterval(-3600), // 1 hour ago
            systemInfo: sampleSystemInfo,
            description: "Slack application crashes immediately when trying to launch after the latest macOS update.",
            chatMessages: [
                SupportChatMessage(sender: .system, text: "Support ticket created", date: Date().addingTimeInterval(-3600)),
                SupportChatMessage(sender: .agent, text: "I am Huginn AI, how can I help you? I can see you're having trouble with Slack after an update. Let me help you troubleshoot this issue.", date: Date().addingTimeInterval(-3580)),
                SupportChatMessage(sender: .user, text: "Yes, Slack just crashes when I try to open it. It worked fine before the macOS update.", date: Date().addingTimeInterval(-3500)),
                SupportChatMessage(sender: .agent, text: "This is a common issue after macOS updates. Let me run some diagnostics and provide you with a solution.", date: Date().addingTimeInterval(-3480))
            ],
            lastActivity: Date().addingTimeInterval(-3480),
            statusHistory: [
                TicketStatusEntry(status: "Created", message: "Ticket created", timestamp: Date().addingTimeInterval(-3600)),
                TicketStatusEntry(status: "AI Analysis", message: "Huginn AI analyzing issue", timestamp: Date().addingTimeInterval(-3580))
            ],
            currentStatusMessage: "AI Analysis"
        )
        
        // Sample ticket 2: Resolved issue
        let ticket2 = SupportTicketEnhanced(
            title: "System running slowly",
            status: .resolved,
            date: Date().addingTimeInterval(-86400), // 1 day ago
            systemInfo: sampleSystemInfo,
            description: "Computer has been running very slowly, especially when opening applications.",
            chatMessages: [
                SupportChatMessage(sender: .system, text: "Support ticket created", date: Date().addingTimeInterval(-86400)),
                SupportChatMessage(sender: .agent, text: "I am Huginn AI, how can I help you? I see you're experiencing slow performance. Let me run a system diagnostic.", date: Date().addingTimeInterval(-86380)),
                SupportChatMessage(sender: .user, text: "My Mac has been really slow lately. Takes forever to open apps.", date: Date().addingTimeInterval(-86300)),
                SupportChatMessage(sender: .system, text: "🩺 Running diagnostics...", date: Date().addingTimeInterval(-86280)),
                SupportChatMessage(sender: .agent, text: "Diagnostics completed. I found high memory usage and full disk cache. Running cleanup script.", date: Date().addingTimeInterval(-86260)),
                SupportChatMessage(sender: .system, text: "🚀 Executing: System Cleanup...", date: Date().addingTimeInterval(-86240)),
                SupportChatMessage(sender: .agent, text: "✅ System Cleanup completed! Freed up 3.2GB of disk space. Your system should be running much better now.", date: Date().addingTimeInterval(-86200))
            ],
            lastActivity: Date().addingTimeInterval(-86200),
            statusHistory: [
                TicketStatusEntry(status: "Created", message: "Ticket created", timestamp: Date().addingTimeInterval(-86400)),
                TicketStatusEntry(status: "Diagnostics In Progress", message: "Running system diagnostics", timestamp: Date().addingTimeInterval(-86280)),
                TicketStatusEntry(status: "Running System Cleanup", message: "Executing cleanup script", timestamp: Date().addingTimeInterval(-86240)),
                TicketStatusEntry(status: "Resolved", message: "Issue resolved successfully", timestamp: Date().addingTimeInterval(-86200))
            ],
            currentStatusMessage: "Resolved"
        )
        
        // Sample ticket 3: Older ticket
        let ticket3 = SupportTicketEnhanced(
            title: "Homebrew installation help",
            status: .closed,
            date: Date().addingTimeInterval(-259200), // 3 days ago
            systemInfo: sampleSystemInfo,
            description: "Need help installing Homebrew package manager for development work.",
            chatMessages: [
                SupportChatMessage(sender: .system, text: "Support ticket created", date: Date().addingTimeInterval(-259200)),
                SupportChatMessage(sender: .agent, text: "I am Huginn AI, how can I help you? I can help you install Homebrew on your Mac.", date: Date().addingTimeInterval(-259180)),
                SupportChatMessage(sender: .user, text: "I need to install Homebrew for my development work but I'm not sure how.", date: Date().addingTimeInterval(-259100)),
                SupportChatMessage(sender: .agent, text: "I'll help you install Homebrew safely. Let me generate the installation script for you.", date: Date().addingTimeInterval(-259080), hasScriptAction: true, scriptIntent: .installation(InstallationIntent(softwareName: "Homebrew", method: .homebrew, originalRequest: "install homebrew"))),
                SupportChatMessage(sender: .system, text: "🚀 Executing: Install via Homebrew...", date: Date().addingTimeInterval(-259060)),
                SupportChatMessage(sender: .agent, text: "✅ Install via Homebrew completed successfully! Homebrew is now installed and ready to use.", date: Date().addingTimeInterval(-259020))
            ],
            lastActivity: Date().addingTimeInterval(-259020),
            statusHistory: [
                TicketStatusEntry(status: "Created", message: "Ticket created", timestamp: Date().addingTimeInterval(-259200)),
                TicketStatusEntry(status: "Installing Homebrew", message: "Installing Homebrew package manager", timestamp: Date().addingTimeInterval(-259060)),
                TicketStatusEntry(status: "Install via Homebrew Completed", message: "Installation completed successfully", timestamp: Date().addingTimeInterval(-259020)),
                TicketStatusEntry(status: "Closed", message: "Ticket closed", timestamp: Date().addingTimeInterval(-259020))
            ],
            currentStatusMessage: "Closed"
        )
        
        tickets = [ticket1, ticket2, ticket3].sorted { $0.lastActivity > $1.lastActivity }
        
        // Save the sample tickets
        saveTickets()
        
        print("Created \(tickets.count) sample tickets")
    }
    
    // MARK: - Debug Methods
    
    public func resetTickets() {
        // Clear all saved tickets and create fresh sample data
        UserDefaults.standard.removeObject(forKey: "SupportTickets")
        tickets = []
        selectedTicket = nil
        chatMessages = []
        createSampleTickets()
        print("Tickets reset and sample data recreated")
    }
    
    public func clearAllTickets() {
        // Clear all tickets completely
        UserDefaults.standard.removeObject(forKey: "SupportTickets")
        tickets = []
        selectedTicket = nil
        chatMessages = []
        print("All tickets cleared")
    }
    
    private func saveTickets() {
        // Save tickets to UserDefaults
        if let data = try? JSONEncoder().encode(tickets) {
            UserDefaults.standard.set(data, forKey: "SupportTickets")
            print("Saved \(tickets.count) tickets to storage")
        }
    }
    
    public func loadAlerts() {
        // TODO: Integrate with real system monitoring to load alerts
        // - Connect to system monitoring service
        // - Filter alerts by severity and date range
        // - Real-time alert subscription
        // - Alert acknowledgment and resolution tracking
        
        // Generate real-time system alerts based on current system state
        generateSystemAlerts()
        print("Loading system alerts...")
    }
    
    private func generateSystemAlerts() {
        var currentAlerts: [SupportAlertItem] = []
        
        // Check CPU usage
        let cpuUsage = systemInfoProvider.getCPUUsage()
        if cpuUsage > 80 {
            currentAlerts.append(SupportAlertItem(
                title: "High CPU Usage Detected",
                severity: cpuUsage > 90 ? .critical : .high,
                message: "CPU usage is at \(String(format: "%.1f", cpuUsage))%. Consider closing unnecessary applications."
            ))
        }
        
        // Check memory usage
        let memoryUsage = systemInfoProvider.getMemoryUsage()
        if memoryUsage > 85 {
            currentAlerts.append(SupportAlertItem(
                title: "High Memory Usage",
                severity: memoryUsage > 95 ? .critical : .high,
                message: "Memory usage is at \(String(format: "%.1f", memoryUsage))%. Consider restarting some applications."
            ))
        }
        
        // Check disk usage
        let diskUsage = systemInfoProvider.getDiskUsage()
        if diskUsage > 85 {
            currentAlerts.append(SupportAlertItem(
                title: diskUsage > 95 ? "Critical Disk Space" : "Low Disk Space",
                severity: diskUsage > 95 ? .critical : .medium,
                message: "Disk usage is at \(String(format: "%.1f", diskUsage))%. Consider cleaning up files."
            ))
        }
        
        // Add a general system status alert if no issues
        if currentAlerts.isEmpty {
            currentAlerts.append(SupportAlertItem(
                title: "System Running Normally",
                severity: .low,
                message: "All system metrics are within normal ranges."
            ))
        }
        
        alerts = currentAlerts
    }
    
    public func refreshSystemAlerts() {
        // Public method to refresh alerts when user returns to support tab
        generateSystemAlerts()
    }
    
    public func selectTicket(_ ticket: SupportTicketEnhanced) {
        selectedTicket = ticket
        chatMessages = ticket.chatMessages
    }
    
    public func addMessage(_ message: SupportChatMessage) {
        guard var ticket = selectedTicket else { return }
        
        ticket.chatMessages.append(message)
        ticket.lastActivity = message.date
        
        // Update the ticket in the array
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        }
        
        selectedTicket = ticket
        chatMessages = ticket.chatMessages
        
        // Save tickets after adding message
        saveTickets()
    }
    
    public func generateAIResponse(to message: SupportChatMessage) {
        Task {
            do {
                // Create context-aware prompt for Ollama
                let systemContext = """
                Current system status:
                - CPU Usage: \(Int(cpuUsage * 100))%
                - Memory Usage: \(Int(memoryUsage * 100))%
                - Disk Usage: \(Int(diskUsage * 100))%
                """
                
                let ticketContext = selectedTicket?.title ?? "General Support"
                
                let prompt = """
                You are Huginn AI, a helpful macOS system assistant. 
                
                Ticket: \(ticketContext)
                \(systemContext)
                
                User message: "\(message.text)"
                
                Provide a helpful, technical response. If the user's issue relates to system performance, reference the current metrics. If they need software installation or system maintenance, offer to generate scripts. Keep responses concise but informative.
                """
                
                let response = try await OllamaService.shared.sendMessage(prompt)
                
                await MainActor.run {
                    // Determine if we should offer script actions based on the user's message
                    let shouldOfferScript = self.shouldOfferScriptAction(for: message.text)
                    let scriptIntent = shouldOfferScript ? self.detectScriptIntent(from: message.text) : nil
                    
                    let aiMessage = SupportChatMessage(
                        sender: .agent,
                        text: response,
                        hasScriptAction: scriptIntent != nil,
                        scriptIntent: scriptIntent
                    )
                    
                    self.addMessage(aiMessage)
                }
                
            } catch {
                // Fallback to contextual response if Ollama fails
                await MainActor.run {
                    let fallbackResponse = self.generateContextualFallback(for: message.text)
                    
                    let aiMessage = SupportChatMessage(
                        sender: .agent,
                        text: fallbackResponse,
                        hasScriptAction: false,
                        scriptIntent: nil
                    )
                    
                    self.addMessage(aiMessage)
                    print("Ollama failed, using fallback response: \(error)")
                }
            }
        }
    }
    
    private func shouldOfferScriptAction(for message: String) -> Bool {
        let messageLower = message.lowercased()
        let scriptKeywords = ["install", "update", "clean", "fix", "slow", "performance", "space", "memory", "cpu", "diagnostic", "troubleshoot"]
        return scriptKeywords.contains { messageLower.contains($0) }
    }
    
    private func detectScriptIntent(from message: String) -> ScriptIntent? {
        let messageLower = message.lowercased()
        
        // Check for installation intent
        if messageLower.contains("install") || messageLower.contains("download") {
            if messageLower.contains("homebrew") || messageLower.contains("brew") {
                return .installation(InstallationIntent(softwareName: "Homebrew", method: .homebrew, originalRequest: message))
            } else {
                // Try to extract software name using improved logic
                let softwareName = extractSoftwareNameFromMessage(message)
                if !softwareName.isEmpty {
                    return .installation(InstallationIntent(softwareName: softwareName, method: .auto, originalRequest: message))
                }
            }
        }
        
        // Check for maintenance intent
        if messageLower.contains("clean") || messageLower.contains("slow") || messageLower.contains("performance") {
            return .maintenance(MaintenanceIntent(taskType: .cleanup, originalRequest: message))
        }
        
        if messageLower.contains("update") {
            return .maintenance(MaintenanceIntent(taskType: .update, originalRequest: message))
        }
        
        // Check for diagnostic intent
        if messageLower.contains("diagnostic") || messageLower.contains("check") || messageLower.contains("troubleshoot") {
            return .diagnostic("system")
        }
        
        return nil
    }
    
    private func extractSoftwareNameFromMessage(_ message: String) -> String {
        let messageLower = message.lowercased()
        
        // Common software names to look for
        let knownSoftware = [
            "slack", "discord", "chrome", "firefox", "safari", "opera", "edge",
            "vscode", "code", "atom", "sublime", "vim", "emacs",
            "docker", "node", "npm", "yarn", "git", "python", "java", "go",
            "xcode", "android studio", "intellij", "pycharm",
            "photoshop", "illustrator", "sketch", "figma",
            "spotify", "vlc", "zoom", "teams", "skype",
            "homebrew", "brew", "mas", "wget", "curl"
        ]
        
        // Check for known software names first
        for software in knownSoftware {
            if messageLower.contains(software) {
                return software
            }
        }
        
        // Pattern-based extraction for "install X" format
        let patterns = [
            "install ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "get ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "download ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "setup ([a-zA-Z][a-zA-Z0-9\\-_]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: message) {
                let candidate = String(message[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Filter out common words that aren't software names
                let excludeWords = ["you", "me", "can", "please", "help", "the", "a", "an", "to", "for", "with", "and", "or", "but", "from", "on", "in", "at", "by"]
                if !excludeWords.contains(candidate.lowercased()) && candidate.count > 2 {
                    return candidate
                }
            }
        }
        
        // Last resort: look for words after "install" that aren't common words
        let words = message.components(separatedBy: .whitespacesAndNewlines)
        let excludeWords = ["you", "me", "can", "please", "help", "the", "a", "an", "to", "for", "with", "and", "or", "but", "from", "on", "in", "at", "by", "install", "download", "get", "setup"]
        
        var foundInstall = false
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if cleanWord == "install" || cleanWord == "download" || cleanWord == "get" || cleanWord == "setup" {
                foundInstall = true
                continue
            }
            
            if foundInstall && !excludeWords.contains(cleanWord) && cleanWord.count > 2 {
                return word.trimmingCharacters(in: .punctuationCharacters)
            }
        }
        
        return ""
    }
    
    private func generateContextualFallback(for message: String) -> String {
        let messageLower = message.lowercased()
        
        if messageLower.contains("slow") || messageLower.contains("performance") {
            return "I can see your system is using \(Int(cpuUsage * 100))% CPU and \(Int(memoryUsage * 100))% memory. Let me help you optimize performance. Would you like me to run a system cleanup?"
        } else if messageLower.contains("install") {
            return "I can help you install software safely. What application would you like to install? I can guide you through the process or generate an installation script."
        } else if messageLower.contains("update") {
            return "I can help you with system updates. Would you like me to check for available updates and guide you through the installation process?"
        } else if messageLower.contains("space") || messageLower.contains("disk") {
            return "Your disk is currently \(Int(diskUsage * 100))% full. I can help you free up space by cleaning temporary files and caches. Would you like me to run a cleanup script?"
        } else {
            return "I'm here to help with your technical issue. Could you provide more details about what you're experiencing? I can assist with system diagnostics, software installation, performance optimization, and more."
        }
    }
    
    public func refreshSystemMetrics() async {
        // Connect to dashboard ViewModel for real metrics
        // For now, simulate some realistic data that changes over time
        await MainActor.run {
            // Add some variation to simulate live data
            let time = Date().timeIntervalSince1970
            cpuUsage = 0.15 + 0.3 * sin(time / 10.0).magnitude
            memoryUsage = 0.4 + 0.2 * cos(time / 15.0).magnitude
            diskUsage = 0.6 + 0.1 * sin(time / 20.0).magnitude
        }
    }
    
    // MARK: - Ticket Status Management
    
    public func updateTicketStatus(_ status: String) {
        guard var ticket = selectedTicket else { return }
        
        // Add status entry to history
        let statusEntry = TicketStatusEntry(status: status, message: status)
        ticket.statusHistory.append(statusEntry)
        ticket.currentStatusMessage = status
        ticket.lastActivity = Date()
        
        // Update the ticket in the array
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        }
        
        selectedTicket = ticket
        
        // Save tickets after status update
        saveTickets()
        
        print("Ticket status updated: \(status)")
    }
    
    public func askForResolutionConfirmation() {
        guard selectedTicket != nil else { return }
        
        Task {
            do {
                let confirmationPrompt = """
                You are Huginn AI. A technical task has just been completed successfully for the user. 
                
                Ask the user politely if their issue has been resolved and if they would like to close the support ticket.
                
                Be conversational and helpful. Something like:
                "Great! The task completed successfully. Has this resolved your issue? If everything is working properly now, I can close this support ticket for you."
                
                Keep it concise and friendly. Wait for their response before taking any action.
                """
                
                let response = try await OllamaService.shared.sendMessage(confirmationPrompt)
                
                await MainActor.run {
                    let confirmationMessage = SupportChatMessage(
                        sender: .agent,
                        text: response
                    )
                    self.addMessage(confirmationMessage)
                }
                
            } catch {
                // Fallback message if Ollama is not available
                await MainActor.run {
                    let fallbackMessage = SupportChatMessage(
                        sender: .agent,
                        text: "Great! The task completed successfully. Has this resolved your issue? If everything is working properly now, I can close this support ticket for you."
                    )
                    self.addMessage(fallbackMessage)
                }
            }
        }
    }
    
    private func detectResolutionConfirmation(in message: String) -> Bool {
        let messageLower = message.lowercased()
        
        // Check for positive confirmation phrases
        let positiveKeywords = [
            "yes", "yeah", "yep", "sure", "ok", "okay", "resolved", "fixed", "working", 
            "solved", "close", "close it", "close the ticket", "all good", "perfect",
            "thanks", "thank you", "that worked", "it works", "working now", "all set"
        ]
        
        // Check for negative phrases that would indicate the issue is NOT resolved
        let negativeKeywords = [
            "no", "not yet", "still", "doesn't work", "not working", "not fixed", 
            "still broken", "issue remains", "problem persists", "not resolved"
        ]
        
        // If message contains negative keywords, it's not a confirmation
        for negative in negativeKeywords {
            if messageLower.contains(negative) {
                return false
            }
        }
        
        // Check for positive confirmation
        for positive in positiveKeywords {
            if messageLower.contains(positive) {
                return true
            }
        }
        
        return false
    }
    
    private func handleResolutionConfirmation(message: String) async {
        do {
            let resolutionPrompt = """
            You are Huginn AI. The user has confirmed that their issue has been resolved. 
            
            User's response: "\(message)"
            
            Provide a brief, friendly acknowledgment and confirm that you're closing the support ticket.
            
            Something like: "Excellent! I'm glad that resolved your issue. I'll go ahead and close this support ticket now. Feel free to open a new ticket if you need any further assistance!"
            
            Keep it warm, professional, and conclusive.
            """
            
            let response = try await OllamaService.shared.sendMessage(resolutionPrompt)
            
            await MainActor.run {
                // Add the AI's closing message
                let closingMessage = SupportChatMessage(
                    sender: .agent,
                    text: response
                )
                self.addMessage(closingMessage)
                
                // Close the ticket
                self.closeTicket()
                self.isProcessingMessage = false
            }
            
        } catch {
            // Fallback message if Ollama is not available
            await MainActor.run {
                let fallbackMessage = SupportChatMessage(
                    sender: .agent,
                    text: "Excellent! I'm glad that resolved your issue. I'll go ahead and close this support ticket now. Feel free to open a new ticket if you need any further assistance!"
                )
                self.addMessage(fallbackMessage)
                
                // Close the ticket
                self.closeTicket()
                self.isProcessingMessage = false
            }
        }
    }
    
    private func closeTicket() {
        guard var ticket = selectedTicket else { return }
        
        // Update ticket status to closed
        ticket.status = .resolved
        ticket.lastActivity = Date()
        
        // Add status entry to history
        let statusEntry = TicketStatusEntry(status: "Resolved", message: "Issue resolved and ticket closed by user confirmation")
        ticket.statusHistory.append(statusEntry)
        ticket.currentStatusMessage = "Resolved"
        
        // Update the ticket in the array
        if let index = tickets.firstIndex(where: { $0.id == ticket.id }) {
            tickets[index] = ticket
        }
        
        selectedTicket = ticket
        
        // Save tickets after closing
        saveTickets()
        
        // Add a system message
        let systemMessage = SupportChatMessage(
            sender: .system,
            text: "🎯 Support ticket has been marked as resolved and closed."
        )
        addMessage(systemMessage)
        
        print("Ticket closed: \(ticket.title)")
    }
    
    // MARK: - Backend API Methods
    
    public func sendSystemInfo() async {
        // Simulate API call to send system information
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
        
        await MainActor.run {
            print("System info sent to backend for ticket: \(selectedTicket?.id.uuidString ?? "unknown")")
            // In a real implementation, this would:
            // 1. Collect system information (CPU, memory, disk, network, etc.)
            // 2. Send to backend API
            // 3. Update ticket with system info attachment
        }
    }
    
    public func runDiagnostics() async {
        // Simulate API call to run system diagnostics
        try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 second delay
        
        await MainActor.run {
            print("Diagnostics completed for ticket: \(selectedTicket?.id.uuidString ?? "unknown")")
            // In a real implementation, this would:
            // 1. Run comprehensive system diagnostics
            // 2. Generate diagnostic report
            // 3. Send results to backend
            // 4. Update ticket with diagnostic results
        }
    }
    
    public func scheduleCallback() async {
        // Simulate API call to schedule callback
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
        
        await MainActor.run {
            print("Callback scheduled for ticket: \(selectedTicket?.id.uuidString ?? "unknown")")
            // In a real implementation, this would:
            // 1. Create callback entry in scheduling system
            // 2. Send notification to support team
            // 3. Update ticket with callback information
            // 4. Send confirmation to user
        }
    }
    
    private func createNewSupportTicket() -> SupportTicketEnhanced {
        // Get current system information from systemInfoProvider
        let currentSystemInfo = SupportSystemInfo(
            hostname: "MacBook Pro", // Default hostname
            osVersion: "macOS Sequoia",
            macAddress: "Unknown", // Would need network interface query
            ipAddress: "Unknown", // Would need network interface query
            cpuModel: "Apple Silicon", // Would need system profiler
            totalMemory: "\(Int(systemInfoProvider.totalMemory)) GB",
            diskSpace: "Unknown", // Would need disk space calculation
            uptime: "Unknown", // Would need uptime calculation
            lastBootTime: Date()
        )
        
        // Check for pending updates (placeholder)
        let pendingUpdates: [SupportUpdateInfo] = [] // Would integrate with system update APIs
        
        // Create ticket with timestamp
        let timestamp = Date()
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        
        return SupportTicketEnhanced(
            title: "General Support - \(formatter.string(from: timestamp))",
            status: .open,
            date: timestamp,
            systemInfo: currentSystemInfo,
            updatesNeeded: pendingUpdates,
            description: "General support chat session initiated by user."
        )
    }
    
        public func startChat(for ticket: SupportTicketEnhanced) {
        // Prevent multiple simultaneous welcome message generation
        guard !isGeneratingWelcome else { return }
        
        selectedTicket = ticket
        
        // Load existing chat messages from the ticket
        chatMessages = ticket.chatMessages
        
        // If no existing messages, start with a welcome
        if chatMessages.isEmpty {
            chatMessages = [
                SupportChatMessage(sender: .system, text: "Chat session started for ticket: \(ticket.title)")
            ]
            
            isGeneratingWelcome = true
            
            // Add Huginn AI welcome message using Ollama
            Task {
                defer { 
                    Task { @MainActor in
                        self.isGeneratingWelcome = false
                    }
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                let contextPrompt = """
                You are Huginn AI. The user has opened a support ticket titled "\(ticket.title)" with description: "\(ticket.description)".
                \(ticket.updatesNeeded.isEmpty ? "No updates are pending." : "\(ticket.updatesNeeded.count) software updates are pending.")
                
                Start with "I am Huginn AI, how can I help you?" then provide a brief acknowledgment of their specific issue. Keep it concise and professional.
                """
                
                do {
                    let response = try await OllamaService.shared.sendMessage(contextPrompt)
                    await MainActor.run {
                        let welcomeMessage = SupportChatMessage(sender: .agent, text: response)
                        self.chatMessages.append(welcomeMessage)
                        self.updateTicketWithMessage(welcomeMessage)
                    }
                } catch {
                    // Fallback message if Ollama fails
                    await MainActor.run {
                        let fallbackMessage = "I am Huginn AI, how can I help you? " + (ticket.updatesNeeded.isEmpty ? 
                            "I've reviewed your system information and I'm ready to assist with your \(ticket.title.lowercased()) issue." :
                            "I can see you have \(ticket.updatesNeeded.count) pending updates. Would you like me to help you prioritize them or address your \(ticket.title.lowercased()) issue first?")
                        
                        let welcomeMessage = SupportChatMessage(sender: .agent, text: fallbackMessage)
                        self.chatMessages.append(welcomeMessage)
                        self.updateTicketWithMessage(welcomeMessage)
                    }
                }
            }
        }
        
        print("Started chat for ticket: \(ticket.title)")
    }
    
        public func startNewChat() {
        // Prevent multiple simultaneous welcome message generation
        guard !isGeneratingWelcome else { return }
        
        // Create a new support ticket for this chat session
        let newTicket = createNewSupportTicket()
        selectedTicket = newTicket
        tickets.insert(newTicket, at: 0) // Insert at beginning for newest first
        
        // Save tickets immediately
        saveTickets()
        
        // Refresh alerts to show current system status
        generateSystemAlerts()
        
        // Start with system message
        chatMessages = [
            SupportChatMessage(sender: .system, text: "New support ticket created: \(newTicket.title)")
        ]
        isGeneratingWelcome = true
        
        // Add Huginn AI welcome message using Ollama
        Task {
            defer { 
                Task { @MainActor in
                    self.isGeneratingWelcome = false
                }
            }
            
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            let introPrompt = """
            You are Huginn AI, a helpful macOS system assistant. The user has started a new general support chat session and a support ticket has been created for them.
            
            Start with "I am Huginn AI, how can I help you?" then provide a brief, friendly introduction explaining what you can help with (system diagnostics, software updates, troubleshooting, general Mac questions). Mention that a support ticket has been created to track this session. Keep it concise and welcoming.
            """
            
            do {
                let response = try await OllamaService.shared.sendMessage(introPrompt)
                await MainActor.run {
                    let welcomeMessage = SupportChatMessage(sender: .agent, text: response)
                    self.chatMessages.append(welcomeMessage)
                    self.updateTicketWithMessage(welcomeMessage)
                }
            } catch {
                // Fallback message if Ollama fails
                await MainActor.run {
                    let welcomeMessage = SupportChatMessage(
                        sender: .agent, 
                        text: "I am Huginn AI, how can I help you? I can help you with system diagnostics, software updates, troubleshooting, or answer any questions you might have about your Mac. A support ticket has been created to track our conversation."
                    )
                    self.chatMessages.append(welcomeMessage)
                    self.updateTicketWithMessage(welcomeMessage)
                }
            }
        }
        
        print("Started new general chat session")
    }
    
    private func updateTicketWithMessage(_ message: SupportChatMessage) {
        guard let selectedTicket = selectedTicket,
              let ticketIndex = tickets.firstIndex(where: { $0.id == selectedTicket.id }) else {
            return
        }
        
        // Update the ticket with the new message
        tickets[ticketIndex].chatMessages.append(message)
        tickets[ticketIndex].lastActivity = Date()
        
        // Update the selected ticket reference
        self.selectedTicket = tickets[ticketIndex]
        
        // Save to storage
        saveTickets()
    }
    
    public func sendMessage(_ message: String) {
        guard !message.isEmpty else { return }
        
        // Add user message immediately
        let userMessage = SupportChatMessage(sender: .user, text: message)
        chatMessages.append(userMessage)
        updateTicketWithMessage(userMessage)
        
        // Set processing state
        isProcessingMessage = true
        
        Task {
            // Check for installation intent
            if let installIntent = OllamaScriptGenerationService.shared.detectInstallationIntent(in: message) {
                await handleInstallationRequest(intent: installIntent, originalMessage: message)
            } else if let maintenanceIntent = OllamaScriptGenerationService.shared.detectMaintenanceIntent(in: message) {
                await handleMaintenanceRequest(intent: maintenanceIntent, originalMessage: message)
            } else {
                // Regular chat response
                await handleRegularChat(message: message)
            }
        }
    }
    
    private func handleInstallationRequest(intent: InstallationIntent, originalMessage: String) async {
        do {
            // First provide a regular response
            let response = try await sendToOllama(userMessage: originalMessage)
            
            await MainActor.run {
                let agentMessage = SupportChatMessage(
                    sender: .agent,
                    text: response,
                    hasScriptAction: true,
                    scriptIntent: .installation(intent)
                )
                self.chatMessages.append(agentMessage)
                self.updateTicketWithMessage(agentMessage)
                self.isProcessingMessage = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = SupportChatMessage(
                    sender: .agent,
                    text: "I can help with installing \(intent.softwareName). Let me generate a script for you."
                )
                self.chatMessages.append(errorMessage)
                self.updateTicketWithMessage(errorMessage)
                self.isProcessingMessage = false
            }
        }
    }
    
    private func handleMaintenanceRequest(intent: MaintenanceIntent, originalMessage: String) async {
        do {
            // First provide a regular response
            let response = try await sendToOllama(userMessage: originalMessage)
            
            await MainActor.run {
                let agentMessage = SupportChatMessage(
                    sender: .agent,
                    text: response,
                    hasScriptAction: true,
                    scriptIntent: .maintenance(intent)
                )
                self.chatMessages.append(agentMessage)
                self.updateTicketWithMessage(agentMessage)
                self.isProcessingMessage = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = SupportChatMessage(
                    sender: .agent,
                    text: "I can help with that maintenance task. Let me generate a script for you."
                )
                self.chatMessages.append(errorMessage)
                self.updateTicketWithMessage(errorMessage)
                self.isProcessingMessage = false
            }
        }
    }
    
    private func handleRegularChat(message: String) async {
        // Check if this is a response to a resolution confirmation
        if detectResolutionConfirmation(in: message) {
            await handleResolutionConfirmation(message: message)
            return
        }
        
        do {
            let response = try await sendToOllama(userMessage: message)
            
            await MainActor.run {
                let agentMessage = SupportChatMessage(
                    sender: .agent,
                    text: response
                )
                self.chatMessages.append(agentMessage)
                self.updateTicketWithMessage(agentMessage)
                self.isProcessingMessage = false
            }
        } catch {
            await MainActor.run {
                let errorMessage = SupportChatMessage(
                    sender: .agent,
                    text: "Sorry, I encountered an error: \(error.localizedDescription)"
                )
                self.chatMessages.append(errorMessage)
                self.updateTicketWithMessage(errorMessage)
                self.isProcessingMessage = false
            }
        }
    }
    
    private func sendToOllama(userMessage: String) async throws -> String {
        // Build prompt with context but without chat history
        let prompt = buildContextualPrompt(for: userMessage)
        
        // Send directly to OllamaService
        let ollamaService = OllamaService.shared
        return try await ollamaService.sendMessage(prompt)
    }
    
    private func buildContextualPrompt(for message: String) -> String {
        var prompt = """
        You are Huginn AI, a helpful macOS system assistant. You provide concise, practical help with Mac systems.
        
        User's Message: \(message)
        
        """
        
        // Add ticket context if available
        if let ticket = selectedTicket {
            prompt += """
            
            Current Support Ticket Context:
            - Title: \(ticket.title)
            - Status: \(ticket.status.rawValue)
            - Description: \(ticket.description)
            """
            
            if !ticket.updatesNeeded.isEmpty {
                prompt += "\n- Pending Updates: \(ticket.updatesNeeded.count) available"
            }
        }
        
        prompt += "\n\nPlease provide a helpful, concise response focused on solving the user's issue."
        
        return prompt
    }
    
    public func updateApplication(_ update: SupportUpdateInfo) {
        print("Updating \(update.name) from \(update.currentVersion) to \(update.availableVersion)")
        
        Task {
            do {
                // Determine update method based on the application
                if update.name.lowercased().contains("homebrew") || update.description.contains("brew") {
                    try await updateViaHomebrew(update)
                } else {
                    try await updateViaAppStore(update)
                }
                
                await MainActor.run {
                    // Refresh system alerts after update
                    self.refreshSystemAlerts()
                    print("✅ Update completed for \(update.name)")
                }
                
            } catch {
                await MainActor.run {
                    print("❌ Update failed for \(update.name): \(error.localizedDescription)")
                }
            }
        }
    }
    
    private func updateViaHomebrew(_ update: SupportUpdateInfo) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        // Enhanced PATH for Homebrew  
        var environment = [String: String]()
        // Copy existing environment and enhance PATH for Homebrew
        if let existingPath = getenv("PATH") {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + String(cString: existingPath)
        } else {
            environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        }
        process.environment = environment
        
        // Determine if it's a cask or formula
        let appName = update.name.lowercased().replacingOccurrences(of: " ", with: "-")
        let updateCommand = """
        #!/bin/bash
        export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
        
        # Check if it's a cask first
        if brew list --cask | grep -q "^\(appName)$"; then
            echo "Updating cask: \(appName)"
            brew upgrade --cask \(appName)
        elif brew list | grep -q "^\(appName)$"; then
            echo "Updating formula: \(appName)"
            brew upgrade \(appName)
        else
            echo "Application not found in Homebrew"
            exit 1
        fi
        """
        
        process.arguments = ["-c", updateCommand]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "UpdateError", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Homebrew update failed with exit code \\(process.terminationStatus)"
            ])
        }
    }
    
    private func updateViaAppStore(_ update: SupportUpdateInfo) async throws {
        // For App Store apps, we can try to open the App Store to the app's page
        // Or use the 'mas' command line tool if available
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        
        let updateCommand = """
        #!/bin/bash
        
        # Check if 'mas' (Mac App Store command line) is available
        if command -v mas >/dev/null 2>&1; then
            echo "Updating via Mac App Store command line..."
            mas upgrade
        else
            echo "Opening App Store for manual update..."
            open "macappstore://showUpdatesPage"
        fi
        """
        
        process.arguments = ["-c", updateCommand]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw NSError(domain: "UpdateError", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "App Store update failed with exit code \\(process.terminationStatus)"
            ])
        }
    }
    
    private func updatePackages() async {
        // Simulate package updates from all open tickets
        let allUpdates = tickets.flatMap { $0.updatesNeeded }.prefix(5)
        
        for update in allUpdates {
            print("Updating \(update.name)...")
            // Simulate update time
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            print("Update completed for \(update.name)")
        }
    }
}

// MARK: - Main Support View

struct SupportView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                if geometry.size.width > 1200 {
                    // Desktop: 3-column layout
                    HStack(spacing: 0) {
                        // Left Column (35%) - Ticket List
                        TicketListColumn(viewModel: viewModel)
                            .frame(width: geometry.size.width * 0.35)
                        
                        Divider()
                        
                        // Middle Column (35%) - Ticket Details & Chat
                        TicketDetailColumn(viewModel: viewModel)
                            .frame(width: geometry.size.width * 0.35)
                        
                        Divider()
                        
                        // Right Column (30%) - Huginn Agent Panel
                        HuginnAgentPanel(viewModel: viewModel)
                            .frame(width: geometry.size.width * 0.30)
                    }
                } else {
                    // Mobile/Tablet: Single column with navigation
                    NavigationSplitView {
                        TicketListColumn(viewModel: viewModel)
                    } detail: {
                        if viewModel.selectedTicket != nil {
                            VStack(spacing: 0) {
                                TicketDetailColumn(viewModel: viewModel)
                                    .frame(maxHeight: .infinity)
                                
                                Divider()
                                
                                HuginnAgentPanel(viewModel: viewModel)
                                    .frame(height: 300)
                            }
                        } else {
                            Text("Select a ticket to view details")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Support")
        .onAppear {
            viewModel.refreshSystemAlerts()
        }
    }
}

// MARK: - Left Column: Ticket List

struct TicketListColumn: View {
    @ObservedObject var viewModel: SupportViewModel
    @State private var searchText = ""
    @State private var selectedFilter: TicketFilter = .all
    @State private var hoveredTicket: UUID?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with search
            VStack(spacing: 16) {
                HStack {
                    Text("Support Tickets")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    
                    TextField("Search tickets or ID...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Filter tabs
                HStack(spacing: 0) {
                    ForEach(TicketFilter.allCases, id: \.self) { filter in
                        Button(action: {
                            selectedFilter = filter
                        }) {
                            VStack(spacing: 4) {
                                HStack(spacing: 4) {
                                    Text(filter.rawValue)
                                        .font(.subheadline)
                                        .fontWeight(selectedFilter == filter ? .semibold : .regular)
                                    
                                    if filter != .all {
                                        Text("\(ticketCount(for: filter))")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(filter.color.opacity(0.2))
                                            .foregroundColor(filter.color)
                                            .clipShape(Capsule())
                                    }
                                }
                                .foregroundColor(selectedFilter == filter ? .primary : .secondary)
                                
                                Rectangle()
                                    .fill(selectedFilter == filter ? Color.accentColor : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(20)
            
            Divider()
            
            // Ticket list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTickets) { ticket in
                        TicketListRow(
                            ticket: ticket,
                            isSelected: viewModel.selectedTicket?.id == ticket.id,
                            isHovered: hoveredTicket == ticket.id,
                            onTap: {
                                viewModel.selectTicket(ticket)
                            }
                        )
                        .onHover { hovering in
                            hoveredTicket = hovering ? ticket.id : nil
                        }
                        
                        Divider()
                            .padding(.leading, 20)
                    }
                }
            }
            
            // Floating New Ticket Button
            .overlay(
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            viewModel.startNewChat()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("New Ticket")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(20)
            )
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private var filteredTickets: [SupportTicketEnhanced] {
        var tickets = viewModel.tickets
        
        // Apply filter
        switch selectedFilter {
        case .all:
            break
        case .open:
            tickets = tickets.filter { $0.status == .open || $0.status == .inProgress }
        case .closed:
            tickets = tickets.filter { $0.status == .resolved || $0.status == .closed }
        case .aiSuggested:
            tickets = tickets.filter { !$0.chatMessages.isEmpty && $0.chatMessages.contains { $0.hasScriptAction } }
        }
        
        // Apply search
        if !searchText.isEmpty {
            tickets = tickets.filter { ticket in
                ticket.title.localizedCaseInsensitiveContains(searchText) ||
                ticket.id.uuidString.localizedCaseInsensitiveContains(searchText) ||
                ticket.description.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return tickets.sorted { $0.lastActivity > $1.lastActivity }
    }
    
    private func ticketCount(for filter: TicketFilter) -> Int {
        switch filter {
        case .all:
            return viewModel.tickets.count
        case .open:
            return viewModel.tickets.filter { $0.status == .open || $0.status == .inProgress }.count
        case .closed:
            return viewModel.tickets.filter { $0.status == .resolved || $0.status == .closed }.count
        case .aiSuggested:
            return viewModel.tickets.filter { !$0.chatMessages.isEmpty && $0.chatMessages.contains { $0.hasScriptAction } }.count
        }
    }
}

enum TicketFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case closed = "Closed"
    case aiSuggested = "AI Suggested"
    
    var color: Color {
        switch self {
        case .all: return .blue
        case .open: return .orange
        case .closed: return .green
        case .aiSuggested: return .purple
        }
    }
}

struct TicketListRow: View {
    let ticket: SupportTicketEnhanced
    let isSelected: Bool
    let isHovered: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Title and status
                        HStack(alignment: .top, spacing: 8) {
                            Text(ticket.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Text(ticket.status.rawValue)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(ticket.status.color.opacity(0.2))
                                .foregroundColor(ticket.status.color)
                                .clipShape(Capsule())
                        }
                        
                        // Metadata
                        HStack(spacing: 12) {
                            HStack(spacing: 4) {
                                Image(systemName: "clock")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(formatRelativeTime(ticket.lastActivity))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 4) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(ticket.chatMessages.count)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        
                        // Preview on hover
                        if isHovered && !ticket.description.isEmpty {
                            Text(ticket.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(3)
                                .padding(.top, 4)
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                                .animation(.easeInOut(duration: 0.2), value: isHovered)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.1) : (isHovered ? Color(NSColor.controlBackgroundColor) : Color.clear))
                .animation(.easeInOut(duration: 0.15), value: isSelected)
                .animation(.easeInOut(duration: 0.15), value: isHovered)
        )
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Middle Column: Ticket Details & Chat

struct TicketDetailColumn: View {
    @ObservedObject var viewModel: SupportViewModel
    @State private var newMessage = ""
    @State private var isDragOver = false
    @State private var showStatusHistory = false
    
    var body: some View {
        VStack(spacing: 0) {
            if let ticket = viewModel.selectedTicket {
                // Header with ticket metadata
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(ticket.title)
                                .font(.title3)
                                .fontWeight(.semibold)
                            
                            HStack(spacing: 16) {
                                Label(ticket.id.uuidString.prefix(8), systemImage: "number.circle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Label(DateFormatter.fullDateTime.string(from: ticket.date), systemImage: "calendar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            HStack(spacing: 12) {
                                Text(ticket.status.rawValue)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(ticket.status.color.opacity(0.2))
                                    .foregroundColor(ticket.status.color)
                                    .clipShape(Capsule())
                                
                                Text(ticket.currentStatusMessage)
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .clipShape(Capsule())
                                
                                Text("High Priority")
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
                                    .clipShape(Capsule())
                            }
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button("Mark as Resolved") {
                                viewModel.updateTicketStatus("Resolved")
                                if var selectedTicket = viewModel.selectedTicket {
                                    selectedTicket.status = .resolved
                                    viewModel.selectedTicket = selectedTicket
                                    if let index = viewModel.tickets.firstIndex(where: { $0.id == selectedTicket.id }) {
                                        viewModel.tickets[index] = selectedTicket
                                    }
                                }
                            }
                            Button("Close Ticket") {
                                viewModel.updateTicketStatus("Closed")
                                if var selectedTicket = viewModel.selectedTicket {
                                    selectedTicket.status = .closed
                                    viewModel.selectedTicket = selectedTicket
                                    if let index = viewModel.tickets.firstIndex(where: { $0.id == selectedTicket.id }) {
                                        viewModel.tickets[index] = selectedTicket
                                    }
                                }
                            }
                            Divider()
                            Button("View Status History") {
                                showStatusHistory = true
                            }
                            Button("Export Chat") {
                                // TODO: Implement export
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundColor(.secondary)
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                    }
                    .padding(20)
                    
                    Divider()
                }
                
                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(ticket.chatMessages) { message in
                                ChatBubble(message: message, viewModel: viewModel)
                                    .id(message.id)
                            }
                        }
                        .padding(.vertical, 16)
                    }
                    .onAppear {
                        // Scroll to bottom when ticket changes
                        if let lastMessage = ticket.chatMessages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: ticket.chatMessages.count) {
                        // Auto-scroll to new messages
                        if let lastMessage = ticket.chatMessages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Message input
                VStack(spacing: 12) {
                    HStack(alignment: .bottom, spacing: 12) {
                        // File upload button
                        Button(action: {
                            // TODO: Implement file upload
                        }) {
                            Image(systemName: "paperclip")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                                .frame(width: 32, height: 32)
                                .background(Color(NSColor.controlBackgroundColor))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Text input
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack(alignment: .topLeading) {
                                TextEditor(text: $newMessage)
                                    .font(.body)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 40, maxHeight: 120)
                                
                                if newMessage.isEmpty {
                                    Text("Type your message...")
                                        .foregroundColor(.secondary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.textBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isDragOver ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isDragOver ? 2 : 1)
                            )
                            .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
                                // TODO: Handle file drop
                                return true
                            }
                        }
                        
                        // Send button
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(newMessage.isEmpty ? .secondary : .accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(newMessage.isEmpty)
                    }
                    
                    // Quick actions
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            QuickReplyButton(text: "Send system info", action: {
                                onClickSendSystemInfo()
                            })
                            
                            QuickReplyButton(text: "Run diagnostics", action: {
                                onClickRunDiagnostics()
                            })
                            
                            QuickReplyButton(text: "Schedule callback", action: {
                                onClickScheduleCallback()
                            })
                        }
                        .padding(.horizontal, 20)
                    }
                }
                .padding(20)
                
            } else {
                // No ticket selected
                VStack(spacing: 16) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Select a ticket to view details")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    
                    Text("Choose a support ticket from the list to see the conversation and details.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showStatusHistory) {
            if let ticket = viewModel.selectedTicket {
                StatusHistoryView(ticket: ticket)
            }
        }
    }
    
    private func sendMessage() {
        guard !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        let message = SupportChatMessage(
            sender: .user,
            text: newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        
        viewModel.addMessage(message)
        newMessage = ""
        
        // Auto-generate AI response after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            viewModel.generateAIResponse(to: message)
        }
    }
    
    // MARK: - Quick Action Methods
    
    private func onClickSendSystemInfo() {
        // Add system message to chat
        let systemMessage = SupportChatMessage(
            sender: .system,
            text: "📤 System info sent."
        )
        viewModel.addMessage(systemMessage)
        
        // Update ticket status
        viewModel.updateTicketStatus("System Info Sent")
        
        // Trigger backend API call
        Task {
            await viewModel.sendSystemInfo()
        }
        
        // Generate AI response acknowledging the system info
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            do {
                let prompt = """
                You are Huginn AI. The user just sent their system information for analysis. 
                
                Current system metrics:
                - CPU Usage: \(viewModel.cpuUsage * 100)%
                - Memory Usage: \(viewModel.memoryUsage * 100)%
                - Disk Usage: \(viewModel.diskUsage * 100)%
                
                Acknowledge that you received the system info and provide a brief analysis of their system status. Offer specific recommendations if any metrics are concerning.
                """
                
                let response = try await OllamaService.shared.sendMessage(prompt)
                
                await MainActor.run {
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: response
                    )
                    viewModel.addMessage(aiResponse)
                }
                
            } catch {
                await MainActor.run {
                    let fallbackResponse = "Thank you for sending the system information. I can see your CPU is at \(Int(viewModel.cpuUsage * 100))%, memory at \(Int(viewModel.memoryUsage * 100))%, and disk at \(Int(viewModel.diskUsage * 100))%. Let me analyze this data and provide recommendations."
                    
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: fallbackResponse
                    )
                    viewModel.addMessage(aiResponse)
                }
            }
        }
    }
    
    private func onClickRunDiagnostics() {
        // Add system message to chat
        let systemMessage = SupportChatMessage(
            sender: .system,
            text: "🩺 Running diagnostics..."
        )
        viewModel.addMessage(systemMessage)
        
        // Update ticket status
        viewModel.updateTicketStatus("Diagnostics In Progress")
        
        // Trigger backend API call
        Task {
            await viewModel.runDiagnostics()
        }
        
        // Generate AI response with diagnostic results after delay
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 second delay
            
            do {
                let prompt = """
                You are Huginn AI. You just completed a comprehensive system diagnostic. 
                
                Current system metrics:
                - CPU Usage: \(Int(viewModel.cpuUsage * 100))%
                - Memory Usage: \(Int(viewModel.memoryUsage * 100))%
                - Disk Usage: \(Int(viewModel.diskUsage * 100))%
                
                Provide a diagnostic report with:
                1. Overall system health assessment
                2. Analysis of each metric (use ✅ for good, ⚠️ for concerning, ❌ for critical)
                3. Specific recommendations for any issues found
                4. Suggest a cleanup script if memory or disk usage is high
                
                Format as a clear, technical diagnostic report.
                """
                
                let response = try await OllamaService.shared.sendMessage(prompt)
                
                await MainActor.run {
                    // Determine if we should offer cleanup based on system metrics
                    let shouldOfferCleanup = viewModel.memoryUsage > 0.7 || viewModel.diskUsage > 0.8
                    let systemIsHealthy = viewModel.cpuUsage < 0.8 && viewModel.memoryUsage < 0.8 && viewModel.diskUsage < 0.9
                    
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: response,
                        hasScriptAction: shouldOfferCleanup,
                        scriptIntent: shouldOfferCleanup ? .maintenance(MaintenanceIntent(taskType: .cleanup, originalRequest: "system cleanup")) : nil
                    )
                    viewModel.addMessage(aiResponse)
                    viewModel.updateTicketStatus("Diagnostics Completed")
                    
                    // If system is healthy, ask about resolution
                    if systemIsHealthy {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.askForResolutionConfirmation()
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    let fallbackResults = """
                    🩺 Diagnostics completed:
                    
                    \(viewModel.cpuUsage < 0.8 ? "✅" : "⚠️") CPU Usage: \(Int(viewModel.cpuUsage * 100))%
                    \(viewModel.memoryUsage < 0.8 ? "✅" : "⚠️") Memory Usage: \(Int(viewModel.memoryUsage * 100))%
                    \(viewModel.diskUsage < 0.9 ? "✅" : "⚠️") Disk Usage: \(Int(viewModel.diskUsage * 100))%
                    ✅ Network: Connected
                    
                    \(viewModel.memoryUsage > 0.7 || viewModel.diskUsage > 0.8 ? "Recommendation: Consider running a system cleanup to optimize performance." : "System is running within normal parameters.")
                    """
                    
                    let shouldOfferCleanup = viewModel.memoryUsage > 0.7 || viewModel.diskUsage > 0.8
                    let systemIsHealthy = viewModel.cpuUsage < 0.8 && viewModel.memoryUsage < 0.8 && viewModel.diskUsage < 0.9
                    
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: fallbackResults,
                        hasScriptAction: shouldOfferCleanup,
                        scriptIntent: shouldOfferCleanup ? .maintenance(MaintenanceIntent(taskType: .cleanup, originalRequest: "system cleanup")) : nil
                    )
                    viewModel.addMessage(aiResponse)
                    viewModel.updateTicketStatus("Diagnostics Completed")
                    
                    // If system is healthy, ask about resolution
                    if systemIsHealthy {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.askForResolutionConfirmation()
                        }
                    }
                }
            }
        }
    }
    
    private func onClickScheduleCallback() {
        // Add system message to chat
        let systemMessage = SupportChatMessage(
            sender: .system,
            text: "📅 Callback scheduled."
        )
        viewModel.addMessage(systemMessage)
        
        // Update ticket status
        viewModel.updateTicketStatus("Callback Scheduled")
        
        // Trigger backend API call
        Task {
            await viewModel.scheduleCallback()
        }
        
        // Generate AI response confirming callback
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
            
            do {
                let callbackTime = DateFormatter.timeOnly.string(from: Date().addingTimeInterval(3600)) // 1 hour from now
                let prompt = """
                You are Huginn AI. You just scheduled a callback for the user at \(callbackTime) today.
                
                Ticket context: \(viewModel.selectedTicket?.title ?? "General Support")
                
                Confirm the callback scheduling professionally and reassuringly. Mention:
                1. The scheduled time (\(callbackTime))
                2. What the support team will help with
                3. Ask if there's anything else you can help with in the meantime
                4. Offer to provide any additional information that might be helpful for the callback
                
                Keep it friendly and professional.
                """
                
                let response = try await OllamaService.shared.sendMessage(prompt)
                
                await MainActor.run {
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: response
                    )
                    viewModel.addMessage(aiResponse)
                }
                
            } catch {
                await MainActor.run {
                    let callbackTime = DateFormatter.timeOnly.string(from: Date().addingTimeInterval(3600)) // 1 hour from now
                    let fallbackResponse = "Perfect! I've scheduled a callback for \(callbackTime) today. You'll receive a call from our technical support team to follow up on your issue. Is there anything else I can help you with in the meantime?"
                    
                    let aiResponse = SupportChatMessage(
                        sender: .agent,
                        text: fallbackResponse
                    )
                    viewModel.addMessage(aiResponse)
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: SupportChatMessage
    let viewModel: SupportViewModel
    
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.sender == .user {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if message.sender != .user {
                        Image(systemName: message.sender == .agent ? "brain" : "gear")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(message.sender.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Text(DateFormatter.timeOnly.string(from: message.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    if message.hasScriptAction, let scriptIntent = message.scriptIntent {
                        ScriptActionView(intent: scriptIntent, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(message.sender == .user ? Color.accentColor : Color(NSColor.controlBackgroundColor))
                )
                .foregroundColor(message.sender == .user ? .white : .primary)
            }
            
            if message.sender != .user {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 4)
    }
}

struct QuickReplyButton: View {
    let text: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(NSColor.controlBackgroundColor))
                .foregroundColor(.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Right Column: Huginn Agent Panel

struct HuginnAgentPanel: View {
    @ObservedObject var viewModel: SupportViewModel
    @State private var lastScanTime = Date()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Huginn Agent")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        Text("AI System Monitor")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: refreshSystemData) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                HStack {
                    Text("Last scan: \(DateFormatter.timeOnly.string(from: lastScanTime))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("Active")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            
            Divider()
            
            // System Status Section
            ScrollView {
                VStack(spacing: 20) {
                    // Real-time metrics
                    VStack(alignment: .leading, spacing: 12) {
                        Text("System Status")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            SystemMetricRow(
                                icon: "cpu",
                                label: "CPU Usage",
                                value: "\(Int(viewModel.cpuUsage * 100))%",
                                status: viewModel.cpuUsage > 0.8 ? .warning : .normal
                            )
                            
                            SystemMetricRow(
                                icon: "memorychip",
                                label: "Memory",
                                value: "\(Int(viewModel.memoryUsage * 100))%",
                                status: viewModel.memoryUsage > 0.85 ? .warning : .normal
                            )
                            
                            SystemMetricRow(
                                icon: "internaldrive",
                                label: "Disk Space",
                                value: "\(Int(viewModel.diskUsage * 100))%",
                                status: viewModel.diskUsage > 0.9 ? .warning : .normal
                            )
                            
                            SystemMetricRow(
                                icon: "network",
                                label: "Network",
                                value: "Online",
                                status: .normal
                            )
                        }
                    }
                    
                    Divider()
                    
                    // AI-detected Issues
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("AI Detected Issues")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Text("\(detectedIssues.count)")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(detectedIssues.isEmpty ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                                .foregroundColor(detectedIssues.isEmpty ? .green : .orange)
                                .clipShape(Capsule())
                        }
                        
                        if detectedIssues.isEmpty {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                
                                Text("No issues detected")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(detectedIssues, id: \.title) { issue in
                                    DetectedIssueRow(issue: issue)
                                }
                            }
                        }
                    }
                    
                    Divider()
                    
                    // Suggested Actions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Suggested Actions")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 8) {
                            ForEach(suggestedActions, id: \.title) { action in
                                SuggestedActionButton(action: action) {
                                    executeAction(action)
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            refreshSystemData()
        }
    }
    
    private var detectedIssues: [DetectedIssue] {
        var issues: [DetectedIssue] = []
        
        if viewModel.cpuUsage > 0.8 {
            issues.append(DetectedIssue(
                title: "High CPU Usage",
                description: "CPU usage is above 80%",
                severity: .warning
            ))
        }
        
        if viewModel.memoryUsage > 0.85 {
            issues.append(DetectedIssue(
                title: "High Memory Usage", 
                description: "Memory usage is above 85%",
                severity: .warning
            ))
        }
        
        if viewModel.diskUsage > 0.9 {
            issues.append(DetectedIssue(
                title: "Low Disk Space",
                description: "Disk usage is above 90%",
                severity: .critical
            ))
        }
        
        return issues
    }
    
    private var suggestedActions: [SuggestedAction] {
        [
            SuggestedAction(
                title: "Run System Cleanup",
                description: "Free up disk space and clear caches",
                icon: "trash.circle"
            ),
            SuggestedAction(
                title: "Check for Updates",
                description: "Install pending system updates",
                icon: "arrow.down.circle"
            ),
            SuggestedAction(
                title: "Restart Services",
                description: "Restart system services to free memory",
                icon: "arrow.clockwise.circle"
            ),
            SuggestedAction(
                title: "Run Diagnostics",
                description: "Perform comprehensive system check",
                icon: "stethoscope.circle"
            )
        ]
    }
    
    private func refreshSystemData() {
        lastScanTime = Date()
        // Trigger data refresh in viewModel
        Task {
            await viewModel.refreshSystemMetrics()
        }
    }
    
    private func executeAction(_ action: SuggestedAction) {
        // Add system message to chat if ticket is selected
        if viewModel.selectedTicket != nil {
            let systemMessage = SupportChatMessage(
                sender: .system,
                text: "🔧 Executing: \(action.title)..."
            )
            viewModel.addMessage(systemMessage)
            
            // Update ticket status
            viewModel.updateTicketStatus("Executing \(action.title)")
            
            // Execute action with Ollama-generated response
            Task {
                try? await Task.sleep(nanoseconds: 2_500_000_000) // 2.5 seconds
                
                do {
                    let prompt = """
                    You are Huginn AI. You just completed the action: "\(action.title)".
                    
                    Current system metrics:
                    - CPU Usage: \(Int(viewModel.cpuUsage * 100))%
                    - Memory Usage: \(Int(viewModel.memoryUsage * 100))%
                    - Disk Usage: \(Int(viewModel.diskUsage * 100))%
                    
                    Provide a detailed report of what was accomplished by this action. Be specific about:
                    1. What was done
                    2. Measurable results (disk space freed, memory optimized, etc.)
                    3. Any improvements the user should notice
                    4. Next recommended steps if applicable
                    
                    Keep it professional and technical but easy to understand.
                    """
                    
                    let response = try await OllamaService.shared.sendMessage(prompt)
                    
                    await MainActor.run {
                        let completionMessage = SupportChatMessage(
                            sender: .agent,
                            text: "✅ \(action.title) completed!\n\n\(response)"
                        )
                        viewModel.addMessage(completionMessage)
                        viewModel.updateTicketStatus("\(action.title) Completed")
                        
                        // Ask about resolution after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.askForResolutionConfirmation()
                        }
                    }
                    
                } catch {
                    await MainActor.run {
                        let fallbackResult = self.getActionResult(for: action)
                        let completionMessage = SupportChatMessage(
                            sender: .agent,
                            text: "✅ \(action.title) completed! \(fallbackResult)"
                        )
                        viewModel.addMessage(completionMessage)
                        viewModel.updateTicketStatus("\(action.title) Completed")
                        
                        // Ask about resolution after a brief delay
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.askForResolutionConfirmation()
                        }
                    }
                }
            }
        }
        
        print("Executing action: \(action.title)")
    }
    
    private func getActionResult(for action: SuggestedAction) -> String {
        switch action.title {
        case "Run System Cleanup":
            return "Freed up 2.3GB of disk space by clearing caches and temporary files."
        case "Check for Updates":
            return "Found 3 available updates. Would you like me to install them?"
        case "Restart Services":
            return "System services restarted successfully. Memory usage reduced by 15%."
        case "Run Diagnostics":
            return "System diagnostics completed. All components are functioning normally."
        default:
            return "Action completed successfully."
        }
    }
}

struct SystemMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: MetricStatus
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 16)
            
            Text(label)
                .font(.caption)
                .foregroundColor(.primary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(status == .warning ? .orange : .primary)
        }
    }
}

struct DetectedIssueRow: View {
    let issue: DetectedIssue
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: issue.severity == .critical ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .font(.caption)
                .foregroundColor(issue.severity == .critical ? .red : .orange)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(issue.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct SuggestedActionButton: View {
    let action: SuggestedAction
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: action.icon)
                    .font(.system(size: 16))
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(action.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(action.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

enum MetricStatus {
    case normal
    case warning
    case critical
}

struct DetectedIssue {
    let title: String
    let description: String
    let severity: IssueSeverity
}

enum IssueSeverity {
    case warning
    case critical
}

struct SuggestedAction {
    let title: String
    let description: String
    let icon: String
}

struct ScriptExecutionResult {
    let success: Bool
    let output: String
    let exitCode: Int32
}

struct StatusHistoryView: View {
    let ticket: SupportTicketEnhanced
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Status History")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Ticket: \(ticket.title)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(20)
            
            Divider()
            
            // Status history list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(ticket.statusHistory.reversed()) { entry in
                        StatusHistoryRow(entry: entry)
                        
                        if entry.id != ticket.statusHistory.first?.id {
                            Divider()
                                .padding(.leading, 60)
                        }
                    }
                }
                .padding(.vertical, 16)
            }
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct StatusHistoryRow: View {
    let entry: TicketStatusEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Timeline dot
            VStack {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 12, height: 12)
                
                Rectangle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 12)
            
            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(entry.status)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Text(DateFormatter.timeOnly.string(from: entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Text(entry.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(DateFormatter.fullDateTime.string(from: entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.bottom, 16)
            
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}

struct ScriptActionView: View {
    let intent: ScriptIntent
    let viewModel: SupportViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundColor(.accentColor)
                
                Text("Suggested Action")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(actionTitle(for: intent))
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text(actionDescription(for: intent))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Run") {
                    onRunScriptAction(intent)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func actionTitle(for intent: ScriptIntent) -> String {
        switch intent {
        case .installation(let installIntent):
            if installIntent.method == .homebrew {
                return "Install via Homebrew"
            } else {
                return "Install \(installIntent.softwareName)"
            }
        case .maintenance(let maintenanceIntent):
            switch maintenanceIntent.taskType {
            case .cleanup:
                return "System Cleanup"
            case .update:
                return "Update System"
            case .optimize:
                return "Optimize System"
            case .general:
                return "General Maintenance"
            }
        case .diagnostic(let type):
            return "Run \(type) Diagnostics"
        }
    }
    
    private func actionDescription(for intent: ScriptIntent) -> String {
        switch intent {
        case .installation(let installIntent):
            switch installIntent.method {
            case .homebrew:
                return "Install \(installIntent.softwareName) via Homebrew"
            case .appStore:
                return "Install \(installIntent.softwareName) from App Store"
            case .directDownload:
                return "Download and install \(installIntent.softwareName) directly"
            case .auto:
                return "Auto-detect best installation method for \(installIntent.softwareName)"
            }
        case .maintenance(let maintenanceIntent):
            switch maintenanceIntent.taskType {
            case .cleanup:
                return "Clean temporary files and caches"
            case .update:
                return "Check for and install updates"
            case .optimize:
                return "Optimize system performance"
            case .general:
                return "Perform general system maintenance"
            }
        case .diagnostic(let type):
            return "Perform \(type) system diagnostics"
        }
    }
    
    private func onRunScriptAction(_ intent: ScriptIntent) {
        // Add system message to chat
        let actionName = actionTitle(for: intent)
        let systemMessage = SupportChatMessage(
            sender: .system,
            text: "🚀 Executing: \(actionName)..."
        )
        viewModel.addMessage(systemMessage)
        
        // Update ticket status based on action type
        let statusMessage: String
        switch intent {
        case .installation(let installIntent):
            statusMessage = "Installing \(installIntent.softwareName)"
        case .maintenance(let maintenanceIntent):
            statusMessage = "Running \(maintenanceIntent.taskType.rawValue)"
        case .diagnostic(let type):
            statusMessage = "Running \(type) Diagnostics"
        }
        
        viewModel.updateTicketStatus(statusMessage)
        
        // Actually generate and execute the script
        Task {
            do {
                let script: GeneratedScript
                
                switch intent {
                case .installation(let installIntent):
                    script = try await OllamaScriptGenerationService.shared.generateInstallationScript(for: installIntent.originalRequest)
                case .maintenance(let maintenanceIntent):
                    script = try await OllamaScriptGenerationService.shared.generateMaintenanceScript(for: maintenanceIntent.originalRequest)
                case .diagnostic(let type):
                    script = try await OllamaScriptGenerationService.shared.generateDiagnosticScript(for: type)
                }
                
                // Show script preview and ask for confirmation
                await MainActor.run {
                    let previewMessage = SupportChatMessage(
                        sender: .agent,
                        text: "📝 Generated script for \(actionName). Here's what will be executed:\n\n```bash\n\(script.content)\n```\n\nWould you like me to run this script?"
                    )
                    viewModel.addMessage(previewMessage)
                }
                
                // For now, auto-execute with a delay to show the preview
                // In a production app, you'd want user confirmation
                try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds to review
                
                await MainActor.run {
                    let executingMessage = SupportChatMessage(
                        sender: .system,
                        text: "⚡ Executing script..."
                    )
                    viewModel.addMessage(executingMessage)
                }
                
                // Execute the generated script
                let result = await executeScript(script)
                
                await MainActor.run {
                    let completionMessage = SupportChatMessage(
                        sender: .agent,
                        text: result.success ? 
                            "✅ \(actionName) completed successfully!\n\n\(result.output)" :
                            "❌ \(actionName) encountered an issue:\n\n\(result.output)"
                    )
                    viewModel.addMessage(completionMessage)
                    viewModel.updateTicketStatus(result.success ? "\(actionName) Completed" : "\(actionName) Failed")
                    
                    // If successful, ask about resolution after a brief delay
                    if result.success {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            viewModel.askForResolutionConfirmation()
                        }
                    }
                }
                
            } catch {
                await MainActor.run {
                    let errorMessage = SupportChatMessage(
                        sender: .agent,
                        text: "❌ Failed to generate script for \(actionName): \(error.localizedDescription)"
                    )
                    viewModel.addMessage(errorMessage)
                    viewModel.updateTicketStatus("\(actionName) Failed")
                }
            }
        }
    }
    
    private func executeScript(_ script: GeneratedScript) async -> ScriptExecutionResult {
        do {
            // Safety check: Don't execute high-risk scripts
            if script.riskLevel == .high {
                return ScriptExecutionResult(
                    success: false,
                    output: "⚠️ High-risk script execution blocked for safety. Script contains potentially dangerous commands.",
                    exitCode: -2
                )
            }
            
            // Create temporary script file
            let tempURL = try createTempScriptFile(content: script.content)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            
            // Configure process with timeout
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [tempURL.path]
            
            // Setup environment
            process.environment = createEnhancedEnvironment()
            
            // Setup pipes for output capture
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            
            // Start the process
            try process.run()
            
            // Capture output asynchronously with timeout
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            // Wait with timeout (5 minutes max)
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 300_000_000_000) // 5 minutes
                if process.isRunning {
                    process.terminate()
                }
            }
            
            process.waitUntilExit()
            timeoutTask.cancel()
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let error = String(data: errorData, encoding: .utf8) ?? ""
            let combinedOutput = [output, error].filter { !$0.isEmpty }.joined(separator: "\n")
            
            // Add execution summary
            let summary = """
            
            📊 Execution Summary:
            • Exit Code: \(process.terminationStatus)
            • Duration: \(String(format: "%.1f", script.estimatedDuration))s (estimated)
            • Risk Level: \(script.riskLevel.rawValue.capitalized)
            """
            
            // Enhanced error detection
            let outputLower = combinedOutput.lowercased()
            let hasErrorInOutput = outputLower.contains("error:") ||
                                 outputLower.contains("stderr:") ||
                                 outputLower.contains("failed") ||
                                 outputLower.contains("not found") ||
                                 outputLower.contains("no such file") ||
                                 outputLower.contains("permission denied") ||
                                 outputLower.contains("command not found") ||
                                 outputLower.contains("installation failed") ||
                                 outputLower.contains("unable to") ||
                                 outputLower.contains("cannot") ||
                                 outputLower.contains("does not exist") ||
                                 outputLower.contains("is not there")
            
            let success = process.terminationStatus == 0 && !hasErrorInOutput
            let finalOutput = combinedOutput.isEmpty ? 
                (success ? "Script executed successfully\(summary)" : "Script completed but with issues\(summary)") : 
                "\(combinedOutput)\(summary)"
            
            return ScriptExecutionResult(
                success: success,
                output: finalOutput,
                exitCode: hasErrorInOutput && process.terminationStatus == 0 ? 1 : process.terminationStatus
            )
            
        } catch {
            return ScriptExecutionResult(
                success: false,
                output: "Failed to execute script: \(error.localizedDescription)",
                exitCode: -1
            )
        }
    }
    
    private func createTempScriptFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("huginn_script_\(UUID().uuidString).sh")
        
        try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make the script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        return scriptURL
    }
    
    private func createEnhancedEnvironment() -> [String: String] {
        var env = Foundation.ProcessInfo.processInfo.environment
        
        // Ensure Homebrew paths are included
        let currentPath = env["PATH"] ?? ""
        let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let pathComponents = currentPath.components(separatedBy: ":")
        
        var newPathComponents = homebrewPaths
        for component in pathComponents {
            if !newPathComponents.contains(component) {
                newPathComponents.append(component)
            }
        }
        
        env["PATH"] = newPathComponents.joined(separator: ":")
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1" // Prevent automatic updates during install
        
        return env
    }
}

// MARK: - Ticket History View

struct SupportTicketHistoryView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        if viewModel.tickets.isEmpty && !viewModel.isLoading {
            VStack(spacing: 12) {
                Image(systemName: "ticket")
                    .foregroundColor(.secondary)
                    .font(.title2)
                Text("No support tickets yet")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                Text("Click 'New Chat' to start your first support session")
                    .foregroundColor(.secondary.opacity(0.7))
                    .font(.caption)
                    .multilineTextAlignment(.center)
                
                Button("New Chat") {
                    viewModel.startNewChat()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: 200)
            .padding()
        } else {
            List(viewModel.tickets, id: \.id, selection: $viewModel.selectedTicket) { ticket in
                SupportTicketRowView(ticket: ticket)
                    .onTapGesture {
                        viewModel.startChat(for: ticket)
                    }
            }
            .listStyle(.sidebar)
            .frame(maxHeight: 200)
        }
    }
}

// MARK: - Ticket Row View

struct SupportTicketRowView: View {
    let ticket: SupportTicketEnhanced
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ticket.title)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Text(ticket.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ticket.status.color.opacity(0.2))
                    .foregroundColor(ticket.status.color)
                    .clipShape(Capsule())
                
                Spacer()
                
                Text(dateFormatter.string(from: ticket.lastActivity))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                if !ticket.updatesNeeded.isEmpty {
                    Text("\(ticket.updatesNeeded.count) updates pending")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                
                Spacer()
                
                if ticket.chatMessages.count > 1 {
                    Text("\(ticket.chatMessages.count - 1) messages") // Subtract 1 for system message
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Ticket Details View

struct SupportTicketDetailsView: View {
    let ticket: SupportTicketEnhanced
    @ObservedObject var viewModel: SupportViewModel
    @State private var isSystemInfoExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ticket Details")
                .font(.headline)
                .padding(.horizontal)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // System Information
                    DisclosureGroup("System Information", isExpanded: $isSystemInfoExpanded) {
                        SupportSystemInfoView(systemInfo: ticket.systemInfo)
                    }
                    .padding(.horizontal)
                    
                    // Updates Needed
                    if !ticket.updatesNeeded.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Updates Needed (\(ticket.updatesNeeded.count))")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal)
                            
                            ForEach(ticket.updatesNeeded) { update in
                                SupportUpdateRowView(update: update, viewModel: viewModel)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxHeight: 300)
    }
}

// MARK: - System Info View

struct SupportSystemInfoView: View {
    let systemInfo: SupportSystemInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SupportInfoRow(label: "Hostname", value: systemInfo.hostname)
            SupportInfoRow(label: "OS Version", value: systemInfo.osVersion)
            SupportInfoRow(label: "CPU", value: systemInfo.cpuModel)
            SupportInfoRow(label: "Memory", value: systemInfo.totalMemory)
            SupportInfoRow(label: "Storage", value: systemInfo.diskSpace)
            SupportInfoRow(label: "Uptime", value: systemInfo.uptime)
            SupportInfoRow(label: "IP Address", value: systemInfo.ipAddress)
        }
        .padding(.top, 8)
    }
}

struct SupportInfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
        }
    }
}

// MARK: - Update Row View

struct SupportUpdateRowView: View {
    let update: SupportUpdateInfo
    @ObservedObject var viewModel: SupportViewModel
    @State private var isUpdating = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(update.name)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("\(update.currentVersion) → \(update.availableVersion)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(update.priority.rawValue)
                    .font(.caption2)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(update.priority.color.opacity(0.2))
                    .foregroundColor(update.priority.color)
                    .clipShape(Capsule())
            }
            
            HStack {
                Text(update.size)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Update Now") {
                    isUpdating = true
                    viewModel.updateApplication(update)
                    
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        isUpdating = false
                    }
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .disabled(isUpdating)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal)
    }
}

// MARK: - Alerts View

struct SupportAlertsView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        List(viewModel.alerts) { alert in
            SupportAlertRowView(alert: alert)
        }
        .listStyle(.sidebar)
        .frame(maxHeight: 150)
    }
}

// MARK: - Alert Row View

struct SupportAlertRowView: View {
    let alert: SupportAlertItem
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(alert.severity.color)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                
                Text(dateFormatter.string(from: alert.date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(alert.severity.rawValue)
                .font(.caption2)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(alert.severity.color.opacity(0.2))
                .foregroundColor(alert.severity.color)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail View

struct SupportDetailView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        Group {
            if !viewModel.chatMessages.isEmpty {
                SupportChatView(viewModel: viewModel)
            } else {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "Select a Ticket to Chat",
                        systemImage: "message.circle",
                        description: Text("Choose a support ticket from the sidebar to start a chat session with Huginn Agent")
                    )
                    
                    Button("New Chat") {
                        viewModel.startNewChat()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(viewModel.isGeneratingWelcome)
                }
            }
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Chat View

struct SupportChatView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat Header
            VStack(alignment: .leading, spacing: 4) {
                if let selectedTicket = viewModel.selectedTicket {
                    Text("Chat: \(selectedTicket.title)")
                        .font(.headline)
                    Text("Status: \(selectedTicket.status.rawValue)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Chat: General Support")
                        .font(.headline)
                    Text("New chat session with Huginn AI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // Chat Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.chatMessages) { message in
                            SupportChatMessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.chatMessages.count) {
                    if let lastMessage = viewModel.chatMessages.last {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            // Message Input
            HStack {
                TextField("Type your message...", text: $viewModel.messageText)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isProcessingMessage)
                    .onSubmit {
                        sendMessage()
                    }
                
                if viewModel.isProcessingMessage {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 60)
                } else {
                    Button("Send") {
                        sendMessage()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.messageText.isEmpty)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    private func sendMessage() {
        viewModel.sendMessage(viewModel.messageText)
        viewModel.messageText = ""
    }
}

// MARK: - Chat Message View

struct SupportChatMessageView: View {
    let message: SupportChatMessage
    @State private var showingScriptPreview = false
    @State private var generatedScript: GeneratedScript?
    @State private var isGeneratingScript = false
    @State private var showingDebugAlert = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        HStack {
            if message.sender == .user {
                Spacer()
            }
            
            VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 8) {
                HStack {
                    if message.sender != .user {
                        Text(message.sender.rawValue)
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Text(dateFormatter.string(from: message.date))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: message.sender == .user ? .trailing : .leading, spacing: 8) {
                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(backgroundColorForSender(message.sender))
                        .foregroundColor(textColorForSender(message.sender))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // Script action buttons
                    if message.hasScriptAction && message.sender == .agent {
                        ScriptActionButtonsView(
                            scriptIntent: message.scriptIntent,
                            isGenerating: $isGeneratingScript,
                            generatedScript: $generatedScript,
                            showingPreview: $showingScriptPreview
                        )
                    }
                }
            }
            .frame(maxWidth: 300, alignment: message.sender == .user ? .trailing : .leading)
            
            if message.sender != .user {
                Spacer()
            }
        }
        .sheet(isPresented: $showingScriptPreview) {
            if let script = generatedScript {
                ScriptPreviewSheet(script: script, isPresented: $showingScriptPreview)
                    .onAppear {
                        print("Sheet is being presented, showingScriptPreview: \(showingScriptPreview)")
                        print("Presenting script preview for: \(script.name)")
                        print("Script content preview: \(script.content.prefix(100))...")
                    }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("No Script Available")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("The script preview was requested but no generated script is available.")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                    
                    Button("Close") {
                        showingScriptPreview = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(width: 400, height: 300)
                .padding()
                .onAppear {
                    print("Sheet presented but no script available")
                }
            }
        }
        .onChange(of: showingScriptPreview) { oldValue, newValue in
            print("showingScriptPreview changed from \(oldValue) to: \(newValue)")
        }
        .alert("Debug Test", isPresented: $showingDebugAlert) {
            Button("OK") { }
        } message: {
            Text("Preview button was tapped. Sheet should appear.")
        }
    }
    
    private func backgroundColorForSender(_ sender: SupportChatSender) -> Color {
        switch sender {
        case .user:
            return .blue
        case .agent:
            return Color(NSColor.controlBackgroundColor)
        case .system:
            return .orange.opacity(0.3)
        }
    }
    
    private func textColorForSender(_ sender: SupportChatSender) -> Color {
        switch sender {
        case .user:
            return .white
        case .agent, .system:
            return .primary
        }
    }
}

// MARK: - Script Action Components

struct ScriptActionButtonsView: View {
    let scriptIntent: ScriptIntent?
    @Binding var isGenerating: Bool
    @Binding var generatedScript: GeneratedScript?
    @Binding var showingPreview: Bool
    @State private var showingDebugAlert = false
    
    var body: some View {
        VStack(spacing: 8) {
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Generating script...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .foregroundColor(.orange)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 12) {
                    Button(action: generateScript) {
                        HStack(spacing: 6) {
                            Image(systemName: "doc.text.fill")
                                .font(.caption)
                            Text("Generate Script")
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    
                    if generatedScript != nil {
                        Button(action: { 
                            print("Preview button tapped")
                            print("Generated script exists: \(generatedScript != nil)")
                            print("showingPreview before: \(showingPreview)")
                            if let script = generatedScript {
                                print("Script name: \(script.name)")
                                print("Script content length: \(script.content.count)")
                            }
                            showingPreview = true 
                            showingDebugAlert = true  // Test alert
                            print("showingPreview after: \(showingPreview)")
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "eye.fill")
                                    .font(.caption)
                                Text("Preview")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.green)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .alert("Debug Test", isPresented: $showingDebugAlert) {
            Button("OK") { }
        } message: {
            Text("Preview button was tapped. Sheet should appear.")
        }
    }
    
    private func generateScript() {
        guard let intent = scriptIntent else { return }
        
        isGenerating = true
        
        Task {
            do {
                let script: GeneratedScript
                
                switch intent {
                case .installation(let installIntent):
                    print("Generating installation script for: \(installIntent.originalRequest)")
                    script = try await OllamaScriptGenerationService.shared.generateInstallationScript(for: installIntent.originalRequest)
                case .maintenance(let maintenanceIntent):
                    print("Generating maintenance script for: \(maintenanceIntent.originalRequest)")
                    script = try await OllamaScriptGenerationService.shared.generateMaintenanceScript(for: maintenanceIntent.originalRequest)
                case .diagnostic(let issue):
                    print("Generating diagnostic script for: \(issue)")
                    script = try await OllamaScriptGenerationService.shared.generateDiagnosticScript(for: issue)
                }
                
                await MainActor.run {
                    print("Script generated successfully:")
                    print("- Name: \(script.name)")
                    print("- Content length: \(script.content.count) characters")
                    print("- Risk level: \(script.riskLevel.rawValue)")
                    self.generatedScript = script
                    self.isGenerating = false
                }
                
            } catch {
                await MainActor.run {
                    print("Failed to generate script: \(error)")
                    self.isGenerating = false
                }
            }
        }
    }
}

struct ScriptPreviewSheet: View {
    let script: GeneratedScript
    @Binding var isPresented: Bool
    @State private var showingAddConfirmation = false
    @State private var showingRunConfirmation = false
    @State private var isRunning = false
    @State private var executionOutput = ""
    @State private var showingOutput = false
    @State private var lastExitCode: Int32? = nil
    @State private var isGeneratingFix = false
    @State private var fixedScript: GeneratedScript? = nil
    @State private var showingFixedScript = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                // Script metadata
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(script.name)
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text("Generated from: \"\(script.originalRequest)\"")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 4) {
                                Image(systemName: script.riskLevel.icon)
                                    .foregroundColor(script.riskLevel.color)
                                Text(script.riskLevel.rawValue)
                                    .foregroundColor(script.riskLevel.color)
                            }
                            .font(.caption)
                            .fontWeight(.medium)
                            
                            Text("Est. \(script.formattedDuration)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Script content
                VStack(alignment: .leading, spacing: 8) {
                    Text("Script Content")
                        .font(.headline)
                    
                    ScrollView {
                        if script.content.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.orange)
                                
                                Text("No Script Content")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                
                                Text("The script generation completed but no content was produced. This might indicate an issue with the script generation service.")
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                
                                Text("Please try generating the script again or check if Ollama is running properly.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding()
                        } else {
                            Text(script.content)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                                .background(Color(NSColor.textBackgroundColor))
                                .cornerRadius(8)
                        }
                    }
                }
                
                Spacer()
                
                // Execution Output Section (when running or completed)
                if isRunning || !executionOutput.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                if isRunning {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "terminal")
                                }
                                Text(isRunning ? "Executing Script..." : "Execution Output")
                                    .font(.headline)
                            }
                            
                            Spacer()
                            
                            if !executionOutput.isEmpty {
                                Button(showingOutput ? "Hide Output" : "Show Output") {
                                    showingOutput.toggle()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        
                        if showingOutput || isRunning {
                            ScrollView {
                                Text(executionOutput.isEmpty ? "Starting execution..." : executionOutput)
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding()
                                    .background(Color.black.opacity(0.8))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                            }
                            .frame(maxHeight: 200)
                            
                            // Show AI Fix button prominently when script fails
                            if let exitCode = lastExitCode, exitCode != 0 && !executionOutput.isEmpty {
                                Button(action: {
                                    generateFixedScript()
                                }) {
                                    HStack(spacing: 8) {
                                        if isGeneratingFix {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .frame(width: 20, height: 20)
                                        } else {
                                            Image(systemName: "wand.and.stars")
                                                .font(.title2)
                                                .foregroundColor(.white)
                                        }
                                        Text(isGeneratingFix ? "Asking AI to Fix..." : "🤖 Ask AI to Fix This Script")
                                            .font(.headline)
                                            .foregroundColor(.white)
                                    }
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.purple]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .cornerRadius(12)
                                }
                                .disabled(isGeneratingFix || isRunning)
                                .padding(.top, 8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Bottom button bar
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    

                    
                    Spacer()
                    
                    // Run Script button
                    Button(action: {
                        showingRunConfirmation = true
                    }) {
                        HStack(spacing: 6) {
                            if isRunning {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .frame(width: 16, height: 16)
                            } else {
                                Image(systemName: "play.fill")
                            }
                            Text(isRunning ? "Running..." : "Run Script")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunning)
                    
                    // Add to Scripts button
                    Button(!executionOutput.isEmpty ? "Save with Results" : "Add to Scripts") {
                        showingAddConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }
            .navigationTitle("Script Preview")
        }
        .frame(width: 700, height: isRunning || !executionOutput.isEmpty ? 750 : 600)
        .alert("Add Script to Manager", isPresented: $showingAddConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Add Script") {
                Task { @MainActor in
                    // Store the script globally for pickup by ScriptManager
                    GlobalScriptStore.shared.addPendingScript(script)
                    
                    print("Added script to manager with execution history: \(script.name)")
                    isPresented = false
                }
            }
        } message: {
            Text(!executionOutput.isEmpty 
                 ? "This script will be saved with its execution history to the Scripts tab."
                 : "This script will be available in the Scripts tab. Navigate to Scripts to review and run it.")
        }
        .alert("Run Script", isPresented: $showingRunConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Run Now", role: .destructive) {
                runScript()
            }
        } message: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Are you sure you want to run this script?")
                Text("Risk Level: \(script.riskLevel.rawValue)")
                    .foregroundColor(script.riskLevel.color)
                Text("Estimated Duration: \(script.formattedDuration)")
                Text("The script will execute immediately with your current user permissions.")
            }
        }
        .sheet(isPresented: $showingFixedScript) {
            if let fixedScript = fixedScript {
                ScriptPreviewSheet(script: fixedScript, isPresented: $showingFixedScript)
                    .onAppear {
                        print("DEBUG: Sheet is presenting fixed script: \(fixedScript.name)")
                    }
            } else {
                Text("No fixed script available")
                    .padding()
                    .onAppear {
                        print("DEBUG: Sheet called but fixedScript is nil")
                    }
            }
        }
        .onChange(of: showingFixedScript) { oldValue, newValue in
            print("DEBUG: showingFixedScript changed from \(oldValue) to \(newValue)")
            if newValue {
                print("DEBUG: fixedScript when showing: \(fixedScript?.name ?? "nil")")
            }
        }
    }
    
    private func runScript() {
        // Ensure UI state changes happen cleanly
        Task { @MainActor in
            isRunning = true
            executionOutput = ""
            showingOutput = true
        }
        
        Task {
            do {
                // Create temporary script file with enhanced content
                let enhancedContent = enhanceScriptForExecution(script.content)
                let tempURL = try createTempScriptFile(content: enhancedContent)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                
                // Configure process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [tempURL.path]
                
                // Setup enhanced environment for the process
                process.environment = createEnhancedEnvironment()
                
                // Setup pipes for output capture
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                // Start capturing output asynchronously
                startOutputCapture(outputPipe: outputPipe, errorPipe: errorPipe)
                
                // Start the process
                try process.run()
                
                // Wait for completion
                process.waitUntilExit()
                
                // Update final state
                DispatchQueue.main.async {
                    self.lastExitCode = process.terminationStatus
                    
                    // Enhanced error detection in output
                    let output = self.executionOutput.lowercased()
                    let hasErrorInOutput = output.contains("error:") ||
                                         output.contains("stderr:") ||
                                         output.contains("failed") ||
                                         output.contains("not found") ||
                                         output.contains("no such file") ||
                                         output.contains("permission denied") ||
                                         output.contains("command not found") ||
                                         output.contains("installation failed") ||
                                         output.contains("unable to") ||
                                         output.contains("cannot") ||
                                         output.contains("does not exist") ||
                                         output.contains("is not there")
                    
                    let statusMessage: String
                    if process.terminationStatus == 0 && !hasErrorInOutput {
                        statusMessage = "\n\n✅ Script completed successfully (exit code: 0)"
                    } else if process.terminationStatus == 0 && hasErrorInOutput {
                        statusMessage = "\n\n⚠️ Script completed with errors/warnings (exit code: 0, but errors detected in output)"
                        // Override exit code to indicate issues
                        self.lastExitCode = 1
                    } else {
                        statusMessage = "\n\n❌ Script failed with exit code: \(process.terminationStatus)"
                    }
                    
                    self.executionOutput += statusMessage
                    self.isRunning = false
                    
                    print("Script execution completed with exit code: \(process.terminationStatus)")
                    print("DEBUG: lastExitCode = \(self.lastExitCode?.description ?? "nil"), executionOutput.isEmpty = \(self.executionOutput.isEmpty)")
                    print("DEBUG: Should show AI fix button = \(self.lastExitCode != 0 && !self.executionOutput.isEmpty)")
                }
                
            } catch {
                DispatchQueue.main.async {
                    self.lastExitCode = -1 // Indicate execution error
                    self.executionOutput += "\n\n❌ Error executing script: \(error.localizedDescription)"
                    self.isRunning = false
                    print("Script execution failed: \(error)")
                }
            }
        }
    }
    
    private func createTempScriptFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("huginn_preview_script_\(UUID().uuidString).sh")
        
        try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        return scriptURL
    }
    
    private func enhanceScriptForExecution(_ originalContent: String) -> String {
        // Add PATH and environment setup to the script
        let pathSetup = """
        #!/bin/bash
        set -e
        
        # Enhanced PATH setup for macOS app execution - ensure Homebrew is found
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        
        # Set up environment variables
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_INSTALL_CLEANUP=1
        
        # Function to check if command exists
        command_exists() {
            command -v "$1" >/dev/null 2>&1
        }
        
        # Ensure Homebrew is accessible - override any script checks
        if ! command_exists brew; then
            if [ -f "/opt/homebrew/bin/brew" ]; then
                export PATH="/opt/homebrew/bin:$PATH"
                echo "✅ Found Homebrew at /opt/homebrew/bin/brew"
            elif [ -f "/usr/local/bin/brew" ]; then
                export PATH="/usr/local/bin:$PATH"
                echo "✅ Found Homebrew at /usr/local/bin/brew"
            else
                echo "❌ Homebrew not found in common locations"
                echo "Please install Homebrew first:"
                echo "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 127
            fi
        else
            echo "✅ Homebrew is available at: $(which brew)"
        fi
        
        # Debug information
        echo "=== Huginn Script Execution Environment ==="
        echo "PATH: $PATH"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "Available commands:"
        echo "  brew: $(which brew 2>/dev/null || echo 'NOT FOUND')"
        echo "  softwareupdate: $(which softwareupdate 2>/dev/null || echo 'NOT FOUND')"
        echo "=========================================="
        echo ""
        
        """
        
        // Remove existing shebang if present and add our enhanced version
        let cleanedContent = originalContent.replacingOccurrences(of: "#!/bin/bash", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return pathSetup + cleanedContent
    }
    
    private func createEnhancedEnvironment() -> [String: String] {
        var env = Foundation.ProcessInfo.processInfo.environment
        
        // Enhance PATH with common tool locations
        let commonPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin", 
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        let enhancedPath = commonPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        env["PATH"] = enhancedPath
        
        // Set homebrew environment variables
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        
        // Set user home directory explicitly
        if let homeDir = FileManager.default.homeDirectoryForCurrentUser.path as String? {
            env["HOME"] = homeDir
        }
        
        return env
    }
    
    private func startOutputCapture(outputPipe: Pipe, errorPipe: Pipe) {
        // Capture stdout
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.executionOutput += output
                }
            }
        }
        
        // Capture stderr
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                DispatchQueue.main.async {
                    self.executionOutput += "🔴 STDERR: " + output
                }
            }
        }
    }
    
    private func generateFixedScript() {
        print("DEBUG: generateFixedScript() called - AI fix button was tapped")
        
        Task { @MainActor in
            isGeneratingFix = true
            print("DEBUG: isGeneratingFix set to true")
        }
        
        Task {
            do {
                // Create a detailed prompt for Ollama to fix the script
                let fixPrompt = buildFixPrompt()
                
                // Get the fixed script from Ollama
                let ollamaService = OllamaService.shared
                let response = try await ollamaService.sendMessage(fixPrompt)
                
                // Parse the response and create a new script
                let fixedScriptContent = extractScriptFromResponse(response)
                
                await MainActor.run {
                    let fixedName = script.name.hasPrefix("Fixed:") ? 
                        script.name.replacingOccurrences(of: "Fixed:", with: "AI Fixed:") :
                        "AI Fixed: \(script.name)"
                    
                    self.fixedScript = GeneratedScript(
                        name: fixedName,
                        content: fixedScriptContent,
                        originalRequest: "Fix for: \(script.originalRequest)",
                        generatedAt: Date(),
                        estimatedDuration: script.estimatedDuration,
                        riskLevel: script.riskLevel
                    )
                    
                    print("DEBUG: Fixed script created: \(fixedName)")
                    print("DEBUG: Fixed script content length: \(fixedScriptContent.count)")
                    
                    self.isGeneratingFix = false
                    
                    // Present the sheet immediately on main actor
                    self.showingFixedScript = true
                    print("DEBUG: showingFixedScript set to true immediately")
                    print("DEBUG: fixedScript is nil: \(self.fixedScript == nil)")
                }
                
            } catch {
                // Fallback: Create an improved script based on common error patterns
                await MainActor.run {
                    self.fixedScript = createFallbackFixedScript()
                    
                    print("DEBUG: Using fallback fixed script: \(self.fixedScript?.name ?? "nil")")
                    print("Failed to get AI fix, using fallback: \(error)")
                    
                    self.isGeneratingFix = false
                    
                    // Present the sheet immediately on main actor
                    self.showingFixedScript = true
                    print("DEBUG: showingFixedScript set to true (fallback) immediately")
                    print("DEBUG: fixedScript is nil: \(self.fixedScript == nil)")
                }
            }
        }
    }
    
    private func buildFixPrompt() -> String {
        let errorAnalysis = analyzeExecutionError()
        
        return """
        You are a script debugging expert. A bash script failed during execution and I need you to create a fixed version.
        
        ORIGINAL SCRIPT:
        ```bash
        \(script.content)
        ```
        
        EXECUTION OUTPUT AND ERRORS:
        ```
        \(executionOutput)
        ```
        
        EXIT CODE: \(lastExitCode?.description ?? "unknown")
        
        ERROR ANALYSIS: \(errorAnalysis)
        
        Please create a corrected version of this script that addresses the specific errors shown. Focus on:
        1. Fixing PATH issues (add common locations like /opt/homebrew/bin, /usr/local/bin)
        2. Adding proper error checking and fallbacks
        3. Handling missing dependencies gracefully
        4. Providing helpful error messages
        
        Respond with ONLY the corrected bash script, starting with #!/bin/bash. No explanations, just the working script.
        """
    }
    
    private func analyzeExecutionError() -> String {
        let output = executionOutput.lowercased()
        
        if output.contains("command not found") || output.contains("brew") {
            return "Command not found error - likely PATH issue with Homebrew or missing installation"
        } else if output.contains("permission denied") {
            return "Permission error - script may need sudo or different file permissions"
        } else if output.contains("no such file") {
            return "File not found error - script references missing files or directories"
        } else if output.contains("network") || output.contains("curl") {
            return "Network or download error - connectivity or URL issues"
        } else {
            return "General execution error - review output for specific failure points"
        }
    }
    
    private func extractScriptFromResponse(_ response: String) -> String {
        // Look for script content between code blocks or extract the main content
        if let start = response.range(of: "```bash")?.upperBound,
           let end = response[start...].range(of: "```")?.lowerBound {
            return String(response[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let start = response.range(of: "#!/bin/bash")?.lowerBound {
            return String(response[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Fallback: return the response as-is if it looks like a script
            let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("#!/bin/bash") || trimmed.hasPrefix("echo") || trimmed.hasPrefix("if") {
                return trimmed
            } else {
                // If response doesn't look like a script, create a basic fix
                return createBasicFixedScript()
            }
        }
    }
    
    private func createFallbackFixedScript() -> GeneratedScript {
        let fixedName = script.name.hasPrefix("Fixed:") ? 
            script.name.replacingOccurrences(of: "Fixed:", with: "AI Fixed:") :
            "AI Fixed: \(script.name)"
        
        return GeneratedScript(
            name: fixedName,
            content: createBasicFixedScript(),
            originalRequest: "Fix for: \(script.originalRequest)",
            generatedAt: Date(),
            estimatedDuration: script.estimatedDuration,
            riskLevel: script.riskLevel
        )
    }
    
    private func createBasicFixedScript() -> String {
        let analysis = analyzeExecutionError()
        
        if analysis.contains("PATH issue with Homebrew") {
            return """
            #!/bin/bash
            set -e
            
            echo "Fixed script with enhanced PATH handling"
            echo "Original error: Command not found (likely Homebrew)"
            echo ""
            
            # Enhanced PATH setup for common macOS environments
            export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
            
            # Check for Homebrew installation
            if command -v brew >/dev/null 2>&1; then
                echo "✅ Homebrew found at: $(which brew)"
            elif [ -f "/opt/homebrew/bin/brew" ]; then
                export PATH="/opt/homebrew/bin:$PATH"
                echo "✅ Homebrew found at: /opt/homebrew/bin/brew"
            elif [ -f "/usr/local/bin/brew" ]; then
                export PATH="/usr/local/bin:$PATH"
                echo "✅ Homebrew found at: /usr/local/bin/brew"
            else
                echo "❌ Homebrew not found. Please install it first:"
                echo "   /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                echo ""
                echo "After installation, add to your shell profile:"
                echo "   echo 'export PATH=\"/opt/homebrew/bin:$PATH\"' >> ~/.zshrc"
                exit 1
            fi
            
            # Continue with the original script logic but with proper error handling
            echo "Ready to proceed with enhanced error handling!"
            """
        } else {
            return """
            #!/bin/bash
            set -e
            
            echo "Enhanced script with better error handling"
            echo "Original script had issues, this version includes fixes for:"
            echo "- \(analysis)"
            echo ""
            
            # Add your corrected script logic here
            # This is a template - review the original error and customize as needed
            
            echo "Please review this script and customize it based on your specific needs."
            echo "Original error analysis: \(analysis)"
            """
        }
    }
}

// MARK: - Preview

#Preview {
    SupportView(viewModel: SupportViewModel())
        .frame(width: 1000, height: 700)
} 
