import Foundation

actor OllamaService {
    static let shared = OllamaService()
    private let baseURL = "http://localhost:11434"

    private init() {}

    func checkStatus() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw URLError(.badURL)
        }
        
        // Create request with timeout
        var request = URLRequest(url: url)
        request.timeoutInterval = 5.0
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 5.0
        let session = URLSession(configuration: config)
        
        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return httpResponse.statusCode == 200
    }

    func sendMessage(_ message: String) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/generate") else {
            throw URLError(.badURL)
        }
        let requestBody: [String: Any] = [
            "model": "llama3:8b",
            "prompt": message,
            "stream": false
        ]
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        // Add timeout of 15 seconds to prevent hanging
        request.timeoutInterval = 15.0
        
        // Create custom URLSession with timeout
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15.0
        config.timeoutIntervalForResource = 15.0
        let session = URLSession(configuration: config)
        
        let (data, response) = try await session.data(for: request)
        
        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            if let errorString = String(data: data, encoding: .utf8) {
                print("Ollama Error (\(httpResponse.statusCode)): \(errorString)")
            }
            throw URLError(.badServerResponse)
        }
        
        let decoder = JSONDecoder()
        let ollamaResponse = try decoder.decode(OllamaResponse.self, from: data)
        return ollamaResponse.response
    }
}

struct OllamaResponse: Codable, Sendable {
    let model: String
    let createdAt: String?
    let response: String
    let done: Bool
    let context: [Int]?
    let totalDuration: Int?
    let loadDuration: Int?
    let promptEvalCount: Int?
    let promptEvalDuration: Int?
    let evalCount: Int?
    let evalDuration: Int?
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response
        case done
        case context
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
} 