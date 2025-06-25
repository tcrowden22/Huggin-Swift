import Foundation

@MainActor
class OdinSettings: ObservableObject {
    @Published var baseURL: String = "https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1"
    @Published var enrollmentToken: String = ""
    @Published var isEnabled: Bool = false
    @Published var taskPollInterval: Int = 60 // seconds
    @Published var telemetryInterval: Int = 900 // seconds (15 minutes)
    @Published var autoStart: Bool = true
    @Published var enableLogging: Bool = true
    @Published var logLevel: LogLevel = .info
    
    // Connection status
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var lastConnectionAttempt: Date?
    @Published var lastSuccessfulConnection: Date?
    @Published var connectionError: String?
    @Published var lastError: String?
    
    // Agent information
    @Published var agentId: String?
    @Published var isAuthenticated: Bool = false
    @Published var tokenExpiry: Date?
    
    enum LogLevel: String, CaseIterable, Identifiable {
        case debug = "DEBUG"
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
        
        var id: String { rawValue }
        
        var displayName: String {
            switch self {
            case .debug: return "Debug"
            case .info: return "Info"
            case .warn: return "Warning"
            case .error: return "Error"
            }
        }
    }
    
    enum ConnectionStatus: String, CaseIterable {
        case disconnected = "disconnected"
        case connecting = "connecting"
        case connected = "connected"
        case error = "error"
        case authenticating = "authenticating"
        case authenticated = "authenticated"
        
