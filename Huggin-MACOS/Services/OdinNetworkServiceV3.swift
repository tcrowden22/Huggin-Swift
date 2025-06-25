import Foundation

/// Network service for ODIN API communication using serial number authentication
class OdinNetworkServiceV3: ObservableObject, @unchecked Sendable {
    
    // MARK: - Dependencies
    private let authManager: OdinSerialAuthManager
    private var tokenManager: OdinTokenManager?
    private var baseURL: String = "https://lfxfavntadlejwmkrvuv.supabase.co/functions/v1"
    private let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxmeGZhdm50YWRsZWp3bWtydnV2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDcyMzk0MjAsImV4cCI6MjA2MjgxNTQyMH0.AjGjIOeyGETT0O54ySBKbZNrfAxhDtRJaanegopu2go"
    
    // MARK: - Retry Configuration
    private let maxRetries = 3
    private let baseRetryDelay: TimeInterval = 1.0
    
    // MARK: - API Endpoints
    enum Endpoint {
        case enrollAgent
        case checkIn
        case telemetry
        case deviceData
        case tokenRefresh
        
        var path: String {
            switch self {
            case .enrollAgent: return "/enroll-agent"
            case .checkIn: return "/agent-checkin"
            case .telemetry: return "/agent-telemetry"
            case .deviceData: return "/agent-report-data"
            case .tokenRefresh: return "/agent-token-refresh"
            }
        }
    }
    
    // MARK: - Error Types
    
    struct ErrorResponse: Codable {
        let message: String
        let code: String?
        let details: String?
    }
    
    enum NetworkError: LocalizedError {
        case invalidResponse(String)
        case serverError(Int, String)
        case enrollmentTokenInvalid
        case agentNotFound
        case rateLimited
        case timeout
        case httpError(Int, String?)
        case serialNumberRequired
        
        var errorDescription: String? {
            switch self {
            case .invalidResponse(let message):
                return "Invalid response: \(message)"
            case .serverError(let code, let message):
                return "Server error \(code): \(message)"
            case .enrollmentTokenInvalid:
                return "Invalid enrollment token"
            case .agentNotFound:
                return "Agent not found"
            case .rateLimited:
                return "Request rate limited"
            case .timeout:
                return "Request timeout"
            case .httpError(let code, let message):
                return "HTTP Error \(code): \(message ?? "No additional information")"
            case .serialNumberRequired:
                return "Serial number is required for this operation"
            }
        }
    }
    
    // MARK: - Response Models
    
    struct EnrollmentResponse: Codable {
        let success: Bool
        let message: String
        let agentId: String?
        let accessToken: String?
        let refreshToken: String?
        let expiresAt: String?
        
        enum CodingKeys: String, CodingKey {
            case success, message
            case agentId = "agent_id"
            case accessToken = "access_token"
            case refreshToken = "refresh_token"
            case expiresAt = "expires_at"
        }
    }
    
    struct CheckInResponse: Codable {
        let success: Bool
        let tasks: [TaskData]
        let message: String?
    }
    
    struct TaskData: Codable {
        let taskId: String
        let type: String
        let payload: [String: String]
        let priority: Int
        let timeout: Int?
        
        enum CodingKeys: String, CodingKey {
            case taskId = "task_id"
            case type, payload, priority, timeout
        }
    }
    
    struct TelemetryResponse: Codable {
        let success: Bool
        let message: String
    }
    
    // MARK: - Initialization
    init(authManager: OdinSerialAuthManager, tokenManager: OdinTokenManager? = nil) {
        self.authManager = authManager
        self.tokenManager = tokenManager
    }
    
    // MARK: - Configuration
    func configure(baseURL: String, tokenManager: OdinTokenManager? = nil) {
        self.baseURL = baseURL
        self.tokenManager = tokenManager
        print("🔵 NETWORK: Configured with base URL: \(baseURL)")
    }
    
    // MARK: - Public API Methods
    
    /// Send data to a specific endpoint
    func sendData(to endpoint: Endpoint, data: [String: Any]) async throws -> [String: Any] {
        return try await makeRequest(
            endpoint: endpoint,
            body: data,
            retryCount: 0
        )
    }
    
    /// Enroll agent with enrollment token
    func enrollAgent(with token: String, deviceInfo: [String: Any]) async throws -> EnrollmentResponse {
        print("🔵 NETWORK: Enrolling agent with token...")
        
        let requestBody: [String: Any] = [
            "token": token,
            "deviceInfo": deviceInfo
        ]
        
        let response = try await makeRequest(
            endpoint: .enrollAgent,
            body: requestBody,
            retryCount: 0
        )
        
        // Parse enrollment response
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let enrollmentResponse = try? JSONDecoder().decode(EnrollmentResponse.self, from: responseData) else {
            throw NetworkError.invalidResponse("Invalid enrollment response")
        }
        
        print("🟢 NETWORK: Agent enrollment successful")
        return enrollmentResponse
    }
    
