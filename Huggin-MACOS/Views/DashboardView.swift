import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showSystemHealthModal = false
    @State private var showNetworkStatusModal = false
    var onNavigateToSupport: (() -> Void)?
    
    private let columns = [
        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 16)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                DashboardSystemHealthView(viewModel: viewModel) {
                    Task {
                        await viewModel.fetchProcessInfo()
                        showSystemHealthModal = true
                    }
                }
                DashboardDiskHealthView(viewModel: viewModel)
                DashboardAlertsView(viewModel: viewModel)
                DashboardUpdateStatusView(viewModel: viewModel)
                                    ChatLauncherButton(onNavigateToSupport: onNavigateToSupport)
                DashboardTicketsSummaryView(viewModel: viewModel)
                DashboardNetworkStatusView(viewModel: viewModel) {
                    Task {
                        await viewModel.fetchRouteTable()
                        showNetworkStatusModal = true
                    }
                }
                DashboardQuickActionsView(viewModel: viewModel)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showSystemHealthModal) {
            SystemHealthDetailModal(viewModel: viewModel)
        }
        .sheet(isPresented: $showNetworkStatusModal) {
            NetworkStatusDetailModal(viewModel: viewModel)
        }
    }
}

// MARK: - Dashboard System Health View

struct DashboardSystemHealthView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "cpu")
                            .foregroundColor(.blue)
                        Text("System Health")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    VStack(spacing: 8) {
                        MetricRow(
                            label: "CPU Usage",
                            value: viewModel.cpuUsage,
                            color: cpuColor(for: viewModel.cpuUsage)
                        )
                        
                        MetricRow(
                            label: "Memory Usage",
                            value: viewModel.memoryUsage,
                            color: memoryColor(for: viewModel.memoryUsage)
                        )
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func cpuColor(for usage: Double) -> Color {
        if usage > 0.8 { return .red }
        if usage > 0.6 { return .orange }
        return .green
    }
    
    private func memoryColor(for usage: Double) -> Color {
        if usage > 0.8 { return .red }
        if usage > 0.6 { return .orange }
        return .green
    }
}

// MARK: - Dashboard Disk Health View

struct DashboardDiskHealthView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "internaldrive")
                        .foregroundColor(.purple)
                    Text("Storage Health")
                        .font(.headline)
                    Spacer()
                    
                    // SMART Status Badge
                    HStack {
                        Circle()
                            .fill(viewModel.smartStatus ? .green : .red)
                            .frame(width: 8, height: 8)
                        Text(viewModel.smartStatus ? "SMART OK" : "SMART FAIL")
                            .font(.caption)
                            .foregroundColor(viewModel.smartStatus ? .green : .red)
                    }
                }
                
                MetricRow(
                    label: "Disk Usage",
                    value: viewModel.diskUsage,
                    color: diskColor(for: viewModel.diskUsage)
                )
            }
        }
    }
    
    private func diskColor(for usage: Double) -> Color {
        if usage > 0.9 { return .red }
        if usage > 0.8 { return .orange }
        return .green
    }
}

// MARK: - Dashboard Alerts View

struct DashboardAlertsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text("System Alerts")
                        .font(.headline)
                    Spacer()
                    
                    if !viewModel.alerts.isEmpty {
                        Text("\(viewModel.alerts.count)")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red)
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    }
                }
                
                if viewModel.alerts.isEmpty {
                    Text("No alerts")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(viewModel.alerts) { alert in
                        AlertRow(alert: alert)
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Update Status View

struct DashboardUpdateStatusView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle")
                        .foregroundColor(.blue)
                    Text("Software Updates")
                        .font(.headline)
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Last checked:")
                        Spacer()
                        Text(viewModel.lastChecked, style: .relative)
                            .foregroundColor(.secondary)
                    }
                    .font(.caption)
                    
                    HStack {
                        Text("Pending updates:")
                        Spacer()
                        Text("\(viewModel.pendingUpdatesCount)")
                            .foregroundColor(viewModel.pendingUpdatesCount > 0 ? .orange : .green)
                            .fontWeight(.semibold)
                    }
                    
                    Button(action: {
                        Task {
                            await viewModel.checkForUpdates()
                        }
                    }) {
                        Text("Check for Updates")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

// MARK: - Chat Launcher Button

struct ChatLauncherButton: View {
    var onNavigateToSupport: (() -> Void)?
    
    var body: some View {
        DashboardCard {
            VStack(spacing: 12) {
                Image(systemName: "message.circle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Ask Huginn")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("Get AI assistance")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                print("Ask Huginn button tapped - navigating to support")
                onNavigateToSupport?()
            }
        }
    }
}

// MARK: - Dashboard Tickets Summary View

struct DashboardTicketsSummaryView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "ticket")
                        .foregroundColor(.green)
                    Text("Support Tickets")
                        .font(.headline)
                    Spacer()
                    
                    Text("\(viewModel.tickets.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                }
                
                if viewModel.tickets.isEmpty {
                    Text("No open tickets")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(viewModel.tickets) { ticket in
                                TicketRowView(ticket: ticket)
                            }
                        }
                    }
                    .frame(maxHeight: 120)
                    .refreshable {
                        await viewModel.fetchTickets()
                    }
                }
            }
        }
    }
}

