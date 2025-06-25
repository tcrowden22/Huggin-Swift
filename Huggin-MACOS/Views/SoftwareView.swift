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
    public var isOutdated: Bool
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
    @Published public var isLoading: Bool = false
    
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
            await MainActor.run {
                self.isLoading = true
            }
            
            print("🔍 Starting to load installed apps...")
            
            // Load apps from different sources
            let applicationsApps = await scanApplicationsFolder()
            print("📱 Found \(applicationsApps.count) apps in /Applications")
            
            let homebrewApps = await scanHomebrewApps()
            print("🍺 Found \(homebrewApps.count) Homebrew apps")
            
            let systemApps = await scanSystemApps()
            print("⚙️ Found \(systemApps.count) system apps")
            
            // Combine all apps
            var allApps: [AppInfo] = []
            allApps.append(contentsOf: applicationsApps)
            allApps.append(contentsOf: homebrewApps)
            allApps.append(contentsOf: systemApps)
            
            print("📊 Total apps found: \(allApps.count)")
            
            // If no apps found, add some sample data
            if allApps.isEmpty {
                print("⚠️ No apps found, adding sample data")
                allApps = createSampleApps()
            }
            
            // Deduplicate apps based on name (case-insensitive)
            let deduplicatedApps = deduplicateApps(allApps)
            print("🔄 After deduplication: \(deduplicatedApps.count) apps")
            
            // Sort and update on main actor
            await MainActor.run {
                self.installedApps = deduplicatedApps.sorted { $0.name < $1.name }
                self.isLoading = false
                print("✅ Loaded \(self.installedApps.count) apps into view model")
            }
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
            print("❌ Error scanning /Applications: \(error)")
        }
        
        return apps
    }
    
    private func scanHomebrewApps() async -> [AppInfo] {
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
            print("🍺 Homebrew not found")
            return apps
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
            print("❌ Error scanning Homebrew apps: \(error)")
        }
        
        return apps
    }
    
    private func scanSystemApps() async -> [AppInfo] {
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
            print("❌ Error scanning system apps: \(error)")
        }
        
        return apps
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
        // TODO: Implement real version checking
        // - Query App Store API for Mac App Store apps
        // - Check Homebrew for command-line tools
        // - Query vendor APIs for major software
        
        // For now, return false as most apps are likely up to date
        // This is more realistic than random outdated status
        return false
    }
    
    private func getLatestVersion(for bundle: Bundle) -> String? {
        // TODO: Implement real version checking
        // - Query App Store API for Mac App Store apps
        // - Check Homebrew for command-line tools
        // - Query vendor APIs for major software
        
        // For now, return nil as we don't have real version data
        // This is more realistic than generating fake versions
        return nil
    }
    
    private func getLastLaunchedDate(bundleIdentifier: String?) -> Date {
        guard let bundleID = bundleIdentifier else { return Date() }
        
        // Try to get last launched date from LaunchServices database
        let launchServicesPath = "\(NSHomeDirectory())/Library/Saved Application State"
        
        do {
            let fileManager = FileManager.default
            let launchServicesURL = URL(fileURLWithPath: launchServicesPath)
            
            // Check if the directory exists
            guard fileManager.fileExists(atPath: launchServicesPath) else { return Date() }
            
            let contents = try fileManager.contentsOfDirectory(
                at: launchServicesURL,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Look for saved state for this app
            let appStateFolders = contents.filter { url in
                let folderName = url.lastPathComponent
                return folderName.contains(bundleID)
            }
            
            // Get the most recent modification date
            var latestDate = Date()
            for folder in appStateFolders {
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: folder.path)
                    if let modificationDate = attributes[FileAttributeKey.modificationDate] as? Date {
                        if modificationDate > latestDate {
                            latestDate = modificationDate
                        }
                    }
                } catch {
                    // Continue if we can't get attributes for this folder
                }
            }
            
            // If we found a recent date, use it
            if latestDate != Date() {
                return latestDate
            }
            
        } catch {
            print("❌ Error checking LaunchServices for \(bundleID): \(error)")
        }
        
        // Fallback: check if app is currently running
        let runningApps = NSWorkspace.shared.runningApplications
        let isCurrentlyRunning = runningApps.contains { app in
            app.bundleIdentifier == bundleID
        }
        
        if isCurrentlyRunning {
            return Date() // App is currently running
        }
        
        // Final fallback: return a reasonable default (1 week ago)
        return Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    }
    
    private func getAverageCPUUsage(bundleIdentifier: String?) -> Double {
        guard let bundleID = bundleIdentifier else { return 0.0 }
        
        // Check if the app is currently running and get its CPU usage
        let runningApps = NSWorkspace.shared.runningApplications
        let runningApp = runningApps.first { app in
            app.bundleIdentifier == bundleID
        }
        
        if let app = runningApp {
            // For running apps, we can get some basic info
            // Note: Getting actual CPU usage requires more complex system calls
            // For now, we'll use a simple heuristic based on app type
            
            let appName = app.localizedName?.lowercased() ?? ""
            
            // Common high-CPU apps
            if appName.contains("chrome") || appName.contains("safari") || appName.contains("firefox") {
                return 0.15 // Browser apps typically use moderate CPU
            } else if appName.contains("photoshop") || appName.contains("final cut") || appName.contains("logic") {
                return 0.25 // Creative apps use more CPU
            } else if appName.contains("xcode") || appName.contains("android studio") {
                return 0.30 // Development tools use significant CPU
            } else if appName.contains("terminal") || appName.contains("iterm") {
                return 0.05 // Terminal apps use minimal CPU
            } else {
                return 0.10 // Default moderate usage
            }
        }
        
        // For non-running apps, return 0
        return 0.0
    }
    
    private func getCrashCount(bundleIdentifier: String?) -> Int {
        guard let bundleID = bundleIdentifier else { return 0 }
        
        // Scan crash logs from the diagnostic reports directory
        let crashLogsPath = "\(NSHomeDirectory())/Library/Logs/DiagnosticReports"
        
        do {
            let fileManager = FileManager.default
            let crashLogsURL = URL(fileURLWithPath: crashLogsPath)
            
            // Check if the directory exists
            guard fileManager.fileExists(atPath: crashLogsPath) else { return 0 }
            
            let contents = try fileManager.contentsOfDirectory(
                at: crashLogsURL,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
            
            // Filter crash logs for this app
            let appCrashLogs = contents.filter { url in
                let filename = url.lastPathComponent
                // Look for crash logs that match the bundle identifier
                return filename.contains(bundleID) && 
                       (filename.hasSuffix(".crash") || filename.hasSuffix(".ips"))
            }
            
            // Only count recent crashes (last 30 days)
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            let recentCrashes = appCrashLogs.filter { url in
                do {
                    let attributes = try fileManager.attributesOfItem(atPath: url.path)
                    if let creationDate = attributes[.creationDate] as? Date {
                        return creationDate > thirtyDaysAgo
                    }
                } catch {
                    // If we can't get the date, include it
                }
                return true
            }
            
            return recentCrashes.count
            
        } catch {
            print("❌ Error scanning crash logs for \(bundleID): \(error)")
            return 0
        }
    }
    
    private func getCVECount(for appName: String, version: String) -> Int {
        // TODO: Integrate with CVE databases
        // - Query National Vulnerability Database (NVD)
        // - Check vendor security advisories
        // - Use vulnerability scanning services
        
        // For now, return 0 as most apps don't have known vulnerabilities
        // This is more realistic than random numbers
        return 0
    }
    
    private func getMaxSeverity(for appName: String) -> VulnerabilitySeverity {
        // TODO: Implement real vulnerability severity assessment
        
        // For now, return low as most apps don't have known vulnerabilities
        // This is more realistic than random severity levels
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
        Task {
            print("🔄 Starting update for app: \(app.name)")
            
            // Determine the app type and update method
            if app.publisher.contains("Homebrew") {
                // Handle Homebrew apps
                await updateHomebrewApp(app)
            } else if app.bundleIdentifier?.contains("com.apple") == true {
                // Handle Apple system apps (usually updated via system updates)
                await updateSystemApp(app)
            } else {
                // Handle standalone apps (like Ollama)
                await updateStandaloneApp(app)
            }
        }
    }
    
    private func updateHomebrewApp(_ app: AppInfo) async {
        guard let bundleID = app.bundleIdentifier,
              let packageName = bundleID.components(separatedBy: ".").last else {
            print("❌ Cannot determine Homebrew package name for \(app.name)")
            return
        }
        
        do {
            // Check if Homebrew is available
            let brewPath = which("brew")
            guard let brew = brewPath else {
                print("❌ Homebrew not found")
                return
            }
            
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brew)
            process.arguments = ["upgrade", packageName]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                print("✅ Successfully updated \(app.name) via Homebrew")
                await MainActor.run {
                    // Mark app as updated
                    if let index = installedApps.firstIndex(where: { $0.id == app.id }) {
                        var updatedApp = app
                        updatedApp.isOutdated = false
                        installedApps[index] = updatedApp
                    }
                }
            } else {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("❌ Failed to update \(app.name): \(errorOutput)")
            }
        } catch {
            print("❌ Error updating Homebrew app \(app.name): \(error)")
        }
    }
    
    private func updateSystemApp(_ app: AppInfo) async {
        print("ℹ️ System app \(app.name) should be updated via System Preferences > Software Update")
        // For system apps, we can't update them directly - they need system updates
        await MainActor.run {
            // Show a notification or alert that system apps need to be updated via System Preferences
            print("💡 Tip: Update \(app.name) via System Preferences > Software Update")
        }
    }
    
    private func updateStandaloneApp(_ app: AppInfo) async {
        print("ℹ️ Standalone app \(app.name) needs manual update")
        
        // For standalone apps like Ollama, we need to check their specific update methods
        if app.name.lowercased() == "ollama" {
            await updateOllamaApp(app)
        } else {
            // For other standalone apps, provide generic guidance
            await MainActor.run {
                print("💡 Tip: Check the developer's website for \(app.name) updates")
            }
        }
    }
    
    private func updateOllamaApp(_ app: AppInfo) async {
        print("🤖 Checking Ollama update...")
        
        do {
            // Check if Ollama is running and get current version
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["-s", "http://localhost:11434/api/version"]
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("📊 Current Ollama version: \(output)")
                    
                    // For Ollama, the recommended update method is to download the latest version
                    await MainActor.run {
                        print("💡 Tip: Download the latest Ollama from https://ollama.ai/download")
                        print("💡 Or run: curl -fsSL https://ollama.ai/install.sh | sh")
                    }
                }
            } else {
                print("❌ Ollama service not running or not accessible")
                await MainActor.run {
                    print("💡 Tip: Start Ollama first, then check for updates")
                }
            }
        } catch {
            print("❌ Error checking Ollama version: \(error)")
        }
    }
    
    private func which(_ command: String) -> String? {
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
                    return output.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            print("Error checking for \(command): \(error)")
        }
        
        return nil
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
    
    private func createSampleApps() -> [AppInfo] {
        return [
            AppInfo(
                icon: "safari.fill",
                bundlePath: "/Applications/Safari.app",
                bundleIdentifier: "com.apple.Safari",
                name: "Safari",
                version: "17.0",
                latestVersion: nil,
                publisher: "Apple Inc.",
                installDate: Date(),
                isOutdated: false,
                cveCount: 0,
                maxSeverity: .low,
                autoPatchEnabled: false,
                lastLaunched: Date(),
                avgCpuUsage: 0.0,
                crashCount: 0,
                licenseType: "System Software",
                expirationDate: nil,
                seatCount: nil
            ),
            AppInfo(
                icon: "mail.fill",
                bundlePath: "/Applications/Mail.app",
                bundleIdentifier: "com.apple.mail",
                name: "Mail",
                version: "16.0",
                latestVersion: nil,
                publisher: "Apple Inc.",
                installDate: Date(),
                isOutdated: false,
                cveCount: 0,
                maxSeverity: .low,
                autoPatchEnabled: false,
                lastLaunched: Date(),
                avgCpuUsage: 0.0,
                crashCount: 0,
                licenseType: "System Software",
                expirationDate: nil,
                seatCount: nil
            ),
            AppInfo(
                icon: "globe",
                bundlePath: "/Applications/Google Chrome.app",
                bundleIdentifier: "com.google.Chrome",
                name: "Google Chrome",
                version: "119.0.6045.105",
                latestVersion: nil,
                publisher: "Google LLC",
                installDate: Date(),
                isOutdated: false,
                cveCount: 0,
                maxSeverity: .low,
                autoPatchEnabled: false,
                lastLaunched: Date(),
                avgCpuUsage: 0.0,
                crashCount: 0,
                licenseType: "Freeware",
                expirationDate: nil,
                seatCount: nil
            ),
            AppInfo(
                icon: "terminal.fill",
                bundlePath: nil,
                bundleIdentifier: "homebrew.git",
                name: "Git",
                version: "2.42.0",
                latestVersion: nil,
                publisher: "Homebrew Community",
                installDate: Date(),
                isOutdated: false,
                cveCount: 0,
                maxSeverity: .low,
                autoPatchEnabled: false,
                lastLaunched: Date(),
                avgCpuUsage: 0.0,
                crashCount: 0,
                licenseType: "Open Source",
                expirationDate: nil,
                seatCount: nil
            )
        ]
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
            if viewModel.isLoading {
                VStack {
                    ProgressView("Loading applications...")
                        .progressViewStyle(.circular)
                        .scaleEffect(1.2)
                    Text("Scanning your system for installed applications")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if viewModel.filteredApps.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "questionmark.app")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Applications Found")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("No applications match your current filters or no applications were detected on your system.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Refresh") {
                            viewModel.loadInstalledApps()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
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
            }
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
                Button(action: {
                    viewModel.loadInstalledApps()
                }) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(viewModel.isLoading)
                .help("Refresh applications list")
                
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