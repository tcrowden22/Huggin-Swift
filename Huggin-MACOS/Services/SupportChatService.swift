import Foundation
import SwiftUI

@MainActor
class SupportChatService: ObservableObject {
    @Published var messages: [SupportMessage] = []
    @Published var isProcessing = false
    
    private let systemInfo: SystemInfoProvider
    private let ollamaService: OllamaService
    
    init(systemInfo: SystemInfoProvider) {
        self.systemInfo = systemInfo
        self.ollamaService = OllamaService.shared
    }
    
    func sendMessage(_ text: String) async {
        let userMessage = SupportMessage(
            role: .user,
            content: text,
            timestamp: Date()
        )
        messages.append(userMessage)
        
        isProcessing = true
        defer { isProcessing = false }
        
        // Get system information
        let systemStatus = systemInfo.systemSummary
        
        // Prepare the prompt with system information
        let prompt = """
        System Information:
        \(systemStatus)
        
        User Message:
        \(text)
        
        Please provide a helpful response based on the system information and user's question.
        """
        
        do {
            let response = try await ollamaService.sendMessage(prompt)
            let assistantMessage = SupportMessage(
                role: .assistant,
                content: response,
                timestamp: Date()
            )
            messages.append(assistantMessage)
        } catch {
            let errorMessage = SupportMessage(
                role: .assistant,
                content: "Sorry, I encountered an error: \(error.localizedDescription)",
                timestamp: Date()
            )
            messages.append(errorMessage)
        }
    }
    
    func clearChat() {
        messages.removeAll()
    }
} 