import Foundation
import SwiftUI
import Combine
import IOKit
import Network
import SystemConfiguration

extension String {
    func substring(with nsrange: NSRange) -> String? {
        guard let range = Range(nsrange, in: self) else { return nil }
        return String(self[range])
    }
}

// MARK: - Supporting Types

public struct AlertItem: Identifiable {
    public let id = UUID()
    public let title: String
    public let severity: AlertSeverity
    public let remediationAction: () -> Void
    
    public init(title: String, severity: AlertSeverity, remediationAction: @escaping () -> Void) {
        self.title = title
        self.severity = severity
        self.remediationAction = remediationAction
    }
}

public struct Ticket: Identifiable {
    public let id = UUID()
    public let title: String
    public let status: String
    public let date: Date
    
    public init(title: String, status: String, date: Date) {
        self.title = title
        self.status = status
        self.date = date
    }
}

public struct QuickAction: Identifiable {
    public let id = UUID()
    public let name: String
    public let scriptPath: URL
    
    public init(name: String, scriptPath: URL) {
        self.name = name
        self.scriptPath = scriptPath
    }
}

public struct ProcessInfo: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let pid: String
    public let cpuUsage: Double
    public let memoryUsage: Double // MB
    
    public init(name: String, pid: String, cpuUsage: Double, memoryUsage: Double) {
        self.name = name
        self.pid = pid
        self.cpuUsage = cpuUsage
        self.memoryUsage = memoryUsage
    }
}

public struct RouteInfo: Identifiable, Sendable {
    public let id = UUID()
    public let destination: String
    public let gateway: String
    public let flags: String
    public let interface: String
    
    public init(destination: String, gateway: String, flags: String, interface: String) {
        self.destination = destination
        self.gateway = gateway
        self.flags = flags
        self.interface = interface
    }
}

// MARK: - Dashboard ViewModel

