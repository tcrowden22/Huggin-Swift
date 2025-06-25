import Foundation
import Security

/// Modern token management system for ODIN agents with 30-day refresh cycle
class OdinTokenManager: ObservableObject, @unchecked Sendable {
    
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var agentId: String?
    @Published var tokenExpiryDate: Date?
    @Published var refreshTokenExpiryDate: Date?
    @Published var lastRefresh: Date?
    
    // MARK: - Constants
    private let keychainService = "huginn-odin-agent"
    private let keychainAccount = "agent-credentials"
    private let accessTokenLifetime: TimeInterval = 60 * 60 // 1 hour
    private let refreshTokenLifetime: TimeInterval = 30 * 24 * 60 * 60 // 30 days
    private let refreshBuffer: TimeInterval = 5 * 60 // 5 minutes before expiry
    private let rotationBuffer: TimeInterval = 24 * 60 * 60 // 1 day before 30-day expiry
    
    // MARK: - Private Properties
    private var refreshTimer: Timer?
    private var rotationTimer: Timer?
    internal var currentCredentials: TokenCredentials?
    private var networkService: OdinNetworkServiceV3?
    
    // MARK: - Data Models
    
    struct TokenCredentials: Codable {
        let accessToken: String
        let refreshToken: String
        let agentId: String
        let accessTokenExpiresAt: Date
        let refreshTokenExpiresAt: Date
        let issuedAt: Date
        
        // For JWT tokens, we need to decode the expiration from the token itself
        var isAccessTokenExpired: Bool {
            return Date() >= accessTokenExpiresAt
        }
        
        var isRefreshTokenExpired: Bool {
            return Date() >= refreshTokenExpiresAt
        }
        
        var needsAccessTokenRefresh: Bool {
            return Date() >= accessTokenExpiresAt.addingTimeInterval(-300) // 5 minutes buffer
        }
        
        var daysUntilRefreshExpiry: Int {
            let days = refreshTokenExpiresAt.timeIntervalSinceNow / (24 * 60 * 60)
            return max(0, Int(days))
        }
        
        init(accessToken: String, refreshToken: String, agentId: String, accessTokenExpiresAt: Date, refreshTokenExpiresAt: Date) {
            self.accessToken = accessToken
            self.refreshToken = refreshToken
            self.agentId = agentId
            self.accessTokenExpiresAt = accessTokenExpiresAt
            self.refreshTokenExpiresAt = refreshTokenExpiresAt
            self.issuedAt = Date()
        }
    }
    
    enum TokenError: LocalizedError {
        case noCredentials
        case expiredRefreshToken
        case invalidTokenFormat
        case keychainError(OSStatus)
        case networkError(Error)
        case invalidResponse
        
        var errorDescription: String? {
            switch self {
            case .noCredentials:
                return "No valid credentials found"
            case .expiredRefreshToken:
                return "Refresh token has expired"
            case .invalidTokenFormat:
                return "Token format is invalid"
            case .keychainError(let status):
                return "Keychain error: \(status)"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .invalidResponse:
                return "Invalid server response"
            }
        }
    }
    
    // MARK: - Initialization
    
    init() {
        Task {
            await loadStoredCredentials()
            await setupAutomaticRefresh()
        }
    }
    
    // MARK: - Public Methods
    
    /// Set the network service for token refresh operations
    func setNetworkService(_ networkService: OdinNetworkServiceV3) {
        self.networkService = networkService
        print("🔵 TOKEN: Network service configured for token refresh")
    }
    
    /// Store new credentials after successful enrollment
    func storeCredentials(_ credentials: TokenCredentials) async {
        print("🟢 TOKEN: Storing new credentials for agent: \(credentials.agentId)")
        
        self.currentCredentials = credentials
        self.agentId = credentials.agentId
        self.isAuthenticated = true
        self.tokenExpiryDate = credentials.accessTokenExpiresAt
        self.refreshTokenExpiryDate = credentials.refreshTokenExpiresAt
        self.lastRefresh = Date()
        
        await saveToKeychain(credentials)
        await setupAutomaticRefresh()
        
        print("🟢 TOKEN: Credentials stored successfully")
        print("🔵 TOKEN: Access token expires: \(formatDate(credentials.accessTokenExpiresAt))")
        print("🔵 TOKEN: Refresh token expires: \(formatDate(credentials.refreshTokenExpiresAt))")
    }
    
    /// Get current access token for API requests
    func getAccessToken() async throws -> String {
        guard let credentials = currentCredentials else {
            throw TokenError.noCredentials
        }
        
        // Check if token needs refresh
        if credentials.needsAccessTokenRefresh {
            print("🔄 TOKEN: Access token needs refresh")
            try await refreshAccessToken()
        }
        
        guard let updatedCredentials = currentCredentials else {
            throw TokenError.noCredentials
        }
        
        return updatedCredentials.accessToken
    }
    
