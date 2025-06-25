import Foundation
import AppKit

@MainActor
public class ApplicationsProvider: ObservableObject, @unchecked Sendable {
    public struct AppInfo: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let version: String
        public let path: String
        public let isApple: Bool
        
        public init(name: String, version: String, path: String, isApple: Bool) {
            self.name = name
            self.version = version
            self.path = path
            self.isApple = isApple
        }
    }
    
    @Published public var apps: [AppInfo] = []
    @Published public var osVersion: String = ""
    @Published public var osBuild: String = ""
    private nonisolated(unsafe) var timer: Timer?
    
    public init() {
        Task { @MainActor in
            await fetchApplications()
            await fetchSystemInfo()
        }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                await self.fetchApplications()
                await self.fetchSystemInfo()
            }
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    public func refreshApplications() async {
        await fetchApplications()
        await fetchSystemInfo()
    }
    
    public func loadApplications() async {
        await refreshApplications()
    }
    
    private func fetchApplications() async {
        let applications = await withCheckedContinuation { continuation in
            Task.detached {
                let fileManager = FileManager.default
                let homeDirectory = fileManager.homeDirectoryForCurrentUser
                let applicationURLs = [
                    URL(fileURLWithPath: "/Applications"),
                    homeDirectory.appendingPathComponent("Applications")
                ]
                
                var applications: [AppInfo] = []
                
                for baseURL in applicationURLs {
                    guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
                    
                    var allObjects: [Any] = []
                    while let object = enumerator.nextObject() {
                        allObjects.append(object)
                    }
                    for case let fileURL as URL in allObjects {
                        guard fileURL.pathExtension == "app" else { continue }
                        
                        if let bundle = Bundle(url: fileURL),
                           let name = bundle.infoDictionary?["CFBundleName"] as? String ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String,
                           let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String {
                            let isApple = await ApplicationsProvider.isAppleApplication(bundle: bundle, path: fileURL.path)
                            
                            // Debug logging to verify detection
                            if let bundleID = bundle.bundleIdentifier {
                                print("App: \(name) | Bundle ID: \(bundleID) | Apple: \(isApple)")
                            } else {
                                print("App: \(name) | No Bundle ID | Apple: \(isApple)")
                            }
                            
                            applications.append(AppInfo(
                                name: name,
                                version: version,
                                path: fileURL.path,
                                isApple: isApple
                            ))
                        }
                    }
                }
                
                let sortedApplications = applications.sorted(by: { $0.name < $1.name })
                continuation.resume(returning: sortedApplications)
            }
        }
        
        self.apps = applications
    }
    
    private func fetchSystemInfo() async {
        let (version, build) = await withCheckedContinuation { continuation in
            Task.detached {
                var osVersion = ""
                var osBuild = ""
                
                // Get OS version
                let versionProcess = Process()
                versionProcess.launchPath = "/usr/bin/sw_vers"
                versionProcess.arguments = ["-productVersion"]
                
                let versionPipe = Pipe()
                versionProcess.standardOutput = versionPipe
                
                do {
                    try versionProcess.run()
                    versionProcess.waitUntilExit()
                    let versionData = versionPipe.fileHandleForReading.readDataToEndOfFile()
                    if let version = String(data: versionData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        osVersion = version
                    }
                } catch {
                    print("Error fetching OS version: \(error)")
                }
                
                // Get OS build
                let buildProcess = Process()
                buildProcess.launchPath = "/usr/bin/sw_vers"
                buildProcess.arguments = ["-buildVersion"]
                
                let buildPipe = Pipe()
                buildProcess.standardOutput = buildPipe
                
                do {
                    try buildProcess.run()
                    buildProcess.waitUntilExit()
                    let buildData = buildPipe.fileHandleForReading.readDataToEndOfFile()
                    if let build = String(data: buildData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        osBuild = build
                    }
                } catch {
                    print("Error fetching OS build: \(error)")
                }
                
                continuation.resume(returning: (osVersion, osBuild))
            }
        }
        
        self.osVersion = version
        self.osBuild = build
    }
    
    private static func isAppleApplication(bundle: Bundle, path: String) async -> Bool {
        // Check multiple indicators to determine if this is an Apple application
        
        // 1. Check bundle identifier for Apple prefixes
        if let bundleID = bundle.bundleIdentifier {
            let applePrefixes = [
                "com.apple.",
                "com.Apple."
            ]
            for prefix in applePrefixes {
                if bundleID.hasPrefix(prefix) {
                    return true
                }
            }
        }
        
        // 2. Check copyright information
        if let copyright = bundle.infoDictionary?["NSHumanReadableCopyright"] as? String {
            let appleIndicators = [
                "Apple Inc.",
                "Apple Computer",
                "© Apple",
                "Copyright Apple"
            ]
            for indicator in appleIndicators {
                if copyright.contains(indicator) {
                    return true
                }
            }
        }
        
        // 3. Check developer team identifier (for signed apps)
        if let teamID = bundle.infoDictionary?["DTDeveloperTeam"] as? String {
            // Apple's team identifiers
            let appleTeamIDs = ["0DRD64N2MG", "WDKDZ3JBHP"]
            if appleTeamIDs.contains(teamID) {
                return true
            }
        }
        
        // 4. Check if it's in system directories and has Apple signatures
        let systemPaths = [
            "/Applications/",
            "/System/Applications/",
            "/System/Library/CoreServices/",
            "/usr/libexec/"
        ]
        
        for systemPath in systemPaths {
            if path.hasPrefix(systemPath) {
                // For system paths, we'll assume it's Apple unless proven otherwise
                // This is more reliable than running codesign synchronously
                return true
            }
        }
        
        // 5. Check specific Apple app names (fallback)
        if let appName = bundle.infoDictionary?["CFBundleName"] as? String {
            let appleApps = [
                "Safari", "Mail", "Messages", "FaceTime", "Calendar", "Contacts",
                "Reminders", "Notes", "Maps", "Photos", "Camera", "Photo Theater",
                "Music", "TV", "Podcasts", "News", "Stocks", "Voice Memos",
                "Home", "Shortcuts", "Automator", "Terminal", "Console", "Activity Monitor",
                "Disk Utility", "System Preferences", "System Settings", "Migration Assistant",
                "Boot Camp Assistant", "Keychain Access", "Digital Color Meter",
                "Grapher", "Calculator", "Chess", "TextEdit", "Preview", "QuickTime Player",
                "Font Book", "ColorSync Utility", "Bluetooth Screen Sharing", "VoiceOver Utility",
                "Audio MIDI Setup", "System Information", "Network Utility", "RAID Utility",
                "Apple Configurator", "Transporter", "Reality Composer", "Compressor",
                "MainStage", "Logic Pro", "GarageBand", "iMovie", "Final Cut Pro",
                "Motion", "Keynote", "Pages", "Numbers", "Xcode", "Instruments",
                "Accessibility Inspector", "Create ML", "Reality Converter", "SF Symbols",
                "System Toolkit", "Archive Utility", "BOMArchiveHelper", "Installer",
                "Package Installer", "Software Update", "App Store", "Finder"
            ]
            
            if appleApps.contains(appName) {
                return true
            }
        }
        
        return false
    }
} 
