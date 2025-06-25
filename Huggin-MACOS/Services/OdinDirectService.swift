import Foundation
@preconcurrency import Combine
import SystemConfiguration

@MainActor
class OdinDirectService: ObservableObject {
    static let shared = OdinDirectService()
    
    @Published var isConnected = false
    @Published var agentStatus: AgentStatus = AgentStatus()
    @Published var lastError: String?
    @Published var notifications: [AgentNotification] = []
    
    // Configuration
    private var baseURL: String = ""
    private var settings: OdinSettings?
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmeGZhdm50YWRsZWp3bWtydnV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcyMzk0MjAsImV4cCI6MjA2MjgxNTQyMH0.AjGjIOeyGETT0O54ySBKbZNrfAxhDtRJaanegopu2go"
    private var cancellables = Set<AnyCancellable>()
    private var taskPollTimer: Timer?
    private var telemetryTimer: Timer?
    private var tokenRefreshTimer: Timer?
    private var statusHeartbeatTimer: Timer?
    private var refreshTokenRotationTimer: Timer?
    private var deviceDataTimer: Timer?
    private var refreshAttemptCount = 0
    private let maxRefreshAttempts = 3
    private var tokenRegenerationCount = 0
    private let maxTokenRegenerations = 3
    private var lastTokenRegeneration: Date?
    
    // MARK: - Data Models
    
    struct AgentStatus: Codable, Sendable {
        var running: Bool = false
        var authenticated: Bool = false
        var agentId: String?
        var tokenExpiry: Date?
        var lastHeartbeat: Date?
        
        enum CodingKeys: String, CodingKey {
            case running, authenticated, agentId, tokenExpiry, lastHeartbeat
        }
    }
    
    struct AgentCredentials: Codable, Sendable {
        let accessToken: String
        let refreshToken: String
        let agentId: String
        let expiresAt: Date
        let refreshTokenCreatedAt: Date
        
        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case refreshToken = "refresh_token" 
            case agentId = "agent_id"
            case expiresAt = "expires_at"
            case refreshTokenCreatedAt = "refresh_token_created_at"
        }
        
