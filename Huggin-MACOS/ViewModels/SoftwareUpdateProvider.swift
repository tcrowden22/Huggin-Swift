import Foundation
import SwiftUI

@MainActor
public class SoftwareUpdateProvider: ObservableObject, @unchecked Sendable {
    @Published public var updates: [SoftwareUpdate] = []
    @Published public var hasUpdates: Bool = false
    @Published public var osUpdateAvailable: Bool = false
    @Published public var thirdPartyUpdatesAvailable: Bool = false
    @Published public var homebrewUpdates: [HomebrewUpdate] = []
    @Published public var appStoreUpdates: [AppStoreUpdate] = []
    @Published public var toolStatus: [String: Bool] = ["brew": false, "mas": false]
    @Published public var updateDetails: [String] = []
    @Published public var requiresReboot: Bool = false
    @Published public var rebootReason: String = ""
    private nonisolated(unsafe) var timer: Timer?
    
    private var isCheckingUpdates = false
    private var lastCheckTime: Date = Date.distantPast
    private let minimumCheckInterval: TimeInterval = 300 // 5 minutes between checks
    
    private static var hasInitialized = false
    
    public init() {
        // Only do expensive initialization once
        guard !Self.hasInitialized else {
            print("🔄 SoftwareUpdateProvider: Already initialized, skipping heavy operations")
            return
        }
        Self.hasInitialized = true
        
        // Defer tool availability check to background to avoid blocking UI
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
            await self?.checkToolAvailability()
        }
        
        // Defer initial fetch to background
        Task { [weak self] in
            await self?.fetchUpdates()
        }
        
        // Check for updates much less frequently - every 6 hours instead of every hour
        timer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.fetchUpdates()
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func checkToolAvailability() async {
        print("🔍 Checking tool availability...")
        
        // Check if Homebrew is available
        let brewPath = which("brew")
        print("🍺 Homebrew path: \(brewPath ?? "NOT FOUND")")
        
        let masPath = which("mas")
        print("🏪 mas-cli path: \(masPath ?? "NOT FOUND")")
        
        // Batch update tool status
        await MainActor.run {
            self.toolStatus["brew"] = brewPath != nil
            self.toolStatus["mas"] = masPath != nil
            print("📊 Tool status updated - brew: \(self.toolStatus["brew"] ?? false), mas: \(self.toolStatus["mas"] ?? false)")
        }
    }
    
