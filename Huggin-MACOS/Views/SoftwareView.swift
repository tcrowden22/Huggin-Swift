import SwiftUI
import Charts
import AppKit

// MARK: - Data Models

public enum VulnerabilitySeverity: String, CaseIterable, Sendable {
    case low = "Low"
    case medium = "Medium" 
    case high = "High"
    case critical = "Critical"
    
    var color: Color {
        switch self {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

public enum FilterType: String, CaseIterable, Sendable {
    case all = "All"
    case system = "System"
    case thirdParty = "Third-Party"
}

public enum StatusFilter: String, CaseIterable, Sendable {
    case all = "All"
    case upToDate = "Up-to-Date"
    case outOfDate = "Out-of-Date"
    case vulnerable = "Vulnerable"
}

public struct AppInfo: Identifiable, Hashable, Sendable {
    public let id = UUID()
    public let icon: String // SF Symbol name for fallback
    public let bundlePath: String? // Path to app bundle for extracting real icon
    public let bundleIdentifier: String? // Bundle identifier
    public let name: String
    public let version: String
    public let latestVersion: String?
    public let publisher: String
    public let installDate: Date
    public let isOutdated: Bool
    public let cveCount: Int
    public let maxSeverity: VulnerabilitySeverity
    public var autoPatchEnabled: Bool
    public let lastLaunched: Date
    public let avgCpuUsage: Double // 0.0 to 1.0
    public let crashCount: Int
    public let licenseType: String
    public let expirationDate: Date?
    public let seatCount: Int?
    public var isLicenseExpanded: Bool = false
    public var isSelected: Bool = false
    
    // Custom Hashable implementation
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(version)
        hasher.combine(publisher)
    }
    
    // Custom Equatable implementation
    public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
        return lhs.id == rhs.id &&
               lhs.name == rhs.name &&
               lhs.version == rhs.version &&
               lhs.publisher == rhs.publisher
    }
    
    public init(
        icon: String = "app.fill",
        bundlePath: String? = nil,
        bundleIdentifier: String? = nil,
        name: String,
        version: String,
        latestVersion: String? = nil,
        publisher: String,
        installDate: Date = Date(),
        isOutdated: Bool = false,
        cveCount: Int = 0,
        maxSeverity: VulnerabilitySeverity = .low,
        autoPatchEnabled: Bool = false,
        lastLaunched: Date = Date(),
        avgCpuUsage: Double = 0.0,
        crashCount: Int = 0,
        licenseType: String = "Freeware",
        expirationDate: Date? = nil,
        seatCount: Int? = nil
    ) {
        self.icon = icon
        self.bundlePath = bundlePath
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.latestVersion = latestVersion
        self.publisher = publisher
        self.installDate = installDate
        self.isOutdated = isOutdated
        self.cveCount = cveCount
        self.maxSeverity = maxSeverity
        self.autoPatchEnabled = autoPatchEnabled
        self.lastLaunched = lastLaunched
        self.avgCpuUsage = avgCpuUsage
        self.crashCount = crashCount
        self.licenseType = licenseType
        self.expirationDate = expirationDate
        self.seatCount = seatCount
    }
}

// MARK: - App Icon View Component

struct AppIconView: View {
    let app: AppInfo
    let size: CGFloat
    
    @State private var appIcon: NSImage?
    
    init(app: AppInfo, size: CGFloat = 32) {
        self.app = app
        self.size = size
    }
    
