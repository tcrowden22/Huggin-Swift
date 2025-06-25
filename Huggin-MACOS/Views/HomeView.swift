import SwiftUI
import Charts

struct HomeView: View {
    @EnvironmentObject private var systemInfo: SystemInfoProvider
    @StateObject private var eventMonitor: EventMonitorService
    @StateObject private var updateManager = UpdateManager()
    
    // For storing historical data
    @State private var cpuHistory: [MetricPoint] = []
    @State private var memoryHistory: [MetricPoint] = []
    @State private var networkHistory: [MetricPoint] = []
    @State private var batteryHistory: [MetricPoint] = []
    @State private var metricsTimer: Timer?
    private let maxHistoryPoints = 30 // 30 seconds of data at 1-second intervals
    
    init() {
        // Create event monitor without requiring systemInfo in init
        _eventMonitor = StateObject(wrappedValue: EventMonitorService())
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Live Metrics Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Live Metrics")
                        .font(.headline)
                    
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        // CPU Card
                        CompactMetricCard(
                            title: "CPU",
                            value: systemInfo.cpuUsage,
                            unit: "%",
                            history: cpuHistory,
                            color: .blue,
                            icon: "cpu"
                        )
                        
                        // Memory Card
                        CompactMetricCard(
                            title: "Memory",
                            value: systemInfo.memoryUsage,
                            unit: "%",
                            history: memoryHistory,
                            color: .green,
                            icon: "memorychip"
                        )
                        
                        // Network Card
                        CompactMetricCard(
                            title: "Network",
                            value: systemInfo.networkUsage,
                            unit: "%",
                            history: networkHistory,
                            color: .orange,
                            icon: "network"
                        )
                        
                        // Battery Card
                        CompactMetricCard(
                            title: "Battery",
                            value: systemInfo.batteryLevel * 100,
                            unit: "%",
                            history: batteryHistory,
                            color: systemInfo.isCharging ? .green : .purple,
                            icon: systemInfo.isCharging ? "battery.100.bolt" : "battery.100"
                        )
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
                
                // System Overview Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("System Overview")
                        .font(.headline)
                    
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
                        GridRow {
                            Text("Hostname:")
                                .foregroundColor(.secondary)
                            Text(Foundation.ProcessInfo.processInfo.hostName)
                        }
                        GridRow {
                            Text("OS Version:")
                                .foregroundColor(.secondary)
                            Text(Foundation.ProcessInfo.processInfo.operatingSystemVersionString)
                        }
                        GridRow {
                            Text("Disk Usage:")
                                .foregroundColor(.secondary)
                            Text(String(format: "%.1f%%", systemInfo.diskUsage))
                        }
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
                
                // Available Updates Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Available Updates")
                        .font(.headline)
                    
                    if updateManager.updates.isEmpty {
                        Text("No updates available")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(updateManager.updates) { update in
                            HStack {
                                Text(update.name)
                                Spacer()
                                Text(update.version)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .padding()
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
            }
            .padding()
        }
        .frame(minWidth: 800, minHeight: 600)
        .onAppear {
            // Set the systemInfo on the event monitor
            eventMonitor.setSystemInfo(systemInfo)
            // Start metrics collection immediately
            startMetricsCollection()
            // Update checks are managed centrally
        }
        .onDisappear {
            // Clean up timer when view disappears
            metricsTimer?.invalidate()
            metricsTimer = nil
        }
    }
    
    private func startMetricsCollection() {
        // Initial data point
        let timestamp = Date()
        cpuHistory = [MetricPoint(value: systemInfo.cpuUsage, timestamp: timestamp)]
        memoryHistory = [MetricPoint(value: systemInfo.memoryUsage, timestamp: timestamp)]
        networkHistory = [MetricPoint(value: systemInfo.networkUsage, timestamp: timestamp)]
        batteryHistory = [MetricPoint(value: systemInfo.batteryLevel * 100, timestamp: timestamp)]
        
        // Start timer for updates
        metricsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            Task { @MainActor in
                let timestamp = Date()
                
                // Update histories
                cpuHistory.append(MetricPoint(value: systemInfo.cpuUsage, timestamp: timestamp))
                memoryHistory.append(MetricPoint(value: systemInfo.memoryUsage, timestamp: timestamp))
                networkHistory.append(MetricPoint(value: systemInfo.networkUsage, timestamp: timestamp))
                batteryHistory.append(MetricPoint(value: systemInfo.batteryLevel * 100, timestamp: timestamp))
                
                // Trim histories if needed
                if cpuHistory.count > maxHistoryPoints {
                    cpuHistory.removeFirst()
                    memoryHistory.removeFirst()
                    networkHistory.removeFirst()
                    batteryHistory.removeFirst()
                }
            }
        }
    }
}

struct MetricPoint: Identifiable, Sendable {
    let id = UUID()
    let value: Double
    let timestamp: Date
}

struct CompactMetricCard: View {
    let title: String
    let value: Double
    let unit: String
    let history: [MetricPoint]
    let color: Color
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Text(String(format: "%.1f%@", value, unit))
                    .font(.headline)
                    .bold()
            }
            
            if !history.isEmpty {
                Chart(history) { point in
                    LineMark(
                        x: .value("Time", point.timestamp),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                }
                .frame(height: 50)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

#Preview {
    HomeView()
} 