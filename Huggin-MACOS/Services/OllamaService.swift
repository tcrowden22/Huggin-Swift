import Foundation

actor OllamaService {
    static let shared = OllamaService()
    private let baseURL = "http://localhost:11434"

    private init() {}

    func checkStatus() async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw URLError(.badURL)
        }
        let (_, response) = try await URLSession.shared.data(from: url)
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
            "model": "llama2",
            "prompt": message,
            "stream": false
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return response.response
    }
}

struct OllamaResponse: Codable, Sendable {
    let response: String
} 