    var body: some View {
        Group {
            if let icon = appIcon {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: app.icon)
                    .font(.system(size: size * 0.6))
                    .foregroundColor(.blue)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.15))
        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 1)
        .onAppear {
            loadAppIcon()
        }
    }
    
    private func loadAppIcon() {
        guard let bundlePath = app.bundlePath,
              !bundlePath.isEmpty else {
            // For Homebrew apps or apps without bundle paths, keep using SF Symbols
            return
        }
        
        Task.detached {
            let iconData = await extractAppIconData(from: bundlePath)
            await MainActor.run {
                if let data = iconData {
                    self.appIcon = NSImage(data: data)
                }
            }
        }
    }
    
    private func extractAppIconData(from bundlePath: String) async -> Data? {
        guard let bundle = Bundle(path: bundlePath) else { return nil }
        
        // Try to get the app icon from the bundle
        if let iconFileName = bundle.infoDictionary?["CFBundleIconFile"] as? String {
            let iconPath = bundle.path(forResource: iconFileName, ofType: nil) ??
                          bundle.path(forResource: iconFileName, ofType: "icns")
            
            if let iconPath = iconPath,
               let image = NSImage(contentsOfFile: iconPath),
               let tiffData = image.tiffRepresentation {
                return tiffData
            }
        }
        
        // Try common icon file names
        let commonIconNames = ["icon.icns", "Icon.icns", "app.icns", "AppIcon.icns"]
        let resourcesPath = bundle.resourcePath ?? bundlePath
        
        for iconName in commonIconNames {
            let iconPath = (resourcesPath as NSString).appendingPathComponent(iconName)
            if FileManager.default.fileExists(atPath: iconPath),
               let image = NSImage(contentsOfFile: iconPath),
               let tiffData = image.tiffRepresentation {
                return tiffData
            }
        }
        
        // Use NSWorkspace to get the icon for the app
        let workspace = NSWorkspace.shared
        let icon = workspace.icon(forFile: bundlePath)
        return icon.tiffRepresentation
    }
}

// MARK: - View Model

@MainActor
public class SoftwareViewModel: ObservableObject {
    @Published public var installedApps: [AppInfo] = []
    @Published public var searchQuery: String = ""
    @Published public var selectedApp: AppInfo?
    @Published public var filterType: FilterType = .all
    @Published public var statusFilter: StatusFilter = .all
    @Published public var allSelected: Bool = false
    
    public init() {
        loadInstalledApps()
    }
    
    // MARK: - Computed Properties
    
    public var filteredApps: [AppInfo] {
        var apps = installedApps
        
        // Apply search filter
        if !searchQuery.isEmpty {
            apps = apps.filter { app in
                app.name.localizedCaseInsensitiveContains(searchQuery) ||
                app.publisher.localizedCaseInsensitiveContains(searchQuery)
            }
        }
        
        // Apply type filter
        switch filterType {
        case .all:
            break
        case .system:
            apps = apps.filter { $0.publisher.contains("Apple") }
        case .thirdParty:
            apps = apps.filter { !$0.publisher.contains("Apple") }
        }
        
        // Apply status filter
        switch statusFilter {
        case .all:
            break
        case .upToDate:
            apps = apps.filter { !$0.isOutdated }
        case .outOfDate:
            apps = apps.filter { $0.isOutdated }
        case .vulnerable:
            apps = apps.filter { $0.cveCount > 0 }
        }
        
        return apps
    }
    
    public var selectedApps: [AppInfo] {
        return installedApps.filter { $0.isSelected }
    }
    
    // MARK: - Public Methods
    
    public func loadInstalledApps() {
        Task {
            let apps = await withTaskGroup(of: [AppInfo].self) { group in
                group.addTask { await self.scanApplicationsFolder() }
                group.addTask { await self.scanHomebrewApps() }
                group.addTask { await self.scanSystemApps() }
                
                var allApps: [AppInfo] = []
                for await appGroup in group {
                    allApps.append(contentsOf: appGroup)
                }
                return allApps
            }
            
            // Deduplicate apps based on name (case-insensitive)
            // Prefer GUI apps over command-line tools when duplicates exist
            let deduplicatedApps = deduplicateApps(apps)
            
            self.installedApps = deduplicatedApps.sorted { $0.name < $1.name }
        }
    }
    
    private func deduplicateApps(_ apps: [AppInfo]) -> [AppInfo] {
        var appsByName: [String: [AppInfo]] = [:]
        
        // Group apps by normalized name
        for app in apps {
            let normalizedName = app.name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if appsByName[normalizedName] == nil {
                appsByName[normalizedName] = []
            }
            appsByName[normalizedName]?.append(app)
        }
        
        var deduplicatedApps: [AppInfo] = []
        
        for (_, duplicateApps) in appsByName {
            if duplicateApps.count == 1 {
                // No duplicates, keep the app
                deduplicatedApps.append(duplicateApps[0])
            } else {
                // Multiple apps with same name - prefer GUI app over CLI
                let preferredApp = selectPreferredApp(from: duplicateApps)
                deduplicatedApps.append(preferredApp)
                
                // Log the deduplication for debugging
                let appNames = duplicateApps.map { "\($0.name) (\($0.publisher))" }.joined(separator: ", ")
                print("🔍 Deduplicated: \(appNames) → Keeping: \(preferredApp.name) (\(preferredApp.publisher))")
            }
        }
        
        return deduplicatedApps
    }
    