        var displayName: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error: return "Connection Error"
            case .authenticating: return "Authenticating..."
            case .authenticated: return "Authenticated"
            }
        }
        
        var color: String {
            switch self {
            case .disconnected, .error: return "red"
            case .connecting, .authenticating: return "orange"
            case .connected, .authenticated: return "green"
            }
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "odin_settings"
    
    init() {
        loadSettings()
    }
    
    // MARK: - Persistence
    
    func saveSettings() {
        let settings: [String: Any] = [
            "baseURL": baseURL,
            "enrollmentToken": enrollmentToken,
            "isEnabled": isEnabled,
            "taskPollInterval": taskPollInterval,
            "telemetryInterval": telemetryInterval,
            "autoStart": autoStart,
            "enableLogging": enableLogging,
            "logLevel": logLevel.rawValue,
            "agentId": agentId ?? "",
            "lastConnectionAttempt": lastConnectionAttempt?.timeIntervalSince1970 ?? 0,
            "lastSuccessfulConnection": lastSuccessfulConnection?.timeIntervalSince1970 ?? 0
        ]
        
        userDefaults.set(settings, forKey: settingsKey)
        userDefaults.synchronize()
    }
    
    private func loadSettings() {
        guard let settings = userDefaults.dictionary(forKey: settingsKey) else { return }
        
        baseURL = settings["baseURL"] as? String ?? baseURL
        enrollmentToken = settings["enrollmentToken"] as? String ?? enrollmentToken
        isEnabled = settings["isEnabled"] as? Bool ?? isEnabled
        taskPollInterval = settings["taskPollInterval"] as? Int ?? taskPollInterval
        telemetryInterval = settings["telemetryInterval"] as? Int ?? telemetryInterval
        autoStart = settings["autoStart"] as? Bool ?? autoStart
        enableLogging = settings["enableLogging"] as? Bool ?? enableLogging
        
        if let logLevelString = settings["logLevel"] as? String {
            logLevel = LogLevel(rawValue: logLevelString) ?? .info
        }
        
        agentId = settings["agentId"] as? String
        if agentId?.isEmpty == true { agentId = nil }
        
        if let lastAttemptTime = settings["lastConnectionAttempt"] as? TimeInterval, lastAttemptTime > 0 {
            lastConnectionAttempt = Date(timeIntervalSince1970: lastAttemptTime)
        }
        
        if let lastSuccessTime = settings["lastSuccessfulConnection"] as? TimeInterval, lastSuccessTime > 0 {
            lastSuccessfulConnection = Date(timeIntervalSince1970: lastSuccessTime)
        }
    }
    
    // MARK: - Validation
    
    var isValidConfiguration: Bool {
        return !baseURL.isEmpty && 
               URL(string: baseURL) != nil &&
               (!isEnabled || !enrollmentToken.isEmpty)
    }
    
    var configurationErrors: [String] {
        var errors: [String] = []
        
        if baseURL.isEmpty {
            errors.append("Base URL is required")
        } else if URL(string: baseURL) == nil {
            errors.append("Base URL is not valid")
        }
        
        if isEnabled && enrollmentToken.isEmpty {
            errors.append("Enrollment token is required when ODIN is enabled")
        }
        
        if taskPollInterval < 10 {
            errors.append("Task poll interval must be at least 10 seconds")
        }
        
        if telemetryInterval < 60 {
            errors.append("Telemetry interval must be at least 60 seconds")
        }
        
        return errors
    }
    
    // MARK: - Connection Management
    
    func updateConnectionStatus(_ status: ConnectionStatus, error: String? = nil) {
        connectionStatus = status
        connectionError = error
        lastConnectionAttempt = Date()
        
        if status == .authenticated {
            lastSuccessfulConnection = Date()
            isAuthenticated = true
        } else if status == .disconnected || status == .error {
            isAuthenticated = false
        }
        
        saveSettings()
    }
    
    func updateAgentInfo(agentId: String?, tokenExpiry: Date?) {
        self.agentId = agentId
        self.tokenExpiry = tokenExpiry
        saveSettings()
    }
    
    func updateLastConnection(_ date: Date) {
        self.lastSuccessfulConnection = date
        saveSettings()
    }
    
    func clearAgentInfo() {
        self.agentId = nil
        self.isAuthenticated = false
        self.tokenExpiry = nil
        saveSettings()
    }
    
    // MARK: - Reset Functions
    
    func resetToDefaults() {
        baseURL = "https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1"
        enrollmentToken = ""
        isEnabled = false
        taskPollInterval = 60
        telemetryInterval = 900
        autoStart = true
        enableLogging = true
        logLevel = .info
        
        // Clear connection info
        connectionStatus = .disconnected
        lastConnectionAttempt = nil
        lastSuccessfulConnection = nil
        connectionError = nil
        agentId = nil
        isAuthenticated = false
        tokenExpiry = nil
        
        saveSettings()
    }
    
    func clearCredentials() {
        // Clear agent credentials but keep enrollment token for future enrollments
        agentId = nil
        isAuthenticated = false
        tokenExpiry = nil
        connectionStatus = .disconnected
        connectionError = nil
        
        // Also clear from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "huginn-odin-agent"
        ]
        SecItemDelete(query as CFDictionary)
        
        saveSettings()
    }
    
    func clearAllCredentials() {
        // Clear everything including enrollment token
        enrollmentToken = ""
        agentId = nil
        isAuthenticated = false
        tokenExpiry = nil
        connectionStatus = .disconnected
        connectionError = nil
        
        // Also clear from keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "huginn-odin-agent"
        ]
        SecItemDelete(query as CFDictionary)
        
        saveSettings()
    }
    
    func generateNewEnrollmentToken() {
        // Generate a new 64-character hexadecimal enrollment token
        let characters = "abcdef0123456789"
        enrollmentToken = String((0..<64).map { _ in characters.randomElement()! })
        
        print("🔵 SETTINGS: Generated new enrollment token: \(String(enrollmentToken.prefix(8)))...")
        saveSettings()
    }
    
    // MARK: - Convenience Properties
    
    var isConnected: Bool {
        return connectionStatus == .connected || connectionStatus == .authenticated
    }
    
    var statusDisplayText: String {
        if let error = connectionError, connectionStatus == .error {
            return "Error: \(error)"
        }
        return connectionStatus.displayName
    }
    
    var formattedLastConnection: String {
        guard let lastConnection = lastSuccessfulConnection else {
            return "Never"
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastConnection, relativeTo: Date())
    }
    
    var tokenExpiryText: String {
        guard let expiry = tokenExpiry else {
            return "No token"
        }
        
        let timeUntilExpiry = expiry.timeIntervalSinceNow
        if timeUntilExpiry < 0 {
            return "Expired"
        } else if timeUntilExpiry < 300 { // 5 minutes
            return "Expiring soon"
        } else {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Expires \(formatter.localizedString(for: expiry, relativeTo: Date()))"
        }
    }
} 