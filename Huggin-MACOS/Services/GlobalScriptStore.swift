import Foundation
import SwiftUI

// Import the service that defines GeneratedScript
// Note: In a real app, this would be better organized with proper module structure
// For now, we'll rely on the fact that all files are in the same target

// MARK: - Global Script Store

@MainActor
public class GlobalScriptStore: ObservableObject {
    static let shared = GlobalScriptStore()
    
    @Published public var pendingScripts: [GeneratedScript] = []
    
    private init() {}
    
    public func addPendingScript(_ script: GeneratedScript) {
        Task { @MainActor in
            pendingScripts.append(script)
            
            // Notify that a new script is available
            NotificationCenter.default.post(
                name: .newScriptAvailable,
                object: script
            )
            
            print("Added pending script: \(script.name)")
        }
    }
    
    public func consumePendingScripts() async -> [GeneratedScript] {
        let scripts = pendingScripts
        pendingScripts.removeAll()
        return scripts
    }
    
    public var hasPendingScripts: Bool {
        !pendingScripts.isEmpty
    }
}

// MARK: - Notification Extensions

extension Notification.Name {
    static let newScriptAvailable = Notification.Name("newScriptAvailable")
} 