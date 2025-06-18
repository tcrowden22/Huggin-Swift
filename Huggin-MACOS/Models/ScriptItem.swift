import Foundation

// MARK: - Script Manager Data Models

public struct ScriptItem: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public var name: String
    public var content: String
    public var description: String
    public var isRunning: Bool
    public var output: String
    public var createdDate: Date
    public var lastModified: Date
    public var lastRun: Date?
    public var exitCode: Int32?
    
    public init(
        name: String,
        content: String,
        description: String = "",
        isRunning: Bool = false,
        output: String = "",
        createdDate: Date = Date(),
        lastModified: Date = Date(),
        lastRun: Date? = nil,
        exitCode: Int32? = nil
    ) {
        self.name = name
        self.content = content
        self.description = description
        self.isRunning = isRunning
        self.output = output
        self.createdDate = createdDate
        self.lastModified = lastModified
        self.lastRun = lastRun
        self.exitCode = exitCode
    }
    
    // Helper computed properties
    public var isCompleted: Bool {
        !isRunning && lastRun != nil
    }
    
    public var hasError: Bool {
        exitCode != nil && exitCode != 0
    }
    
    public var lastThreeLines: String {
        let lines = output.components(separatedBy: .newlines)
        let relevantLines = lines.suffix(3).filter { !$0.isEmpty }
        return relevantLines.joined(separator: "\n")
    }
    
    public var statusDescription: String {
        if isRunning {
            return "Running..."
        } else if let exitCode = exitCode {
            return exitCode == 0 ? "Completed" : "Failed (Exit: \(exitCode))"
        } else {
            return "Ready"
        }
    }
} 