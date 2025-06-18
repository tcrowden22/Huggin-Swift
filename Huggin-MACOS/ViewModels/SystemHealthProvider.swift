import Foundation
import SwiftUI
import Charts

struct DataPoint: Identifiable {
    let id = UUID()
    let time: Date
    let value: Double
}

@MainActor
class SystemHealthProvider: ObservableObject {
    @Published var healthStatus: SystemHealthStatus = .unknown
    @Published var metrics: SystemMetrics = SystemMetrics()
    @Published var cpuHistory: [DataPoint] = []
    @Published var memoryHistory: [DataPoint] = []
    @Published var networkHistory: [DataPoint] = []
    @Published var diskHistory: [DataPoint] = []
    @Published var cpuHealth: Huggin_MACOS.SystemHealth = .unknown
    @Published var memoryHealth: Huggin_MACOS.SystemHealth = .unknown
    @Published var networkHealth: Huggin_MACOS.SystemHealth = .unknown
    @Published var diskHealth: Huggin_MACOS.SystemHealth = .unknown
    @Published var overallHealth: Huggin_MACOS.SystemHealth = .unknown
    
    private let systemInfo: SystemInfoProvider
    private nonisolated(unsafe) var timer: Timer?
    private let maxDataPoints = 60 // 1 hour of data at 1-minute intervals
    
    // Thresholds for health status
    private let cpuWarningThreshold: Double = 80.0
    private let cpuCriticalThreshold: Double = 90.0
    private let memoryWarningThreshold: Double = 80.0
    private let memoryCriticalThreshold: Double = 90.0
    private let networkWarningThreshold: Double = 80.0
    private let networkCriticalThreshold: Double = 90.0
    private let diskWarningThreshold: Double = 80.0
    private let diskCriticalThreshold: Double = 90.0
    
    init(systemInfo: SystemInfoProvider) {
        self.systemInfo = systemInfo
        startMonitoring()
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func startMonitoring() {
        // Initial update
        Task {
            await collectMetrics()
            await updateHealthStatus()
        }
        
        // Start periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.collectMetrics()
                await self?.updateHealthStatus()
            }
        }
    }
    
    private func collectMetrics() async {
        metrics = SystemMetrics(
            cpuUsage: systemInfo.getCPUUsage(),
            memoryUsage: systemInfo.getMemoryUsage(),
            diskUsage: systemInfo.getDiskUsage(),
            networkUsage: systemInfo.getNetworkUsage(),
            batteryLevel: systemInfo.batteryLevel,
            isCharging: systemInfo.isCharging
        )
        
        let now = Date()
        
        // CPU Usage
        let cpuUsage = systemInfo.getCPUUsage()
        let cpuPoint = DataPoint(time: now, value: cpuUsage)
        cpuHistory.append(cpuPoint)
        if cpuHistory.count > maxDataPoints {
            cpuHistory.removeFirst()
        }
        
        // Memory Usage
        let memoryUsage = systemInfo.getMemoryUsage()
        let memoryPoint = DataPoint(time: now, value: memoryUsage)
        memoryHistory.append(memoryPoint)
        if memoryHistory.count > maxDataPoints {
            memoryHistory.removeFirst()
        }
        
        // Network Usage
        let networkUsage = systemInfo.getNetworkUsage()
        let networkPoint = DataPoint(time: now, value: networkUsage)
        networkHistory.append(networkPoint)
        if networkHistory.count > maxDataPoints {
            networkHistory.removeFirst()
        }
        
        // Disk Usage
        let diskUsage = systemInfo.getDiskUsage()
        let diskPoint = DataPoint(time: now, value: diskUsage)
        diskHistory.append(diskPoint)
        if diskHistory.count > maxDataPoints {
            diskHistory.removeFirst()
        }
    }
    
    private func updateHealthStatus() async {
        // Update individual component health
        cpuHealth = determineHealth(usage: metrics.cpuUsage, warning: cpuWarningThreshold, critical: cpuCriticalThreshold)
        memoryHealth = determineHealth(usage: metrics.memoryUsage, warning: memoryWarningThreshold, critical: memoryCriticalThreshold)
        networkHealth = determineHealth(usage: metrics.networkUsage, warning: networkWarningThreshold, critical: networkCriticalThreshold)
        diskHealth = determineHealth(usage: metrics.diskUsage, warning: diskWarningThreshold, critical: diskCriticalThreshold)
        
        // Determine overall health
        let healthScores = [cpuHealth, memoryHealth, networkHealth, diskHealth]
        if healthScores.contains(.poor) {
            overallHealth = .poor
            healthStatus = .poor
        } else if healthScores.contains(.fair) {
            overallHealth = .fair
            healthStatus = .fair
        } else {
            overallHealth = .good
            healthStatus = .good
        }
    }
    
    private func determineHealth(usage: Double, warning: Double, critical: Double) -> Huggin_MACOS.SystemHealth {
        if usage >= critical {
            return .poor
        } else if usage >= warning {
            return .fair
        } else {
            return .good
        }
    }
} 