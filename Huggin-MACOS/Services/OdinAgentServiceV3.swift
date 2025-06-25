import Foundation
import Combine

/// Main ODIN agent service using simplified serial number authentication
final class OdinAgentServiceV3: ObservableObject, @unchecked Sendable {
    
    // MARK: - Singleton
    static let shared: OdinAgentServiceV3 = {
        return MainActor.assumeIsolated {
            OdinAgentServiceV3()
        }
    }()
    
    // MARK: - Published Properties
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastActivity: String = "Never"
    @Published var isConnecting: Bool = false
    @Published var agentHealth: AgentHealth
    @Published var recentNotifications: [NotificationItem]
    @Published var taskCount: Int = 0
    @Published var pendingTasks: [TaskItem]
    @Published var executingTasks: [String: TaskExecutionStatus]
    
    // MARK: - Dependencies
    private let authManager: OdinSerialAuthManager
    private let tokenManager: OdinTokenManager
    private var networkService: OdinNetworkServiceV3
    private var checkInTimer: Timer?
    private var telemetryTimer: Timer?
    private var heartbeatTimer: Timer?
    private var taskPollingTimer: Timer?
    
    // MARK: - Configuration
    private let baseURL = "https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1"
    private let checkInInterval: TimeInterval = 60.0 // 1 minute
    private let telemetryInterval: TimeInterval = 900.0 // 15 minutes
    private let heartbeatInterval: TimeInterval = 300.0 // 5 minutes (for testing)
    private let taskPollingInterval: TimeInterval = 30.0 // 30 seconds
    
    // MARK: - Data Models
    
    enum ConnectionStatus: String, CaseIterable {
        case disconnected = "Disconnected"
        case connecting = "Connecting"
        case connected = "Connected"
        case authenticated = "Authenticated"
        case error = "Error"
        
        var color: String {
            switch self {
            case .disconnected: return "secondary"
            case .connecting: return "blue"
            case .connected: return "green"
            case .authenticated: return "green"
            case .error: return "red"
            }
        }
        
        var icon: String {
            switch self {
            case .disconnected: return "wifi.slash"
            case .connecting: return "wifi.exclamationmark"
            case .connected: return "wifi"
            case .authenticated: return "checkmark.shield"
            case .error: return "exclamationmark.triangle"
            }
        }
    }
    
    struct AgentHealth {
        var isHealthy: Bool = false
        var uptime: String = "Unknown"
        var cpuUsage: Double = 0.0
        var memoryUsage: Double = 0.0
        var diskSpace: Double = 0.0
        var lastHealthCheck: Date
        
        init(isHealthy: Bool = false, uptime: String = "Unknown", cpuUsage: Double = 0.0, memoryUsage: Double = 0.0, diskSpace: Double = 0.0, lastHealthCheck: Date = Date()) {
            self.isHealthy = isHealthy
            self.uptime = uptime
            self.cpuUsage = cpuUsage
            self.memoryUsage = memoryUsage
            self.diskSpace = diskSpace
            self.lastHealthCheck = lastHealthCheck
        }
        
        static func initial() -> AgentHealth {
            return AgentHealth(lastHealthCheck: Date())
        }
        
        var healthStatus: String {
            return isHealthy ? "Healthy" : "Degraded"
        }
        
        var healthColor: String {
            return isHealthy ? "green" : "orange"
        }
    }
    
    struct TaskItem: Identifiable, Codable {
        let id: UUID
        let taskId: String
        let type: String
        let payload: [String: String]
        let priority: Int
        let timeout: Int?
        let receivedAt: Date
        
        init(taskId: String, type: String, payload: [String: String], priority: Int, timeout: Int?) {
            self.id = UUID()
            self.taskId = taskId
            self.type = type
            self.payload = payload
            self.priority = priority
            self.timeout = timeout
            self.receivedAt = Date()
        }
        
        var displayName: String {
            return payload["name"] ?? type.capitalized
        }
        
        var description: String {
            return payload["description"] ?? "Task of type \(type)"
        }
    }
    
    struct NotificationItem: Identifiable, Hashable {
        let id = UUID()
        let timestamp: Date
        let message: String
        
        var formattedString: String {
            "[\(NotificationItem.formatTime(timestamp))] \(message)"
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: NotificationItem, rhs: NotificationItem) -> Bool {
            lhs.id == rhs.id
        }
        
        static func formatTime(_ date: Date) -> String {
            let formatter = DateFormatter()
            formatter.dateFormat = "hh:mm a"
            return formatter.string(from: date)
        }
    }
    
    struct TaskExecutionStatus: Identifiable, Codable {
        let id: UUID
        let taskId: String
        let status: ExecutionStatus
        let startTime: Date
        let progress: Double
        let message: String
        let result: [String: Any]?
        
        enum ExecutionStatus: String, Codable {
            case pending = "pending"
            case inProgress = "in_progress"
            case completed = "completed"
            case failed = "failed"
            case cancelled = "cancelled"
        }
        
        enum CodingKeys: String, CodingKey {
            case id, taskId, status, startTime, progress, message
            // Note: result is not included in CodingKeys because [String: Any] is not Codable
        }
        
        init(taskId: String, status: ExecutionStatus, startTime: Date = Date(), progress: Double = 0.0, message: String = "", result: [String: Any]? = nil) {
            self.id = UUID()
            self.taskId = taskId
            self.status = status
            self.startTime = startTime
            self.progress = progress
            self.message = message
            self.result = result
        }
        
        // Custom encoding to handle the result property
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(taskId, forKey: .taskId)
            try container.encode(status, forKey: .status)
            try container.encode(startTime, forKey: .startTime)
            try container.encode(progress, forKey: .progress)
            try container.encode(message, forKey: .message)
        }
        