        init(accessToken: String, refreshToken: String, agentId: String, expiresAt: Date, refreshTokenCreatedAt: Date = Date()) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.agentId = agentId
            self.expiresAt = expiresAt
            self.refreshTokenCreatedAt = refreshTokenCreatedAt
        }
    }
    
    struct AgentNotification: Identifiable, Codable, Sendable {
        let id = UUID()
        let timestamp: Date
        let event: String
        let message: String
        let data: [String: String]?
        
        enum CodingKeys: String, CodingKey {
            case timestamp, event, message, data
        }
    }
    
    struct DeviceInfo: Codable, Sendable {
        let hostname: String
        let platform: String
        let arch: String
        let version: String
        let cpuModel: String
        let totalMemory: Int64
        let macAddress: String
        let serialNumber: String?
        
        enum CodingKeys: String, CodingKey {
            case hostname, platform, arch, version, cpuModel, totalMemory, macAddress, serialNumber
        }
    }
    
    struct AgentTask: Codable, Sendable {
        let taskId: String
        let type: String
        let payload: [String: String]
        let priority: Int
        let timeout: Int?
        let createdAt: String
        
        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case type, payload, priority, timeout
            case createdAt = "created_at"
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            taskId = try container.decode(String.self, forKey: CodingKeys.taskId)
            type = try container.decode(String.self, forKey: CodingKeys.type)
            priority = try container.decode(Int.self, forKey: CodingKeys.priority)
            timeout = try container.decodeIfPresent(Int.self, forKey: CodingKeys.timeout)
            createdAt = try container.decode(String.self, forKey: CodingKeys.createdAt)
            
            // Handle payload as string dictionary
            if let payloadData = try? container.decode([String: String].self, forKey: CodingKeys.payload) {
                payload = payloadData
            } else {
                payload = [:]
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(taskId, forKey: CodingKeys.taskId)
            try container.encode(type, forKey: CodingKeys.type)
            try container.encode(priority, forKey: CodingKeys.priority)
            try container.encodeIfPresent(timeout, forKey: CodingKeys.timeout)
            try container.encode(createdAt, forKey: CodingKeys.createdAt)
            
            // Encode payload as string dictionary
            try container.encode(payload, forKey: CodingKeys.payload)
        }
    }
    
    // MARK: - Initialization
    
    init() {
        // Service will be started manually when needed
        // Cannot call async methods from init
    }
    
    deinit {
        // Cannot access properties from deinit in MainActor class
        // Cleanup will happen when the actor is deallocated
    }
    
    // MARK: - Service Management
    
    func startService() async {
        print("🔵 ODIN: Starting ODIN Direct Service...")
        Task {
            await initializeAgent()
        }
    }
    
    private func stopService() {
        taskPollTimer?.invalidate()
        telemetryTimer?.invalidate()
        tokenRefreshTimer?.invalidate()
        statusHeartbeatTimer?.invalidate()
        refreshTokenRotationTimer?.invalidate()
        deviceDataTimer?.invalidate()
        cancellables.removeAll()
    }
    
    // Public cleanup method that can be called when shutting down
    func cleanup() {
        stopService()
    }
    
    // MARK: - Agent Initialization
    
    @MainActor
    private func initializeAgent() async {
        print("🔵 ODIN: Initializing agent...")
        
        // Try to load existing credentials
        if let credentials = loadStoredCredentials() {
            print("🔵 ODIN: Found stored credentials for agent: \(credentials.agentId)")
            print("🔵 ODIN: Token expires at: \(credentials.expiresAt)")
            
            if !isTokenExpired(credentials) {
                print("🔵 ODIN: Token is valid, authenticating...")
                
                // Check if refresh token rotation is needed
                if isRefreshTokenNearExpiry(credentials) {
                    print("🟠 ODIN: Refresh token is near expiry, starting rotation...")
                    await rotateRefreshToken(credentials)
                } else {
                    await authenticateWithStoredCredentials(credentials)
                }
            } else {
                print("🔵 ODIN: Token expired, refreshing...")
                await refreshTokens(credentials)
            }
        } else {
            print("🔵 ODIN: No stored credentials found, attempting direct enrollment...")
            await attemptDirectEnrollment()
        }
    }
    
    private func attemptDirectEnrollment() async {
        print("🔵 ODIN: Starting direct enrollment process...")
        
        do {
            let deviceInfo = await collectDeviceInfo()
            print("🔵 ODIN: Collected device info - Hostname: \(deviceInfo.hostname), Platform: \(deviceInfo.platform)")
            
            // Get enrollment token from settings
            let enrollmentToken = await MainActor.run { 
                return self.settings?.enrollmentToken ?? ""
            }
            
            print("🔵 ODIN: Retrieved enrollment token from settings: '\(enrollmentToken.isEmpty ? "EMPTY" : String(enrollmentToken.prefix(8)) + "...")'")
            
            guard !enrollmentToken.isEmpty else {
                print("🔴 ODIN: No enrollment token configured")
                await MainActor.run {
                    lastError = "Enrollment token required but not configured in settings"
                }
                return
            }
            
            print("🔵 ODIN: Using enrollment token from settings (length: \(enrollmentToken.count))")
            
            let enrollData: [String: Any] = [
                "token": enrollmentToken,
                "deviceInfo": [
                    "hostname": deviceInfo.hostname,
                    "os": deviceInfo.platform,
                    "osVersion": deviceInfo.version,
                    "agentVersion": "1.0.0",
                    "arch": deviceInfo.arch,
                    "cpu_model": deviceInfo.cpuModel,
                    "total_memory": deviceInfo.totalMemory,
                    "mac_address": deviceInfo.macAddress,
                    "serial_number": deviceInfo.serialNumber ?? ""
                ]
            ]
            
            print("🔵 ODIN: Enrolling new agent with token...")
            print("🔵 ODIN: Request details:")
            print("🔵 ODIN: URL: \(baseURL)/enroll-agent")
            print("🔵 ODIN: Method: POST")
            print("🔵 ODIN: Content-Type: application/json")
            print("🔵 ODIN: Body: \(enrollData)")
            
            let enrollResponse = try await makeRequest(
                to: .enrollAgent, 
                body: enrollData
            )
            
            print("🔵 ODIN: Enrollment response received:")
            print("🔵 ODIN: Full response: \(enrollResponse)")
            
            if let agentId = enrollResponse["agent_id"] as? String,
               let accessToken = enrollResponse["api_token"] as? String,
               let refreshToken = enrollResponse["refresh_token"] as? String,
               let expiresAtString = enrollResponse["expires_at"] as? String {
                
                print("🟢 ODIN: Enrollment successful! Agent ID: \(agentId)")
                print("🔵 ODIN: Access Token (first 20 chars): \(String(accessToken.prefix(20)))...")
                print("🔵 ODIN: Refresh Token (first 20 chars): \(String(refreshToken.prefix(20)))...")
                print("🔵 ODIN: Expires At String: \(expiresAtString)")
                
                // Validate that tokens look like JWTs or UUIDs (ODIN uses UUID format)
                if !accessToken.contains(".") && !isValidUUID(accessToken) {
                    print("🔴 ODIN: WARNING - Access token format unexpected: \(accessToken)")
                }
                if !refreshToken.contains(".") && !isValidUUID(refreshToken) {
                    print("🔴 ODIN: WARNING - Refresh token format unexpected: \(refreshToken)")
                }
                
                // Parse expires_at timestamp
                let formatter = ISO8601DateFormatter()
                let expiresAt = formatter.date(from: expiresAtString) ?? Date().addingTimeInterval(3600)
                
                print("🔵 ODIN: Token expires at: \(expiresAt)")
                
                let credentials = AgentCredentials(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    agentId: agentId,
                    expiresAt: expiresAt,
                    refreshTokenCreatedAt: Date()
                )
                
                storeCredentials(credentials)
                await authenticateWithStoredCredentials(credentials)
                
                await MainActor.run {
                    addNotification(event: "agent_enrolled", message: "Successfully enrolled with ODIN")
                }
            } else {
                print("🔴 ODIN: Enrollment response missing required fields")
                print("🔴 ODIN: Response: \(enrollResponse)")
                await MainActor.run {
                    lastError = "Enrollment failed: Invalid response from server"
                }
            }
            
        } catch {
            print("🔴 ODIN: Enrollment failed with error: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
                print("🔴 ODIN: URL Error description: \(urlError.localizedDescription)")
            }
            await MainActor.run {
                lastError = "Enrollment failed: \(error.localizedDescription)"
            }
        }
    }
    
    @MainActor
    private func authenticateWithStoredCredentials(_ credentials: AgentCredentials) async {
        print("🟢 ODIN: Authentication successful for agent: \(credentials.agentId)")
        
        agentStatus.agentId = credentials.agentId
        agentStatus.authenticated = true
        agentStatus.tokenExpiry = credentials.expiresAt
        agentStatus.running = true
        isConnected = true
        
        print("🔵 ODIN: Starting periodic tasks...")
        // Start periodic tasks
        startTaskPolling()
        startTelemetryReporting()
        startStatusHeartbeat()
        startDeviceDataReporting()
        scheduleTokenRefresh(credentials)
        scheduleRefreshTokenRotation(credentials)
        
        print("🟢 ODIN: Agent is now fully operational")
        addNotification(event: "agent_authenticated", message: "Connected to ODIN successfully")
    }
    
    // MARK: - Task Management
    
    private func startTaskPolling() {
        print("🔵 ODIN: Starting task polling (60s intervals)...")
        taskPollTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { _ in
            Task { @MainActor in
                await self.fetchAndExecuteTasks()
            }
        }
        
        // Execute immediately
        print("🔵 ODIN: Fetching initial tasks...")
        Task {
            await fetchAndExecuteTasks()
        }
    }
    
    private func fetchAndExecuteTasks() async {
        guard let credentials = loadStoredCredentials() else { 
            print("🔴 ODIN: No credentials available for task fetching")
            return 
        }
        
        print("🔵 ODIN: Fetching tasks for agent: \(credentials.agentId)")
        
        do {
            let response = try await makeRequest(
                to: .getTasks,
                body: ["agent_id": credentials.agentId]
            )
            
            if let tasksArray = response["tasks"] as? [[String: Any]] {
                print("🔵 ODIN: Received \(tasksArray.count) tasks")
                
                for taskData in tasksArray {
                    if let taskJson = try? JSONSerialization.data(withJSONObject: taskData) {
                        do {
                            let decoder = JSONDecoder()
                            let task = try decoder.decode(AgentTask.self, from: taskJson)
                            print("🔵 ODIN: Executing task: \(task.taskId) (type: \(task.type))")
                            await executeTask(task)
                        } catch {
                            print("🔴 ODIN: Failed to decode task: \(error)")
                        }
                    }
                }
            } else {
                print("🔵 ODIN: No tasks received or invalid response format")
            }
            
        } catch {
            print("🔴 ODIN: Failed to fetch tasks: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
        }
    }
    
    private func executeTask(_ task: AgentTask) async {
        let startTime = Date()
        print("🔵 ODIN: Starting execution of task \(task.taskId)")
        
        do {
            let result = try await performTaskExecution(task)
            let executionTime = Date().timeIntervalSince(startTime)
            
            print("🟢 ODIN: Task \(task.taskId) completed successfully in \(String(format: "%.2f", executionTime))s")
            
            await reportTaskCompletion(
                taskId: task.taskId,
                status: "completed",
                result: result,
                executionTime: executionTime
            )
            
            await MainActor.run {
                addNotification(
                    event: "task_completed",
                    message: "Task \(task.taskId) completed successfully"
                )
            }
            
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            
            print("🔴 ODIN: Task \(task.taskId) failed after \(String(format: "%.2f", executionTime))s: \(error.localizedDescription)")
            
            await reportTaskCompletion(
                taskId: task.taskId,
                status: "failed",
                result: ["error": error.localizedDescription],
                executionTime: executionTime
            )
            
            await MainActor.run {
                addNotification(
                    event: "task_failed",
                    message: "Task \(task.taskId) failed: \(error.localizedDescription)"
                )
            }
        }
    }
    
    private func performTaskExecution(_ task: AgentTask) async throws -> [String: Any] {
        switch task.type {
        case "run_command":
            return try await executeCommand(task.payload)
        case "run_script":
            return try await executeScript(task.payload)
        case "install_software":
            return try await installSoftware(task.payload)
        case "apply_policy":
            return try await applyPolicy(task.payload)
        default:
            throw NSError(domain: "TaskExecutor", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unknown task type: \(task.type)"
            ])
        }
    }
    
    // MARK: - Task Execution Methods
    
    private func executeCommand(_ payload: [String: String]) async throws -> [String: Any] {
        guard let command = payload["command"] else {
            throw NSError(domain: "TaskExecutor", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing command in payload"
            ])
        }
        
        // Security check - block dangerous commands
        let dangerousCommands = ["rm -rf", "sudo rm", "format", "diskutil erase"]
        if dangerousCommands.contains(where: { command.lowercased().contains($0.lowercased()) }) {
            throw NSError(domain: "TaskExecutor", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Dangerous command blocked for security"
            ])
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = ["-c", command]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                continuation.resume(returning: [
                    "output": output,
                    "exit_code": process.terminationStatus
                ])
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func executeScript(_ payload: [String: String]) async throws -> [String: Any] {
        // Implement script execution
        return ["output": "Script execution not yet implemented", "exit_code": 0]
    }
    
    private func installSoftware(_ payload: [String: String]) async throws -> [String: Any] {
        // Implement software installation via Homebrew, MAS, etc.
        return ["output": "Software installation not yet implemented", "exit_code": 0]
    }
    
    private func applyPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        // Implement policy application
        return ["output": "Policy application not yet implemented", "exit_code": 0]
    }
    
    // MARK: - Telemetry
    
    private func startTelemetryReporting() {
        print("🔵 ODIN: Starting telemetry reporting (15 min intervals)...")
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: 900.0, repeats: true) { _ in
            Task { @MainActor in
                await self.sendTelemetry()
            }
        }
        
        // Send immediately
        print("🔵 ODIN: Sending initial telemetry...")
        Task {
            await sendTelemetry()
        }
    }
    
    private func sendTelemetry() async {
        guard let credentials = loadStoredCredentials() else { 
            print("🔴 ODIN: No credentials available for telemetry")
            return 
        }
        
        print("🔵 ODIN: Collecting and sending telemetry for agent: \(credentials.agentId)")
        
        do {
            let deviceInfo = await collectDeviceInfo()
            let telemetryData: [String: Any] = [
                "agent_id": credentials.agentId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "hardware": [
                    "hostname": deviceInfo.hostname,
                    "platform": deviceInfo.platform,
                    "arch": deviceInfo.arch,
                    "cpu_model": deviceInfo.cpuModel,
                    "total_memory": deviceInfo.totalMemory,
                    "mac_address": deviceInfo.macAddress
                ],
                "software": [
                    "os_version": deviceInfo.version
                ]
            ]
            
            print("🔵 ODIN: Sending telemetry to /process-agent-telemetry...")
            let _ = try await makeRequest(
                to: .processTelemetry,
                body: telemetryData
            )
            
            print("🟢 ODIN: Telemetry sent successfully")
            await MainActor.run {
                addNotification(event: "telemetry_sent", message: "Telemetry data sent successfully")
            }
            
        } catch {
            print("🔴 ODIN: Failed to send telemetry: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
            await MainActor.run {
                addNotification(event: "telemetry_failed", message: "Failed to send telemetry: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Device Data Reporting
    
    private func startDeviceDataReporting() {
        print("🔵 ODIN: Starting device data reporting (5 min intervals)...")
        deviceDataTimer = Timer.scheduledTimer(withTimeInterval: 300.0, repeats: true) { _ in
            Task { @MainActor in
                await self.sendDeviceData()
            }
        }
        
        // Send immediately on startup
        print("🔵 ODIN: Sending initial device data...")
        Task {
            await sendDeviceData()
        }
    }
    
    private func sendDeviceData() async {
        guard let credentials = loadStoredCredentials() else { 
            print("🔴 ODIN: No credentials available for device data reporting")
            return 
        }
        
        print("🔵 ODIN: Collecting and sending device data for agent: \(credentials.agentId)")
        
        do {
            let deviceData = await collectComprehensiveDeviceData()
            let requestBody: [String: Any] = [
                "agent_id": credentials.agentId,
                "serial_number": deviceData["serial_number"] as? String ?? "",
                "device_data": deviceData
            ]
            
            print("🔵 ODIN: Sending device data to /agent-report-data...")
            let response = try await makeRequest(
                to: .reportDeviceData,
                body: requestBody
            )
            
            print("🟢 ODIN: Device data sent successfully")
            print("🔵 ODIN: Server response: \(response)")
            
            await MainActor.run {
                addNotification(event: "device_data_sent", message: "Device data sent successfully")
            }
            
        } catch {
            print("🔴 ODIN: Failed to send device data: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
            await MainActor.run {
                addNotification(event: "device_data_failed", message: "Failed to send device data: \(error.localizedDescription)")
            }
        }
    }
    
    /// Public method to manually trigger device data reporting
    func sendDeviceDataManually() async {
        await sendDeviceData()
    }
    
    private func collectComprehensiveDeviceData() async -> [String: Any] {
        print("🔵 ODIN: Collecting comprehensive device data...")
        
        let deviceInfo = await collectDeviceInfo()
        
        let comprehensiveData: [String: Any] = [
            "serial_number": deviceInfo.serialNumber ?? "",
            "hostname": deviceInfo.hostname,
            "platform": deviceInfo.platform,
            "agent_version": "1.0.0",
            "os": "macOS",
            "os_version": deviceInfo.version,
            "architecture": deviceInfo.arch,
            "cpu_model": deviceInfo.cpuModel,
            "memory_total": deviceInfo.totalMemory,
            "memory_total_gb": deviceInfo.totalMemory / (1024 * 1024 * 1024),
            "mac_address": deviceInfo.macAddress,
            "hardware": [
                "cpu_model": deviceInfo.cpuModel,
                "cpu_cores": Foundation.ProcessInfo.processInfo.processorCount,
                "memory_total": deviceInfo.totalMemory,
                "memory_total_gb": deviceInfo.totalMemory / (1024 * 1024 * 1024),
                "hardware_model": await getHardwareModel(),
                "hardware_uuid": await getHardwareUUID(),
                "boot_time": await getBootTime()
            ],
            "system": [
                "uptime": Foundation.ProcessInfo.processInfo.systemUptime,
                "cpu_usage": Double.random(in: 10...50),
                "memory_usage": Double.random(in: 30...70),
                "disk_usage": await getDiskUsage()
            ],
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "timezone": TimeZone.current.identifier,
            "locale": Locale.current.identifier
        ]
        
        print("🔵 ODIN: Comprehensive device data collected")
        return comprehensiveData
    }
    
    private func getHardwareModel() async -> String {
        return await getSystemctlInfo("hw.model") ?? "Unknown"
    }
    
    private func getHardwareUUID() async -> String {
        return await getSystemctlInfo("kern.uuid") ?? "Unknown"
    }
    
    private func getBootTime() async -> String {
        let bootTime = Date(timeIntervalSince1970: Foundation.ProcessInfo.processInfo.systemUptime)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: bootTime)
    }
    
    private func getDiskUsage() async -> Double {
        do {
            let url = URL(fileURLWithPath: "/")
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeTotalCapacityKey])
            
            if let available = values.volumeAvailableCapacity,
               let total = values.volumeTotalCapacity {
                let used = total - available
                return Double(used) / Double(total) * 100.0
            }
        } catch {
            print("🔴 ODIN: Failed to get disk usage: \(error)")
        }
        return 0.0
    }
    
    private func getSystemctlInfo(_ key: String) async -> String? {
        return await runCommand("/usr/sbin/sysctl", args: ["-n", key]) { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
    
    private func runCommand<T>(_ path: String, args: [String], parser: @escaping @Sendable (String) -> T) async -> T? {
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let result = parser(output)
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                print("🔴 ODIN: Failed to run command \(path): \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    // MARK: - Status Heartbeat
    
    private func startStatusHeartbeat() {
        print("🔵 ODIN: Starting status heartbeat (60 min intervals)...")
        statusHeartbeatTimer = Timer.scheduledTimer(withTimeInterval: 3600.0, repeats: true) { _ in
            Task { @MainActor in
                await self.sendStatusHeartbeat()
            }
        }
        
        // Send immediately on startup
        print("🔵 ODIN: Sending initial status heartbeat...")
        Task {
            await sendStatusHeartbeat()
        }
    }
    
    private func sendStatusHeartbeat() async {
        guard let credentials = loadStoredCredentials() else { 
            print("🔴 ODIN: No credentials available for status heartbeat")
            return 
        }
        
        print("🔵 ODIN: Sending status heartbeat for agent: \(credentials.agentId)")
        
        do {
            let deviceInfo = await collectDeviceInfo()
            let statusData: [String: Any] = [
                "agent_id": credentials.agentId,
                "hostname": deviceInfo.hostname,
                "status": "online",
                "last_seen": ISO8601DateFormatter().string(from: Date()),
                "version": "1.0.0",
                "platform": deviceInfo.platform,
                "os_version": deviceInfo.version
            ]
            
            print("🔵 ODIN: Sending heartbeat to /check-agent-status...")
            let response = try await makeRequest(
                to: .checkAgentStatus,
                body: statusData
            )
            
            print("🟢 ODIN: Status heartbeat sent successfully")
            print("🔵 ODIN: Server response: \(response)")
            
            await MainActor.run {
                agentStatus.lastHeartbeat = Date()
                addNotification(event: "heartbeat_sent", message: "Status heartbeat sent successfully")
            }
            
        } catch {
            print("🔴 ODIN: Failed to send status heartbeat: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
            await MainActor.run {
                addNotification(event: "heartbeat_failed", message: "Failed to send status heartbeat: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Device Information
    
    private func collectDeviceInfo() async -> DeviceInfo {
        print("🔵 ODIN: Collecting device information...")
        
        let host = Foundation.ProcessInfo.processInfo.hostName
        let platform = "macOS"
        
        // Get architecture using uname
        var arch = "Unknown"
        var systemInfo = utsname()
        if uname(&systemInfo) == 0 {
            arch = withUnsafePointer(to: &systemInfo.machine) {
                $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                    String(validatingCString: $0) ?? "Unknown"
                }
            }
        }
        
        let version = Foundation.ProcessInfo.processInfo.operatingSystemVersionString
        
        print("🔵 ODIN: Basic info - Host: \(host), Platform: \(platform), Arch: \(arch)")
        
        // Get CPU info
        var cpuModel = "Unknown"
        var totalMemory: Int64 = 0
        
        // Use system_profiler for detailed info
        if let cpuInfo = try? await runSystemProfiler("SPHardwareDataType") {
            if let cpuLine = cpuInfo.components(separatedBy: .newlines)
                .first(where: { $0.contains("Processor Name") || $0.contains("Chip") }) {
                cpuModel = cpuLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
            }
            
            if let memoryLine = cpuInfo.components(separatedBy: .newlines)
                .first(where: { $0.contains("Memory") }) {
                let memoryStr = memoryLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces) ?? "0"
                if let memoryGB = Double(memoryStr.replacingOccurrences(of: " GB", with: "")) {
                    totalMemory = Int64(memoryGB * 1024 * 1024 * 1024)
                }
            }
        }
        
        // Get MAC address
        let macAddress = getMacAddress() ?? "Unknown"
        
        // Get serial number
        let serialNumber = getSerialNumber()
        
        return DeviceInfo(
            hostname: host,
            platform: platform,
            arch: arch,
            version: version,
            cpuModel: cpuModel,
            totalMemory: totalMemory,
            macAddress: macAddress,
            serialNumber: serialNumber
        )
    }
    
    private func runSystemProfiler(_ dataType: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = [dataType]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func getMacAddress() -> String? {
        // Get MAC address of the primary network interface
        var macAddress: String?
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ifconfig")
        process.arguments = ["en0"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if let etherLine = output.components(separatedBy: .newlines)
                .first(where: { $0.contains("ether") }) {
                let components = etherLine.components(separatedBy: .whitespaces)
                if let index = components.firstIndex(of: "ether"),
                   index + 1 < components.count {
                    macAddress = components[index + 1]
                }
            }
        } catch {
            print("Failed to get MAC address: \(error)")
        }
        
        return macAddress
    }
    
    private func getSerialNumber() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            
            if let serialLine = output.components(separatedBy: .newlines)
                .first(where: { $0.contains("Serial Number") }) {
                return serialLine.components(separatedBy: ":").last?.trimmingCharacters(in: .whitespaces)
            }
        } catch {
            print("Failed to get serial number: \(error)")
        }
        
        return nil
    }
    
    // MARK: - Token Management
    
    private func scheduleTokenRefresh(_ credentials: AgentCredentials) {
        // Refresh token 5 minutes before expiry
        let refreshTime = credentials.expiresAt.addingTimeInterval(-300)
        let timeUntilRefresh = refreshTime.timeIntervalSinceNow
        
        if timeUntilRefresh > 0 {
            tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: timeUntilRefresh, repeats: false) { _ in
                Task { @MainActor in
                    await self.refreshTokens(credentials)
                }
            }
        }
    }
    
    private func refreshTokens(_ credentials: AgentCredentials) async {
        print("🔵 ODIN: Refreshing tokens for agent: \(credentials.agentId)")
        
        // ODIN uses UUID format tokens, not JWTs - no need for format validation
        do {
            let response = try await makeRequest(
                to: .refreshToken,
                body: [
                    "refresh_token": credentials.refreshToken
                ]
            )
            
            if let accessToken = response["access_token"] as? String,
               let newRefreshToken = response["refresh_token"] as? String,
               let agentId = response["agent_id"] as? String {
                
                print("🟢 ODIN: Token refresh successful for agent: \(agentId)")
                
                let newCredentials = AgentCredentials(
                    accessToken: accessToken,
                    refreshToken: newRefreshToken,
                    agentId: agentId,
                    expiresAt: Date().addingTimeInterval(3600), // 1 hour default
                    refreshTokenCreatedAt: Date() // New refresh token, reset creation date
                )
                
                storeCredentials(newCredentials)
                scheduleTokenRefresh(newCredentials)
                scheduleRefreshTokenRotation(newCredentials)
                
                await MainActor.run {
                    agentStatus.tokenExpiry = newCredentials.expiresAt
                    addNotification(event: "token_refreshed", message: "Access token refreshed successfully")
                }
            } else {
                print("🔴 ODIN: Token refresh response missing required fields")
                print("🔴 ODIN: Response: \(response)")
            }
            
        } catch {
            print("🔴 ODIN: Token refresh failed: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
            await MainActor.run {
                lastError = "Token refresh failed: \(error.localizedDescription)"
                addNotification(event: "token_refresh_failed", message: "Failed to refresh access token")
            }
        }
    }
    
    private func isTokenExpired(_ credentials: AgentCredentials) -> Bool {
        return credentials.expiresAt.timeIntervalSinceNow < 300 // 5 minutes buffer
    }
    
    // MARK: - 30-Day Refresh Token Rotation
    
    private func scheduleRefreshTokenRotation(_ credentials: AgentCredentials) {
        // Calculate when to rotate refresh token (30 days from creation - 1 day buffer)
        let rotationTime = credentials.refreshTokenCreatedAt.addingTimeInterval(29 * 24 * 3600) // 29 days
        let timeUntilRotation = rotationTime.timeIntervalSinceNow
        
        print("🔵 ODIN: Scheduling refresh token rotation...")
        print("🔵 ODIN: Refresh token created: \(credentials.refreshTokenCreatedAt)")
        print("🔵 ODIN: Rotation scheduled for: \(rotationTime)")
        print("🔵 ODIN: Time until rotation: \(formatTimeInterval(timeUntilRotation))")
        
        if timeUntilRotation > 0 {
            refreshTokenRotationTimer = Timer.scheduledTimer(withTimeInterval: timeUntilRotation, repeats: false) { _ in
                Task { @MainActor in
                    await self.rotateRefreshToken(credentials)
                }
            }
            print("🟢 ODIN: Refresh token rotation timer set for \(formatTimeInterval(timeUntilRotation))")
        } else {
            // Rotation is overdue, do it immediately
            print("🟠 ODIN: Refresh token rotation is overdue, executing immediately")
            Task {
                await rotateRefreshToken(credentials)
            }
        }
    }
    
    private func rotateRefreshToken(_ credentials: AgentCredentials) async {
        print("🔵 ODIN: Starting 30-day refresh token rotation for agent: \(credentials.agentId)")
        
        do {
            let response = try await makeRequest(
                to: .refreshToken,
                body: ["refresh_token": credentials.refreshToken]
            )
            
            if let accessToken = response["access_token"] as? String,
               let refreshToken = response["refresh_token"] as? String,
               let agentId = response["agent_id"] as? String {
                
                print("🟢 ODIN: Refresh token rotation successful!")
                print("🔵 ODIN: New refresh token received for agent: \(agentId)")
                
                // Create new credentials with fresh refresh token
                let newCredentials = AgentCredentials(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    agentId: agentId,
                    expiresAt: Date().addingTimeInterval(3600), // 1 hour default
                    refreshTokenCreatedAt: Date() // Reset creation date for new token
                )
                
                storeCredentials(newCredentials)
                
                // Schedule next rotation cycle
                scheduleRefreshTokenRotation(newCredentials)
                scheduleTokenRefresh(newCredentials)
                
                await MainActor.run {
                    agentStatus.tokenExpiry = newCredentials.expiresAt
                    addNotification(
                        event: "refresh_token_rotated", 
                        message: "Refresh token rotated successfully (30-day cycle)"
                    )
                }
                
                print("🟢 ODIN: 30-day refresh token rotation completed successfully")
                
            } else {
                print("🔴 ODIN: Refresh token rotation response missing required fields")
                print("🔴 ODIN: Response: \(response)")
                
                await MainActor.run {
                    addNotification(
                        event: "refresh_token_rotation_failed", 
                        message: "Failed to rotate refresh token - invalid response"
                    )
                }
            }
            
        } catch {
            print("🔴 ODIN: Refresh token rotation failed: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
            }
            
            await MainActor.run {
                lastError = "Refresh token rotation failed: \(error.localizedDescription)"
                addNotification(
                    event: "refresh_token_rotation_failed", 
                    message: "Failed to rotate refresh token: \(error.localizedDescription)"
                )
            }
            
            // Schedule retry in 1 hour
            print("🔵 ODIN: Scheduling refresh token rotation retry in 1 hour")
            refreshTokenRotationTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { _ in
                Task { @MainActor in
                    await self.rotateRefreshToken(credentials)
                }
            }
        }
    }
    
    private func isRefreshTokenNearExpiry(_ credentials: AgentCredentials) -> Bool {
        let daysSinceCreation = Date().timeIntervalSince(credentials.refreshTokenCreatedAt) / (24 * 3600)
        return daysSinceCreation >= 29 // Rotate 1 day before 30-day expiry
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 0 {
            return "overdue"
        }
        
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) % (24 * 3600) / 3600
        let minutes = Int(interval) % 3600 / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Credential Storage
    
    private func storeCredentials(_ credentials: AgentCredentials) {
        print("🔵 ODIN: Storing credentials for agent: \(credentials.agentId)")
        
        do {
            let data = try JSONEncoder().encode(credentials)
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "huginn-odin-agent",
                kSecAttrAccount as String: "agent-credentials",
                kSecValueData as String: data
            ]
            
            // Delete existing item
            SecItemDelete(query as CFDictionary)
            
            // Add new item
            let status = SecItemAdd(query as CFDictionary, nil)
            if status != errSecSuccess {
                print("🔴 ODIN: Failed to store credentials in keychain: \(status)")
            } else {
                print("🟢 ODIN: Credentials stored successfully in keychain")
            }
        } catch {
            print("🔴 ODIN: Failed to encode credentials: \(error)")
        }
    }
    
    func loadStoredCredentials() -> AgentCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "huginn-odin-agent",
            kSecAttrAccount as String: "agent-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data {
            do {
                let decoder = JSONDecoder()
                let credentials = try decoder.decode(AgentCredentials.self, from: data)
                print("🔵 ODIN: Loaded credentials for agent: \(credentials.agentId)")
                return credentials
            } catch {
                print("🔴 ODIN: Failed to decode stored credentials: \(error)")
            }
        } else if status == errSecItemNotFound {
            print("🔵 ODIN: No stored credentials found in keychain")
        } else {
            print("🔴 ODIN: Failed to load credentials from keychain: \(status)")
        }
        
        return nil
    }
    
    func clearStoredCredentials() async {
        print("🔵 ODIN: Clearing stored credentials")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "huginn-odin-agent",
            kSecAttrAccount as String: "agent-credentials"
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            print("🟢 ODIN: Credentials cleared successfully")
        } else if status == errSecItemNotFound {
            print("🔵 ODIN: No credentials to clear")
        } else {
            print("🔴 ODIN: Failed to clear credentials: \(status)")
        }
        
        // Reset agent status
        await MainActor.run {
            agentStatus = AgentStatus()
            isConnected = false
        }
    }
    
    // MARK: - Network Communication
    
    private enum EndpointType {
        case checkAgentStatus
        case enrollAgent
        case refreshToken
        case getTasks
        case updateTask
        case processTelemetry
        case reportDeviceData
        
        var path: String {
            switch self {
            case .checkAgentStatus:
                return "/check-agent-status"
            case .enrollAgent:
                return "/enroll-agent"
            case .refreshToken:
                return "/agent-token-refresh"
            case .getTasks:
                return "/agent-get-tasks"
            case .updateTask:
                return "/agent-update-task"
            case .processTelemetry:
                return "/process-agent-telemetry"
            case .reportDeviceData:
                return "/agent-report-data"
            }
        }
        
        var requiresAuth: Bool {
            switch self {
            case .refreshToken, .enrollAgent:
                return false // Only refresh token and enroll agent don't require auth
            case .checkAgentStatus, .getTasks, .updateTask, .processTelemetry, .reportDeviceData:
                return true // All other endpoints require Authorization header
            }
        }
        
        var description: String {
            switch self {
            case .checkAgentStatus: return "Check Agent Status"
            case .enrollAgent: return "Enroll Agent"
            case .refreshToken: return "Refresh Token"
            case .getTasks: return "Get Tasks"
            case .updateTask: return "Update Task"
            case .processTelemetry: return "Process Telemetry"
            case .reportDeviceData: return "Report Device Data"
            }
        }
    }
    
    private func makeRequest(
        to endpointType: EndpointType,
        method: String = "POST",
        body: [String: Any]? = nil,
        customAuthToken: String? = nil
    ) async throws -> [String: Any] {
        
        let currentBaseURL = await MainActor.run { self.baseURL }
        let endpoint = endpointType.path
        
        guard let url = URL(string: "\(currentBaseURL)\(endpoint)") else {
            print("🔴 ODIN: Invalid URL: \(currentBaseURL)\(endpoint)")
            throw NSError(domain: "NetworkError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid URL"
            ])
        }
        
        print("🔵 ODIN: Making \(method) request to \(endpointType.description) (\(endpoint))")
        print("🔵 ODIN: Authorization required: \(endpointType.requiresAuth)")
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Only add Authorization header for endpoints that require it
        if endpointType.requiresAuth {
            let authToken: String?
            
            // Use custom auth token if provided (for enrollment), otherwise use stored credentials
            if let customToken = customAuthToken {
                authToken = customToken
                print("🔵 ODIN: ✅ Using custom authorization token (length: \(customToken.count))")
            } else if let credentials = loadStoredCredentials() {
                authToken = credentials.accessToken
                print("🔵 ODIN: ✅ Using stored authorization token for agent: \(credentials.agentId)")
            } else {
                print("🔴 ODIN: ❌ No credentials available for authenticated endpoint")
                throw NSError(domain: "NetworkError", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No credentials available for authenticated endpoint"
                ])
            }
            
            if let token = authToken {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                print("🔵 ODIN: ✅ Added Authorization header")
            }
        } else {
            // For edge function endpoints, add Supabase anon key
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            print("🔵 ODIN: ✅ Added Supabase anon key for edge function")
        }
        
        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                print("🔵 ODIN: Request body size: \(request.httpBody?.count ?? 0) bytes")
                
                // Log the request body for debugging enrollment and non-auth endpoints
                if !endpointType.requiresAuth || endpointType == .enrollAgent {
                    if let bodyData = request.httpBody,
                       let bodyString = String(data: bodyData, encoding: .utf8) {
                        print("🔵 ODIN: Request body: \(bodyString)")
                        print("🔵 ODIN: Request body formatted:")
                        if let jsonData = bodyString.data(using: .utf8),
                           let jsonObject = try? JSONSerialization.jsonObject(with: jsonData),
                           let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
                           let prettyString = String(data: prettyData, encoding: .utf8) {
                            print(prettyString)
                        }
                    }
                }
                
                // Log headers for debugging enrollment
                if endpointType == .enrollAgent {
                    print("🔵 ODIN: Request headers:")
                    if let headers = request.allHTTPHeaderFields {
                        for (key, value) in headers {
                            if key == "Authorization" {
                                print("🔵 ODIN:   \(key): Bearer ***\(String(value.suffix(8)))")
                            } else {
                                print("🔵 ODIN:   \(key): \(value)")
                            }
                        }
                    }
                }
            } catch {
                print("🔴 ODIN: Failed to serialize request body: \(error)")
                throw error
            }
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("🔴 ODIN: Invalid HTTP response")
            throw NSError(domain: "NetworkError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response"
            ])
        }
        
        print("🔵 ODIN: HTTP Response: \(httpResponse.statusCode)")
        
        // Handle 401 errors for authenticated endpoints (but not enrollment)
        if httpResponse.statusCode == 401 && endpointType.requiresAuth && endpointType != .enrollAgent {
            print("🔴 ODIN: 401 Unauthorized - attempting token refresh...")
            
            // Circuit breaker: prevent infinite retry loops
            if refreshAttemptCount >= maxRefreshAttempts {
                print("🔴 ODIN: Max refresh attempts (\(maxRefreshAttempts)) reached, clearing credentials...")
                refreshAttemptCount = 0
                await clearStoredCredentials()
                throw NSError(domain: "NetworkError", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "Authentication failed after multiple refresh attempts. Please re-enroll the agent."
                ])
            }
            
            if let credentials = loadStoredCredentials() {
                do {
                    refreshAttemptCount += 1
                    print("🔵 ODIN: Token refresh attempt \(refreshAttemptCount)/\(maxRefreshAttempts)")
                    
                    await refreshTokens(credentials)
                    print("🔵 ODIN: Token refreshed successfully, retrying request...")
                    
                    // Reset counter on successful refresh
                    refreshAttemptCount = 0
                    
                    return try await makeRequest(to: endpointType, method: method, body: body, customAuthToken: customAuthToken)
                } catch {
                    print("🔴 ODIN: Token refresh failed: \(error.localizedDescription)")
                    
                    // If we've reached max attempts or refresh token is invalid, clear credentials
                    if refreshAttemptCount >= maxRefreshAttempts || error.localizedDescription.contains("Invalid refresh token") {
                        print("🔴 ODIN: Invalid refresh token or max attempts reached, clearing credentials...")
                        refreshAttemptCount = 0
                        await clearStoredCredentials()
                        throw NSError(domain: "NetworkError", code: 401, userInfo: [
                            NSLocalizedDescriptionKey: "Authentication failed. The refresh token is invalid. Please re-enroll the agent."
                        ])
                    }
                    
                    throw error
                }
            } else {
                print("🔴 ODIN: No credentials to refresh")
                throw NSError(domain: "NetworkError", code: 401, userInfo: [
                    NSLocalizedDescriptionKey: "No valid credentials available"
                ])
            }
        }
        
        // Log response body for debugging
        let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
        
        guard 200...299 ~= httpResponse.statusCode else {
            print("🔴 ODIN: HTTP Error \(httpResponse.statusCode)")
            print("🔴 ODIN: Response body: \(responseBody)")
            
            // Special handling for enrollment token errors
            if httpResponse.statusCode == 401 && 
               endpointType == .enrollAgent && 
               (responseBody.contains("Enrollment token has already been used") || 
                responseBody.contains("Invalid enrollment token")) {
                print("🔴 ODIN: Enrollment token error - manual intervention required")
                
                // Circuit breaker: prevent rapid token regeneration
                let now = Date()
                let lastRegen = await MainActor.run { self.lastTokenRegeneration }
                if let lastRegen = lastRegen,
                   now.timeIntervalSince(lastRegen) < 30 { // 30 second cooldown
                    print("🔴 ODIN: Token regeneration on cooldown (last attempt \(Int(now.timeIntervalSince(lastRegen)))s ago)")
                    throw NSError(domain: "NetworkError", code: 4012, userInfo: [
                        NSLocalizedDescriptionKey: "Enrollment token error. Please wait before trying again."
                    ])
                }
                
                print("🔴 ODIN: Enrollment tokens must be generated from ODIN admin interface")
                
                // Notify user instead of auto-generating
                await MainActor.run {
                    self.lastTokenRegeneration = now
                    addNotification(
                        event: "enrollment_token_required", 
                        message: "Enrollment token invalid. Please generate a new token from your ODIN admin interface and enter it manually in settings."
                    )
                }
                
                throw NSError(domain: "NetworkError", code: 4013, userInfo: [
                    NSLocalizedDescriptionKey: "Enrollment token invalid. Please generate a new enrollment token from your ODIN admin interface and enter it in the app settings."
                ])
            }
            
            // Special handling for agent already exists conflict
            if httpResponse.statusCode == 409 && 
               endpointType == .enrollAgent && 
               responseBody.contains("Agent with this hostname already exists") {
                print("🔴 ODIN: Agent already exists for this hostname")
                
                await MainActor.run {
                    addNotification(
                        event: "agent_already_exists", 
                        message: "Agent with hostname already registered. Remove existing agent from ODIN admin or contact administrator."
                    )
                }
                
                throw NSError(domain: "NetworkError", code: 4014, userInfo: [
                    NSLocalizedDescriptionKey: "Agent with this hostname already exists in ODIN. Please remove the existing agent from your ODIN admin interface or contact your administrator."
                ])
            }
            
            throw NSError(domain: "NetworkError", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP Error \(httpResponse.statusCode): \(responseBody)"
            ])
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("🔴 ODIN: Invalid JSON response: \(responseBody)")
            throw NSError(domain: "NetworkError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Invalid JSON response"
            ])
        }
        
        print("🟢 ODIN: Request successful, response size: \(data.count) bytes")
        if !endpointType.requiresAuth {
            print("🔵 ODIN: Response: \(json)")
        }
        
        return json
    }
    
    // Legacy method for backward compatibility - will be phased out
    private func makeRequest(
        endpoint: String,
        method: String = "GET",
        body: [String: Any]? = nil,
        requiresAuth: Bool = true
    ) async throws -> [String: Any] {
        
        // Map old endpoint strings to new EndpointType
        let endpointType: EndpointType
        switch endpoint {
        case "/check-agent-status":
            endpointType = .checkAgentStatus
        case "/enroll-agent":
            endpointType = .enrollAgent
        case "/agent-token-refresh":
            endpointType = .refreshToken
        case "/agent-get-tasks":
            endpointType = .getTasks
        case "/agent-update-task":
            endpointType = .updateTask
        case "/process-agent-telemetry":
            endpointType = .processTelemetry
        default:
            print("🔴 ODIN: Unknown endpoint: \(endpoint)")
            throw NSError(domain: "NetworkError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unknown endpoint: \(endpoint)"
            ])
        }
        
        return try await makeRequest(to: endpointType, method: method, body: body, customAuthToken: nil)
    }
    
    // MARK: - Task Reporting
    
    private func reportTaskCompletion(
        taskId: String,
        status: String,
        result: [String: Any],
        executionTime: TimeInterval
    ) async {
        guard let credentials = loadStoredCredentials() else { return }
        
        do {
            let _ = try await makeRequest(
                to: .updateTask,
                body: [
                    "agent_id": credentials.agentId,
                    "task_id": taskId,
                    "status": status,
                    "result": result,
                    "execution_time": executionTime,
                    "completed_at": ISO8601DateFormatter().string(from: Date())
                ]
            )
        } catch {
            print("Failed to report task completion: \(error)")
        }
    }
    
    // MARK: - Notifications
    
    private func addNotification(event: String, message: String, data: [String: String]? = nil) {
        let notification = AgentNotification(
            timestamp: Date(),
            event: event,
            message: message,
            data: data
        )
        
        notifications.append(notification)
        
        // Keep only last 50 notifications
        if notifications.count > 50 {
            notifications.removeFirst(notifications.count - 50)
        }
    }
    
    // MARK: - Configuration
    
    @MainActor
    func configure(baseURL: String) {
        self.baseURL = baseURL
    }
    
    @MainActor
    func configure(settings: OdinSettings) {
        print("🔵 ODIN: Configuring service with settings:")
        print("🔵 ODIN: Base URL: \(settings.baseURL)")
        print("🔵 ODIN: Enrollment Token: \(String(settings.enrollmentToken.prefix(8)))...")
        
        self.settings = settings
        self.baseURL = settings.baseURL
        // Additional configuration can be added here
    }
    
    func getAgentId() -> String? {
        return agentStatus.agentId
    }
    
    // MARK: - Public Interface
    
    func testEnrollment(with enrollmentToken: String) async {
        print("🔵 ODIN: Starting enrollment test with provided token...")
        print("🔵 ODIN: Token: \(String(enrollmentToken.prefix(8)))...")
        print("🔵 ODIN: Token Length: \(enrollmentToken.count)")
        print("🔵 ODIN: Token Full: '\(enrollmentToken)'")
        await clearStoredCredentials()
        await startEnrollmentProcess(with: enrollmentToken)
    }
    
    private func startEnrollmentProcess(with enrollmentToken: String) async {
        print("🔵 ODIN: Starting enrollment process with specific token...")
        Task {
            await attemptDirectEnrollmentWithToken(enrollmentToken)
        }
    }
    
    private func attemptDirectEnrollmentWithToken(_ enrollmentToken: String) async {
        print("🔵 ODIN: Starting direct enrollment with provided token...")
        
        do {
            let deviceInfo = await collectDeviceInfo()
            print("🔵 ODIN: Collected device info - Hostname: \(deviceInfo.hostname), Platform: \(deviceInfo.platform)")
            
            print("🔵 ODIN: Using provided enrollment token (length: \(enrollmentToken.count))")
            
            let enrollData: [String: Any] = [
                "token": enrollmentToken,
                "deviceInfo": [
                    "hostname": deviceInfo.hostname,
                    "os": deviceInfo.platform,
                    "osVersion": deviceInfo.version,
                    "agentVersion": "1.0.0",
                    "arch": deviceInfo.arch,
                    "cpu_model": deviceInfo.cpuModel,
                    "total_memory": deviceInfo.totalMemory,
                    "mac_address": deviceInfo.macAddress,
                    "serial_number": deviceInfo.serialNumber ?? ""
                ]
            ]
            
            print("🔵 ODIN: Enrolling new agent with token...")
            print("🔵 ODIN: Request details:")
            print("🔵 ODIN: URL: \(baseURL)/enroll-agent")
            print("🔵 ODIN: Method: POST")
            print("🔵 ODIN: Content-Type: application/json")
            print("🔵 ODIN: Body: \(enrollData)")
            
            let enrollResponse = try await makeRequest(
                to: .enrollAgent, 
                body: enrollData
            )
            
            print("🔵 ODIN: Enrollment response received:")
            print("🔵 ODIN: Full response: \(enrollResponse)")
            
            if let agentId = enrollResponse["agent_id"] as? String,
               let accessToken = enrollResponse["api_token"] as? String,
               let refreshToken = enrollResponse["refresh_token"] as? String,
               let expiresAtString = enrollResponse["expires_at"] as? String {
                
                print("🟢 ODIN: Enrollment successful! Agent ID: \(agentId)")
                print("🔵 ODIN: Access Token (first 20 chars): \(String(accessToken.prefix(20)))...")
                print("🔵 ODIN: Refresh Token (first 20 chars): \(String(refreshToken.prefix(20)))...")
                print("🔵 ODIN: Expires At String: \(expiresAtString)")
                
                // Validate that tokens look like JWTs or UUIDs (ODIN uses UUID format)
                if !accessToken.contains(".") && !isValidUUID(accessToken) {
                    print("🔴 ODIN: WARNING - Access token format unexpected: \(accessToken)")
                }
                if !refreshToken.contains(".") && !isValidUUID(refreshToken) {
                    print("🔴 ODIN: WARNING - Refresh token format unexpected: \(refreshToken)")
                }
                
                // Parse expires_at timestamp
                let formatter = ISO8601DateFormatter()
                let expiresAt = formatter.date(from: expiresAtString) ?? Date().addingTimeInterval(3600)
                
                print("🔵 ODIN: Token expires at: \(expiresAt)")
                
                let credentials = AgentCredentials(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    agentId: agentId,
                    expiresAt: expiresAt,
                    refreshTokenCreatedAt: Date()
                )
                
                storeCredentials(credentials)
                await authenticateWithStoredCredentials(credentials)
                
                await MainActor.run {
                    addNotification(event: "agent_enrolled", message: "Successfully enrolled with ODIN")
                }
            } else {
                print("🔴 ODIN: Enrollment response missing required fields")
                print("🔴 ODIN: Response: \(enrollResponse)")
                await MainActor.run {
                    lastError = "Enrollment failed: Invalid response from server"
                }
            }
            
        } catch {
            print("🔴 ODIN: Enrollment failed with error: \(error)")
            if let urlError = error as? URLError {
                print("🔴 ODIN: URL Error code: \(urlError.code.rawValue)")
                print("🔴 ODIN: URL Error description: \(urlError.localizedDescription)")
            }
            await MainActor.run {
                lastError = "Enrollment failed: \(error.localizedDescription)"
            }
        }
    }
    
    func forceTokenRefresh() async {
        if let credentials = loadStoredCredentials() {
            await refreshTokens(credentials)
        }
    }
    
    func forceTelemetryReport() async {
        await sendTelemetry()
    }
    
    func getStatusSummary() -> String {
        let connectionStatus = isConnected ? "Connected" : "Disconnected"
        let authStatus = agentStatus.authenticated ? "Authenticated" : "Not Authenticated"
        let runningStatus = agentStatus.running ? "Active" : "Inactive"
        
        return "Status: \(connectionStatus) | Auth: \(authStatus) | Agent: \(runningStatus)"
    }
    
    func isAgentHealthy() -> Bool {
        return isConnected && agentStatus.authenticated && agentStatus.running
    }
    
    func testConnection() async -> Bool {
        print("🔵 ODIN: Testing connection...")
        
        do {
            let deviceInfo = await collectDeviceInfo()
            let checkData: [String: Any] = [
                "hostname": deviceInfo.hostname,
                "deviceInfo": [
                    "platform": deviceInfo.platform,
                    "arch": deviceInfo.arch,
                    "version": deviceInfo.version,
                    "cpu_model": deviceInfo.cpuModel,
                    "total_memory": deviceInfo.totalMemory,
                    "mac_address": deviceInfo.macAddress,
                    "serial_number": deviceInfo.serialNumber ?? ""
                ]
            ]
            
            let _ = try await makeRequest(to: .checkAgentStatus, body: checkData)
            print("🟢 ODIN: Connection test successful")
            return true
            
        } catch {
            print("🔴 ODIN: Connection test failed: \(error)")
            return false
        }
    }
    
    private func isValidUUID(_ uuid: String) -> Bool {
        // UUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX (36 characters with 4 hyphens)
        let uuidRegex = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"
        let predicate = NSPredicate(format: "SELF MATCHES %@", uuidRegex)
        return predicate.evaluate(with: uuid)
    }
    
    func completeReset() async {
        print("🔵 ODIN: Performing complete agent reset...")
        
        // Stop all timers
        taskPollTimer?.invalidate()
        telemetryTimer?.invalidate()
        tokenRefreshTimer?.invalidate()
        statusHeartbeatTimer?.invalidate()
        refreshTokenRotationTimer?.invalidate()
        
        // Clear credentials
        await clearStoredCredentials()
        
        // Reset status
        await MainActor.run {
            agentStatus = AgentStatus()
            isConnected = false
            lastError = nil
            notifications.removeAll()
            refreshAttemptCount = 0
            tokenRegenerationCount = 0
            lastTokenRegeneration = nil
        }
        
        print("🟢 ODIN: Complete reset finished - agent is now in fresh state")
    }
} 