    /// Agent check-in to get tasks and update status
    func checkIn(systemInfo: [String: Any]) async throws -> CheckInResponse {
        guard let serialNumber = try? await authManager.getSerialNumber() else {
            throw NetworkError.agentNotFound
        }
        
        print("🔵 NETWORK: Agent check-in for serial: \(serialNumber)")
        
        let requestBody: [String: Any] = [
            "serial_number": serialNumber,
            "system_info": systemInfo
        ]
        
        let response = try await makeRequest(
            endpoint: .checkIn,
            body: requestBody,
            retryCount: 0
        )
        
        // Parse check-in response
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let checkInResponse = try? JSONDecoder().decode(CheckInResponse.self, from: responseData) else {
            throw NetworkError.invalidResponse("Invalid check-in response")
        }
        
        print("🟢 NETWORK: Check-in successful - received \(checkInResponse.tasks.count) tasks")
        return checkInResponse
    }
    
    /// Send telemetry data
    func sendTelemetry(data: [String: Any]) async throws -> TelemetryResponse {
        guard let serialNumber = try? await authManager.getSerialNumber() else {
            throw NetworkError.agentNotFound
        }
        
        print("🔵 NETWORK: Sending telemetry data for serial: \(serialNumber)")
        
        var requestBody = data
        requestBody["serial_number"] = serialNumber
        
        let response = try await makeRequest(
            endpoint: .telemetry,
            body: requestBody,
            retryCount: 0
        )
        
        // Parse telemetry response
        guard let responseData = try? JSONSerialization.data(withJSONObject: response),
              let telemetryResponse = try? JSONDecoder().decode(TelemetryResponse.self, from: responseData) else {
            throw NetworkError.invalidResponse("Invalid telemetry response")
        }
        
        print("🟢 NETWORK: Telemetry sent successfully")
        return telemetryResponse
    }
    
    /// Get pending tasks for agent
    func getTasks() async throws -> [String: Any] {
        guard let accessToken = try? await tokenManager?.getAccessToken() else {
            throw NetworkError.agentNotFound
        }
        
        print("🔵 NETWORK: Fetching tasks for agent")
        
        // Make direct request to agent-get-tasks edge function
        let url = URL(string: "\(baseURL)/agent-get-tasks")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse("Invalid JSON response")
        }
        