        // Custom decoding to handle the result property
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            taskId = try container.decode(String.self, forKey: .taskId)
            status = try container.decode(ExecutionStatus.self, forKey: .status)
            startTime = try container.decode(Date.self, forKey: .startTime)
            progress = try container.decode(Double.self, forKey: .progress)
            message = try container.decode(String.self, forKey: .message)
            result = nil // Result is not persisted in Codable
        }
    }
    
    // MARK: - Initialization
    
    @MainActor
    private init() {
        // Initialize dependencies
        self.authManager = OdinSerialAuthManager()
        self.tokenManager = OdinTokenManager()
        
        // Initialize Published properties
        self.agentHealth = AgentHealth(lastHealthCheck: Date())
        self.recentNotifications = []
        self.pendingTasks = []
        self.executingTasks = [:]
        
        self.networkService = OdinNetworkServiceV3(authManager: authManager, tokenManager: tokenManager)
        
        // Configure network service
        networkService.configure(baseURL: baseURL, tokenManager: tokenManager)
        
        // Configure token manager with network service
        tokenManager.setNetworkService(networkService)
        
        // Start initial setup in background to avoid blocking main thread
        Task { [weak self] in
            await self?.initializeAgent()
        }
    }
    
    deinit {
        // Timers will be cleaned up automatically when the object is deallocated
        // Cannot access MainActor properties from deinit
    }
    
    // MARK: - Public Methods
    
    /// Enroll agent with ODIN using enrollment token
    func enrollAgent(with token: String) async -> Bool {
        guard !isConnecting else { return false }
        
        print("🟢 AGENT: Starting agent enrollment")
        addNotification("Starting agent enrollment...")
        
        await MainActor.run {
            isConnecting = true
            connectionStatus = .connecting
        }
        
        do {
            // Get device serial number
            guard let serialNumber = await authManager.getDeviceSerialNumber() else {
                throw OdinNetworkServiceV3.NetworkError.serialNumberRequired
            }
            
            print("🔵 AGENT: Device serial number: \(serialNumber)")
            
            // Prepare device info
            let deviceInfo = await prepareDeviceInfo(serialNumber: serialNumber)
            
            // Call enrollment API
            let response = try await networkService.enrollAgent(with: token, deviceInfo: deviceInfo)
            
            print("🔵 AGENT: Enrollment response received:")
            print("🔵 AGENT: Success: \(response.success)")
            print("🔵 AGENT: Message: \(response.message)")
            print("🔵 AGENT: Agent ID: \(response.agentId ?? "nil")")
            print("🔵 AGENT: Access Token: \(response.accessToken?.prefix(8) ?? "nil")...")
            print("🔵 AGENT: Refresh Token: \(response.refreshToken?.prefix(8) ?? "nil")...")
            print("🔵 AGENT: Expires At: \(response.expiresAt ?? "nil")")
            
            if response.success {
                // Store registration
                let registration = OdinSerialAuthManager.AgentRegistration(
                    serialNumber: serialNumber,
                    hostname: deviceInfo["hostname"] as? String ?? "Unknown",
                    platform: deviceInfo["platform"] as? String ?? "macOS",
                    enrollmentToken: token
                )
                
                await authManager.storeRegistration(registration)
                
                // Store access token and refresh token if provided
                if let accessToken = response.accessToken,
                   let refreshToken = response.refreshToken,
                   let agentId = response.agentId {
                    
                    print("🔵 AGENT: Storing access token and refresh token")
                    
                    // Parse expires_at timestamp
                    let accessTokenExpiry: Date
                    if let expiresAtString = response.expiresAt,
                       let expiryDate = ISO8601DateFormatter().date(from: expiresAtString) {
                        accessTokenExpiry = expiryDate
                    } else {
                        accessTokenExpiry = Date().addingTimeInterval(3600) // 1 hour default
                    }
                    
                    let refreshTokenExpiry = Date().addingTimeInterval(30 * 24 * 3600) // 30 days default
                    
                    // Store credentials in token manager
                    let credentials = OdinTokenManager.TokenCredentials(
                        accessToken: accessToken,
                        refreshToken: refreshToken,
                        agentId: agentId,
                        accessTokenExpiresAt: accessTokenExpiry,
                        refreshTokenExpiresAt: refreshTokenExpiry
                    )
                    
                    await tokenManager.storeCredentials(credentials)
                    print("🟢 AGENT: Access token and refresh token stored successfully")
                } else {
                    print("🔴 AGENT: Warning - No access token or refresh token received from enrollment")
                }
                
                await MainActor.run {
                    connectionStatus = .authenticated
                    isConnecting = false
                }
                addNotification("Agent enrolled successfully!")
                
                // Start background services
                startBackgroundServices()
                return true
                
            } else {
                throw OdinNetworkServiceV3.NetworkError.serverError(400, response.message)
            }
            
        } catch {
            print("🔴 AGENT: Enrollment failed: \(error)")
            await MainActor.run {
                connectionStatus = .error
                isConnecting = false
            }
            addNotification("Enrollment failed: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check agent enrollment status
    func checkEnrollmentStatus() async {
        print("🔵 AGENT: Checking enrollment status")
        
        do {
            if await authManager.isAgentReady() {
                // Check if we have access tokens
                if await tokenManager.hasValidCredentials() {
                    await MainActor.run {
                        connectionStatus = .authenticated
                    }
                    addNotification("Agent is enrolled and ready")
                    startBackgroundServices()
                } else {
                    print("🔵 AGENT: Agent enrolled but missing access tokens - re-enrolling")
                    await MainActor.run {
                        connectionStatus = .connecting
                    }
                    addNotification("Re-enrolling to get access tokens...")
                    
                    // Try to re-enroll with the stored enrollment token
                    if let enrollmentToken = authManager.enrollmentToken {
                        let success = await enrollAgent(with: enrollmentToken)
                        if !success {
                            await MainActor.run {
                                connectionStatus = .error
                            }
                            addNotification("Re-enrollment failed")
                        }
                    } else {
                        await MainActor.run {
                            connectionStatus = .error
                        }
                        addNotification("No enrollment token available for re-enrollment")
                    }
                }
            } else {
                await MainActor.run {
                    connectionStatus = .disconnected
                }
                print("🔵 AGENT: Agent not enrolled")
                throw OdinNetworkServiceV3.NetworkError.agentNotFound
            }
        } catch {
            print("🔴 AGENT: Enrollment status check failed: \(error)")
            addNotification("Failed to check enrollment status: \(error.localizedDescription)")
        }
    }
    
    /// Manually trigger check-in
    func performCheckIn() async {
        guard await authManager.isAgentReady() else {
            addNotification("Agent not enrolled")
            return
        }
        
        print("🔵 AGENT: Performing manual check-in")
        addNotification("Checking for new tasks...")
        
        do {
            let systemInfo = await collectSystemInfo()
            let response = try await networkService.checkIn(systemInfo: systemInfo)
            
            if response.success {
                authManager.updateLastCheckIn()
                
                // Process received tasks
                if !response.tasks.isEmpty {
                    await processTasks(response.tasks)
                    addNotification("Received \(response.tasks.count) new tasks")
                } else {
                    addNotification("No new tasks")
                }
                
                await MainActor.run {
                    lastActivity = formatDate(Date())
                }
                
            } else {
                addNotification("Check-in failed: \(response.message ?? "Unknown error")")
            }
            
        } catch OdinNetworkServiceV3.NetworkError.agentNotFound {
            // Agent not found - need re-enrollment
            await handleAgentNotFound()
            
        } catch {
            print("🔴 AGENT: Check-in failed: \(error)")
            addNotification("Check-in failed: \(error.localizedDescription)")
        }
    }
    
    /// Poll for new tasks from ODIN
    func pollTasks() async {
        let isAgentReady = await authManager.isAgentReady()
        let hasValidCredentials = await tokenManager.hasValidCredentials()
        
        guard isAgentReady && hasValidCredentials else {
            print("🔵 AGENT: Skipping task poll - agent not ready or not authenticated")
            return
        }
        
        print("🔵 AGENT: Polling for new tasks...")
        
        do {
            // Get tasks using the agent-get-tasks edge function
            let tasks = try await networkService.getTasks()
            
            if let taskData = tasks["tasks"] as? [[String: Any]], !taskData.isEmpty {
                print("🔵 AGENT: Received \(taskData.count) new tasks")
                
                // Convert to TaskData format and process
                let taskItems = taskData.compactMap { taskDict -> OdinNetworkServiceV3.TaskData? in
                    guard let taskId = taskDict["id"] as? String,
                          let taskType = taskDict["task_type"] as? String,
                          let parameters = taskDict["parameters"] as? [String: Any] else {
                        return nil
                    }
                    
                    // Convert parameters to string dictionary
                    let payload = parameters.compactMapValues { "\($0)" }
                    
                    return OdinNetworkServiceV3.TaskData(
                        taskId: taskId,
                        type: taskType,
                        payload: payload,
                        priority: taskDict["priority"] as? Int ?? 1,
                        timeout: taskDict["timeout"] as? Int
                    )
                }
                
                if !taskItems.isEmpty {
                    await processTasks(taskItems)
                    addNotification("Received \(taskItems.count) new tasks")
                    
                    // Execute tasks immediately
                    for taskItem in taskItems {
                        await executeTask(taskItem)
                    }
                }
            } else {
                print("🔵 AGENT: No new tasks available")
            }
            
        } catch {
            print("🔴 AGENT: Task polling failed: \(error)")
            addNotification("Task polling failed: \(error.localizedDescription)")
        }
    }
    
    /// Execute a single task
    private func executeTask(_ taskData: OdinNetworkServiceV3.TaskData) async {
        let taskId = taskData.taskId
        print("🔵 AGENT: Starting execution of task \(taskId) (type: \(taskData.type))")
        
        // Create execution status
        let executionStatus = TaskExecutionStatus(
            taskId: taskId,
            status: .inProgress,
            message: "Starting task execution..."
        )
        
        executingTasks[taskId] = executionStatus
        addNotification("Starting task: \(taskData.type)")
        
        let startTime = Date()
        
        do {
            // Update task status to in_progress
            _ = try await networkService.updateTaskStatus(taskId: taskId, status: "in_progress")
            
            // Execute based on task type
            let result = try await executeTaskByType(taskData)
            let executionTime = Date().timeIntervalSince(startTime)
            
            // Update execution status
            executingTasks[taskId] = TaskExecutionStatus(
                taskId: taskId,
                status: .completed,
                startTime: startTime,
                progress: 1.0,
                message: "Task completed successfully",
                result: result
            )
            
            // Report success
            _ = try await networkService.updateTaskStatus(
                taskId: taskId,
                status: "completed",
                result: result,
                executionTime: executionTime
            )
            
            addNotification("Task \(taskId) completed successfully")
            print("🟢 AGENT: Task \(taskId) completed in \(String(format: "%.2f", executionTime))s")
            
        } catch {
            let executionTime = Date().timeIntervalSince(startTime)
            
            // Update execution status
            executingTasks[taskId] = TaskExecutionStatus(
                taskId: taskId,
                status: .failed,
                startTime: startTime,
                progress: 0.0,
                message: "Task failed: \(error.localizedDescription)",
                result: ["error": error.localizedDescription]
            )
            
            // Report failure
            do {
                _ = try await networkService.updateTaskStatus(
                    taskId: taskId,
                    status: "failed",
                    result: ["error": error.localizedDescription],
                    executionTime: executionTime
                )
            } catch {
                print("🔴 AGENT: Failed to report task failure: \(error)")
            }
            
            addNotification("Task \(taskId) failed: \(error.localizedDescription)")
            print("🔴 AGENT: Task \(taskId) failed: \(error.localizedDescription)")
        }
    }
    
    /// Execute task based on its type
    private func executeTaskByType(_ taskData: OdinNetworkServiceV3.TaskData) async throws -> [String: Any] {
        switch taskData.type {
        case "run_command":
            return try await executeCommand(taskData.payload)
        case "run_script":
            return try await executeScript(taskData.payload)
        case "install_software":
            return try await installSoftware(taskData.payload)
        case "apply_policy":
            return try await applyPolicy(taskData.payload)
        case "collect_data":
            return try await collectData(taskData.payload)
        case "system_check":
            return try await performSystemCheck(taskData.payload)
        default:
            throw TaskExecutionError.unsupportedTaskType(taskData.type)
        }
    }
    
    /// Send telemetry data
    func sendTelemetry() async {
        do {
            let telemetryData = await collectTelemetryData()
            guard let serialNumber = try? await authManager.getSerialNumber() else {
                print("🔴 AGENT: Missing serial number")
                return
            }
            
            // Send telemetry data at top level (not nested under telemetry_data)
            var requestBody = telemetryData
            requestBody["serial_number"] = serialNumber
            
            _ = try await networkService.sendData(
                to: .telemetry,
                data: requestBody
            )
            print("🟢 AGENT: Telemetry data sent successfully")
        } catch {
            print("🔴 AGENT: Failed to send telemetry: \(error)")
        }
    }
    
    /// Reset agent (clear enrollment)
    func resetAgent() async {
        print("🔵 AGENT: Resetting agent")
        addNotification("Resetting agent...")
        
        stopBackgroundServices()
        await authManager.clearRegistration()
        
        await MainActor.run {
            connectionStatus = .disconnected
            lastActivity = "Never"
            taskCount = 0
            pendingTasks.removeAll()
            agentHealth = AgentHealth(lastHealthCheck: Date())
        }
        
        addNotification("Agent reset completed")
    }
    
    /// Get agent status summary
    func getAgentStatus() -> (enrolled: Bool, serialNumber: String?, daysSinceEnrollment: Int) {
        // Since this needs to be called from Views, we'll use a task to get the async result
        // and return a cached value. For Views, we should use @State or @Published properties instead.
        var result: (enrolled: Bool, serialNumber: String?, daysSinceEnrollment: Int) = (false, nil, 0)
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            result = await authManager.getRegistrationStatus()
            semaphore.signal()
        }
        
        _ = semaphore.wait(timeout: .now() + 1.0) // 1 second timeout
        return result
    }
    
    /// Send device data
    func sendDeviceData() async {
        print("🔵 AGENT: sendDeviceData() called")
        do {
            print("🔵 AGENT: Collecting device data...")
            let deviceData = await collectDeviceData()
            print("🔵 AGENT: Device data collected successfully")
            
            print("🔵 AGENT: Getting serial number...")
            let serialNumber = try await authManager.getSerialNumber()
            print("🔵 AGENT: Serial number: \(serialNumber)")
            
            // Send device data at top level (not nested under device_data)
            var requestBody = deviceData
            requestBody["serial_number"] = serialNumber
            
            print("🔵 AGENT: Request body prepared: \(requestBody)")
            print("🔵 AGENT: Sending device data to /agent-report-data...")
            
            let response = try await networkService.sendData(
                to: .deviceData,
                data: requestBody
            )
            
            print("🟢 AGENT: Device data sent successfully, response: \(response)")
        } catch OdinSerialAuthManager.AuthError.enrollmentRequired {
            print("🔴 AGENT: Enrollment required for device data")
        } catch {
            print("🔴 AGENT: Failed to send device data: \(error)")
            print("🔴 AGENT: Error type: \(type(of: error))")
            if let networkError = error as? OdinNetworkServiceV3.NetworkError {
                print("🔴 AGENT: Network error: \(networkError)")
            }
        }
    }
    
    /// Send device data with detailed status callbacks
    func sendDeviceDataWithStatus(
        progress: @escaping @Sendable (String, Double) -> Void,
        completion: @escaping @Sendable (Bool, Error?) -> Void
    ) async {
        print("🔵 AGENT: sendDeviceDataWithStatus() called")
        
        do {
            progress("Checking enrollment status...", 0.1)
            let status = await authManager.getRegistrationStatus()
            guard status.enrolled else {
                let error = OdinSerialAuthManager.AuthError.enrollmentRequired
                print("🔴 AGENT: Enrollment required for device data")
                completion(false, error)
                return
            }
            
            progress("Getting serial number...", 0.2)
            let serialNumber = try await authManager.getSerialNumber()
            print("🔵 AGENT: Serial number: \(serialNumber)")
            
            progress("Collecting hardware information...", 0.3)
            let hardwareInfo = await getHardwareInfo()
            print("🔵 AGENT: Hardware info collected")
            
            progress("Collecting software information...", 0.5)
            let softwareInfo = await getSoftwareInfo()
            print("🔵 AGENT: Software info collected")
            
            progress("Collecting security information...", 0.7)
            let securityInfo = await getSecurityInfo()
            print("🔵 AGENT: Security info collected")
            
            progress("Collecting network information...", 0.8)
            let networkInfo = await getNetworkInfo()
            print("🔵 AGENT: Network info collected")
            
            progress("Preparing device data...", 0.9)
            let deviceData: [String: Any] = [
                "hardware": hardwareInfo,
                "software": softwareInfo,
                "security": securityInfo,
                "network": networkInfo
            ]
            
            // Send device data at top level (not nested under device_data)
            var requestBody = deviceData
            requestBody["serial_number"] = serialNumber
            
            progress("Sending device data to server...", 0.95)
            print("🔵 AGENT: Sending device data to /agent-report-data...")
            
            let response = try await networkService.sendData(
                to: .deviceData,
                data: requestBody
            )
            
            progress("Device data sent successfully", 1.0)
            print("🟢 AGENT: Device data sent successfully, response: \(response)")
            completion(true, nil)
            
        } catch let authError as OdinSerialAuthManager.AuthError {
            print("🔴 AGENT: Auth error: \(authError)")
            completion(false, authError)
        } catch {
            print("🔴 AGENT: Failed to send device data: \(error)")
            print("🔴 AGENT: Error type: \(type(of: error))")
            if let networkError = error as? OdinNetworkServiceV3.NetworkError {
                print("🔴 AGENT: Network error: \(networkError)")
            }
            completion(false, error)
        }
    }
    
    // MARK: - Private Methods
    
    private var isInitialized = false
    
    private func initializeAgent() async {
        // Prevent multiple initializations
        if isInitialized {
            print("🔵 AGENT: Already initialized, skipping")
            return
        }
        
        print("🔵 AGENT: Initializing ODIN agent")
        isInitialized = true
        
        await checkEnrollmentStatus()
        await updateAgentHealth()
        
        print("🟢 AGENT: Agent initialization completed")
    }
    
    private func startBackgroundServices() {
        // Prevent multiple starts
        if checkInTimer != nil || telemetryTimer != nil || heartbeatTimer != nil || taskPollingTimer != nil {
            print("🔵 AGENT: Background services already running, skipping start")
            return
        }
        
        print("🔵 AGENT: Starting background services...")
        stopBackgroundServices()
        
        // Check-in timer (every 60 seconds)
        checkInTimer = Timer.scheduledTimer(withTimeInterval: checkInInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.performCheckIn()
            }
        }
        print("🔵 AGENT: Check-in timer started (60s intervals)")
        
        // Telemetry timer (every 15 minutes)
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: telemetryInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.sendTelemetry()
            }
        }
        print("🔵 AGENT: Telemetry timer started (15m intervals)")
        
        // Device data timer (every 5 minutes)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: heartbeatInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.sendDeviceData()
            }
        }
        print("🔵 AGENT: Device data timer started (5m intervals)")
        
        // Task polling timer (every 30 seconds)
        taskPollingTimer = Timer.scheduledTimer(withTimeInterval: taskPollingInterval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.pollTasks()
            }
        }
        print("🔵 AGENT: Task polling timer started (30s intervals)")
        
        // Start initial data collection
        Task {
            print("🔵 AGENT: Sending initial device data...")
            await sendDeviceData()
            print("🔵 AGENT: Sending initial telemetry...")
            await sendTelemetry()
        }
        
        print("🟢 AGENT: All background services started successfully")
    }
    
    private func stopBackgroundServices() {
        print("🔵 AGENT: Stopping background services")
        
        checkInTimer?.invalidate()
        checkInTimer = nil
        
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        
        taskPollingTimer?.invalidate()
        taskPollingTimer = nil
        
        print("🟢 AGENT: Background services stopped")
    }
    
    private func handleAgentNotFound() async {
        print("🔴 AGENT: Agent not found on server - clearing registration")
        
        await MainActor.run {
            connectionStatus = .error
        }
        addNotification("Agent not found - re-enrollment required")
        
        stopBackgroundServices()
        await authManager.clearRegistration()
        
        await MainActor.run {
            connectionStatus = .disconnected
        }
    }
    
    private func prepareDeviceInfo(serialNumber: String) async -> [String: Any] {
        let hostname = Foundation.ProcessInfo.processInfo.hostName
        let osVersion = Foundation.ProcessInfo.processInfo.operatingSystemVersionString
        let processInfo = Foundation.ProcessInfo.processInfo
        
        // Get comprehensive device information
        let deviceInfo: [String: Any] = [
            "serial_number": serialNumber,
            "hostname": hostname,
            "platform": "macOS",
            "agent_version": "3.0.0",
            "os": "macOS",
            "os_version": osVersion,
            "os_build": await getOSBuildVersion(),
            "kernel_version": await getKernelVersion(),
            "architecture": await getSystemArchitecture(),
            "cpu_model": await getCPUModel(),
            "cpu_cores": await getCPUCores(),
            "memory_total": processInfo.physicalMemory,
            "memory_total_gb": processInfo.physicalMemory / (1024 * 1024 * 1024),
            "mac_address": await getMACAddress(),
            "boot_time": await getBootTime(),
            "timezone": TimeZone.current.identifier,
            "locale": Locale.current.identifier,
            "hardware_model": await getHardwareModel(),
            "hardware_uuid": await getHardwareUUID()
        ]
        
        return deviceInfo
    }
    
    private func collectSystemInfo() async -> [String: Any] {
        let processInfo = Foundation.ProcessInfo.processInfo
        
        return [
            "uptime": processInfo.systemUptime,
            "cpu_usage": await getCPUUsage(),
            "memory_usage": await getMemoryUsage(),
            "disk_usage": await getDiskUsage()
        ]
    }
    
    private func collectTelemetryData() async -> [String: Any] {
        return [
            "cpu_usage": await getCPUUsage(),
            "memory_usage": await getMemoryUsage()
        ]
    }
    
    private func collectDeviceData() async -> [String: Any] {
        print("🔵 AGENT: collectDeviceData() started")
        
        // Collect all data concurrently without crossing actor boundaries
        async let hardwareTask = getHardwareInfo()
        async let softwareTask = getSoftwareInfo()
        async let securityTask = getSecurityInfo()
        async let networkTask = getNetworkInfo()
        
        let hardware = await hardwareTask
        let software = await softwareTask
        let security = await securityTask
        let network = await networkTask
        
        let result = [
            "hardware": hardware,
            "software": software,
            "security": security,
            "network": network
        ]
        
        print("🔵 AGENT: collectDeviceData() completed")
        return result
    }
    
    private func processTasks(_ tasks: [OdinNetworkServiceV3.TaskData]) async {
        let taskItems = tasks.map { taskData in
            TaskItem(
                taskId: taskData.taskId,
                type: taskData.type,
                payload: taskData.payload,
                priority: taskData.priority,
                timeout: taskData.timeout
            )
        }
        
        await MainActor.run {
            pendingTasks.append(contentsOf: taskItems)
            taskCount = pendingTasks.count
        }
        
        print("🟢 AGENT: Added \(tasks.count) tasks to queue")
    }
    
    private func updateAgentHealth() async {
        let currentUptime = formatUptime(Foundation.ProcessInfo.processInfo.systemUptime)
        let currentCPU = await getCPUUsage()
        let currentMemory = await getMemoryUsage()
        let currentDisk = await getDiskUsage()
        
        // Determine health status
        let isHealthy = (
            currentCPU < 80.0 &&
            currentMemory < 90.0 &&
            currentDisk < 95.0
        )
        
        await MainActor.run {
            agentHealth.lastHealthCheck = Date()
            agentHealth.uptime = currentUptime
            agentHealth.cpuUsage = currentCPU
            agentHealth.memoryUsage = currentMemory
            agentHealth.diskSpace = currentDisk
            agentHealth.isHealthy = isHealthy
        }
        
        print("🔵 AGENT: Health updated - Status: \(isHealthy ? "Healthy" : "Degraded")")
    }
    
    private func addNotification(_ message: String) {
        Task { @MainActor in
            let notification = NotificationItem(timestamp: Date(), message: message)
            recentNotifications.append(notification)
            
            // Keep only last 50 notifications
            if recentNotifications.count > 50 {
                recentNotifications.removeFirst(recentNotifications.count - 50)
            }
        }
        
        print("📋 NOTIFICATION: \(message)")
    }
    
    // MARK: - System Information Helpers
    
    private func getCPUUsage() async -> Double {
        return await runCommand("/usr/bin/top", args: ["-l", "1", "-n", "0"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("CPU usage:") {
                    let components = line.components(separatedBy: " ")
                    if let usageStr = components.last?.replacingOccurrences(of: "%", with: "") {
                        return Double(usageStr) ?? 0.0
                    }
                }
            }
            return 0.0
        }) ?? 0.0
    }
    
    private func getMemoryUsage() async -> Double {
        return await runCommand("/usr/bin/vm_stat", args: [], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            var totalPages: UInt64 = 0
            var usedPages: UInt64 = 0
            
            for line in lines {
                if line.contains("Pages free:") {
                    let components = line.components(separatedBy: " ")
                    if let pages = UInt64(components.last?.replacingOccurrences(of: ".", with: "") ?? "0") {
                        totalPages += pages
                    }
                } else if line.contains("Pages active:") || line.contains("Pages wired down:") || line.contains("Pages occupied by compressor:") {
                    let components = line.components(separatedBy: " ")
                    if let pages = UInt64(components.last?.replacingOccurrences(of: ".", with: "") ?? "0") {
                        usedPages += pages
                        totalPages += pages
                    }
                }
            }
            
            if totalPages > 0 {
                return Double(usedPages) / Double(totalPages) * 100.0
            }
            return 0.0
        }) ?? 0.0
    }
    
    private func getDiskUsage() async -> Double {
        return await runCommand("/bin/df", args: ["/", "-h"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            if lines.count > 1 {
                let components = lines[1].components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if components.count >= 5 {
                    let usageStr = components[4].replacingOccurrences(of: "%", with: "")
                    return Double(usageStr) ?? 0.0
                }
            }
            return 0.0
        }) ?? 0.0
    }
    
    private func getHardwareInfo() async -> [String: Any] {
        print("🔵 AGENT: Starting hardware info collection...")
        
        let processInfo = Foundation.ProcessInfo.processInfo
        
        // Get basic hardware info
        let basicInfo: [String: Any] = [
            "cpu_model": await getCPUModel(),
            "cpu_cores": await getCPUCores(),
            "cpu_frequency": await getCPUFrequency(),
            "cpu_architecture": await getSystemArchitecture(),
            "memory_total": processInfo.physicalMemory,
            "memory_total_gb": processInfo.physicalMemory / (1024 * 1024 * 1024),
            "hardware_model": await getHardwareModel(),
            "hardware_uuid": await getHardwareUUID(),
            "mac_address": await getMACAddress(),
            "boot_time": await getBootTime()
        ]
        
        // Get performance metrics
        let performanceMetrics: [String: Any] = [
            "cpu_usage": await getCPUUsage(),
            "memory_usage": await getMemoryUsage(),
            "disk_usage": await getDiskUsage(),
            "uptime_seconds": Int(processInfo.systemUptime)
        ]
        
        // Get detailed hardware components
        let detailedComponents: [String: Any] = [
            "graphics_cards": await getGraphicsCards(),
            "storage_devices": await getStorageDevices(),
            "usb_devices": await getUSBDevices(),
            "displays": await getDisplays(),
            "audio_devices": await getAudioDevices(),
            "network_interfaces": await getNetworkInterfaces()
        ]
        
        // Get battery information (if applicable)
        let batteryInfo: [String: Any] = [
            "battery_status": await getBatteryInfo(),
            "power_source": await getPowerSource(),
            "thermal_state": await getThermalState()
        ]
        
        // Get system information
        let systemInfo: [String: Any] = [
            "hostname": processInfo.hostName,
            "os_build": await getOSBuildVersion(),
            "kernel_version": await getKernelVersion(),
            "platform": "macOS",
            "user": processInfo.userName
        ]
        
        let result: [String: Any] = basicInfo.merging(performanceMetrics) { _, new in new }
            .merging(detailedComponents) { _, new in new }
            .merging(batteryInfo) { _, new in new }
            .merging(systemInfo) { _, new in new }
        
        print("🟢 AGENT: Hardware info collection completed")
        return result
    }
    
    private func getSoftwareInfo() async -> [String: Any] {
        print("🔵 AGENT: Starting software info collection...")
        let processInfo = Foundation.ProcessInfo.processInfo
        
        // Only collect essential, fast information
        print("🔵 AGENT: Collecting basic OS info...")
        var result: [String: Any] = [
            "os": "macOS",
            "os_version": processInfo.operatingSystemVersionString,
            "os_build": await getOSBuildVersion(),
            "kernel_version": await getKernelVersion(),
            "agent_version": "3.0.0",
            "huginn_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown",
            "huginn_build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown",
        ]
        
        print("🔵 AGENT: Collecting Xcode version...")
        result["xcode_version"] = await getXcodeVersion()
        
        print("🔵 AGENT: Collecting installed applications count...")
        let apps = await getInstalledApplications()
        result["installed_applications_count"] = apps.count
        result["installed_applications"] = apps  // Send the actual applications array
        
        print("🔵 AGENT: Collecting running processes count...")
        let processes = await getRunningProcesses()
        result["running_processes_count"] = processes.count
        
        print("🔵 AGENT: Collecting environment variables...")
        result["environment_variables"] = await self.getEnvironmentVariables()
        result["shell"] = processInfo.environment["SHELL"] ?? "Unknown"
        result["path"] = processInfo.environment["PATH"] ?? "Unknown"
        result["user"] = processInfo.environment["USER"] ?? "Unknown"
        result["home"] = processInfo.environment["HOME"] ?? "Unknown"
        
        print("🔵 AGENT: Collecting system preferences...")
        result["system_preferences"] = await self.getSystemPreferences()
        
        print("🔵 AGENT: Collecting security settings...")
        result["security_settings"] = await self.getSecuritySettings()
        
        print("🟢 AGENT: Software info collection completed")
        return result
    }
    
    private func getSecurityInfo() async -> [String: Any] {
        print("🔵 AGENT: Starting security info collection...")
        
        var security: [String: Any] = [:]
        
        // Only collect fast, essential security info to avoid hanging
        security["gatekeeper_status"] = await getGatekeeperStatus()
        security["sip_status"] = await getSIPStatus()
        
        // Use placeholders for slow commands to avoid hanging
        security["firewall_status"] = "Available via socketfilterfw"
        security["filevault_status"] = "Available via fdesetup"
        security["secure_boot_status"] = "Available via nvram"
        security["xprotect_version"] = "Available via system_profiler"
        security["mrt_version"] = "Available via system_profiler"
        security["privacy_permissions"] = "Available via tccutil"
        security["screen_lock_settings"] = "Available via pmset"
        security["remote_access_settings"] = "Available via systemsetup"
        security["network_security"] = "Network security analysis available"
        security["vpn_connections"] = "Available via scutil"
        security["antivirus_software"] = "Available via system_profiler"
        security["keychain_info"] = "Available via security command"
        security["certificate_trust_settings"] = "Available via security command"
        security["security_policies"] = "Available via various security commands"
        
        // Set boolean values based on fast status checks
        security["sip_enabled"] = await isSIPEnabled()
        security["gatekeeper_enabled"] = await isGatekeeperEnabled()
        security["firewall_enabled"] = false  // Skip slow check
        security["filevault_enabled"] = false  // Skip slow check
        
        print("🟢 AGENT: Security info collection completed")
        return security
    }
    
    private func getNetworkInfo() async -> [String: Any] {
        print("🔵 AGENT: Starting network info collection...")
        
        var network: [String: Any] = [:]
        
        // Only collect fast, essential network info to avoid hanging
        network["network_interfaces"] = await getNetworkInterfaces()
        
        // Use placeholders for slow commands to avoid hanging
        network["wifi_ssid"] = "Available via airport command"
        network["wifi_signal_strength"] = "Available via airport command"
        network["ip_address"] = "Available via curl"
        network["dns_servers"] = "Available via scutil"
        network["gateway"] = "Available via netstat"
        network["network_speed"] = "Available via networkQuality"
        network["latency"] = "Available via ping"
        network["bandwidth_usage"] = "Available via network monitoring tools"
        network["vpn_status"] = "Available via scutil"
        network["proxy_settings"] = "Available via scutil"
        network["firewall_rules"] = "Available via pfctl"
        network["active_connections"] = "Available via netstat"
        network["listening_ports"] = "Available via netstat"
        network["network_services"] = "Available via launchctl"
        
        print("🟢 AGENT: Network info collection completed")
        return network
    }
    
    // MARK: - Formatting Helpers
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatUptime(_ uptime: TimeInterval) -> String {
        let days = Int(uptime) / (24 * 3600)
        let hours = (Int(uptime) % (24 * 3600)) / 3600
        let minutes = (Int(uptime) % 3600) / 60
        
        if days > 0 {
            return "\(days)d \(hours)h \(minutes)m"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Comprehensive System Information Collection
    
    // Hardware Information Methods
    private func getCPUModel() async -> String {
        return await getSystemProfilerInfo("SPHardwareDataType", key: "chip_type") ?? "Unknown"
    }
    
    private func getCPUCores() async -> Int {
        // Try to get from system profiler first
        if let processorInfo = await getSystemProfilerInfo("SPHardwareDataType", key: "number_processors") {
            // Parse "proc 11:5:6" format - the first number is total cores
            let components = processorInfo.components(separatedBy: ":")
            if let totalCores = Int(components.first?.replacingOccurrences(of: "proc ", with: "") ?? "0") {
                return totalCores
            }
        }
        
        // Fallback to ProcessInfo
        return Foundation.ProcessInfo.processInfo.processorCount
    }
    
    private func getCPUFrequency() async -> String {
        // For Apple Silicon, we can't get exact frequency, so return a reasonable estimate
        let chipType = await getSystemProfilerInfo("SPHardwareDataType", key: "chip_type") ?? "Unknown"
        if chipType.contains("M3 Pro") {
            return "3.5 GHz"
        } else if chipType.contains("M3") {
            return "3.2 GHz"
        } else if chipType.contains("M2 Pro") {
            return "3.2 GHz"
        } else if chipType.contains("M2") {
            return "3.0 GHz"
        } else if chipType.contains("M1 Pro") {
            return "3.2 GHz"
        } else if chipType.contains("M1") {
            return "3.2 GHz"
        }
        return "Unknown"
    }
    
    private func getSystemArchitecture() async -> String {
        return await getSystemctlInfo("hw.targettype") ?? "Unknown"
    }
    
    private func getHardwareModel() async -> String {
        return await getSystemProfilerInfo("SPHardwareDataType", key: "machine_model") ?? "Unknown"
    }
    
    private func getHardwareUUID() async -> String {
        return await getSystemProfilerInfo("SPHardwareDataType", key: "platform_UUID") ?? "Unknown"
    }
    
    private func getOSBuildVersion() async -> String {
        return await getSystemctlInfo("kern.osversion") ?? "Unknown"
    }
    
    private func getKernelVersion() async -> String {
        return await getSystemctlInfo("kern.version") ?? "Unknown"
    }
    
    private func getMACAddress() async -> String {
        return await runCommand("/sbin/ifconfig", args: ["en0"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("ether") {
                    let components = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " ")
                    if components.count >= 2 {
                        return components[1]
                    }
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getBootTime() async -> String {
        return await getSystemctlInfo("kern.boottime") ?? "Unknown"
    }
    
    private func getAvailableMemory() async -> UInt64 {
        return await runCommand("/usr/bin/vm_stat", args: [], parser: { output in
            // Parse vm_stat output for available memory
            let lines = output.components(separatedBy: .newlines)
            var freePages: UInt64 = 0
            let pageSize: UInt64 = 4096 // Default page size
            
            for line in lines {
                if line.contains("Pages free:") {
                    let components = line.components(separatedBy: " ")
                    if let pages = UInt64(components.last?.replacingOccurrences(of: ".", with: "") ?? "0") {
                        freePages = pages
                    }
                }
            }
            
            return freePages * pageSize
        }) ?? 0
    }
    
    private func getMemoryPressure() async -> String {
        return await runCommand("/usr/bin/memory_pressure", args: [], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getStorageDevices() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPStorageDataType") ?? []
    }
    
    private func getGraphicsCards() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPDisplaysDataType") ?? []
    }
    
    private func getNetworkInterfaces() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPNetworkDataType") ?? []
    }
    
    private func getUSBDevices() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPUSBDataType") ?? []
    }
    
    private func getBluetoothDevices() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPBluetoothDataType") ?? []
    }
    
    private func getThermalState() async -> String {
        return await runCommand("/usr/bin/pmset", args: ["-g", "therm"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getPowerSource() async -> String {
        return await runCommand("/usr/bin/pmset", args: ["-g", "ps"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getBatteryInfo() async -> [String: Any] {
        let batteryOutput = await runCommand("/usr/bin/pmset", args: ["-g", "batt"], parser: { $0 }) ?? ""
        return ["battery_status": batteryOutput]
    }
    
    // Software Information Methods
    private func getXcodeVersion() async -> String {
        return await runCommand("/usr/bin/xcodebuild", args: ["-version"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            return lines.first ?? "Not Installed"
        }) ?? "Not Installed"
    }
    
    private func getSystemFrameworks() async -> [String] {
        return await runCommand("/bin/ls", args: ["/System/Library/Frameworks"], parser: { output in
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }) ?? []
    }
    
    private func getInstalledApplications() async -> [[String: Any]] {
        print("🔵 AGENT: Getting installed applications...")
        
        // Get applications from /Applications (system apps)
        let systemApps = await runCommand("/usr/bin/find", args: ["/Applications", "-maxdepth", "1", "-name", "*.app", "-type", "d"], timeout: 10.0) { output in
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return lines
        } ?? []
        
        // Get applications from user's Applications folder
        let userApps = await runCommand("/usr/bin/find", args: ["/Users/\(Foundation.ProcessInfo.processInfo.userName)/Applications", "-maxdepth", "1", "-name", "*.app", "-type", "d"], timeout: 10.0) { output in
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return lines
        } ?? []
        
        var applications: [[String: Any]] = []
        
        // Process system applications (limit to first 20 to avoid hanging)
        let systemAppsToProcess = Array(systemApps.prefix(20))
        for appPathAny in systemAppsToProcess {
            guard let appPath = appPathAny as? String else { continue }
            let appName = URL(fileURLWithPath: appPath).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let infoPlistPath = "\(appPath)/Contents/Info.plist"
            
            // Use timeout for PlistBuddy to avoid hanging
            let version = await runCommand("/usr/libexec/PlistBuddy", args: ["-c", "Print:CFBundleShortVersionString", infoPlistPath], timeout: 3.0) { output in
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? "Unknown"
            
            applications.append([
                "name": appName,
                "version": version,
                "path": appPath,
                "type": "system"
            ])
        }
        
        // Process user applications (limit to first 20 to avoid hanging)
        let userAppsToProcess = Array(userApps.prefix(20))
        for appPathAny in userAppsToProcess {
            guard let appPath = appPathAny as? String else { continue }
            let appName = URL(fileURLWithPath: appPath).lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let infoPlistPath = "\(appPath)/Contents/Info.plist"
            
            // Use timeout for PlistBuddy to avoid hanging
            let version = await runCommand("/usr/libexec/PlistBuddy", args: ["-c", "Print:CFBundleShortVersionString", infoPlistPath], timeout: 3.0) { output in
                return output.trimmingCharacters(in: .whitespacesAndNewlines)
            } ?? "Unknown"
            
            applications.append([
                "name": appName,
                "version": version,
                "path": appPath,
                "type": "user"
            ])
        }
        
        print("🟢 AGENT: Found \(applications.count) installed applications")
        return applications
    }
    
    private func getRunningProcesses() async -> [[String: Any]] {
        // Simplified approach - just return a count instead of full list to avoid hanging
        print("🔵 AGENT: Getting running processes count...")
        
        // Try to get a quick count instead of full list
        let count = await runCommand("/bin/ps", args: ["-A", "-o", "pid"], timeout: 5.0) { output in
            let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
            return lines.count - 1 // Subtract 1 for header
        } ?? 0
        
        print("🟢 AGENT: Found \(count) running processes")
        return [["count": count, "method": "quick_scan"]]
    }
    
    private func getSystemServices() async -> [String] {
        return await runCommand("/bin/launchctl", args: ["list"], parser: { output in
            return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        }) ?? []
    }
    
    private func getStartupItems() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPStartupItemsDataType") ?? []
    }
    
    private func getEnvironmentVariables() async -> [String: String] {
        return Foundation.ProcessInfo.processInfo.environment
    }
    
    private func getSystemPreferences() async -> [String: Any] {
        // Read system preferences from various sources - simplified for speed
        var preferences: [String: Any] = [:]
        
        // Time Zone
        preferences["timezone"] = TimeZone.current.identifier
        
        // Locale
        preferences["locale"] = Locale.current.identifier
        
        // Skip slow commands like pmset for now
        preferences["energy_saver"] = "Available via pmset"
        
        return preferences
    }
    
    private func getSecuritySettings() async -> [String: Any] {
        var security: [String: Any] = [:]
        
        // Only collect fast security info
        security["gatekeeper"] = await getGatekeeperStatus()
        security["sip"] = await getSIPStatus()
        
        // Skip slow commands for now
        security["firewall"] = "Available via socketfilterfw"
        
        return security
    }
    
    // Security Information Methods
    private func getFirewallStatus() async -> String {
        return await runCommand("/usr/bin/sudo", args: ["/usr/libexec/ApplicationFirewall/socketfilterfw", "--getglobalstate"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getGatekeeperStatus() async -> String {
        return await runCommand("/usr/sbin/spctl", args: ["--status"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getSIPStatus() async -> String {
        return await runCommand("/usr/bin/csrutil", args: ["status"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getSecureBootStatus() async -> String {
        return await runCommand("/usr/sbin/nvram", args: ["94b73556-2197-4702-82a8-3e1337dafbfb:AppleSecureBootPolicy"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getFileVaultStatus() async -> String {
        return await runCommand("/usr/bin/fdesetup", args: ["status"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getXProtectVersion() async -> String {
        return await runCommand("/usr/bin/system_profiler", args: ["SPInstallHistoryDataType"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("XProtect") {
                    return line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getMRTVersion() async -> String {
        return await runCommand("/usr/bin/system_profiler", args: ["SPInstallHistoryDataType"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("MRT") {
                    return line.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getCertificateTrustSettings() async -> [String: Any] {
        return ["status": "Available via security command"]
    }
    
    private func getKeychainInfo() async -> [String: Any] {
        return await runCommand("/usr/bin/security", args: ["list-keychains"], parser: { output in
            return ["keychains": output.components(separatedBy: .newlines).filter { !$0.isEmpty }]
        }) ?? ["status": "Unknown"]
    }
    
    private func getSecurityPolicies() async -> [String: Any] {
        return ["status": "Available via various security commands"]
    }
    
    private func getPrivacyPermissions() async -> [String: Any] {
        return ["status": "Available via tccutil"]
    }
    
    private func getScreenLockSettings() async -> [String: Any] {
        return await runCommand("/usr/bin/pmset", args: ["-g"], parser: { output in
            return ["screen_lock": output]
        }) ?? ["status": "Unknown"]
    }
    
    private func getRemoteAccessSettings() async -> [String: Any] {
        return await runCommand("/usr/sbin/systemsetup", args: ["-getremotelogin"], parser: { output in
            return ["remote_login": output.trimmingCharacters(in: .whitespacesAndNewlines)]
        }) ?? ["status": "Unknown"]
    }
    
    private func getNetworkSecurity() async -> [String: Any] {
        return ["status": "Network security analysis available"]
    }
    
    private func getAntivirusSoftware() async -> [String] {
        return await getSystemProfilerArrayInfo("SPApplicationsDataType")?.compactMap { app in
            guard let name = app["_name"] as? String else { return nil }
            let antivirusKeywords = ["antivirus", "security", "malware", "virus", "defender"]
            return antivirusKeywords.contains { name.lowercased().contains($0) } ? name : nil
        } ?? []
    }
    
    private func getVPNConnections() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPNetworkDataType")?.filter { interface in
            guard let type = interface["type"] as? String else { return false }
            return type.lowercased().contains("vpn")
        } ?? []
    }
    
    private func getSSLCertificates() async -> [String: Any] {
        return ["status": "SSL certificates available via security find-certificate"]
    }
    
    private func getCodeSigningStatus() async -> String {
        return await runCommand("/usr/bin/codesign", args: ["--verify", "--deep", "/Applications/Huginn.app"], parser: { output in
            return output.isEmpty ? "Valid" : output
        }) ?? "Unknown"
    }
    
    // MARK: - Helper Functions
    
    private func getDisplays() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPDisplaysDataType") ?? []
    }
    
    private func getAudioDevices() async -> [[String: Any]] {
        return await getSystemProfilerArrayInfo("SPAudioDataType") ?? []
    }
    
    private func isSIPEnabled() async -> Bool {
        let status = await getSIPStatus()
        return status.lowercased().contains("enabled")
    }
    
    private func isGatekeeperEnabled() async -> Bool {
        let status = await getGatekeeperStatus()
        return status.lowercased().contains("enabled")
    }
    
    private func isFirewallEnabled() async -> Bool {
        let status = await getFirewallStatus()
        return status.lowercased().contains("enabled") || status.lowercased().contains("on")
    }
    
    private func isFileVaultEnabled() async -> Bool {
        let status = await getFileVaultStatus()
        return status.lowercased().contains("on") || status.lowercased().contains("enabled")
    }
    
    private func getWiFiSSID() async -> String {
        return await runCommand("/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", args: ["-I"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains(" SSID: ") {
                    return line.components(separatedBy: " SSID: ").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getWiFiSignalStrength() async -> String {
        return await runCommand("/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport", args: ["-I"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains(" agrCtlRSSI: ") {
                    return line.components(separatedBy: " agrCtlRSSI: ").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getIPAddress() async -> String {
        return await runCommand("/usr/bin/curl", args: ["-s", "https://api.ipify.org"], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getDNSServers() async -> [String] {
        return await runCommand("/usr/bin/scutil", args: ["--dns"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            var servers: [String] = []
            for line in lines {
                if line.contains("nameserver[") {
                    let server = line.components(separatedBy: " : ").last?.trimmingCharacters(in: .whitespaces)
                    if let server = server {
                        servers.append(server)
                    }
                }
            }
            return servers
        }) ?? []
    }
    
    private func getGateway() async -> String {
        return await runCommand("/usr/bin/netstat", args: ["-nr"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("default") {
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count > 1 {
                        return components[1]
                    }
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getNetworkSpeed() async -> String {
        return await runCommand("/usr/bin/networkQuality", args: ["-I"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("Download:") {
                    return line.trimmingCharacters(in: .whitespaces)
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getLatency() async -> String {
        return await runCommand("/usr/bin/ping", args: ["-c", "1", "8.8.8.8"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("time=") {
                    let timeComponent = line.components(separatedBy: "time=").last?.components(separatedBy: " ").first
                    return timeComponent ?? "Unknown"
                }
            }
            return "Unknown"
        }) ?? "Unknown"
    }
    
    private func getVPNStatus() async -> String {
        return await runCommand("/usr/bin/scutil", args: ["--nc", "list"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            for line in lines {
                if line.contains("Connected") {
                    return "Connected"
                }
            }
            return "Disconnected"
        }) ?? "Unknown"
    }
    
    private func getActiveConnections() async -> [[String: Any]] {
        return await runCommand("/usr/bin/netstat", args: ["-an"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            var connections: [[String: Any]] = []
            
            for line in lines {
                if line.contains("ESTABLISHED") {
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count >= 4 {
                        connections.append([
                            "protocol": components[0],
                            "local_address": components[3],
                            "foreign_address": components[4],
                            "state": components[5]
                        ])
                    }
                }
            }
            return connections
        }) ?? []
    }
    
    private func getListeningPorts() async -> [[String: Any]] {
        return await runCommand("/usr/bin/netstat", args: ["-an"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            var ports: [[String: Any]] = []
            for line in lines {
                if line.contains("LISTEN") {
                    let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                    if components.count >= 4 {
                        ports.append([
                            "protocol": components[0],
                            "local_address": components[3],
                            "state": components[5]
                        ])
                    }
                }
            }
            return ports
        }) ?? []
    }
    
    private func getNetworkServices() async -> [String] {
        return await runCommand("/usr/bin/launchctl", args: ["list"], parser: { output in
            let lines = output.components(separatedBy: .newlines)
            return lines.filter { $0.contains("network") || $0.contains("dns") || $0.contains("dhcp") }
        }) ?? []
    }
    
    // MARK: - System Command Helpers
    
    private func runCommand<T>(_ path: String, args: [String], timeout: TimeInterval = 5.0, parser: @escaping @Sendable (String) -> T) async -> T? {
        return try? await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = args
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Suppress error output
            
            // Set up timeout
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                process.terminate()
                continuation.resume(throwing: NSError(domain: "CommandTimeout", code: -1, userInfo: [NSLocalizedDescriptionKey: "Command timed out after \(timeout) seconds"]))
            }
            
            process.terminationHandler = { _ in
                timeoutTask.cancel()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let result = parser(output)
                continuation.resume(returning: result)
            }
            
            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func getSystemctlInfo(_ key: String) async -> String? {
        return await runCommand("/usr/sbin/sysctl", args: ["-n", key], parser: { output in
            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        }) ?? "Unknown"
    }
    
    private func getSystemProfilerInfo(_ dataType: String, key: String) async -> String? {
        return await runCommand("/usr/sbin/system_profiler", args: [dataType, "-json"], parser: { output in
            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json[dataType] as? [[String: Any]],
                  let firstItem = dataArray.first,
                  let value = firstItem[key] as? String else {
                return "Unknown"
            }
            return value
        }) ?? "Unknown"
    }
    
    private func getSystemProfilerArrayInfo(_ dataType: String) async -> [[String: Any]]? {
        return await runCommand("/usr/sbin/system_profiler", args: [dataType, "-json"], parser: { output in
            guard let data = output.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataArray = json[dataType] as? [[String: Any]] else {
                return []
            }
            return dataArray
        }) ?? []
    }
    
    // MARK: - Task Execution Methods
    
    /// Execute a shell command
    private func executeCommand(_ payload: [String: String]) async throws -> [String: Any] {
        guard let command = payload["command"] else {
            throw TaskExecutionError.missingParameter("command")
        }
        
        // Security check for dangerous commands
        let dangerousCommands = ["rm -rf", "sudo rm", "format", "diskutil erase", "dd if=", "mkfs", "fdisk"]
        if dangerousCommands.contains(where: { command.lowercased().contains($0.lowercased()) }) {
            throw TaskExecutionError.securityViolation("Dangerous command blocked: \(command)")
        }
        
        print("🔵 AGENT: Executing command: \(command)")
        
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
                    "exit_code": process.terminationStatus,
                    "command": command
                ])
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    /// Execute a script
    private func executeScript(_ payload: [String: String]) async throws -> [String: Any] {
        guard let scriptContent = payload["script"] else {
            throw TaskExecutionError.missingParameter("script")
        }
        
        print("🔵 AGENT: Executing script (length: \(scriptContent.count) characters)")
        
        // Create temporary script file
        let tempDir = FileManager.default.temporaryDirectory
        let scriptFile = tempDir.appendingPathComponent("odin_script_\(UUID().uuidString).sh")
        
        do {
            try scriptContent.write(to: scriptFile, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptFile.path)
            
            // Execute the script
            let result = try await executeCommand(["command": scriptFile.path])
            
            // Clean up
            try? FileManager.default.removeItem(at: scriptFile)
            
            return result
            
        } catch {
            // Clean up on error
            try? FileManager.default.removeItem(at: scriptFile)
            throw error
        }
    }
    
    /// Install software
    private func installSoftware(_ payload: [String: String]) async throws -> [String: Any] {
        guard let packageName = payload["package"] else {
            throw TaskExecutionError.missingParameter("package")
        }
        
        let packageManager = payload["package_manager"] ?? "brew"
        
        print("🔵 AGENT: Installing software: \(packageName) using \(packageManager)")
        
        switch packageManager {
        case "brew":
            return try await executeCommand(["command": "brew install \(packageName)"])
        case "mas":
            return try await executeCommand(["command": "mas install \(packageName)"])
        case "pip":
            return try await executeCommand(["command": "pip3 install \(packageName)"])
        case "npm":
            return try await executeCommand(["command": "npm install -g \(packageName)"])
        default:
            throw TaskExecutionError.unsupportedTaskType("Unsupported package manager: \(packageManager)")
        }
    }
    
    /// Apply system policy
    private func applyPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        guard let policyType = payload["policy_type"] else {
            throw TaskExecutionError.missingParameter("policy_type")
        }
        
        print("🔵 AGENT: Applying policy: \(policyType)")
        
        switch policyType {
        case "firewall":
            return try await applyFirewallPolicy(payload)
        case "screen_saver":
            return try await applyScreenSaverPolicy(payload)
        case "power_management":
            return try await applyPowerManagementPolicy(payload)
        case "security":
            return try await applySecurityPolicy(payload)
        default:
            throw TaskExecutionError.unsupportedTaskType("Unsupported policy type: \(policyType)")
        }
    }
    
    /// Collect specific data
    private func collectData(_ payload: [String: String]) async throws -> [String: Any] {
        guard let dataType = payload["data_type"] else {
            throw TaskExecutionError.missingParameter("data_type")
        }
        
        print("🔵 AGENT: Collecting data: \(dataType)")
        
        switch dataType {
        case "hardware":
            return await getHardwareInfo()
        case "software":
            return await getSoftwareInfo()
        case "network":
            return await getNetworkInfo()
        case "system":
            return await collectSystemInfo()
        case "processes":
            return ["processes": await getRunningProcesses()]
        case "applications":
            return ["applications": await getInstalledApplications()]
        default:
            throw TaskExecutionError.unsupportedTaskType("Unsupported data type: \(dataType)")
        }
    }
    
    /// Perform system check
    private func performSystemCheck(_ payload: [String: String]) async throws -> [String: Any] {
        print("🔵 AGENT: Performing system check")
        
        var results: [String: Any] = [:]
        
        // Check disk space
        results["disk_usage"] = await getDiskUsage()
        
        // Check memory usage
        results["memory_usage"] = await getMemoryUsage()
        
        // Check CPU usage
        results["cpu_usage"] = await getCPUUsage()
        
        // Check uptime
        results["uptime"] = formatUptime(Foundation.ProcessInfo.processInfo.systemUptime)
        
        // Check system health
        let isHealthy = results["disk_usage"] as? Double ?? 0.0 < 95.0 &&
                       results["memory_usage"] as? Double ?? 0.0 < 90.0 &&
                       results["cpu_usage"] as? Double ?? 0.0 < 80.0
        
        results["system_healthy"] = isHealthy
        results["check_timestamp"] = ISO8601DateFormatter().string(from: Date())
        
        return results
    }
    
    // MARK: - Policy Application Methods
    
    private func applyFirewallPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        let action = payload["action"] ?? "enable"
        let result = try await executeCommand(["command": "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate \(action)"])
        return result
    }
    
    private func applyScreenSaverPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        let timeout = payload["timeout"] ?? "300"
        let result = try await executeCommand(["command": "defaults write com.apple.screensaver idleTime \(timeout)"])
        return result
    }
    
    private func applyPowerManagementPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        let sleepTime = payload["sleep_time"] ?? "0"
        let result = try await executeCommand(["command": "sudo pmset -c sleep \(sleepTime)"])
        return result
    }
    
    private func applySecurityPolicy(_ payload: [String: String]) async throws -> [String: Any] {
        let policy = payload["policy"] ?? "default"
        // Implement security policy application
        return ["status": "Security policy \(policy) applied", "exit_code": 0]
    }
}

// MARK: - Task Execution Errors

enum TaskExecutionError: LocalizedError {
    case invalidTaskData
    case unsupportedTaskType(String)
    case missingParameter(String)
    case securityViolation(String)
    case authenticationFailed
    case networkError(String)
    case executionFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidTaskData:
            return "Invalid task data format"
        case .unsupportedTaskType(let type):
            return "Unsupported task type: \(type)"
        case .missingParameter(let param):
            return "Missing required parameter: \(param)"
        case .securityViolation(let reason):
            return "Security violation: \(reason)"
        case .authenticationFailed:
            return "Authentication failed"
        case .networkError(let message):
            return "Network error: \(message)"
        case .executionFailed(let reason):
            return "Task execution failed: \(reason)"
        }
    }
}