    /// Manual token refresh
    func refreshAccessToken() async throws {
        guard let credentials = currentCredentials else {
            throw TokenError.noCredentials
        }
        
        if credentials.isRefreshTokenExpired {
            print("🔴 TOKEN: Refresh token has expired - re-enrollment required")
            await clearCredentials()
            throw TokenError.expiredRefreshToken
        }
        
        print("🔄 TOKEN: Refreshing access token...")
        
        // Make API call to refresh token
        let refreshResponse = try await makeTokenRefreshRequest(refreshToken: credentials.refreshToken, agentId: credentials.agentId)
        
        // Parse response
        guard let accessToken = refreshResponse["access_token"] as? String,
              let agentId = refreshResponse["agent_id"] as? String else {
            throw TokenError.invalidResponse
        }
        
        // Parse optional new refresh token and expiry dates
        let newRefreshToken = refreshResponse["refresh_token"] as? String ?? credentials.refreshToken
        
        let accessTokenExpiry: Date
        if let expiresAtString = refreshResponse["expires_at"] as? String,
           let expiryDate = ISO8601DateFormatter().date(from: expiresAtString) {
            accessTokenExpiry = expiryDate
        } else {
            accessTokenExpiry = Date().addingTimeInterval(accessTokenLifetime)
        }
        
        let refreshTokenExpiry: Date
        if let refreshExpiresAtString = refreshResponse["refresh_expires_at"] as? String,
           let refreshExpiryDate = ISO8601DateFormatter().date(from: refreshExpiresAtString) {
            refreshTokenExpiry = refreshExpiryDate
        } else {
            refreshTokenExpiry = credentials.refreshTokenExpiresAt
        }
        
        // Create new credentials
        let newCredentials = TokenCredentials(
            accessToken: accessToken,
            refreshToken: newRefreshToken,
            agentId: agentId,
            accessTokenExpiresAt: accessTokenExpiry,
            refreshTokenExpiresAt: refreshTokenExpiry
        )
        
        await storeCredentials(newCredentials)
        print("🟢 TOKEN: Access token refreshed successfully")
    }
    
    /// Rotate refresh token (30-day cycle)
    func rotateRefreshToken() async throws {
        guard let credentials = currentCredentials else {
            throw TokenError.noCredentials
        }
        
        print("🔄 TOKEN: Starting 30-day refresh token rotation...")
        
        // Use the same refresh endpoint for rotation
        let rotationResponse = try await makeTokenRefreshRequest(refreshToken: credentials.refreshToken, agentId: credentials.agentId)
        
        // Parse response
        guard let accessToken = rotationResponse["access_token"] as? String,
              let refreshToken = rotationResponse["refresh_token"] as? String,
              let agentId = rotationResponse["agent_id"] as? String else {
            throw TokenError.invalidResponse
        }
        
        // Parse expiry dates
        let accessTokenExpiry: Date
        if let expiresAtString = rotationResponse["expires_at"] as? String,
           let expiryDate = ISO8601DateFormatter().date(from: expiresAtString) {
            accessTokenExpiry = expiryDate
        } else {
            accessTokenExpiry = Date().addingTimeInterval(accessTokenLifetime)
        }
        
        let refreshTokenExpiry: Date
        if let refreshExpiresAtString = rotationResponse["refresh_expires_at"] as? String,
           let refreshExpiryDate = ISO8601DateFormatter().date(from: refreshExpiresAtString) {
            refreshTokenExpiry = refreshExpiryDate
        } else {
            refreshTokenExpiry = Date().addingTimeInterval(refreshTokenLifetime)
        }
        
        // Create new credentials with fresh refresh token
        let newCredentials = TokenCredentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            agentId: agentId,
            accessTokenExpiresAt: accessTokenExpiry,
            refreshTokenExpiresAt: refreshTokenExpiry
        )
        