    private func selectPreferredApp(from apps: [AppInfo]) -> AppInfo {
        // Preference order:
        // 1. GUI apps (with bundle paths) over CLI tools
        // 2. Apps from known publishers over unknown ones
        // 3. Newer versions over older ones
        // 4. Non-Homebrew over Homebrew (for GUI apps)
        
        let guiApps = apps.filter { $0.bundlePath != nil && !$0.bundlePath!.isEmpty }
        let cliApps = apps.filter { $0.bundlePath == nil || $0.bundlePath!.isEmpty }
        
        // If we have GUI apps, prefer them
        if !guiApps.isEmpty {
            // Among GUI apps, prefer non-Homebrew
            let nonHomebrewGUI = guiApps.filter { !$0.publisher.contains("Homebrew") }
            if !nonHomebrewGUI.isEmpty {
                return nonHomebrewGUI.first!
            }
            return guiApps.first!
        }
        
        // If only CLI apps, prefer newer versions
        return cliApps.sorted { app1, app2 in
            // Simple version comparison (not perfect but good enough)
            return app1.version.compare(app2.version, options: .numeric) == .orderedDescending
        }.first ?? apps.first!
    }
    
    private func scanApplicationsFolder() async -> [AppInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                var apps: [AppInfo] = []
                let applicationsURL = URL(fileURLWithPath: "/Applications")
                
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: applicationsURL,
                        includingPropertiesForKeys: [.isApplicationKey, .creationDateKey, .contentModificationDateKey],
                        options: [.skipsHiddenFiles]
                    )
                    
