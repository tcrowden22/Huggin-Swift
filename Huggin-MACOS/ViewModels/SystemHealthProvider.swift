import Foundation
import SwiftUI
import Charts

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
        // Initial update with delay to avoid view update conflicts
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second delay
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
        // Collect all metrics first
        let cpuUsage = systemInfo.getCPUUsage()
        let memoryUsage = systemInfo.getMemoryUsage()
        let diskUsage = systemInfo.getDiskUsage()
        let networkUsage = systemInfo.getNetworkUsage()
        let now = Date()
        
        // Create new data points
        let cpuPoint = DataPoint(time: now, value: cpuUsage)
        let memoryPoint = DataPoint(time: now, value: memoryUsage)
        let networkPoint = DataPoint(time: now, value: networkUsage)
        let diskPoint = DataPoint(time: now, value: diskUsage)
        
        // Update histories with proper array management
        var newCpuHistory = cpuHistory
        var newMemoryHistory = memoryHistory
        var newNetworkHistory = networkHistory
        var newDiskHistory = diskHistory
        
        newCpuHistory.append(cpuPoint)
        newMemoryHistory.append(memoryPoint)
        newNetworkHistory.append(networkPoint)
        newDiskHistory.append(diskPoint)
        
        if newCpuHistory.count > maxDataPoints {
            newCpuHistory.removeFirst()
        }
        if newMemoryHistory.count > maxDataPoints {
            newMemoryHistory.removeFirst()
        }
        if newNetworkHistory.count > maxDataPoints {
            newNetworkHistory.removeFirst()
        }
        if newDiskHistory.count > maxDataPoints {
            newDiskHistory.removeFirst()
        }
        
        // Batch update all published properties
        await MainActor.run {
            self.metrics = SystemMetrics(
                cpuUsage: cpuUsage,
                memoryUsage: memoryUsage,
                diskUsage: diskUsage,
                networkUsage: networkUsage,
                batteryLevel: self.systemInfo.batteryLevel,
                isCharging: self.systemInfo.isCharging
            )
            
            self.cpuHistory = newCpuHistory
            self.memoryHistory = newMemoryHistory
            self.networkHistory = newNetworkHistory
            self.diskHistory = newDiskHistory
        }
    }
    
    private func updateHealthStatus() async {
        // Calculate health statuses
        let newCpuHealth = determineHealth(usage: metrics.cpuUsage, warning: cpuWarningThreshold, critical: cpuCriticalThreshold)
        let newMemoryHealth = determineHealth(usage: metrics.memoryUsage, warning: memoryWarningThreshold, critical: memoryCriticalThreshold)
        let newNetworkHealth = determineHealth(usage: metrics.networkUsage, warning: networkWarningThreshold, critical: networkCriticalThreshold)
        let newDiskHealth = determineHealth(usage: metrics.diskUsage, warning: diskWarningThreshold, critical: diskCriticalThreshold)
        
        // Determine overall health
        let healthScores = [newCpuHealth, newMemoryHealth, newNetworkHealth, newDiskHealth]
        let newOverallHealth: Huggin_MACOS.SystemHealth
        let newHealthStatus: SystemHealthStatus
        
        if healthScores.contains(.poor) {
            newOverallHealth = .poor
            newHealthStatus = .poor
        } else if healthScores.contains(.fair) {
            newOverallHealth = .fair
            newHealthStatus = .fair
        } else {
            newOverallHealth = .good
            newHealthStatus = .good
        }
        
        // Batch update all health properties
        await MainActor.run {
            self.cpuHealth = newCpuHealth
            self.memoryHealth = newMemoryHealth
            self.networkHealth = newNetworkHealth
            self.diskHealth = newDiskHealth
            self.overallHealth = newOverallHealth
            self.healthStatus = newHealthStatus
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
    
    func loadSystemHealth() async {
        await collectMetrics()
        await updateHealthStatus()
    }
} 