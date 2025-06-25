import Foundation
import Security

/// Simplified serial number-based authentication manager for ODIN agents
class OdinSerialAuthManager: ObservableObject, @unchecked Sendable {
    
    // MARK: - Published Properties
    @Published var isEnrolled: Bool = false
    @Published var serialNumber: String?
    @Published var enrollmentDate: Date?
    @Published var lastCheckIn: Date?
    @Published var enrollmentToken: String?
    
    // MARK: - Constants
    private let keychainService = "huginn-odin-agent"
    private let keychainAccount = "agent-serial"
    private let storageKey = "odin_agent_serial_data"
    
    // MARK: - Data Models
    
    struct AgentRegistration: Codable, Sendable {
        let serialNumber: String
        let enrollmentDate: Date
        let hostname: String
        let platform: String
        let agentVersion: String
        let enrollmentToken: String
        
        init(serialNumber: String, hostname: String, platform: String, enrollmentToken: String, agentVersion: String = "3.0.0") {
            self.serialNumber = serialNumber
            self.enrollmentDate = Date()
            self.hostname = hostname
            self.platform = platform
            self.enrollmentToken = enrollmentToken
            self.agentVersion = agentVersion
        }
    }
    
    enum AuthError: LocalizedError {
        case noSerialNumber
        case enrollmentRequired
        case invalidResponse
        case keychainError(OSStatus)
        case networkError(Error)
        case agentNotFound
        
        var errorDescription: String? {
            switch self {
            case .noSerialNumber:
                return "Device serial number not found"
            case .enrollmentRequired:
                return "Agent enrollment required"
            case .invalidResponse:
                return "Invalid server response"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .agentNotFound:
                return "Agent not found - re-enrollment required"
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadStoredRegistration()
        }
    }
    
    // MARK: - Public Methods
    
    /// Check if agent is enrolled and ready
    func isAgentReady() async -> Bool {
        return isEnrolled && serialNumber != nil
    }
    
    /// Get the current serial number for API requests
    func getSerialNumber() async throws -> String {
        guard let serialNumber = serialNumber else {
            throw AuthError.enrollmentRequired
        }
        return serialNumber
    }
    
    /// Get the enrollment token for API requests
    func getEnrollmentToken() throws -> String {
        print("🔵 SERIAL: Getting enrollment token...")
        print("🔵 SERIAL: enrollmentToken is nil: \(enrollmentToken == nil)")
        if let token = enrollmentToken {
            print("🔵 SERIAL: Found enrollment token: \(token.prefix(8))...")
            return token
        } else {
            print("🔴 SERIAL: No enrollment token found")
            throw AuthError.enrollmentRequired
        }
    }
    
    /// Store agent registration after successful enrollment
    func storeRegistration(_ registration: AgentRegistration) async {
        print("🟢 SERIAL: Storing agent registration for serial: \(registration.serialNumber)")
        print("🔵 SERIAL: Enrollment token: \(registration.enrollmentToken.prefix(8))...")
        
        self.serialNumber = registration.serialNumber
        self.enrollmentDate = registration.enrollmentDate
        self.isEnrolled = true
        self.lastCheckIn = Date()
        self.enrollmentToken = registration.enrollmentToken
        
        await saveToKeychain(registration)
        
        print("🟢 SERIAL: Agent registration stored successfully")
        print("🔵 SERIAL: Serial Number: \(registration.serialNumber)")
        print("🔵 SERIAL: Enrolled: \(formatDate(registration.enrollmentDate))")
        print("🔵 SERIAL: Token stored: \(self.enrollmentToken?.prefix(8) ?? "nil")...")
    }
    
    /// Update last check-in time
    func updateLastCheckIn() {
        lastCheckIn = Date()
    }
    
    /// Clear agent registration (for re-enrollment)
    func clearRegistration() async {
        print("🔵 SERIAL: Clearing agent registration")
        
        serialNumber = nil
        enrollmentDate = nil
        lastCheckIn = nil
        isEnrolled = false
        enrollmentToken = nil
        
        await deleteFromKeychain()
        
        print("🟢 SERIAL: Agent registration cleared")
    }
    