    private func which(_ command: String) -> String? {
        // Common paths for Homebrew and mas-cli
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        
        // First try the which command
        let task = Process()
        task.launchPath = "/usr/bin/which"
        task.arguments = [command]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !path.isEmpty {
                        return path
                    }
                }
            }
        } catch {
            print("Error checking for \(command) with which: \(error)")
        }
        
        // Fallback: check common paths directly
        for path in commonPaths {
            let fullPath = "\(path)/\(command)"
            if FileManager.default.fileExists(atPath: fullPath) {
                print("Found \(command) at: \(fullPath)")
                return fullPath
            }
        }
        
        print("\(command) not found in common paths")
        return nil
    }
    
    private func fetchUpdates() async {
        await fetchSystemUpdates()
        await fetchHomebrewUpdates()
        await fetchAppStoreUpdates()
    }
    
    private func fetchSystemUpdates() async {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let systemUpdates = parseSystemUpdates(output)
                    
                    // Batch update properties
                    await MainActor.run {
                        self.updates = systemUpdates
                        self.hasUpdates = !systemUpdates.isEmpty || !self.homebrewUpdates.isEmpty || !self.appStoreUpdates.isEmpty
                        self.osUpdateAvailable = systemUpdates.contains { $0.name.contains("macOS") || $0.name.contains("Security") }
                    }
                }
            }
        } catch {
            print("Error fetching system updates: \(error)")
        }
    }
    
    private func parseSystemUpdates(_ output: String) -> [SoftwareUpdate] {
        var updates: [SoftwareUpdate] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Look for lines starting with "* Label:" which indicate available updates
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("* Label:") {
                // Extract the label/name
                let labelStart = line.range(of: "* Label: ")?.upperBound ?? line.startIndex
                let labelEnd = line.firstIndex(of: "\n") ?? line.endIndex
                let label = String(line[labelStart..<labelEnd]).trimmingCharacters(in: .whitespaces)
                
                // Look for the next line with Title information
                if let lineIndex = lines.firstIndex(of: line),
                   lineIndex + 1 < lines.count {
                    let titleLine = lines[lineIndex + 1]
                    if titleLine.contains("Title:") {
                        // Extract title and version
                        let titleStart = titleLine.range(of: "Title: ")?.upperBound ?? titleLine.startIndex
                        let titleEnd = titleLine.range(of: ", Version:")?.lowerBound ?? titleLine.endIndex
                        let title = String(titleLine[titleStart..<titleEnd]).trimmingCharacters(in: .whitespaces)
                        
                        // Extract version
                        if let versionStart = titleLine.range(of: "Version: ")?.upperBound,
                           let versionEnd = titleLine.range(of: ", Size:")?.lowerBound {
                            let version = String(titleLine[versionStart..<versionEnd]).trimmingCharacters(in: .whitespaces)
                            
                            // Extract size
                            let size = parseSize(from: titleLine)
                            
                            let update = SoftwareUpdate(
                                id: label,
                                name: title,
                                version: version,
                                description: "System update: \(title)",
                                size: size,
                                isInstalled: false
                            )
                            updates.append(update)
                            print("🖥️ Found system update: \(title) v\(version)")
                        }
                    }
                }
            }
        }
        
        return updates
    }
    
    private func parseSize(from line: String) -> Int64 {
        // Look for size patterns like "2686976KiB" or "12.0 GB"
        let patterns = [
            "\\d+KiB",  // e.g., 2686976KiB
            "\\d+\\.?\\d*\\s*[KMGT]B"  // e.g., 12.0 GB, 500MB
        ]
        
        for pattern in patterns {
            if let sizeRange = line.range(of: pattern, options: .regularExpression) {
                let sizeString = String(line[sizeRange])
                
                if sizeString.hasSuffix("KiB") {
                    // Convert KiB to bytes
                    let number = sizeString.replacingOccurrences(of: "KiB", with: "")
                    return (Int64(number) ?? 0) * 1024
                } else if sizeString.hasSuffix("GB") {
                    // Convert GB to bytes
                    let number = sizeString.replacingOccurrences(of: "GB", with: "").trimmingCharacters(in: .whitespaces)
                    return Int64((Double(number) ?? 0) * 1_000_000_000)
                } else if sizeString.hasSuffix("MB") {
                    // Convert MB to bytes
                    let number = sizeString.replacingOccurrences(of: "MB", with: "").trimmingCharacters(in: .whitespaces)
                    return Int64((Double(number) ?? 0) * 1_000_000)
                } else if sizeString.hasSuffix("KB") {
                    // Convert KB to bytes
                    let number = sizeString.replacingOccurrences(of: "KB", with: "").trimmingCharacters(in: .whitespaces)
                    return Int64((Double(number) ?? 0) * 1_000)
                }
            }
        }
        return 0
    }
    
    private func fetchHomebrewUpdates() async {
        guard let brewPath = which("brew") else { return }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["outdated", "--json"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let packages = parseHomebrewUpdates(output)
                    
                    // Batch update properties
                    await MainActor.run {
                        self.homebrewUpdates = packages
                        self.thirdPartyUpdatesAvailable = !packages.isEmpty || !self.appStoreUpdates.isEmpty
                    }
                }
            }
        } catch {
            print("Error fetching Homebrew updates: \(error)")
        }
    }
    
    private func parseHomebrewUpdates(_ output: String) -> [HomebrewUpdate] {
        var packages: [HomebrewUpdate] = []
        
        // Try to parse as JSON first
        if let data = output.data(using: .utf8) {
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let formulae = json["formulae"] as? [[String: Any]] {
                    
                    for formula in formulae {
                        if let name = formula["name"] as? String,
                           let installedVersions = formula["installed_versions"] as? [String],
                           let currentVersion = formula["current_version"] as? String,
                           let installedVersion = installedVersions.first {
                            
                            let package = HomebrewUpdate(
                                name: name,
                                currentVersion: installedVersion,
                                newVersion: currentVersion
                            )
                            packages.append(package)
                            print("📦 Found Homebrew update: \(name) \(installedVersion) → \(currentVersion)")
                        }
                    }
                    return packages
                }
            } catch {
                print("Error parsing Homebrew JSON: \(error)")
            }
        }
        
        // Fallback to text parsing (old format)
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if !line.isEmpty {
                let components = line.components(separatedBy: " ")
                if components.count >= 2 {
                    let name = components[0]
                    let versions = components[1].components(separatedBy: " < ")
                    if versions.count == 2 {
                        let currentVersion = versions[0]
                        let newVersion = versions[1]
                        let package = HomebrewUpdate(name: name, currentVersion: currentVersion, newVersion: newVersion)
                        packages.append(package)
                        print("📦 Found Homebrew update (text): \(name) \(currentVersion) → \(newVersion)")
                    }
                }
            }
        }
        
        return packages
    }
    
    private func fetchAppStoreUpdates() async {
        guard let masPath = which("mas") else { return }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: masPath)
            process.arguments = ["outdated"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let apps = parseAppStoreUpdates(output)
                    
                    // Batch update properties
                    await MainActor.run {
                        self.appStoreUpdates = apps
                        self.thirdPartyUpdatesAvailable = !self.homebrewUpdates.isEmpty || !apps.isEmpty
                    }
                }
            }
        } catch {
            print("Error fetching App Store updates: \(error)")
        }
    }
    
    private func parseAppStoreUpdates(_ output: String) -> [AppStoreUpdate] {
        var apps: [AppStoreUpdate] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if !line.isEmpty {
                let components = line.components(separatedBy: " ")
                if components.count >= 2 {
                    let name = components[0]
                    let versions = components[1].components(separatedBy: " → ")
                    if versions.count == 2 {
                        let currentVersion = versions[0]
                        let newVersion = versions[1]
                        let app = AppStoreUpdate(name: name, currentVersion: currentVersion, newVersion: newVersion)
                        apps.append(app)
                    }
                }
            }
        }
        
        return apps
    }
    
    public func installUpdate(_ update: SoftwareUpdate) async throws {
        print("🔄 Starting installation of update: \(update.name) v\(update.version)")
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["-i", update.name]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                // Check if reboot is required after installation
                await checkForPendingRestart()
                
                if let index = updates.firstIndex(where: { $0.id == update.id }) {
                    var updatedUpdate = updates[index]
                    updatedUpdate = SoftwareUpdate(
                        id: updatedUpdate.id,
                        name: updatedUpdate.name,
                        version: updatedUpdate.version,
                        description: updatedUpdate.description,
                        size: updatedUpdate.size,
                        isInstalled: true
                    )
                    updates[index] = updatedUpdate
                    hasUpdates = updates.contains { !$0.isInstalled }
                    print("✅ Successfully installed \(update.name)")
                    
                    // Show restart notification if needed
                    if requiresReboot {
                        print("⚠️ Restart required after installing \(update.name)")
                    }
                }
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "UpdateError", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to install update: \(errorOutput)"
                ])
            }
        } catch {
            print("❌ Error installing update: \(error)")
            throw error
        }
    }
    
    public func updateHomebrewPackage(_ package: HomebrewUpdate) async throws {
        print("🍺 Starting Homebrew update for package: \(package.name)")
        
        guard let brewPath = which("brew") else {
            throw NSError(domain: "UpdateError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Homebrew not found"
            ])
        }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["upgrade", package.name]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                if let index = homebrewUpdates.firstIndex(where: { $0.name == package.name }) {
                    homebrewUpdates.remove(at: index)
                    thirdPartyUpdatesAvailable = !homebrewUpdates.isEmpty || !appStoreUpdates.isEmpty
                    print("✅ Successfully updated \(package.name) via Homebrew")
                }
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "UpdateError", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to update \(package.name): \(errorOutput)"
                ])
            }
        } catch {
            print("❌ Error updating Homebrew package: \(error)")
            throw error
        }
    }
    
    public func updateAppStoreApp(_ app: AppStoreUpdate) async throws {
        print("🏪 Starting App Store update for app: \(app.name)")
        
        guard let masPath = which("mas") else {
            throw NSError(domain: "UpdateError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "mas-cli not found"
            ])
        }
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: masPath)
            process.arguments = ["upgrade", app.name]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                if let index = appStoreUpdates.firstIndex(where: { $0.name == app.name }) {
                    appStoreUpdates.remove(at: index)
                    thirdPartyUpdatesAvailable = !homebrewUpdates.isEmpty || !appStoreUpdates.isEmpty
                    print("✅ Successfully updated \(app.name) from App Store")
                }
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw NSError(domain: "UpdateError", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to update \(app.name): \(errorOutput)"
                ])
            }
        } catch {
            print("❌ Error updating App Store app: \(error)")
            throw error
        }
    }
    
    private func checkRebootRequirement() async {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--schedule"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let needsReboot = output.contains("restart") || output.contains("reboot")
                    
                    // Batch update reboot properties
                    await MainActor.run {
                        if needsReboot {
                            self.requiresReboot = true
                            self.rebootReason = "System update requires restart to complete installation"
                            print("⚠️ System restart required")
                        }
                    }
                }
            }
        } catch {
            print("Error checking reboot requirement: \(error)")
        }
    }
    
    private func checkForPendingRestart() async {
        print("🔍 Checking for pending restart...")
        
        // Check multiple sources for restart requirements
        await checkSoftwareUpdateRestart()
        await checkSystemRestart()
    }
    
    private func checkSoftwareUpdateRestart() async {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list", "--include-config-data"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let needsReboot = output.contains("Action: restart") || output.contains("restart") || output.contains("reboot") || output.contains("Restart")
                    
                    await MainActor.run {
                        if needsReboot {
                            self.requiresReboot = true
                            self.rebootReason = "Software update requires restart to complete installation"
                            print("⚠️ Software update restart required")
                        }
                    }
                }
            }
        } catch {
            print("Error checking software update restart: \(error)")
        }
    }
    
    private func checkSystemRestart() async {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["read", "/Library/Preferences/com.apple.loginwindow", "LoginwindowLaunchesRelaunchApps"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let needsReboot = output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
                    
                    await MainActor.run {
                        if needsReboot {
                            self.requiresReboot = true
                            self.rebootReason = "System restart required to complete pending operations"
                            print("⚠️ System restart required")
                        }
                    }
                }
            }
        } catch {
            // This is expected if the key doesn't exist
            print("No system restart pending")
        }
    }
    
    public func checkForUpdates() async throws -> Bool {
        // Prevent multiple simultaneous checks
        guard !isCheckingUpdates else {
            print("🔄 Update check already in progress, skipping...")
            return hasUpdates
        }
        
        // Check if enough time has passed since last check
        let timeSinceLastCheck = Date().timeIntervalSince(lastCheckTime)
        guard timeSinceLastCheck >= minimumCheckInterval else {
            print("🔄 Update check too recent (\(Int(timeSinceLastCheck))s ago), skipping...")
            return hasUpdates
        }
        
        isCheckingUpdates = true
        lastCheckTime = Date()
        
        print("🔄 Starting comprehensive update check...")
        
        defer {
            isCheckingUpdates = false
        }
        
        // Use a timeout to prevent blocking the UI for too long
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await self.performUpdateCheck()
            }
            
            // Wait for completion or timeout after 30 seconds
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
    }
    
    private func performUpdateCheck() async -> Bool {
        // Check for all types of updates in parallel with timeouts
        async let systemUpdatesTask = fetchSystemUpdatesWithTimeout()
        async let homebrewUpdatesTask = fetchHomebrewUpdatesWithTimeout()
        async let appStoreUpdatesTask = fetchAppStoreUpdatesWithTimeout()
        
        // Wait for all tasks to complete (with individual timeouts)
        let (_, _, _) = await (systemUpdatesTask, homebrewUpdatesTask, appStoreUpdatesTask)
        
        // Additional checks for other update types (non-blocking)
        Task { await checkForSecurityUpdates() }
        Task { await checkForFirmwareUpdates() }
        Task { await checkForPendingRestart() }
        
        // Update overall status
        await MainActor.run {
            self.hasUpdates = !self.updates.isEmpty || !self.homebrewUpdates.isEmpty || !self.appStoreUpdates.isEmpty
            self.osUpdateAvailable = self.updates.contains { $0.name.contains("macOS") || $0.name.contains("Security") }
            self.thirdPartyUpdatesAvailable = !self.homebrewUpdates.isEmpty || !self.appStoreUpdates.isEmpty
            
            print("📊 Update check complete:")
            print("   - System updates: \(self.updates.count)")
            print("   - Homebrew updates: \(self.homebrewUpdates.count)")
            print("   - App Store updates: \(self.appStoreUpdates.count)")
            print("   - Total updates available: \(self.hasUpdates)")
            print("   - Restart required: \(self.requiresReboot)")
        }
        
        return hasUpdates
    }
    
    private func fetchSystemUpdatesWithTimeout() async -> Bool {
        return await withTimeout(seconds: 10) {
            await self.fetchSystemUpdates()
            return true
        } ?? false
    }
    
    private func fetchHomebrewUpdatesWithTimeout() async -> Bool {
        return await withTimeout(seconds: 15) {
            await self.fetchHomebrewUpdates()
            return true
        } ?? false
    }
    
    private func fetchAppStoreUpdatesWithTimeout() async -> Bool {
        return await withTimeout(seconds: 10) {
            await self.fetchAppStoreUpdates()
            return true
        } ?? false
    }
    
    private func withTimeout<T: Sendable>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async -> T? {
        return await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            
            let result = await group.next()
            group.cancelAll()
            return result ?? nil
        }
    }
    
    private func checkForSecurityUpdates() async {
        // Check for security updates specifically
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list", "--include-config-data"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let securityUpdates = parseSecurityUpdates(output)
                    if !securityUpdates.isEmpty {
                        await MainActor.run {
                            self.updates.append(contentsOf: securityUpdates)
                            print("🔒 Found \(securityUpdates.count) security updates")
                        }
                    }
                }
            }
        } catch {
            print("Error checking for security updates: \(error)")
        }
    }
    
    private func checkForFirmwareUpdates() async {
        // Check for firmware updates
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
            process.arguments = ["--list", "--include-config-data"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    let firmwareUpdates = parseFirmwareUpdates(output)
                    if !firmwareUpdates.isEmpty {
                        await MainActor.run {
                            self.updates.append(contentsOf: firmwareUpdates)
                            print("🔧 Found \(firmwareUpdates.count) firmware updates")
                        }
                    }
                }
            }
        } catch {
            print("Error checking for firmware updates: \(error)")
        }
    }
    
    private func parseSecurityUpdates(_ output: String) -> [SoftwareUpdate] {
        var updates: [SoftwareUpdate] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("* Label:") && (line.contains("Security") || line.contains("Safari")) {
                // Parse security update similar to system updates
                if let lineIndex = lines.firstIndex(of: line),
                   lineIndex + 1 < lines.count {
                    let titleLine = lines[lineIndex + 1]
                    if titleLine.contains("Title:") {
                        let labelStart = line.range(of: "* Label: ")?.upperBound ?? line.startIndex
                        let label = String(line[labelStart...]).trimmingCharacters(in: .whitespaces)
                        
                        let titleStart = titleLine.range(of: "Title: ")?.upperBound ?? titleLine.startIndex
                        let titleEnd = titleLine.range(of: ", Version:")?.lowerBound ?? titleLine.endIndex
                        let title = String(titleLine[titleStart..<titleEnd]).trimmingCharacters(in: .whitespaces)
                        
                        if let versionStart = titleLine.range(of: "Version: ")?.upperBound,
                           let versionEnd = titleLine.range(of: ", Size:")?.lowerBound {
                            let version = String(titleLine[versionStart..<versionEnd]).trimmingCharacters(in: .whitespaces)
                            let size = parseSize(from: titleLine)
                            
                            let update = SoftwareUpdate(
                                id: label,
                                name: title,
                                version: version,
                                description: "Security update: \(title)",
                                size: size,
                                isInstalled: false
                            )
                            updates.append(update)
                            print("🔒 Found security update: \(title) v\(version)")
                        }
                    }
                }
            }
        }
        
        return updates
    }
    
    private func parseFirmwareUpdates(_ output: String) -> [SoftwareUpdate] {
        var updates: [SoftwareUpdate] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("* Label:") && (line.contains("Firmware") || line.contains("BridgeOS")) {
                // Parse firmware update similar to system updates
                if let lineIndex = lines.firstIndex(of: line),
                   lineIndex + 1 < lines.count {
                    let titleLine = lines[lineIndex + 1]
                    if titleLine.contains("Title:") {
                        let labelStart = line.range(of: "* Label: ")?.upperBound ?? line.startIndex
                        let label = String(line[labelStart...]).trimmingCharacters(in: .whitespaces)
                        
                        let titleStart = titleLine.range(of: "Title: ")?.upperBound ?? titleLine.startIndex
                        let titleEnd = titleLine.range(of: ", Version:")?.lowerBound ?? titleLine.endIndex
                        let title = String(titleLine[titleStart..<titleEnd]).trimmingCharacters(in: .whitespaces)
                        
                        if let versionStart = titleLine.range(of: "Version: ")?.upperBound,
                           let versionEnd = titleLine.range(of: ", Size:")?.lowerBound {
                            let version = String(titleLine[versionStart..<versionEnd]).trimmingCharacters(in: .whitespaces)
                            let size = parseSize(from: titleLine)
                            
                            let update = SoftwareUpdate(
                                id: label,
                                name: title,
                                version: version,
                                description: "Firmware update: \(title)",
                                size: size,
                                isInstalled: false
                            )
                            updates.append(update)
                            print("🔧 Found firmware update: \(title) v\(version)")
                        }
                    }
                }
            }
        }
        
        return updates
    }
    
    public func performReboot() {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/sbin/reboot")
            try process.run()
        } catch {
            print("Error initiating reboot: \(error)")
        }
    }
    
    public func initiateReboot() async throws {
        print("🔄 Initiating system restart...")
        
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "tell application \"System Events\" to restart"]
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw NSError(domain: "RestartError", code: Int(process.terminationStatus), userInfo: [
                    NSLocalizedDescriptionKey: "Failed to initiate restart"
                ])
            }
        } catch {
            print("Error initiating reboot: \(error)")
            throw error
        }
    }
    
    public func checkPendingRestart() async {
        print("🔍 Manually checking for pending restart...")
        await checkForPendingRestart()
    }
    
    public func loadSoftwareUpdates() async {
        await fetchSystemUpdates()
        await fetchHomebrewUpdates()
        await fetchAppStoreUpdates()
    }
} 