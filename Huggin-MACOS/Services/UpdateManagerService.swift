import Foundation
import Combine

struct UpdateInfo: Sendable {
    let name: String
    let version: String
    let type: UpdateServiceType
    let description: String?
    let label: String?
}

enum UpdateServiceType: Sendable {
    case os
    case homebrew
    case appStore
}

struct UpdateResult: Sendable {
    let success: Bool
    let message: String
}

@MainActor
class UpdateManagerService: ObservableObject {
    @Published var updates: [UpdateInfo] = []
    @Published var isChecking = false
    @Published var lastChecked: Date?
    @Published var osUpdates: [String] = []
    @Published var homebrewUpdates: [String] = []
    @Published var appStoreUpdates: [String] = []
    @Published var errors: [String] = []
    
    private nonisolated(unsafe) var timer: Timer?
    private let softwareUpdateProvider: SoftwareUpdateProvider
    
    init(softwareUpdateProvider: SoftwareUpdateProvider) {
        self.softwareUpdateProvider = softwareUpdateProvider
        Task {
            await checkAllUpdates()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkAllUpdates()
            }
        }
    }
    
    deinit { 
        timer?.invalidate() 
    }
    
    func checkAllUpdates() async {
        await checkForUpdates()
    }

    func checkForUpdates() async {
        isChecking = true
        errors.removeAll()
        
        // Check all update sources concurrently
        async let osTask: Void = checkOSUpdates()
        async let homebrewTask: Void = checkHomebrewUpdates()
        async let appStoreTask: Void = checkAppStoreUpdates()
        
        // Wait for all tasks to complete
        _ = await (osTask, homebrewTask, appStoreTask)
        
        lastChecked = Date()
        isChecking = false
    }
    
    private func checkOSUpdates() async {
        do {
            let hasUpdates = try await softwareUpdateProvider.checkForUpdates()
            if hasUpdates {
                osUpdates = softwareUpdateProvider.updates.map { $0.name }
            } else {
                osUpdates = []
            }
        } catch {
            errors.append("Failed to check OS updates: \(error.localizedDescription)")
        }
    }
    
    private func checkHomebrewUpdates() async {
        // Simulate checking Homebrew updates
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        homebrewUpdates = ["python", "node", "git"]
    }
    
    private func checkAppStoreUpdates() async {
        // Simulate checking App Store updates
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        appStoreUpdates = ["Xcode", "Safari", "Mail"]
    }
    
    func installUpdate(_ updateName: String) async {
        // Simulate update installation
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        
        // Remove from appropriate list
        if let index = osUpdates.firstIndex(of: updateName) {
            osUpdates.remove(at: index)
        } else if let index = homebrewUpdates.firstIndex(of: updateName) {
            homebrewUpdates.remove(at: index)
        } else if let index = appStoreUpdates.firstIndex(of: updateName) {
            appStoreUpdates.remove(at: index)
        }
    }
    
    func installAllUpdates() async {
        await withTaskGroup(of: Void.self) { group in
            for update in osUpdates {
                group.addTask {
                    await self.installUpdate(update)
                }
            }
            for update in homebrewUpdates {
                group.addTask {
                    await self.installUpdate(update)
                }
            }
            for update in appStoreUpdates {
                group.addTask {
                    await self.installUpdate(update)
                }
            }
        }
    }
    
    // Legacy methods for compatibility
    func installUpdate(for update: UpdateInfo) -> UpdateResult? {
        switch update.type {
        case .os:
            guard let _ = update.label else {
                return UpdateResult(success: false, message: "No update label found.")
            }
            // Simulate OS update installation
            return UpdateResult(success: true, message: "Update completed successfully.")
        case .homebrew:
            // Simulate Homebrew update installation
            return UpdateResult(success: true, message: "Update completed successfully.")
        case .appStore:
            return UpdateResult(success: false, message: "Unsupported update type: \(update.type)")
        }
    }
    
    private func which(_ command: String) throws -> String {
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [command]
        let pipe = Pipe()
        task.standardOutput = pipe
        try task.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { 
            throw NSError(domain: "which", code: 1) 
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 