    /// Get registration status summary
    func getRegistrationStatus() async -> (enrolled: Bool, serialNumber: String?, daysSinceEnrollment: Int) {
        let days = enrollmentDate?.timeIntervalSinceNow.magnitude ?? 0
        let daysSince = Int(days / (24 * 3600))
        
        return (
            enrolled: isEnrolled,
            serialNumber: serialNumber,
            daysSinceEnrollment: daysSince
        )
    }
    
    /// Get device serial number from system
    func getDeviceSerialNumber() async -> String? {
        return await getSystemInfo(for: "IOPlatformSerialNumber")
    }
    
    // MARK: - Private Methods
    
    private func loadStoredRegistration() async {
        print("🔵 SERIAL: Loading stored agent registration")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess, let data = result as? Data {
            do {
                let registration = try JSONDecoder().decode(AgentRegistration.self, from: data)
                
                self.serialNumber = registration.serialNumber
                self.enrollmentDate = registration.enrollmentDate
                self.isEnrolled = true
                self.enrollmentToken = registration.enrollmentToken
                
                print("🟢 SERIAL: Loaded registration for serial: \(registration.serialNumber)")
                print("🔵 SERIAL: Enrolled: \(formatDate(registration.enrollmentDate))")
                print("🔵 SERIAL: Token loaded: \(self.enrollmentToken?.prefix(8) ?? "nil")...")
                
            } catch {
                print("🔴 SERIAL: Failed to decode registration: \(error)")
                await clearRegistration()
            }
        } else if status == errSecItemNotFound {
            print("🔵 SERIAL: No stored registration found")
        } else {
            print("🔴 SERIAL: Keychain error loading registration: \(status)")
        }
    }
    
    private func saveToKeychain(_ registration: AgentRegistration) async {
        print("🔵 SERIAL: Saving registration to keychain")
        
        do {
            let data = try JSONEncoder().encode(registration)
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: keychainService,
                kSecAttrAccount as String: keychainAccount,
                kSecValueData as String: data
            ]
            
            // Delete existing item first
            SecItemDelete(query as CFDictionary)
            
            // Add new item
            let status = SecItemAdd(query as CFDictionary, nil)
            
            if status == errSecSuccess {
                print("🟢 SERIAL: Registration saved to keychain successfully")
            } else {
                print("🔴 SERIAL: Failed to save registration to keychain: \(status)")
            }
        } catch {
            print("🔴 SERIAL: Failed to encode registration: \(error)")
        }
    }
    
    private func deleteFromKeychain() async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status == errSecSuccess || status == errSecItemNotFound {
            print("🟢 SERIAL: Registration deleted from keychain")
        } else {
            print("🔴 SERIAL: Failed to delete registration from keychain: \(status)")
        }
    }
    
    private func getSystemInfo(for key: String) async -> String? {
        // Try multiple methods to get serial number
        
        // Method 1: Try sysctl with IOPlatformSerialNumber
        if let serial = await trySystemctl("hw.serialnumber") {
            return serial
        }
        
        // Method 2: Try system_profiler
        if let serial = await trySystemProfiler() {
            return serial
        }
        
        // Method 3: Try ioreg
        if let serial = await tryIOreg() {
            return serial
        }
        
        print("🔴 SERIAL: All serial number detection methods failed")
        return nil
    }
    
    private func trySystemctl(_ key: String) async -> String? {
        return try? await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/sysctl")
            process.arguments = ["-n", key]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Suppress error output
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                
                if let output = output, !output.isEmpty && output != "unknown" {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func trySystemProfiler() async -> String? {
        return try? await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPHardwareDataType", "-json"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let spHardware = json["SPHardwareDataType"] as? [[String: Any]],
                       let hardware = spHardware.first,
                       let serialNumber = hardware["serial_number"] as? String {
                        continuation.resume(returning: serialNumber)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    continuation.resume(returning: nil)
                }
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func tryIOreg() async -> String? {
        return try? await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
            process.arguments = ["-l", "-k", "IOPlatformSerialNumber"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                
                // Parse ioreg output for serial number
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    if line.contains("IOPlatformSerialNumber") {
                        // Extract serial number from line like: "IOPlatformSerialNumber" = "C02ABC123DEF"
                        let components = line.components(separatedBy: "\"")
                        if components.count >= 4 {
                            let serial = components[3]
                            if !serial.isEmpty {
                                continuation.resume(returning: serial)
                                return
                            }
                        }
                    }
                }
                
                continuation.resume(returning: nil)
            }
            
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
} 