// MARK: - Dashboard Network Status View

struct DashboardNetworkStatusView: View {
    @ObservedObject var viewModel: DashboardViewModel
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            DashboardCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: networkIcon)
                            .foregroundColor(.blue)
                        Text("Network Status")
                            .font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Connection:")
                            Spacer()
                            Text(viewModel.interfaceType)
                                .foregroundColor(.secondary)
                        }
                        
                        if !viewModel.networkName.isEmpty && viewModel.networkName != viewModel.interfaceType {
                            HStack {
                                Text("Network:")
                                Spacer()
                                Text(viewModel.networkName)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack {
                            Text("Ping:")
                            Spacer()
                            Text("\(Int(viewModel.pingTime)) ms")
                                .foregroundColor(pingColor)
                        }
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var networkIcon: String {
        viewModel.interfaceType == "Wi-Fi" ? "wifi" : "network"
    }
    
    private var pingColor: Color {
        if viewModel.pingTime > 100 { return .red }
        if viewModel.pingTime > 50 { return .orange }
        return .green
    }
}

// MARK: - Dashboard Quick Actions View

struct DashboardQuickActionsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    private let actionColumns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        DashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "bolt.circle")
                        .foregroundColor(.yellow)
                    Text("Quick Actions")
                        .font(.headline)
                    Spacer()
                }
                
                LazyVGrid(columns: actionColumns, spacing: 8) {
                    ForEach(viewModel.quickActions) { action in
                        QuickActionButton(action: action)
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct DashboardCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct MetricRow: View {
    let label: String
    let value: Double
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(value * 100))%")
                    .font(.caption)
                    .foregroundColor(color)
            }
            
            ProgressView(value: value)
                .progressViewStyle(LinearProgressViewStyle(tint: color))
        }
    }
}

struct AlertRow: View {
    let alert: AlertItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption)
                    .lineLimit(2)
                
                Text(alert.severity.label)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(alert.severity.color.opacity(0.2))
                    .foregroundColor(alert.severity.color)
                    .clipShape(Capsule())
            }
            
            Spacer()
            
            Button("Fix Now") {
                alert.remediationAction()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

struct TicketRowView: View {
    let ticket: Ticket
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ticket.title)
                    .font(.caption)
                    .lineLimit(1)
                
                Text(ticket.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(ticket.status)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.2))
                .foregroundColor(statusColor)
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }
    
    private var statusColor: Color {
        switch ticket.status.lowercased() {
        case "open": return .red
        case "in progress": return .orange
        case "resolved": return .green
        default: return .blue
        }
    }
}

struct QuickActionButton: View {
    let action: QuickAction
    @State private var isRunning = false
    
    var body: some View {
        Button(action: {
            runScript()
        }) {
            VStack(spacing: 4) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.circle.fill")
                        .foregroundColor(.blue)
                }
                
                Text(action.name)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(isRunning)
    }
    
    private func runScript() {
        // TODO: Implement real script execution
        // - Validate script exists and has execute permissions
        // - Run script via Process with proper error handling
        // - Show execution feedback to user
        
        isRunning = true
        
        // Simulate script execution
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRunning = false
            print("TODO: Execute script at \(action.scriptPath.path)")
        }
    }
}

// MARK: - Modal Views