                    for appURL in contents {
                        let resourceValues = try? appURL.resourceValues(forKeys: [.isApplicationKey])
                        guard resourceValues?.isApplication == true else { continue }
                        
                        if let appInfo = await self.createAppInfo(from: appURL) {
                            apps.append(appInfo)
                        }
                    }
                } catch {
                    // Silently handle scanning errors
                }
                
                continuation.resume(returning: apps)
            }
        }
    }
    
    private func scanHomebrewApps() async -> [AppInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                var apps: [AppInfo] = []
                
                // Check if Homebrew is installed
                let homebrewPaths = [
                    "/opt/homebrew/bin/brew", // Apple Silicon
                    "/usr/local/bin/brew"     // Intel
                ]
                
                var brewPath: String?
                for path in homebrewPaths {
                    if FileManager.default.fileExists(atPath: path) {
                        brewPath = path
                        break
                    }
                }
                
                guard let brew = brewPath else {
                    continuation.resume(returning: apps)
                    return
                }
                
                // Get list of installed Homebrew packages
                let process = Process()
                process.launchPath = brew
                process.arguments = ["list", "--formula", "--versions"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe() // Suppress errors
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        let lines = output.components(separatedBy: .newlines)
                        
                        for line in lines {
                            if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let components = line.components(separatedBy: " ")
                                if components.count >= 2 {
                                    let name = components[0]
                                    let version = components[1]
                                    
                                    let appInfo = AppInfo(
                                        icon: "terminal.fill",
                                        bundlePath: nil, // Homebrew packages don't have bundle paths
                                        bundleIdentifier: "homebrew.\(name)",
                                        name: name,
                                        version: version,
                                        latestVersion: await self.getHomebrewLatestVersion(package: name),
                                        publisher: "Homebrew Community",
                                        installDate: await self.getHomebrewInstallDate(package: name),
                                        isOutdated: await self.isHomebrewPackageOutdated(package: name),
                                        cveCount: 0, // TODO: Integrate with vulnerability databases
                                        maxSeverity: .low,
                                        autoPatchEnabled: false,
                                        lastLaunched: Date(), // TODO: Track actual usage
                                        avgCpuUsage: 0.0, // TODO: Get from system monitoring
                                        crashCount: 0, // TODO: Parse crash logs
                                        licenseType: "Open Source",
                                        expirationDate: nil,
                                        seatCount: nil
                                    )
                                    apps.append(appInfo)
                                }
                            }
                        }
                    }
                } catch {
                    // Silently handle Homebrew scanning errors
                }
                
                continuation.resume(returning: apps)
            }
        }
    }
    
    private func scanSystemApps() async -> [AppInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                var apps: [AppInfo] = []
                let systemAppsURL = URL(fileURLWithPath: "/System/Applications")
                
                do {
                    let contents = try FileManager.default.contentsOfDirectory(
                        at: systemAppsURL,
                        includingPropertiesForKeys: [.isApplicationKey, .creationDateKey],
                        options: [.skipsHiddenFiles]
                    )
                    
                    for appURL in contents {
                        let resourceValues = try? appURL.resourceValues(forKeys: [.isApplicationKey])
                        guard resourceValues?.isApplication == true else { continue }
                        
                        if let appInfo = await self.createAppInfo(from: appURL, isSystemApp: true) {
                            apps.append(appInfo)
                        }
                    }
                } catch {
                    // Silently handle system apps scanning errors
                }
                
                continuation.resume(returning: apps)
            }
        }
    }
    
    private func createAppInfo(from appURL: URL, isSystemApp: Bool = false) async -> AppInfo? {
        let appName = appURL.deletingPathExtension().lastPathComponent
        let bundlePath = appURL.path
        
        // Get app bundle info
        guard let bundle = Bundle(path: bundlePath) else { return nil }
        
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let _ = bundle.infoDictionary?["CFBundleVersion"] as? String ?? version
        let displayName = bundle.infoDictionary?["CFBundleDisplayName"] as? String ?? 
                         bundle.infoDictionary?["CFBundleName"] as? String ?? appName
        
        // Determine publisher
        let publisher = getAppPublisher(bundle: bundle, isSystemApp: isSystemApp)
        
        // Get installation date
        let installDate = getInstallDate(for: appURL)
        
        // Get app icon name
        let iconName = getAppIcon(bundle: bundle, isSystemApp: isSystemApp)
        
        // Check if app is outdated (simplified check)
        let isOutdated = checkIfAppIsOutdated(bundle: bundle, currentVersion: version)
        
        // Get last launched date
        let lastLaunched = getLastLaunchedDate(bundleIdentifier: bundle.bundleIdentifier)
        
        return AppInfo(
            icon: iconName,
            bundlePath: appURL.path,
            bundleIdentifier: bundle.bundleIdentifier,
            name: displayName,
            version: version,
            latestVersion: isOutdated ? getLatestVersion(for: bundle) : version,
            publisher: publisher,
            installDate: installDate,
            isOutdated: isOutdated,
            cveCount: getCVECount(for: displayName, version: version),
            maxSeverity: getMaxSeverity(for: displayName),
            autoPatchEnabled: false, // TODO: Read from preferences
            lastLaunched: lastLaunched,
            avgCpuUsage: getAverageCPUUsage(bundleIdentifier: bundle.bundleIdentifier),
            crashCount: getCrashCount(bundleIdentifier: bundle.bundleIdentifier),
            licenseType: getLicenseType(bundle: bundle, isSystemApp: isSystemApp),
            expirationDate: nil, // TODO: Read from licensing system
            seatCount: nil // TODO: Read from licensing system
        )
    }
    
    // MARK: - Helper Methods for Real Data
    
    private func getAppPublisher(bundle: Bundle, isSystemApp: Bool) -> String {
        if isSystemApp {
            return "Apple Inc."
        }
        
        if let copyright = bundle.infoDictionary?["NSHumanReadableCopyright"] as? String {
            // Try to extract company name from copyright string
            if copyright.contains("Apple") {
                return "Apple Inc."
            } else if copyright.contains("Microsoft") {
                return "Microsoft Corporation"
            } else if copyright.contains("Adobe") {
                return "Adobe Inc."
            } else if copyright.contains("Google") {
                return "Google LLC"
            }
        }
        
        // Fallback to bundle identifier domain
        if let bundleID = bundle.bundleIdentifier {
            let components = bundleID.components(separatedBy: ".")
            if components.count >= 2 {
                let domain = components[1]
                return domain.capitalized + " Inc."
            }
        }
        
        return "Unknown Publisher"
    }
    
    private func getInstallDate(for appURL: URL) -> Date {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: appURL.path)
            return attributes[.creationDate] as? Date ?? Date()
        } catch {
            return Date()
        }
    }
    
    private func getAppIcon(bundle: Bundle, isSystemApp: Bool) -> String {
        let appName = bundle.infoDictionary?["CFBundleName"] as? String ?? ""
        
        // Map common apps to appropriate SF Symbols
        switch appName.lowercased() {
        case let name where name.contains("safari"):
            return "safari.fill"
        case let name where name.contains("mail"):
            return "mail.fill"
        case let name where name.contains("finder"):
            return "folder.fill"
        case let name where name.contains("terminal"):
            return "terminal.fill"
        case let name where name.contains("music"):
            return "music.note"
        case let name where name.contains("photo"):
            return "photo.fill"
        case let name where name.contains("calendar"):
            return "calendar"
        case let name where name.contains("calculator"):
            return "function"
        case let name where name.contains("text"):
            return "doc.text.fill"
        case let name where name.contains("word"):
            return "doc.text.fill"
        case let name where name.contains("excel"):
            return "tablecells.fill"
        case let name where name.contains("powerpoint"):
            return "rectangle.fill.on.rectangle.fill"
        case let name where name.contains("chrome"):
            return "globe"
        case let name where name.contains("firefox"):
            return "globe"
        case let name where name.contains("slack"):
            return "message.fill"
        case let name where name.contains("discord"):
            return "message.fill"
        case let name where name.contains("zoom"):
            return "video.fill"
        case let name where name.contains("spotify"):
            return "music.note"
        default:
            return isSystemApp ? "gearshape.fill" : "app.fill"
        }
    }
    
    private func checkIfAppIsOutdated(bundle: Bundle, currentVersion: String) -> Bool {
        // Simple heuristic: check if it's a major app and randomize for demo
        guard let bundleID = bundle.bundleIdentifier else { return false }
        
        let majorApps = [
            "com.microsoft.Word",
            "com.adobe.Photoshop",
            "com.google.Chrome",
            "com.spotify.client"
        ]
        
        return majorApps.contains(bundleID) && Bool.random()
    }
    
    private func getLatestVersion(for bundle: Bundle) -> String? {
        // TODO: Implement real version checking
        // - Query App Store API for Mac App Store apps
        // - Check Homebrew for command-line tools
        // - Query vendor APIs for major software
        
        let currentVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let versionComponents = currentVersion.components(separatedBy: ".")
        
        if let major = Int(versionComponents.first ?? "1") {
            return "\(major).\(Int.random(in: 1...9)).0"
        }
        
        return currentVersion
    }
    
    private func getLastLaunchedDate(bundleIdentifier: String?) -> Date {
        // TODO: Implement real last launched tracking
        // - Query LaunchServices database
        // - Parse system logs for app launch events
        // - Use NSWorkspace runningApplications for currently running apps
        
        // For now, return a random recent date
        let daysAgo = Int.random(in: 0...30)
        return Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
    }
    
    private func getAverageCPUUsage(bundleIdentifier: String?) -> Double {
        // TODO: Implement real CPU usage tracking
        // - Use Activity Monitor data
        // - Parse system resource usage logs
        // - Integrate with system monitoring APIs
        
        return Double.random(in: 0.0...0.5) // Random CPU usage between 0-50%
    }
    
    private func getCrashCount(bundleIdentifier: String?) -> Int {
        // TODO: Implement real crash log parsing
        // - Scan ~/Library/Logs/DiagnosticReports for app crashes
        // - Parse crash log metadata
        // - Filter by time period (e.g., last 30 days)
        
        return Int.random(in: 0...3) // Random crash count
    }
    
    private func getCVECount(for appName: String, version: String) -> Int {
        // TODO: Integrate with CVE databases
        // - Query National Vulnerability Database (NVD)
        // - Check vendor security advisories
        // - Use vulnerability scanning services
        
        let vulnerableApps = ["Adobe", "Microsoft", "Chrome"]
        return vulnerableApps.contains { appName.contains($0) } ? Int.random(in: 0...5) : 0
    }
    
    private func getMaxSeverity(for appName: String) -> VulnerabilitySeverity {
        // TODO: Implement real vulnerability severity assessment
        
        if appName.contains("Adobe") || appName.contains("Microsoft") {
            return [.medium, .high, .critical].randomElement() ?? .low
        }
        return .low
    }
    
    private func getLicenseType(bundle: Bundle, isSystemApp: Bool) -> String {
        if isSystemApp {
            return "System Software"
        }
        
        guard let bundleID = bundle.bundleIdentifier else { return "Unknown" }
        
        switch bundleID {
        case let id where id.contains("microsoft"):
            return "Subscription"
        case let id where id.contains("adobe"):
            return "Commercial"
        case let id where id.contains("apple"):
            return "Freeware"
        case let id where id.contains("spotify"):
            return "Freemium"
        default:
            return ["Freeware", "Commercial", "Open Source"].randomElement() ?? "Unknown"
        }
    }
    
    // MARK: - Homebrew Helper Methods
    
    private func getHomebrewLatestVersion(package: String) async -> String? {
        // TODO: Query Homebrew API for latest version
        return nil
    }
    
    private func getHomebrewInstallDate(package: String) async -> Date {
        // TODO: Parse Homebrew installation logs
        return Date()
    }
    
    private func isHomebrewPackageOutdated(package: String) async -> Bool {
        // TODO: Check with `brew outdated`
        return Bool.random()
    }
    
    public func update(app: AppInfo) {
        // TODO: Implement real update functionality
        // - Check app source (App Store, Homebrew, DMG, etc.)
        // - Download and install updates securely
        // - Verify signatures and checksums
        // - Handle update failures and rollbacks
        // - Update vulnerability status post-update
        
        guard let index = installedApps.firstIndex(where: { $0.id == app.id }) else { return }
        
        // Simulate update process
        var updatedApp = app
        if let latestVersion = app.latestVersion {
            updatedApp = AppInfo(
                icon: app.icon,
                bundlePath: app.bundlePath,
                bundleIdentifier: app.bundleIdentifier,
                name: app.name,
                version: latestVersion,
                latestVersion: latestVersion,
                publisher: app.publisher,
                installDate: app.installDate,
                isOutdated: false,
                cveCount: 0, // Assume vulnerabilities are patched
                maxSeverity: .low,
                autoPatchEnabled: app.autoPatchEnabled,
                lastLaunched: app.lastLaunched,
                avgCpuUsage: app.avgCpuUsage,
                crashCount: app.crashCount,
                licenseType: app.licenseType,
                expirationDate: app.expirationDate,
                seatCount: app.seatCount
            )
        }
        
        installedApps[index] = updatedApp
    }
    
    public func bulkUpdate() {
        // TODO: Implement bulk update functionality
        // - Queue multiple updates safely
        // - Handle dependencies and conflicts
        // - Provide progress tracking
        // - Allow cancellation of batch operations
        
        let selectedApps = installedApps.filter { $0.isSelected && $0.isOutdated }
        for app in selectedApps {
            update(app: app)
        }
        
        // Clear selections after bulk operation
        toggleAllSelection(false)
    }
    
    public func bulkUninstall() {
        // TODO: Implement bulk uninstall functionality
        // - Safely remove selected applications
        // - Clean up associated files and preferences
        // - Handle system-protected apps
        // - Provide confirmation dialogs for dangerous operations
        
        installedApps.removeAll { $0.isSelected }
        allSelected = false
    }
    
    public func exportCSV() {
        // TODO: Implement CSV export functionality
        // - Generate comprehensive software inventory report
        // - Include vulnerability and licensing information
        // - Format for compliance and audit purposes
        // - Allow custom field selection
        
        // Placeholder: would generate CSV file
        print("Exporting \(installedApps.count) applications to CSV...")
    }
    
    public func toggleAppSelection(_ app: AppInfo) {
        guard let index = installedApps.firstIndex(where: { $0.id == app.id }) else { return }
        installedApps[index].isSelected.toggle()
        updateAllSelectedState()
    }
    
    public func toggleAllSelection(_ selected: Bool? = nil) {
        let newSelection = selected ?? !allSelected
        allSelected = newSelection
        
        for index in installedApps.indices {
            installedApps[index].isSelected = newSelection
        }
    }
    
    private func updateAllSelectedState() {
        let filteredCount = filteredApps.count
        let selectedCount = filteredApps.filter { $0.isSelected }.count
        
        if selectedCount == 0 {
            allSelected = false
        } else if selectedCount == filteredCount {
            allSelected = true
        }
    }
}

