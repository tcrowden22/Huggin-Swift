import Foundation
import SwiftUI

// MARK: - Script Execution Service

@MainActor
public class ScriptExecutionService: ObservableObject, @unchecked Sendable {
    static let shared = ScriptExecutionService()
    
    @Published public var isExecuting = false
    @Published public var executionCount = 0
    
    private init() {}
    
    // MARK: - Core Execution Methods
    
    public func validateScript(_ content: String) -> ScriptValidationResult {
        // TODO: Integrate with Ollama for AI-powered script analysis
        // - Send script to Ollama for safety analysis
        // - Check for potentially dangerous commands
        // - Suggest improvements or alternatives
        // - Validate syntax and best practices
        
        var issues: [String] = []
        var suggestions: [String] = []
        
        // Basic validation checks
        if content.contains("rm -rf /") {
            issues.append("Dangerous command detected: rm -rf /")
        }
        
        if content.contains("sudo") {
            suggestions.append("Consider running without sudo for security")
        }
        
        if !content.hasPrefix("#!/bin/bash") && !content.hasPrefix("#!") {
            suggestions.append("Add shebang line (#!/bin/bash) for clarity")
        }
        
        let riskLevel: ScriptRiskLevel
        if !issues.isEmpty {
            riskLevel = .high
        } else if content.contains("curl") || content.contains("wget") {
            riskLevel = .medium
        } else {
            riskLevel = .low
        }
        
        return ScriptValidationResult(
            isValid: issues.isEmpty,
            riskLevel: riskLevel,
            issues: issues,
            suggestions: suggestions
        )
    }
    
    public func enhanceScript(_ content: String) async throws -> String {
        // TODO: Integrate with Ollama for script enhancement
        // - Send script to Ollama with enhancement prompt
        // - Add error handling and logging
        // - Optimize for performance
        // - Add documentation comments
        
        let _ = """
        You are a bash scripting expert. Please enhance this script by:
        1. Adding proper error handling (set -e, etc.)
        2. Adding informative comments
        3. Improving performance where possible
        4. Adding safety checks
        5. Following bash best practices
        
        Original script:
        \(content)
        
        Return only the enhanced script code, no explanations.
        """
        
        // For now, return the original script with basic enhancements
        // TODO: Replace with actual Ollama integration
        return addBasicEnhancements(to: content)
    }
    
    public func explainScript(_ content: String) async throws -> String {
        // TODO: Integrate with Ollama for script explanation
        // - Break down what each command does
        // - Explain the overall purpose
        // - Highlight potential side effects
        // - Suggest use cases
        
        let _ = """
        Please explain this bash script in detail:
        1. What does it do overall?
        2. Break down each command
        3. What are the potential side effects?
        4. When would you use this script?
        
        Script:
        \(content)
        """
        
        // TODO: Replace with actual Ollama integration
        return generateBasicExplanation(for: content)
    }
    
    // MARK: - Execution Statistics
    
    public func recordExecution() {
        executionCount += 1
        print("Script execution recorded. Total: \(executionCount)")
    }
    
    public func setExecuting(_ executing: Bool) {
        isExecuting = executing
    }
    
    // MARK: - Private Helper Methods
    
    private func addBasicEnhancements(to script: String) -> String {
        var enhanced = script
        
        // Add shebang if missing
        if !enhanced.hasPrefix("#!") {
            enhanced = "#!/bin/bash\n\n" + enhanced
        }
        
        // Add basic error handling
        if !enhanced.contains("set -e") {
            enhanced = enhanced.replacingOccurrences(
                of: "#!/bin/bash",
                with: "#!/bin/bash\nset -e  # Exit on any error"
            )
        }
        
        // Add header comment
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
        enhanced = enhanced.replacingOccurrences(
            of: "#!/bin/bash",
            with: """
            #!/bin/bash
            # Enhanced by Huginn Script Manager on \(timestamp)
            # This script has been automatically enhanced with error handling
            """
        )
        
        return enhanced
    }
    
    private func generateBasicExplanation(for script: String) -> String {
        let lines = script.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        var explanation = "Script Analysis:\n\n"
        explanation += "This script contains \(lines.count) executable commands.\n\n"
        
        explanation += "Commands breakdown:\n"
        for (index, line) in lines.enumerated() {
            explanation += "\(index + 1). \(line.trimmingCharacters(in: .whitespaces))\n"
        }
        
        explanation += "\nNote: This is a basic analysis. For detailed AI-powered explanations, integrate with Ollama service."
        
        return explanation
    }
}

// MARK: - Supporting Types

public struct ScriptValidationResult: Sendable {
    public let isValid: Bool
    public let riskLevel: ScriptRiskLevel
    public let issues: [String]
    public let suggestions: [String]
    
    public init(isValid: Bool, riskLevel: ScriptRiskLevel, issues: [String], suggestions: [String]) {
        self.isValid = isValid
        self.riskLevel = riskLevel
        self.issues = issues
        self.suggestions = suggestions
    }
}

public enum ScriptRiskLevel: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    
    public var color: Color {
        switch self {
        case .low: return Color("huginn-green")
        case .medium: return Color("huginn-orange")
        case .high: return Color("huginn-red")
        }
    }
    
    public var icon: String {
        switch self {
        case .low: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.shield.fill"
        case .high: return "xmark.shield.fill"
        }
    }
}

// MARK: - Extensions

extension Color {
    static let scriptGreen = Color("huginn-green")
    static let scriptOrange = Color("huginn-orange")
    static let scriptRed = Color("huginn-red")
} 