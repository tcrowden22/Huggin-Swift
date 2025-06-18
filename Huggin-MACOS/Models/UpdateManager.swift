import Foundation

public enum UpdateType: CaseIterable {
    case os
    case homebrew
    case appstore
    case other
}

public struct Update: Identifiable {
    public let id = UUID()
    public let name: String
    public let version: String
    public let type: UpdateType
    public let description: String?
    
    public init(name: String, version: String, type: UpdateType, description: String?) {
        self.name = name
        self.version = version
        self.type = type
        self.description = description
    }
}

@MainActor
public class UpdateManager: ObservableObject {
    @Published public var updates: [Update] = []
    
    public init() {
        // Defer the initial check to avoid AttributeGraph issues
        Task {
            // Small delay to ensure view initialization is complete
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            await checkForUpdates()
        }
    }
    
    public func checkForUpdates() async {
        // Clear existing updates
        updates.removeAll()
        
        // Check for macOS updates
        await checkMacOSUpdates()
        
        // Check for Homebrew updates
        await checkHomebrewUpdates()
        
        // Check for App Store updates
        await checkAppStoreUpdates()
    }
    
    private func checkMacOSUpdates() async {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["-l"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            
            do {
                try process.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Parse the output to find available updates
                    // This is a simplified version - you might want to add more sophisticated parsing
                    if output.contains("Software Update found") {
                        await MainActor.run {
                            self.updates.append(Update(
                                name: "macOS Update",
                                version: "Latest",
                                type: UpdateType.os,
                                description: "System software update available"
                            ))
                        }
                    }
                }
            } catch {
                print("Error checking for macOS updates: \(error)")
            }
        }.value
    }
    
    private func checkHomebrewUpdates() async {
        await Task.detached {
            // Check if Homebrew is installed before trying to run it
            let homebrewPaths = ["/usr/local/bin/brew", "/opt/homebrew/bin/brew"]
            
            guard let brewPath = homebrewPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                // Homebrew not installed, skip silently
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["outdated", "--quiet"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe() // Suppress error output
            
            do {
                try process.run()
                process.waitUntilExit()
                
                // Only proceed if the command was successful
                guard process.terminationStatus == 0 else { return }
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let packages = output.components(separatedBy: .newlines)
                        .filter { !$0.isEmpty }
                    
                    await MainActor.run {
                        for package in packages {
                            self.updates.append(Update(
                                name: package,
                                version: "Update available",
                                type: UpdateType.homebrew,
                                description: nil
                            ))
                        }
                    }
                }
            } catch {
                // Fail silently - don't spam logs if Homebrew commands fail
            }
        }.value
    }
    
    private func checkAppStoreUpdates() async {
        // This would typically use the App Store API
        // For now, we'll just add a placeholder
        await MainActor.run {
            updates.append(Update(
                name: "App Store Updates",
                version: "Check App Store",
                type: UpdateType.appstore,
                description: "Updates available in the App Store"
            ))
        }
    }
} 