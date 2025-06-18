import Foundation
import SwiftUI

@MainActor
class EventMonitorService: ObservableObject {
    @Published var events: [SystemEvent] = []
    private var systemInfo: SystemInfoProvider?
    private nonisolated(unsafe) var timer: Timer?
    
    // Thresholds for events
    private let cpuWarningThreshold: Double = 80.0
    private let memoryWarningThreshold: Double = 80.0
    private let diskWarningThreshold: Double = 80.0
    
    init() {
        startMonitoring()
    }
    
    func setSystemInfo(_ systemInfo: SystemInfoProvider) {
        self.systemInfo = systemInfo
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        // Initial check
        Task {
            await checkSystemMetrics()
        }
        
        // Start periodic checks
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.checkSystemMetrics()
            }
        }
    }
    
    private func checkSystemMetrics() async {
        guard let systemInfo = systemInfo else { return }
        
        let now = Date()
        
        // Check CPU usage
        let cpuUsage = systemInfo.getCPUUsage()
        if cpuUsage >= cpuWarningThreshold {
            addEvent(
                type: SystemEventType.cpu,
                message: "High CPU usage: \(String(format: "%.1f", cpuUsage))%",
                timestamp: now
            )
        }
        
        // Check Memory usage
        let memoryUsage = systemInfo.getMemoryUsage()
        if memoryUsage >= memoryWarningThreshold {
            addEvent(
                type: SystemEventType.memory,
                message: "High memory usage: \(String(format: "%.1f", memoryUsage))%",
                timestamp: now
            )
        }
        
        // Check Disk usage
        let diskUsage = systemInfo.getDiskUsage()
        if diskUsage >= diskWarningThreshold {
            addEvent(
                type: SystemEventType.disk,
                message: "High disk usage: \(String(format: "%.1f", diskUsage))%",
                timestamp: now
            )
        }
    }
    
    private func addEvent(type: SystemEventType, message: String, timestamp: Date) {
        let event = SystemEvent(type: type, message: message, timestamp: timestamp)
        events.insert(event, at: 0)
        // Keep only the last 100 events
        if events.count > 100 {
            events.removeLast()
        }
    }
} 