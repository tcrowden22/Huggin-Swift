import SwiftUI
import Foundation

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
    
    public init(
        title: String,
        status: SupportTicketStatus = .open,
        date: Date = Date(),
        systemInfo: SupportSystemInfo,
        updatesNeeded: [SupportUpdateInfo] = [],
        description: String = "",
        chatMessages: [SupportChatMessage] = [],
        lastActivity: Date = Date()
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
        
        // Load tickets from UserDefaults (simple persistence)
        if let data = UserDefaults.standard.data(forKey: "SupportTickets"),
           let savedTickets = try? JSONDecoder().decode([SupportTicketEnhanced].self, from: data) {
            tickets = savedTickets.sorted { $0.lastActivity > $1.lastActivity }
            print("Loaded \(tickets.count) tickets from storage")
        } else {
            tickets = []
            print("No saved tickets found, starting fresh")
        }
        
        isLoading = false
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
        NavigationSplitView {
            SupportSidebarView(viewModel: viewModel)
        } detail: {
            SupportDetailView(viewModel: viewModel)
        }
        .navigationTitle("Support")
        .onAppear {
            // Refresh alerts when returning to the support tab
            // This ensures current system status is shown
            viewModel.refreshSystemAlerts()
        }
    }
}

// MARK: - Sidebar View

struct SupportSidebarView: View {
    @ObservedObject var viewModel: SupportViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Ticket History Section
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Support Tickets")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button("New Chat") {
                            viewModel.startNewChat()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal)
                .padding(.top)
                
                SupportTicketHistoryView(viewModel: viewModel)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Selected Ticket Details Section
            if let selectedTicket = viewModel.selectedTicket {
                SupportTicketDetailsView(ticket: selectedTicket, viewModel: viewModel)
            }
            
            Divider()
                .padding(.vertical, 8)
            
            // Alerts Section
            VStack(alignment: .leading, spacing: 8) {
                Text("System Alerts")
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding(.horizontal)
                
                SupportAlertsView(viewModel: viewModel)
            }
        }
        .frame(minWidth: 350)
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
                    let statusMessage = process.terminationStatus == 0 
                        ? "\n\n✅ Script completed successfully (exit code: 0)"
                        : "\n\n❌ Script failed with exit code: \(process.terminationStatus)"
                    
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
        
        # Enhanced PATH setup for macOS app execution
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        
        # Set up environment variables
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_INSTALL_CLEANUP=1
        
        # Function to check if command exists
        command_exists() {
            command -v "$1" >/dev/null 2>&1
        }
        
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