        await storeCredentials(newCredentials)
        print("🟢 TOKEN: Refresh token rotated successfully")
    }
    
    /// Clear all credentials and reset state
    func clearCredentials() async {
        print("🔵 TOKEN: Clearing all credentials")
        
        stopTimers()
        
        currentCredentials = nil
        isAuthenticated = false
        agentId = nil
        tokenExpiryDate = nil
        refreshTokenExpiryDate = nil
        lastRefresh = nil
        
        await deleteFromKeychain()
        
        print("🟢 TOKEN: Credentials cleared successfully")
    }
    
    /// Stop all timers safely
    private func stopTimers() {
        refreshTimer?.invalidate()
        rotationTimer?.invalidate()
        refreshTimer = nil
        rotationTimer = nil
    }
    
    /// Public cleanup method for proper resource management
    func cleanup() {
        stopTimers()
    }
    
    /// Check if current credentials are valid
    func hasValidCredentials() async -> Bool {
        guard let credentials = currentCredentials else { return false }
        return !credentials.isRefreshTokenExpired
    }
    
    /// Get credential status summary
    func getCredentialStatus() -> (accessValid: Bool, refreshValid: Bool, daysUntilExpiry: Int) {
        guard let credentials = currentCredentials else {
            return (accessValid: false, refreshValid: false, daysUntilExpiry: 0)
        }
        
        return (
            accessValid: !credentials.isAccessTokenExpired,
            refreshValid: !credentials.isRefreshTokenExpired,
            daysUntilExpiry: credentials.daysUntilRefreshExpiry
        )
    }
    
    // MARK: - Private Methods
    
    private func loadStoredCredentials() async {
        print("🔵 TOKEN: Loading stored credentials from keychain")
        
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
                let credentials = try JSONDecoder().decode(TokenCredentials.self, from: data)
                
                if !credentials.isRefreshTokenExpired {
                    self.currentCredentials = credentials
                    self.agentId = credentials.agentId
                    self.isAuthenticated = true
                    self.tokenExpiryDate = credentials.accessTokenExpiresAt
                    self.refreshTokenExpiryDate = credentials.refreshTokenExpiresAt
                    self.lastRefresh = credentials.issuedAt
                    
                    print("🟢 TOKEN: Loaded valid credentials for agent: \(credentials.agentId)")
                    print("🔵 TOKEN: Access token expires: \(formatDate(credentials.accessTokenExpiresAt))")
                    print("🔵 TOKEN: Refresh token expires: \(formatDate(credentials.refreshTokenExpiresAt))")
                } else {
                    print("🔴 TOKEN: Stored refresh token has expired")
                    await clearCredentials()
                }
            } catch {
                print("🔴 TOKEN: Failed to decode stored credentials: \(error)")
                await clearCredentials()
            }
        } else if status == errSecItemNotFound {
            print("🔵 TOKEN: No stored credentials found")
        } else {
            print("🔴 TOKEN: Keychain error loading credentials: \(status)")
        }
    }
    
    private func saveToKeychain(_ credentials: TokenCredentials) async {
        print("🔵 TOKEN: Saving credentials to keychain")
        
        do {
            let data = try JSONEncoder().encode(credentials)
            
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
                print("🟢 TOKEN: Credentials saved to keychain successfully")
            } else {
                print("🔴 TOKEN: Failed to save credentials to keychain: \(status)")
            }
        } catch {
            print("🔴 TOKEN: Failed to encode credentials: \(error)")
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
            print("🟢 TOKEN: Credentials deleted from keychain")
        } else {
            print("🔴 TOKEN: Failed to delete credentials from keychain: \(status)")
        }
    }
    
    private func setupAutomaticRefresh() async {
        guard let credentials = currentCredentials else { return }
        
        // Cancel existing timers
        refreshTimer?.invalidate()
        rotationTimer?.invalidate()
        
        // Setup access token refresh timer
        let refreshTime = credentials.accessTokenExpiresAt.timeIntervalSinceNow - refreshBuffer
        if refreshTime > 0 {
            refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshTime, repeats: false) { _ in
                Task {
                    do {
                        try await self.refreshAccessToken()
                    } catch {
                        print("🔴 TOKEN: Automatic refresh failed: \(error)")
                    }
                }
            }
            print("🔵 TOKEN: Access token refresh scheduled in \(formatTimeInterval(refreshTime))")
        }
        
        // Setup refresh token rotation timer
        let rotationTime = credentials.refreshTokenExpiresAt.timeIntervalSinceNow - rotationBuffer
        if rotationTime > 0 {
            rotationTimer = Timer.scheduledTimer(withTimeInterval: rotationTime, repeats: false) { _ in
                Task {
                    do {
                        try await self.rotateRefreshToken()
                    } catch {
                        print("🔴 TOKEN: Automatic rotation failed: \(error)")
                    }
                }
            }
            print("🔵 TOKEN: Refresh token rotation scheduled in \(formatTimeInterval(rotationTime))")
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval < 0 { return "overdue" }
        
        let days = Int(interval) / (24 * 3600)
        let hours = Int(interval) % (24 * 3600) / 3600
        let minutes = Int(interval) % 3600 / 60
        
        if days > 0 {
            return "\(days)d \(hours)h"
        } else if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    // MARK: - Network Methods
    
    private func makeTokenRefreshRequest(refreshToken: String, agentId: String) async throws -> [String: Any] {
        guard let networkService = networkService else {
            throw TokenError.networkError(NSError(domain: "TokenRefresh", code: 500, userInfo: [NSLocalizedDescriptionKey: "Network service not configured"]))
        }
        
        return try await networkService.refreshToken(refreshToken: refreshToken, agentId: agentId)
    }
} 