        print("🟢 NETWORK: Tasks fetched successfully")
        return json
    }
    
    /// Update task status
    func updateTaskStatus(taskId: String, status: String, result: [String: Any]? = nil, executionTime: TimeInterval? = nil) async throws -> [String: Any] {
        guard let accessToken = try? await tokenManager?.getAccessToken() else {
            throw NetworkError.agentNotFound
        }
        
        print("🔵 NETWORK: Updating task \(taskId) status to \(status)")
        
        var requestBody: [String: Any] = [
            "task_id": taskId,
            "status": status
        ]
        
        if let result = result {
            requestBody["result"] = result
        }
        
        if let executionTime = executionTime {
            requestBody["execution_time"] = executionTime
        }
        
        // Make direct request to agent-update-task edge function
        let url = URL(string: "\(baseURL)/agent-update-task")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse("Invalid response")
        }
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw NetworkError.httpError(httpResponse.statusCode, errorMessage)
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.invalidResponse("Invalid JSON response")
        }
        
        print("🟢 NETWORK: Task status updated successfully")
        return json
    }
    
    /// Refresh access token using refresh token
    func refreshToken(refreshToken: String, agentId: String) async throws -> [String: Any] {
        print("🔵 NETWORK: Refreshing access token...")
        
        let requestBody: [String: Any] = [
            "refresh_token": refreshToken,
            "agent_id": agentId
        ]
        
        let response = try await makeRequest(
            endpoint: .tokenRefresh,
            body: requestBody,
            retryCount: 0
        )
        
        print("🟢 NETWORK: Token refresh successful")
        return response
    }
    
    // MARK: - Private Methods
    
    private func makeRequest(
        endpoint: Endpoint,
        method: String = "POST",
        body: [String: Any]? = nil,
        retryCount: Int
    ) async throws -> [String: Any] {
        
        // Construct URL
        guard let url = URL(string: "\(baseURL)\(endpoint.path)") else {
            throw NetworkError.invalidResponse("Invalid URL")
        }
        
        print("🔵 NETWORK: Making \(method) request to \(endpoint.path)")
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30.0
        
        // Add authentication
        if endpoint == .deviceData || endpoint == .checkIn || endpoint == .telemetry {
            // Use access token for authenticated endpoints
            if let tokenManager = tokenManager {
                do {
                    let accessToken = try await tokenManager.getAccessToken()
                    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
                    print("🔵 NETWORK: Added access token for \(endpoint.path)")
                } catch {
                    print("🔴 NETWORK: Failed to get access token: \(error)")
                    throw NetworkError.agentNotFound
                }
            } else {
                // Fallback to enrollment token if no token manager
                let enrollmentToken = try authManager.getEnrollmentToken()
                request.setValue("Bearer \(enrollmentToken)", forHTTPHeaderField: "Authorization")
                print("🔵 NETWORK: Added enrollment token for \(endpoint.path) (fallback)")
            }
        } else {
            // Use Supabase anon key for enrollment and token refresh
            request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
            request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
            print("🔵 NETWORK: Added Supabase anon key for endpoint \(endpoint.path)")
        }
        
        // Debug: Print all headers being sent
        print("🔵 NETWORK: Request headers:")
        for (key, value) in request.allHTTPHeaderFields ?? [:] {
            if key.lowercased() == "authorization" {
                print("🔵 NETWORK:   \(key): Bearer ***\(String(value.suffix(8)))")
            } else {
                print("🔵 NETWORK:   \(key): \(value)")
            }
        }
        
        // Add request body
        if let body = body {
            do {
                let jsonData = try JSONSerialization.data(withJSONObject: body)
                request.httpBody = jsonData
                print("🔵 NETWORK: Request body size: \(jsonData.count) bytes")
                
                // Debug: Print request body
                if let bodyString = String(data: jsonData, encoding: .utf8) {
                    print("🔵 NETWORK: Request body: \(bodyString)")
                }
            } catch {
                print("🔴 NETWORK: Failed to serialize request body: \(error)")
                throw NetworkError.invalidResponse("Failed to serialize request body")
            }
        }
        
        // Execute request with retry logic
        return try await executeRequestWithRetry(request: request, endpoint: endpoint, retryCount: retryCount)
    }
    
    private func executeRequestWithRetry(
        request: URLRequest,
        endpoint: Endpoint,
        retryCount: Int
    ) async throws -> [String: Any] {
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse("Not an HTTP response")
            }
            
            print("🔵 NETWORK: HTTP Status: \(httpResponse.statusCode)")
            
            // Handle 401 Unauthorized - try to refresh token and retry for authenticated endpoints
            if httpResponse.statusCode == 401 && 
               (endpoint == .deviceData || endpoint == .checkIn || endpoint == .telemetry) && 
               retryCount == 0 {
                print("🔄 NETWORK: Got 401 error on \(endpoint.path), attempting token refresh...")
                
                if let tokenManager = tokenManager {
                    do {
                        // Try to refresh the access token
                        try await tokenManager.refreshAccessToken()
                        print("🟢 NETWORK: Token refreshed successfully, retrying request...")
                        
                        // Create new request with fresh token
                        var retryRequest = request
                        let newAccessToken = try await tokenManager.getAccessToken()
                        retryRequest.setValue("Bearer \(newAccessToken)", forHTTPHeaderField: "Authorization")
                        
                        // Retry with fresh token (increment retry count to prevent infinite loop)
                        return try await executeRequestWithRetry(
                            request: retryRequest,
                            endpoint: endpoint,
                            retryCount: retryCount + 1
                        )
                    } catch {
                        print("🔴 NETWORK: Token refresh failed: \(error)")
                        // If token refresh fails, fall through to throw the original 401 error
                    }
                }
            }
            
            guard 200...299 ~= httpResponse.statusCode else {
                // Try to parse error message from response
                let errorMessage: String
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = message
                } else {
                    errorMessage = "HTTP Error \(httpResponse.statusCode)"
                }
                throw NetworkError.httpError(httpResponse.statusCode, errorMessage)
            }
            
            // Success - parse response
            return try parseSuccessResponse(data: data)
            
        } catch {
            // Handle network errors
            if let urlError = error as? URLError {
                print("🔴 NETWORK: URL Error: \(urlError.localizedDescription)")
                
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw NetworkError.invalidResponse("No internet connection")
                case .timedOut:
                    throw NetworkError.timeout
                default:
                    // Retry on network errors if possible
                    if retryCount < maxRetries {
                        return try await retryRequest(request: request, endpoint: endpoint, retryCount: retryCount)
                    } else {
                        throw NetworkError.serverError(0, urlError.localizedDescription)
                    }
                }
            } else {
                throw error
            }
        }
    }
    
    private func retryRequest(
        request: URLRequest,
        endpoint: Endpoint,
        retryCount: Int
    ) async throws -> [String: Any] {
        
        let nextRetryCount = retryCount + 1
        let delay = baseRetryDelay * pow(2.0, Double(retryCount)) // Exponential backoff
        
        print("🔄 NETWORK: Retrying request (\(nextRetryCount)/\(maxRetries)) in \(delay)s...")
        
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        
        return try await executeRequestWithRetry(
            request: request,
            endpoint: endpoint,
            retryCount: nextRetryCount
        )
    }
    
    private func parseSuccessResponse(data: Data) throws -> [String: Any] {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.invalidResponse("Invalid response format")
            }
            
            print("🟢 NETWORK: Response parsed successfully")
            return json
            
        } catch {
            print("🔴 NETWORK: Failed to parse response: \(error)")
            throw NetworkError.invalidResponse("Failed to parse response")
        }
    }
    
    private func parseErrorMessage(data: Data) -> String {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = json["error"] as? String {
                return errorMessage
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                return message
            }
        } catch {
            // Ignore parsing errors
        }
        
        // Fallback to raw response
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }
} 