// MARK: - Main Software View

struct SoftwareView: View {
    @StateObject private var viewModel = SoftwareViewModel()
    @State private var showingCrashLogs = false
    @State private var selectedCrashApp: AppInfo?
    
    var body: some View {
        NavigationSplitView {
            InstalledAppsView(viewModel: viewModel, showingCrashLogs: $showingCrashLogs, selectedCrashApp: $selectedCrashApp)
        } detail: {
            if let selectedApp = viewModel.selectedApp {
                AppDetailView(app: selectedApp, viewModel: viewModel)
            } else {
                ContentUnavailableView(
                    "Select an Application",
                    systemImage: "app.fill",
                    description: Text("Choose an app from the sidebar to view detailed information")
                )
            }
        }
        .sheet(isPresented: $showingCrashLogs) {
            if let crashApp = selectedCrashApp {
                CrashLogsView(app: crashApp)
            }
        }
        .navigationTitle("Software Management")
    }
}

// MARK: - Installed Apps List View

struct InstalledAppsView: View {
    @ObservedObject var viewModel: SoftwareViewModel
    @Binding var showingCrashLogs: Bool
    @Binding var selectedCrashApp: AppInfo?
    
    var body: some View {
        VStack(spacing: 0) {
            // Filters & Search Header
            VStack(spacing: 12) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search applications...", text: $viewModel.searchQuery)
                        .textFieldStyle(.roundedBorder)
                }
                
                // Type Filter
                Picker("App Type", selection: $viewModel.filterType) {
                    ForEach(FilterType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                
                // Status Filter
                Picker("Status", selection: $viewModel.statusFilter) {
                    ForEach(StatusFilter.allCases, id: \.self) { status in
                        Text(status.rawValue).tag(status)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            // Bulk Actions Toolbar
            BulkActionsToolbar(viewModel: viewModel)
            
            // Apps List
            List(viewModel.filteredApps, id: \.id, selection: $viewModel.selectedApp) { app in
                AppRowView(
                    app: app,
                    viewModel: viewModel,
                    showingCrashLogs: $showingCrashLogs,
                    selectedCrashApp: $selectedCrashApp
                )
                .tag(app)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Bulk Actions Toolbar

struct BulkActionsToolbar: View {
    @ObservedObject var viewModel: SoftwareViewModel
    
    var body: some View {
        HStack {
            // Select All Checkbox
            Button(action: {
                viewModel.toggleAllSelection()
            }) {
                HStack {
                    Image(systemName: viewModel.allSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(viewModel.allSelected ? .blue : .secondary)
                    Text("Select All")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Bulk Action Buttons
            HStack(spacing: 8) {
                Button("Update Selected") {
                    viewModel.bulkUpdate()
                }
                .disabled(viewModel.selectedApps.filter { $0.isOutdated }.isEmpty)
                
                Button("Uninstall Selected") {
                    viewModel.bulkUninstall()
                }
                .disabled(viewModel.selectedApps.isEmpty)
                
                Button("Export CSV") {
                    viewModel.exportCSV()
                }
            }
            .font(.caption)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .border(Color(NSColor.separatorColor), width: 0.5)
    }
}

// MARK: - App Row View

struct AppRowView: View {
    let app: AppInfo
    @ObservedObject var viewModel: SoftwareViewModel
    @Binding var showingCrashLogs: Bool
    @Binding var selectedCrashApp: AppInfo?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
    
    var body: some View {
        HStack(spacing: 12) {
            // Selection Checkbox
            Button(action: {
                viewModel.toggleAppSelection(app)
            }) {
                Image(systemName: app.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(app.isSelected ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            
            // App Icon
            AppIconView(app: app, size: 32)
                .background(Color.white.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 0.5)
                )
            
            // App Info
            VStack(alignment: .leading, spacing: 4) {
                // Name and Version
                HStack {
                    Text(app.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Version Info
                    HStack(spacing: 4) {
                        Text(app.version)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if app.isOutdated, let latest = app.latestVersion {
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(latest)
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }
                
                // Publisher and Install Date
                HStack {
                    Text(app.publisher)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Installed: \(dateFormatter.string(from: app.installDate))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                // Status Badges and Metrics
                HStack {
                    // Vulnerability Badge
                    if app.cveCount > 0 {
                        Label("CVE: \(app.cveCount)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(app.maxSeverity.color)
                            .clipShape(Capsule())
                    }
                    
                    // Crash Count Badge
                    if app.crashCount > 0 {
                        Button(action: {
                            selectedCrashApp = app
                            showingCrashLogs = true
                        }) {
                            Label("Crashes: \(app.crashCount)", systemImage: "exclamationmark.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                    
                    // Telemetry Info
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("CPU: \(String(format: "%.1f%%", app.avgCpuUsage * 100))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("Last: \(dateFormatter.string(from: app.lastLaunched))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Auto-Patch Toggle
                HStack {
                    Toggle("Auto-Patch", isOn: .constant(app.autoPatchEnabled))
                        .font(.caption2)
                        .disabled(true) // TODO: Make functional when integrated
                    
                    Spacer()
                    
                    // Update Button
                    if app.isOutdated {
                        Button("Update Now") {
                            viewModel.update(app: app)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .font(.caption)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - App Detail View

struct AppDetailView: View {
    let app: AppInfo
    @ObservedObject var viewModel: SoftwareViewModel
    @State private var isLicenseExpanded = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                HStack {
                    AppIconView(app: app, size: 64)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(app.name)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        Text(app.publisher)
                            .font(.title2)
                            .foregroundColor(.secondary)
                        
                        HStack {
                            Text("Version \(app.version)")
                                .font(.title3)
                            
                            if app.isOutdated, let latest = app.latestVersion {
                                Image(systemName: "arrow.right")
                                    .foregroundColor(.orange)
                                Text(latest)
                                    .font(.title3)
                                    .foregroundColor(.orange)
                                
                                Button("Update Now") {
                                    viewModel.update(app: app)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    
                    Spacer()
                }
                
                Divider()
                
                // Security & Vulnerabilities
                VStack(alignment: .leading, spacing: 12) {
                    Text("Security Status")
                        .font(.headline)
                    
                    if app.cveCount > 0 {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(app.maxSeverity.color)
                            Text("\(app.cveCount) known vulnerabilities")
                            Text("Max Severity: \(app.maxSeverity.rawValue)")
                                .foregroundColor(app.maxSeverity.color)
                                .fontWeight(.semibold)
                        }
                    } else {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(.green)
                            Text("No known vulnerabilities")
                                .foregroundColor(.green)
                        }
                    }
                    
                    Toggle("Auto-Patch Enabled", isOn: .constant(app.autoPatchEnabled))
                        .disabled(true) // TODO: Make functional
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Usage Statistics
                VStack(alignment: .leading, spacing: 12) {
                    Text("Usage Statistics")
                        .font(.headline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Text("Last Launched:")
                            Text(dateFormatter.string(from: app.lastLaunched))
                                .foregroundColor(.secondary)
                        }
                        
                        GridRow {
                            Text("Average CPU Usage:")
                            Text("\(String(format: "%.1f%%", app.avgCpuUsage * 100))")
                                .foregroundColor(.secondary)
                        }
                        
                        GridRow {
                            Text("Crash Count:")
                            Text("\(app.crashCount)")
                                .foregroundColor(app.crashCount > 0 ? .red : .secondary)
                        }
                        
                        GridRow {
                            Text("Install Date:")
                            Text(dateFormatter.string(from: app.installDate))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                // Licensing Information
                DisclosureGroup("Licensing Details", isExpanded: $isLicenseExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("License Type:")
                                .fontWeight(.medium)
                            Text(app.licenseType)
                                .foregroundColor(.secondary)
                        }
                        
                        if let expirationDate = app.expirationDate {
                            HStack {
                                Text("Expires:")
                                    .fontWeight(.medium)
                                Text(dateFormatter.string(from: expirationDate))
                                    .foregroundColor(expirationDate < Date() ? .red : .secondary)
                            }
                        }
                        
                        if let seatCount = app.seatCount {
                            HStack {
                                Text("Licensed Seats:")
                                    .fontWeight(.medium)
                                Text("\(seatCount)")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                
                Spacer()
            }
            .padding()
        }
        .frame(minWidth: 500)
    }
}

// MARK: - Crash Logs Modal

struct CrashLogsView: View {
    let app: AppInfo
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title)
                Text("Crash Reports - \(app.name)")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // TODO: Implement real crash log viewing
            // - Parse system crash logs from ~/Library/Logs/DiagnosticReports
            // - Filter by application bundle identifier
            // - Display crash timestamps, stack traces, and exception codes
            // - Provide options to submit reports to developers
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Crash Log Analysis")
                        .font(.headline)
                    
                    Text("Found \(app.crashCount) crash reports for \(app.name)")
                        .foregroundColor(.secondary)
                    
                    // Placeholder crash log entries
                    ForEach(0..<app.crashCount, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("Crash \(index + 1)")
                                    .fontWeight(.medium)
                                Spacer()
                                Text(Calendar.current.date(byAdding: .day, value: -index, to: Date()) ?? Date(), style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Text("Exception Type: EXC_BAD_ACCESS (SIGSEGV)")
                                .font(.caption)
                                .foregroundColor(.red)
                            
                            Text("Application crashed due to memory access violation")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

// MARK: - Preview

#Preview {
    SoftwareView()
        .frame(width: 1200, height: 800)
} 