@MainActor
public class DashboardViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public var cpuUsage: Double = 0.0 // 0-1
    @Published public var memoryUsage: Double = 0.0 // 0-1
    @Published public var diskUsage: Double = 0.0 // 0-1
    @Published public var smartStatus: Bool = true
    @Published public var alerts: [AlertItem] = []
    @Published public var lastChecked: Date = Date()
    @Published public var pendingUpdatesCount: Int = 0
    @Published public var tickets: [Ticket] = []
    @Published public var interfaceType: String = "Wi-Fi" // "Wi-Fi" or "Ethernet" 
    @Published public var networkName: String = "" // Wi-Fi SSID or interface name
    @Published public var pingTime: Double = 0.0 // ms
    @Published public var quickActions: [QuickAction] = []
    @Published public var topProcessesByCPU: [ProcessInfo] = []
    @Published public var topProcessesByMemory: [ProcessInfo] = []
    @Published public var routingTable: [RouteInfo] = []
    
    // MARK: - Private Properties
    private nonisolated(unsafe) var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    public init() {
        startPeriodicUpdates()
        loadInitialData()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Real CPU and memory metrics using system APIs
    public func updateMetrics() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.updateCPUUsage() }
            group.addTask { await self.updateMemoryUsage() }
            group.addTask { await self.updateDiskUsage() }
            group.addTask { await self.updateSMARTStatus() }
        }
        
        await MainActor.run {
            self.lastChecked = Date()
        }
    }
    
    private func updateCPUUsage() async {
        let usage = await withCheckedContinuation { continuation in
            Task.detached {
                // Use top command to get CPU usage
                let process = Process()
                process.launchPath = "/usr/bin/top"
                process.arguments = ["-l", "1", "-n", "0"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        // Parse CPU usage from top output
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("CPU usage:") {
                                // Parse format like "CPU usage: 2.94% user, 1.47% sys, 95.58% idle"
                                // Use regex to extract percentages more reliably
                                let pattern = "CPU usage: ([0-9.]+)% user, ([0-9.]+)% sys"
                                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                                    let range = NSRange(location: 0, length: line.utf16.count)
                                    if let match = regex.firstMatch(in: line, options: [], range: range) {
                                        let userRange = match.range(at: 1)
                                        let sysRange = match.range(at: 2)
                                        
                                        if let userCPUStr = line.substring(with: userRange),
                                           let sysCPUStr = line.substring(with: sysRange),
                                           let userCPU = Double(userCPUStr),
                                           let sysCPU = Double(sysCPUStr) {
                                            let totalUsage = (userCPU + sysCPU) / 100.0
                                            continuation.resume(returning: totalUsage)
                                            return
                                        }
                                    }
                                }
                                
                                // Fallback: manual parsing
                                let components = line.components(separatedBy: " ")
                                for i in 0..<components.count {
                                    if components[i] == "user," && i > 0 {
                                        let userStr = components[i-1].replacingOccurrences(of: "%", with: "")
                                        if let userCPU = Double(userStr), i+2 < components.count {
                                            let sysStr = components[i+2].replacingOccurrences(of: "%", with: "")
                                            if let sysCPU = Double(sysStr) {
                                                let totalUsage = (userCPU + sysCPU) / 100.0
                                                continuation.resume(returning: totalUsage)
                                                return
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                } catch {
                    // Silently handle CPU usage errors
                }
                
                continuation.resume(returning: 0.0)
            }
        }
        
        await MainActor.run {
            self.cpuUsage = usage
        }
    }
    
    private func updateMemoryUsage() async {
        let usage = await withCheckedContinuation { continuation in
            Task.detached {
                // Use vm_stat command to get memory usage
                let process = Process()
                process.launchPath = "/usr/bin/vm_stat"
                process.arguments = []
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        var free: Double = 0
                        var active: Double = 0
                        var inactive: Double = 0
                        var wired: Double = 0
                        
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("Pages free:") {
                                let parts = line.components(separatedBy: ":")
                                if parts.count > 1 {
                                    let numberStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
                                    free = Double(numberStr) ?? 0
                                }
                            } else if line.contains("Pages active:") {
                                let parts = line.components(separatedBy: ":")
                                if parts.count > 1 {
                                    let numberStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
                                    active = Double(numberStr) ?? 0
                                }
                            } else if line.contains("Pages inactive:") {
                                let parts = line.components(separatedBy: ":")
                                if parts.count > 1 {
                                    let numberStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
                                    inactive = Double(numberStr) ?? 0
                                }
                            } else if line.contains("Pages wired down:") {
                                let parts = line.components(separatedBy: ":")
                                if parts.count > 1 {
                                    let numberStr = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ".", with: "")
                                    wired = Double(numberStr) ?? 0
                                }
                            }
                        }
                        
                        let totalPages = free + active + inactive + wired
                        let usedPages = active + inactive + wired
                        
                        if totalPages > 0 {
                            let memoryUsage = usedPages / totalPages
                            continuation.resume(returning: memoryUsage)
                        } else {
                            continuation.resume(returning: 0.0)
                        }
                    } else {
                        continuation.resume(returning: 0.0)
                    }
                } catch {
                    continuation.resume(returning: 0.0)
                }
            }
        }
        
        await MainActor.run {
            self.memoryUsage = usage
        }
    }
    
    private func updateDiskUsage() async {
        let usage = await withCheckedContinuation { continuation in
            Task.detached {
                let fileManager = FileManager.default
                guard let homeURL = fileManager.urls(for: .userDirectory, in: .localDomainMask).first else {
                    continuation.resume(returning: 0.0)
                    return
                }
                
                do {
                    let resourceValues = try homeURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
                    
                    guard let totalCapacity = resourceValues.volumeTotalCapacity,
                          let availableCapacity = resourceValues.volumeAvailableCapacity else {
                        continuation.resume(returning: 0.0)
                        return
                    }
                    
                    let usedCapacity = totalCapacity - availableCapacity
                    let usage = Double(usedCapacity) / Double(totalCapacity)
                    continuation.resume(returning: usage)
                } catch {
                    continuation.resume(returning: 0.0)
                }
            }
        }
        
        await MainActor.run {
            self.diskUsage = usage
        }
    }
    
    private func updateSMARTStatus() async {
        let status = await withCheckedContinuation { continuation in
            Task.detached {
                // Run diskutil info to get SMART status
                let process = Process()
                process.launchPath = "/usr/sbin/diskutil"
                process.arguments = ["info", "/"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        // Look for SMART status in the output
                        let smartOK = output.contains("SMART Status: Verified") || 
                                     output.contains("SMART Status: OK") ||
                                     !output.contains("SMART Status: Failing")
                        continuation.resume(returning: smartOK)
                    } else {
                        continuation.resume(returning: true) // Default to OK if can't determine
                    }
                } catch {
                    continuation.resume(returning: true) // Default to OK on error
                }
            }
        }
        
        await MainActor.run {
            self.smartStatus = status
        }
    }
    
    /// Real system alerts based on actual system conditions
    public func fetchAlerts() async {
        var currentAlerts: [AlertItem] = []
        
        // Check CPU usage for high usage alert
        if cpuUsage > 0.8 {
            currentAlerts.append(AlertItem(title: "High CPU Usage Detected", severity: .error) {
                print("TODO: Implement CPU optimization")
            })
        }
        
        // Check memory usage for high memory alert
        if memoryUsage > 0.8 {
            currentAlerts.append(AlertItem(title: "High Memory Usage", severity: .warning) {
                print("TODO: Implement memory cleanup")
            })
        }
        
        // Check disk usage for low disk space alert
        if diskUsage > 0.9 {
            currentAlerts.append(AlertItem(title: "Disk Space Critical", severity: .critical) {
                print("TODO: Implement disk cleanup")
            })
        } else if diskUsage > 0.8 {
            currentAlerts.append(AlertItem(title: "Disk Space Low", severity: .warning) {
                print("TODO: Implement disk cleanup")
            })
        }
        
        // Check SMART status for disk health alert
        if !smartStatus {
            currentAlerts.append(AlertItem(title: "Disk Health Warning", severity: .critical) {
                print("TODO: Backup data immediately")
            })
        }
        
        // Check ping time for network issues
        if pingTime > 500 {
            currentAlerts.append(AlertItem(title: "Network Connectivity Issues", severity: .warning) {
                print("TODO: Check network connection")
            })
        }
        
        await MainActor.run {
            self.alerts = currentAlerts
        }
    }
    
    /// TODO: Integrate with macOS Software Update APIs
    /// Should check for system and application updates
    public func checkForUpdates() async {
        // TODO: Implement real update checking
        // - Use NSMetadataQuery for App Store updates
        // - Check system updates via softwareupdate command
        // - Query third-party updaters
        
        // Placeholder implementation
        pendingUpdatesCount = Int.random(in: 0...5)
        lastChecked = Date()
    }
    
    /// TODO: Integrate with ticketing system backend
    /// Should fetch support tickets from API
    public func fetchTickets() async {
        // TODO: Implement real ticket fetching
        // - Connect to support ticket API
        // - Parse ticket data
        // - Handle authentication
        
        // Placeholder implementation
        tickets = [
            Ticket(title: "System Performance Issue", status: "Open", date: Date().addingTimeInterval(-86400)),
            Ticket(title: "Software Installation Request", status: "In Progress", date: Date().addingTimeInterval(-172800))
        ]
    }
    
    /// Real network monitoring using system commands and APIs
    public func monitorNetwork() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.detectNetworkInterface() }
            group.addTask { await self.measurePing() }
        }
    }
    
    private func detectNetworkInterface() async {
        let (interfaceType, networkName) = await withCheckedContinuation { continuation in
            Task.detached {
                // Try multiple approaches to detect network connection
                
                // Method 1: Check route table for active default route
                let routeProcess = Process()
                routeProcess.launchPath = "/usr/sbin/netstat"
                routeProcess.arguments = ["-rn", "-f", "inet"]
                
                let routePipe = Pipe()
                routeProcess.standardOutput = routePipe
                
                var hasActiveConnection = false
                var activeInterface = ""
                
                do {
                    try routeProcess.run()
                    routeProcess.waitUntilExit()
                    
                    let routeData = routePipe.fileHandleForReading.readDataToEndOfFile()
                    if let routeOutput = String(data: routeData, encoding: .utf8) {
                        let lines = routeOutput.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("default") {
                                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                                if components.count >= 6 {
                                    activeInterface = components[5] // Interface name like en0, en1
                                    hasActiveConnection = true
                                    break
                                }
                            }
                        }
                    }
                } catch {
                    // Silently handle route table errors
                }
                
                if hasActiveConnection {
                    // Check if it's Wi-Fi (usually en0 on most Macs)
                    if activeInterface == "en0" {
                        // Try to get Wi-Fi SSID
                        let wifiProcess = Process()
                        wifiProcess.launchPath = "/usr/sbin/networksetup"
                        wifiProcess.arguments = ["-getairportnetwork", activeInterface]
                        
                        let wifiPipe = Pipe()
                        wifiProcess.standardOutput = wifiPipe
                        
                        do {
                            try wifiProcess.run()
                            wifiProcess.waitUntilExit()
                            
                            let wifiData = wifiPipe.fileHandleForReading.readDataToEndOfFile()
                            if let wifiOutput = String(data: wifiData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                                if wifiOutput.contains("Current Wi-Fi Network:") {
                                    let ssid = wifiOutput.replacingOccurrences(of: "Current Wi-Fi Network: ", with: "")
                                    if !ssid.isEmpty && !ssid.contains("not associated") {
                                        continuation.resume(returning: ("Wi-Fi", ssid))
                                        return
                                    }
                                }
                            }
                        } catch {
                            // Silently handle Wi-Fi SSID errors
                        }
                        
                        // If we can't get SSID but interface is active, assume Wi-Fi
                        continuation.resume(returning: ("Wi-Fi", "Connected"))
                        return
                    } else {
                        // Assume Ethernet for other interfaces
                        continuation.resume(returning: ("Ethernet", "Connected"))
                        return
                    }
                }
                
                // Fallback: Check if any interface has an IP
                let ifconfigProcess = Process()
                ifconfigProcess.launchPath = "/sbin/ifconfig"
                ifconfigProcess.arguments = []
                
                let ifconfigPipe = Pipe()
                ifconfigProcess.standardOutput = ifconfigPipe
                
                do {
                    try ifconfigProcess.run()
                    ifconfigProcess.waitUntilExit()
                    
                    let ifconfigData = ifconfigPipe.fileHandleForReading.readDataToEndOfFile()
                    if let ifconfigOutput = String(data: ifconfigData, encoding: .utf8) {
                        let sections = ifconfigOutput.components(separatedBy: "\n\n")
                        for section in sections {
                            if section.contains("en0:") && section.contains("inet ") && section.contains("status: active") {
                                continuation.resume(returning: ("Wi-Fi", "Connected"))
                                return
                            } else if section.contains("en1:") && section.contains("inet ") && section.contains("status: active") {
                                continuation.resume(returning: ("Ethernet", "Connected"))
                                return
                            }
                        }
                    }
                } catch {
                    // Silently handle ifconfig errors
                }
                
                // Final fallback
                continuation.resume(returning: ("Offline", "No Connection"))
            }
        }
        
        await MainActor.run {
            self.interfaceType = interfaceType
            self.networkName = networkName
        }
    }
    
    private func measurePing() async {
        let ping = await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.launchPath = "/sbin/ping"
                process.arguments = ["-c", "1", "-t", "3", "8.8.8.8"] // Single ping to Google DNS with 3s timeout
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    let startTime = Date()
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        // Parse ping time from output like "64 bytes from 8.8.8.8: icmp_seq=0 ttl=116 time=23.456 ms"
                        let lines = output.components(separatedBy: .newlines)
                        for line in lines {
                            if line.contains("time=") {
                                let components = line.components(separatedBy: "time=")
                                if components.count > 1 {
                                    let timeStr = components[1].components(separatedBy: " ")[0]
                                    if let pingTime = Double(timeStr) {
                                        continuation.resume(returning: pingTime)
                                        return
                                    }
                                }
                            }
                        }
                    }
                    
                    // If we can't parse the time, calculate based on execution time
                    let executionTime = Date().timeIntervalSince(startTime) * 1000
                    continuation.resume(returning: executionTime)
                    
                } catch {
                    continuation.resume(returning: 999.0) // High ping indicates connection issues
                }
            }
        }
        
        await MainActor.run {
            self.pingTime = ping
        }
    }
    
    public func fetchProcessInfo() async {
        async let cpuProcesses = getTopProcessesByCPU()
        async let memoryProcesses = getTopProcessesByMemory()
        
        let (cpu, memory) = await (cpuProcesses, memoryProcesses)
        
        await MainActor.run {
            self.topProcessesByCPU = cpu
            self.topProcessesByMemory = memory
        }
    }
    
    public func fetchRouteTable() async {
        let routes = await getRouteTable()
        await MainActor.run {
            self.routingTable = routes
        }
    }
    
    private func getTopProcessesByCPU() async -> [ProcessInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.launchPath = "/usr/bin/top"
                process.arguments = ["-l", "1", "-o", "cpu", "-n", "10", "-stats", "pid,command,cpu,mem"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        var processes: [ProcessInfo] = []
                        let lines = output.components(separatedBy: .newlines)
                        var foundProcesses = false
                        
                        for line in lines {
                            if line.contains("PID") && line.contains("COMMAND") {
                                foundProcesses = true
                                continue
                            }
                            
                            if foundProcesses && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                                if components.count >= 4 {
                                    let pid = components[0]
                                    let command = components[1]
                                    let cpuStr = components[2].replacingOccurrences(of: "%", with: "")
                                    let memStr = components[3].replacingOccurrences(of: "M", with: "").replacingOccurrences(of: "+", with: "")
                                    
                                    if let cpu = Double(cpuStr), let mem = Double(memStr) {
                                        processes.append(ProcessInfo(name: command, pid: pid, cpuUsage: cpu, memoryUsage: mem))
                                    }
                                }
                            }
                        }
                        
                        continuation.resume(returning: Array(processes.prefix(10)))
                    } else {
                        continuation.resume(returning: [])
                    }
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func getTopProcessesByMemory() async -> [ProcessInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.launchPath = "/usr/bin/top"
                process.arguments = ["-l", "1", "-o", "mem", "-n", "10", "-stats", "pid,command,cpu,mem"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        var processes: [ProcessInfo] = []
                        let lines = output.components(separatedBy: .newlines)
                        var foundProcesses = false
                        
                        for line in lines {
                            if line.contains("PID") && line.contains("COMMAND") {
                                foundProcesses = true
                                continue
                            }
                            
                            if foundProcesses && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                                if components.count >= 4 {
                                    let pid = components[0]
                                    let command = components[1]
                                    let cpuStr = components[2].replacingOccurrences(of: "%", with: "")
                                    let memStr = components[3].replacingOccurrences(of: "M", with: "").replacingOccurrences(of: "+", with: "")
                                    
                                    if let cpu = Double(cpuStr), let mem = Double(memStr) {
                                        processes.append(ProcessInfo(name: command, pid: pid, cpuUsage: cpu, memoryUsage: mem))
                                    }
                                }
                            }
                        }
                        
                        continuation.resume(returning: Array(processes.prefix(10)))
                    } else {
                        continuation.resume(returning: [])
                    }
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }
    
    private func getRouteTable() async -> [RouteInfo] {
        return await withCheckedContinuation { continuation in
            Task.detached {
                let process = Process()
                process.launchPath = "/usr/sbin/netstat"
                process.arguments = ["-rn"]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8) {
                        var routes: [RouteInfo] = []
                        let lines = output.components(separatedBy: .newlines)
                        var foundIPv4 = false
                        
                        for line in lines {
                            if line.contains("Destination") && line.contains("Gateway") {
                                foundIPv4 = true
                                continue
                            }
                            
                            if foundIPv4 && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                let components = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                                if components.count >= 4 {
                                    let destination = components[0]
                                    let gateway = components[1]
                                    let flags = components[2]
                                    let interface = components[3]
                                    
                                    routes.append(RouteInfo(destination: destination, gateway: gateway, flags: flags, interface: interface))
                                }
                            }
                        }
                        
                        continuation.resume(returning: routes)
                    } else {
                        continuation.resume(returning: [])
                    }
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// TODO: Load quick actions from configuration
    /// Should read script paths from app bundle or user preferences
    public func loadQuickActions() async {
        // TODO: Implement real quick actions loading
        // - Read from configuration file
        // - Scan designated scripts directory
        // - Validate script permissions
        
        // Placeholder implementation
        let scriptsURL = Bundle.main.bundleURL.appendingPathComponent("Scripts")
        quickActions = [
            QuickAction(name: "System Cleanup", scriptPath: scriptsURL.appendingPathComponent("cleanup.sh")),
            QuickAction(name: "Reset Network", scriptPath: scriptsURL.appendingPathComponent("reset_network.sh")),
            QuickAction(name: "Clear Cache", scriptPath: scriptsURL.appendingPathComponent("clear_cache.sh"))
        ]
    }
    
    // MARK: - Private Methods
    
    private func startPeriodicUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { 
                    self?.updateTimer?.invalidate()
                    return 
                }
                await self.updateMetrics()
                await self.fetchAlerts() // Update alerts based on new metrics
            }
        }
        
        // Ensure the timer runs on the main run loop
        if let timer = updateTimer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
    
    private func loadInitialData() {
        Task {
            await updateMetrics()
            await fetchAlerts()
            await checkForUpdates()
            await fetchTickets()
            await monitorNetwork()
            await loadQuickActions()
        }
    }
} 