struct SystemHealthDetailModal: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "cpu")
                        .foregroundColor(.blue)
                        .font(.title)
                    Text("System Health Details")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Overall System Metrics
                        VStack(alignment: .leading, spacing: 12) {
                            Text("System Overview")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Text("CPU Usage")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(Int(viewModel.cpuUsage * 100))%")
                                        .foregroundColor(viewModel.cpuUsage > 0.8 ? .red : viewModel.cpuUsage > 0.6 ? .orange : .green)
                                        .fontWeight(.semibold)
                                }
                                
                                HStack {
                                    Text("Memory Usage")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(Int(viewModel.memoryUsage * 100))%")
                                        .foregroundColor(viewModel.memoryUsage > 0.8 ? .red : viewModel.memoryUsage > 0.6 ? .orange : .green)
                                        .fontWeight(.semibold)
                                }
                                
                                HStack {
                                    Text("Disk Usage")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(Int(viewModel.diskUsage * 100))%")
                                        .foregroundColor(viewModel.diskUsage > 0.9 ? .red : viewModel.diskUsage > 0.8 ? .orange : .green)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                        
                        // Top CPU Processes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top CPU Processes")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Process")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("PID")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 60)
                                    Text("CPU %")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 60)
                                    Text("Memory")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 80)
                                }
                                .padding(.horizontal)
                                .foregroundColor(.secondary)
                                
                                ForEach(viewModel.topProcessesByCPU) { process in
                                    HStack {
                                        Text(process.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(process.pid)
                                            .font(.caption)
                                            .frame(width: 60)
                                        Text("\(process.cpuUsage, specifier: "%.1f")%")
                                            .font(.caption)
                                            .foregroundColor(process.cpuUsage > 50 ? .red : process.cpuUsage > 20 ? .orange : .primary)
                                            .frame(width: 60)
                                        Text("\(process.memoryUsage, specifier: "%.0f")M")
                                            .font(.caption)
                                            .frame(width: 80)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                        
                        // Top Memory Processes
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Top Memory Processes")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Process")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("PID")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 60)
                                    Text("CPU %")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 60)
                                    Text("Memory")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 80)
                                }
                                .padding(.horizontal)
                                .foregroundColor(.secondary)
                                
                                ForEach(viewModel.topProcessesByMemory) { process in
                                    HStack {
                                        Text(process.name)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(process.pid)
                                            .font(.caption)
                                            .frame(width: 60)
                                        Text("\(process.cpuUsage, specifier: "%.1f")%")
                                            .font(.caption)
                                            .frame(width: 60)
                                        Text("\(process.memoryUsage, specifier: "%.0f")M")
                                            .font(.caption)
                                            .foregroundColor(process.memoryUsage > 1000 ? .red : process.memoryUsage > 500 ? .orange : .primary)
                                            .frame(width: 80)
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 600, minHeight: 500)
    }
}

struct NetworkStatusDetailModal: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            VStack(spacing: 20) {
                // Header
                HStack {
                    Image(systemName: "network")
                        .foregroundColor(.blue)
                        .font(.title)
                    Text("Network Status Details")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.horizontal)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Current Connection Info
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Current Connection")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Interface Type")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(viewModel.interfaceType)
                                        .foregroundColor(.secondary)
                                        .fontWeight(.semibold)
                                }
                                
                                if !viewModel.networkName.isEmpty && viewModel.networkName != viewModel.interfaceType {
                                    HStack {
                                        Text("Network Name")
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(viewModel.networkName)
                                            .foregroundColor(.secondary)
                                            .fontWeight(.semibold)
                                    }
                                }
                                
                                HStack {
                                    Text("Ping Time")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(Int(viewModel.pingTime)) ms")
                                        .foregroundColor(viewModel.pingTime > 100 ? .red : viewModel.pingTime > 50 ? .orange : .green)
                                        .fontWeight(.semibold)
                                }
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                        
                        // Routing Table
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Routing Table")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Destination")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("Gateway")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 120)
                                    Text("Flags")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 60)
                                    Text("Interface")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .frame(width: 80)
                                }
                                .padding(.horizontal)
                                .foregroundColor(.secondary)
                                
                                ForEach(viewModel.routingTable) { route in
                                    HStack {
                                        Text(route.destination)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(route.gateway)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .frame(width: 120)
                                        Text(route.flags)
                                            .font(.caption)
                                            .frame(width: 60)
                                        Text(route.interface)
                                            .font(.caption)
                                            .fontWeight(route.destination == "default" ? .semibold : .regular)
                                            .foregroundColor(route.destination == "default" ? .blue : .primary)
                                            .frame(width: 80)
                                    }
                                    .padding(.horizontal)
                                    .background(route.destination == "default" ? Color.blue.opacity(0.1) : Color.clear)
                                }
                            }
                            .padding(.vertical)
                            .background(Color(NSColor.controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .padding(.horizontal)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - Preview

struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
            .frame(width: 1200, height: 800)
    }
} 