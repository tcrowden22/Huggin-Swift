import SwiftUI

// MARK: - Dashboard View

struct DashboardView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @State private var showSystemHealthModal = false
    @State private var showNetworkStatusModal = false
    @State private var showAlertAIAssistant = false
    @State private var selectedAlert: AlertItem?
    @State private var isCompactMode = false
    @State private var expandedSections: Set<String> = []
    var onNavigateToSupport: (() -> Void)?
    @StateObject private var agentService = OdinAgentServiceV3.shared
    @StateObject private var systemHealthProvider: SystemHealthProvider
    @StateObject private var hardwareProviders: HardwareProviders
    @StateObject private var applicationsProvider: ApplicationsProvider
    @StateObject private var softwareUpdateProvider: SoftwareUpdateProvider
    @StateObject private var securityStatusProvider: SecurityStatusProvider
    @StateObject private var systemInfoProvider: SystemInfoProvider
    @StateObject private var updateManagerService: UpdateManagerService
    @StateObject private var loadingStateManager: LoadingStateManager
    
    init(onNavigateToSupport: (() -> Void)? = nil) {
        self.onNavigateToSupport = onNavigateToSupport
        
        let systemInfoProvider = SystemInfoProvider()
        let systemHealthProvider = SystemHealthProvider(systemInfo: systemInfoProvider)
        let hardwareProviders = HardwareProviders()
        let applicationsProvider = ApplicationsProvider()
        let softwareUpdateProvider = SoftwareUpdateProvider()
        let securityStatusProvider = SecurityStatusProvider()
        let updateManagerService = UpdateManagerService(softwareUpdateProvider: softwareUpdateProvider)
        
        self._systemInfoProvider = StateObject(wrappedValue: systemInfoProvider)
        self._systemHealthProvider = StateObject(wrappedValue: systemHealthProvider)
        self._hardwareProviders = StateObject(wrappedValue: hardwareProviders)
        self._applicationsProvider = StateObject(wrappedValue: applicationsProvider)
        self._softwareUpdateProvider = StateObject(wrappedValue: softwareUpdateProvider)
        self._securityStatusProvider = StateObject(wrappedValue: securityStatusProvider)
        self._updateManagerService = StateObject(wrappedValue: updateManagerService)
        self._loadingStateManager = StateObject(wrappedValue: LoadingStateManager(
            systemHealthProvider: systemHealthProvider,
            updateManager: updateManagerService,
            systemInfo: systemInfoProvider
        ))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    // Header with compact mode toggle
                    DashboardHeader(isCompactMode: $isCompactMode)
                    
                    if geometry.size.width > 900 && !isCompactMode {
                        // Desktop: Two-column layout
                        HStack(alignment: .top, spacing: 24) {
                            // Left Column: System Overview
                            SystemOverviewColumn(
                                viewModel: viewModel,
                                expandedSections: $expandedSections,
                                onSystemHealthTap: {
                                    Task {
                                        await viewModel.fetchProcessInfo()
                                        showSystemHealthModal = true
                                    }
                                },
                                onNetworkTap: {
                                    Task {
                                        await viewModel.fetchRouteTable()
                                        showNetworkStatusModal = true
                                    }
                                },
                                softwareUpdateProvider: softwareUpdateProvider
                            )
                            .frame(maxWidth: .infinity)
                            
                            // Right Column: Support & Actions
                            SupportActionsColumn(
                                viewModel: viewModel,
                                expandedSections: $expandedSections,
                                onAlertClick: { alert in
                                    selectedAlert = alert
                                    showAlertAIAssistant = true
                                },
                                onNavigateToSupport: onNavigateToSupport
                            )
                            .frame(maxWidth: .infinity)
                        }
                    } else {
                        // Tablet/Mobile: Single-column stacked layout
                        VStack(spacing: 20) {
                            SystemOverviewColumn(
                                viewModel: viewModel,
                                expandedSections: $expandedSections,
                                onSystemHealthTap: {
                                    Task {
                                        await viewModel.fetchProcessInfo()
                                        showSystemHealthModal = true
                                    }
                                },
                                onNetworkTap: {
                                    Task {
                                        await viewModel.fetchRouteTable()
                                        showNetworkStatusModal = true
                                    }
                                },
                                softwareUpdateProvider: softwareUpdateProvider
                            )
                            
                            SupportActionsColumn(
                                viewModel: viewModel,
                                expandedSections: $expandedSections,
                                onAlertClick: { alert in
                                    selectedAlert = alert
                                    showAlertAIAssistant = true
                                },
                                onNavigateToSupport: onNavigateToSupport
                            )
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showSystemHealthModal) {
            SystemHealthDetailModal(viewModel: viewModel)
        }
        .sheet(isPresented: $showNetworkStatusModal) {
            NetworkStatusDetailModal(viewModel: viewModel)
        }
        .sheet(isPresented: $showAlertAIAssistant) {
            if let alert = selectedAlert {
                AlertAIAssistantModal(alert: alert, isPresented: $showAlertAIAssistant)
            }
        }
        .onAppear {
            print("🟢 DASHBOARD: View appeared - starting lightweight initialization")
            // Start lightweight operations immediately for UI responsiveness
            Task {
                await viewModel.updateMetrics()
            }
            
            // Start background loading without blocking UI
            Task {
                await loadingStateManager.startLoading()
            }
            
            Task {
                await loadDashboardData()
            }
        }
        .onDisappear {
            print("🟡 DASHBOARD: View disappeared - continuing background updates")
            // Keep updates running in background for live data
        }
    }
    
    private func loadDashboardData() async {
        // Start all providers in background without waiting for completion
        Task { await systemHealthProvider.loadSystemHealth() }
        Task { await hardwareProviders.loadHardwareData() }
        Task { await applicationsProvider.loadApplications() }
        Task { await securityStatusProvider.loadSecurityStatus() }
        // Software updates are handled by LoadingStateManager to avoid duplication
        
        await MainActor.run {
            loadingStateManager.stopLoading()
        }
    }
}

// MARK: - Dashboard Header

struct DashboardHeader: View {
    @Binding var isCompactMode: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("System Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("Real-time system monitoring and management")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Compact mode toggle
            HStack(spacing: 12) {
                Label("Compact View", systemImage: isCompactMode ? "rectangle.grid.1x2.fill" : "rectangle.grid.2x2")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Toggle("", isOn: $isCompactMode)
                    .toggleStyle(SwitchToggleStyle())
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - System Overview Column

struct SystemOverviewColumn: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var expandedSections: Set<String>
    let onSystemHealthTap: () -> Void
    let onNetworkTap: () -> Void
    let softwareUpdateProvider: SoftwareUpdateProvider
    
    var body: some View {
        VStack(spacing: 20) {
            // Section Header
            SectionHeader(
                title: "System Overview",
                icon: "desktopcomputer",
                subtitle: "Performance and health monitoring"
            )
            
            // System Performance Card (Full Width)
            StandardCard(
                title: "💻 System Performance",
                subtitle: "Last updated \(viewModel.lastChecked.formatted(.relative(presentation: .named)))",
                status: systemHealthStatus,
                isExpandable: true,
                isExpanded: expandedSections.contains("performance"),
                onTap: onSystemHealthTap,
                onToggleExpand: {
                    toggleSection("performance")
                }
            ) {
                SystemPerformanceContent(viewModel: viewModel, isExpanded: expandedSections.contains("performance"))
            }
            
            // Task Status Card (Full Width)
            TaskStatusCard(agentService: OdinAgentServiceV3.shared)
            
            // Storage & Network Row (Half Width Each)
            HStack(spacing: 16) {
                StandardCard(
                    title: "💾 Storage",
                    subtitle: "SMART: \(viewModel.smartStatus ? "Healthy" : "Warning")",
                    status: storageStatus,
                    cardSize: .half
                ) {
                    StorageContent(viewModel: viewModel)
                }
                
                StandardCard(
                    title: "🌐 Network",
                    subtitle: "\(viewModel.interfaceType) • \(Int(viewModel.pingTime))ms",
                    status: networkStatus,
                    cardSize: .half,
                    onTap: onNetworkTap
                ) {
                    NetworkContent(viewModel: viewModel)
                }
            }
            
            // Updates Row (Half Width Each)
            HStack(spacing: 16) {
                StandardCard(
                    title: "📦 Software Updates",
                    subtitle: "Checked \(viewModel.lastChecked.formatted(.relative(presentation: .named)))",
                    status: softwareUpdateStatus,
                    cardSize: .half
                ) {
                    SoftwareUpdatesContent(viewModel: viewModel)
                }
                
                StandardCard(
                    title: "🔄 System Updates",
                    subtitle: "\(viewModel.pendingUpdatesCount) pending",
                    status: systemUpdateStatus,
                    cardSize: .half
                ) {
                    SystemUpdatesContent(viewModel: viewModel)
                }
            }
        }
    }
    
    // Helper methods for status calculation
    private var systemHealthStatus: CardStatus {
        if viewModel.cpuUsage > 0.9 || viewModel.memoryUsage > 0.9 || viewModel.diskUsage > 0.95 {
            return .error
        } else if viewModel.cpuUsage > 0.7 || viewModel.memoryUsage > 0.8 || viewModel.diskUsage > 0.85 {
            return .warning
        } else {
            return .success
        }
    }
    
    private var storageStatus: CardStatus {
        if !viewModel.smartStatus { return .error }
        if viewModel.diskUsage > 0.9 { return .error }
        if viewModel.diskUsage > 0.8 { return .warning }
        return .success
    }
    
    private var networkStatus: CardStatus {
        if viewModel.pingTime > 200 { return .error }
        if viewModel.pingTime > 100 { return .warning }
        return .success
    }
    
    private var softwareUpdateStatus: CardStatus {
        if viewModel.pendingUpdatesCount > 10 { return .warning }
        if viewModel.pendingUpdatesCount > 0 { return .info }
        return .success
    }
    
    private var systemUpdateStatus: CardStatus {
        if viewModel.pendingUpdatesCount > 5 { return .error }
        if viewModel.pendingUpdatesCount > 0 { return .warning }
        return .success
    }
    
    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

// MARK: - Support & Actions Column

struct SupportActionsColumn: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Binding var expandedSections: Set<String>
    let onAlertClick: (AlertItem) -> Void
    var onNavigateToSupport: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 20) {
            // Section Header
            SectionHeader(
                title: "Support & Actions",
                icon: "bubble.left.and.bubble.right",
                subtitle: "Alerts, assistance, and quick tools"
            )
            
            // Critical Alerts Card (Full Width)
            StandardCard(
                title: "🚨 Critical Alerts",
                subtitle: alertsSubtitle,
                status: alertsStatus,
                isExpandable: true,
                isExpanded: expandedSections.contains("alerts"),
                onToggleExpand: {
                    toggleSection("alerts")
                }
            ) {
                AlertsContent(
                    viewModel: viewModel,
                    isExpanded: expandedSections.contains("alerts"),
                    onAlertClick: onAlertClick
                )
            }
            
            // Support Tickets & AI Assistant Row
            HStack(spacing: 16) {
                StandardCard(
                    title: "🎫 Support Tickets",
                    subtitle: ticketsSubtitle,
                    cardSize: .half
                ) {
                    TicketsContent(viewModel: viewModel)
                }
                
                StandardCard(
                    title: "🤖 Ask Huginn",
                    subtitle: "AI-powered assistance",
                    cardSize: .half,
                    onTap: {
                        onNavigateToSupport?()
                    }
                ) {
                    AIAssistantContent(onNavigateToSupport: onNavigateToSupport)
                }
            }
            
            // Quick Actions Card (Full Width)
            StandardCard(
                title: "⚡ Quick Actions",
                subtitle: "System maintenance tools",
                isExpandable: true,
                isExpanded: expandedSections.contains("actions"),
                onToggleExpand: {
                    toggleSection("actions")
                }
            ) {
                QuickActionsContent(
                    viewModel: viewModel,
                    isExpanded: expandedSections.contains("actions")
                )
            }
        }
    }
    
    // Helper computed properties
    private var alertsStatus: CardStatus {
        if viewModel.alerts.contains(where: { $0.severity == .critical }) {
            return .error
        } else if viewModel.alerts.contains(where: { $0.severity == .error }) {
            return .error
        } else if viewModel.alerts.contains(where: { $0.severity == .warning }) {
            return .warning
        } else if !viewModel.alerts.isEmpty {
            return .info
        } else {
            return .success
        }
    }
    
    private var alertsSubtitle: String {
        if viewModel.alerts.isEmpty {
            return "All systems normal"
        } else {
            return "\(viewModel.alerts.count) alerts requiring attention"
        }
    }
    
    private var ticketsSubtitle: String {
        if viewModel.tickets.isEmpty {
            return "No open tickets"
        } else {
            return "\(viewModel.tickets.count) open tickets"
        }
    }
    
    private func toggleSection(_ section: String) {
        if expandedSections.contains(section) {
            expandedSections.remove(section)
        } else {
            expandedSections.insert(section)
        }
    }
}

// MARK: - Section Header Component

struct SectionHeader: View {
    let title: String
    let icon: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .frame(width: 28, height: 28)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            // Section divider with gradient
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.3), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Standardized Card Component

enum CardSize {
    case full, half, third
    
    var maxWidth: CGFloat? {
        switch self {
        case .full: return .infinity
        case .half: return .infinity
        case .third: return .infinity
        }
    }
}

struct StandardCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let status: CardStatus?
    let cardSize: CardSize
    let isExpandable: Bool
    let isExpanded: Bool
    let onTap: (() -> Void)?
    let onToggleExpand: (() -> Void)?
    let content: Content
    
    @State private var isHovered = false
    
    init(
        title: String,
        subtitle: String? = nil,
        status: CardStatus? = nil,
        cardSize: CardSize = .full,
        isExpandable: Bool = false,
        isExpanded: Bool = false,
        onTap: (() -> Void)? = nil,
        onToggleExpand: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.status = status
        self.cardSize = cardSize
        self.isExpandable = isExpandable
        self.isExpanded = isExpanded
        self.onTap = onTap
        self.onToggleExpand = onToggleExpand
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Card Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                HStack(spacing: 8) {
                    if let status = status {
                        StatusBadge(status: status)
                    }
                    
                    if isExpandable {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                onToggleExpand?()
                            }
                        }) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    
                    if onTap != nil {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Card Content
            content
        }
        .padding(20)
        .frame(maxWidth: cardSize.maxWidth)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(
                    color: .black.opacity(isHovered ? 0.15 : 0.08),
                    radius: isHovered ? 8 : 4,
                    x: 0,
                    y: isHovered ? 4 : 2
                )
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering && (onTap != nil || isExpandable)
        }
        .onTapGesture {
            if let onTap = onTap {
                onTap()
            } else if isExpandable {
                withAnimation(.easeInOut(duration: 0.2)) {
                    onToggleExpand?()
                }
            }
        }
    }
}

// MARK: - Content Components

struct SystemPerformanceContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isExpanded: Bool
    
    var body: some View {
        VStack(spacing: 16) {
            // Main metrics row
            HStack(spacing: 20) {
                MetricDisplay(
                    icon: "cpu",
                    label: "CPU",
                    value: viewModel.cpuUsage,
                    color: cpuColor(for: viewModel.cpuUsage),
                    isLarge: true
                )
                
                MetricDisplay(
                    icon: "memorychip",
                    label: "Memory",
                    value: viewModel.memoryUsage,
                    color: memoryColor(for: viewModel.memoryUsage),
                    isLarge: true
                )
                
                MetricDisplay(
                    icon: "internaldrive",
                    label: "Storage",
                    value: viewModel.diskUsage,
                    color: diskColor(for: viewModel.diskUsage),
                    isLarge: true
                )
            }
            
            if isExpanded {
                Divider()
                
                // Additional metrics when expanded
                VStack(spacing: 12) {
                    HStack {
                        Label("Active Processes", systemImage: "list.bullet")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(viewModel.totalProcesses)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Label("System Uptime", systemImage: "clock")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.systemUptime)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Label("Available Space", systemImage: "externaldrive")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.availableSpace)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
            }
        }
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
    
    private func diskColor(for usage: Double) -> Color {
        if usage > 0.9 { return .red }
        if usage > 0.8 { return .orange }
        return .green
    }
}

struct MetricDisplay: View {
    let icon: String
    let label: String
    let value: Double
    let color: Color
    let isLarge: Bool
    
    init(icon: String, label: String, value: Double, color: Color, isLarge: Bool = false) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.isLarge = isLarge
    }
    
    var body: some View {
        VStack(spacing: isLarge ? 8 : 6) {
            Image(systemName: icon)
                .font(isLarge ? .title2 : .title3)
                .foregroundColor(color)
            
            Text(label)
                .font(isLarge ? .subheadline : .caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
            
            Text("\(Int(value * 100))%")
                .font(isLarge ? .title3 : .subheadline)
                .fontWeight(.bold)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity)
    }
}

struct StorageContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Circle()
                    .fill(viewModel.smartStatus ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(viewModel.smartStatus ? "SMART OK" : "SMART Fail")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            ProgressView(value: viewModel.diskUsage)
                .progressViewStyle(LinearProgressViewStyle(tint: diskColor(for: viewModel.diskUsage)))
            
            HStack {
                Text("Used: \(Int(viewModel.diskUsage * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Available: \(viewModel.availableSpace)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func diskColor(for usage: Double) -> Color {
        if usage > 0.9 { return .red }
        if usage > 0.8 { return .orange }
        return .green
    }
}

struct NetworkContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: viewModel.interfaceType == "Wi-Fi" ? "wifi" : "ethernet")
                    .foregroundColor(.accentColor)
                Text(viewModel.interfaceType)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }
            
            HStack {
                Text("Ping:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(viewModel.pingTime))ms")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(pingColor)
            }
            
            if !viewModel.networkName.isEmpty && viewModel.networkName != viewModel.interfaceType {
                HStack {
                    Text("Network:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.networkName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
    }
    
    private var pingColor: Color {
        if viewModel.pingTime > 100 { return .red }
        if viewModel.pingTime > 50 { return .orange }
        return .green
    }
}

struct SoftwareUpdatesContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Available Updates")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.pendingUpdatesCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.pendingUpdatesCount > 0 ? .orange : .green)
            }
            
            Button("Refresh Now") {
                Task {
                    await viewModel.checkForUpdates()
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
    }
}

struct SystemUpdatesContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Pending")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(viewModel.pendingUpdatesCount)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(viewModel.pendingUpdatesCount > 0 ? .orange : .green)
            }
            
            if viewModel.pendingUpdatesCount > 0 {
                Button("Install \(viewModel.pendingUpdatesCount) Updates") {
                    // TODO: Install updates
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            } else {
                Text("System up to date")
                    .font(.caption)
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

struct AlertsContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isExpanded: Bool
    let onAlertClick: (AlertItem) -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.alerts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text("All systems normal")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                let displayedAlerts = isExpanded ? viewModel.alerts : Array(viewModel.alerts.prefix(3))
                
                ForEach(displayedAlerts) { alert in
                    AlertRowCompact(alert: alert, onAlertClick: onAlertClick)
                }
                
                if !isExpanded && viewModel.alerts.count > 3 {
                    Text("+ \(viewModel.alerts.count - 3) more alerts")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }
}

struct AlertRowCompact: View {
    let alert: AlertItem
    let onAlertClick: (AlertItem) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: alertIcon)
                .font(.subheadline)
                .foregroundColor(alert.severity.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(alert.severity.label.uppercased())
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(alert.severity.color)
            }
            
            Spacer()
            
            Button("Fix") {
                onAlertClick(alert)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.mini)
        }
        .padding(.vertical, 4)
        .background(alert.severity.color.opacity(0.05))
        .cornerRadius(8)
    }
    
    private var alertIcon: String {
        switch alert.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
}

struct TicketsContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            if viewModel.tickets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                    Text("No open tickets")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                HStack {
                    Text("Open")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(viewModel.tickets.count)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.orange)
                }
                
                // Show latest ticket
                if let latest = viewModel.tickets.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(latest.title)
                            .font(.caption)
                            .lineLimit(1)
                        Text(latest.date, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct AIAssistantContent: View {
    var onNavigateToSupport: (() -> Void)?
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "message.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Help")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("AI assistance")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            
            Button("Start Chat") {
                onNavigateToSupport?()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
    }
}

struct QuickActionsContent: View {
    @ObservedObject var viewModel: DashboardViewModel
    let isExpanded: Bool
    
    var body: some View {
        if isExpanded {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(viewModel.quickActions) { action in
                    QuickActionButton(action: action)
                }
            }
        } else {
            HStack(spacing: 12) {
                ForEach(viewModel.quickActions.prefix(3)) { action in
                    QuickActionButton(action: action)
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let action: QuickAction
    @State private var isRunning = false
    @State private var isHovered = false
    
    var body: some View {
        Button(action: runScript) {
            VStack(spacing: 8) {
                if isRunning {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "play.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
                
                Text(action.name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: .black.opacity(isHovered ? 0.1 : 0.05), radius: isHovered ? 4 : 2)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isHovered)
        }
        .buttonStyle(.plain)
        .disabled(isRunning)
        .onHover { hovering in
            isHovered = hovering
        }
    }
    
    private func runScript() {
        isRunning = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isRunning = false
            print("TODO: Execute script at \(action.scriptPath.path)")
        }
    }
}

// MARK: - Enhanced Status Badge

struct StatusBadge: View {
    let status: CardStatus
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.caption2)
            Text(statusText)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(status.color)
        )
    }
    
    private var statusText: String {
        switch status {
        case .success: return "Healthy"
        case .warning: return "Warning"
        case .error: return "Error"
        case .info: return "Info"
        case .loading: return "Loading"
        }
    }
}

// MARK: - Card Status (keeping existing implementation)

enum CardStatus {
    case success
    case warning
    case error
    case info
    case loading
    
    var color: Color {
        switch self {
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        case .info: return .blue
        case .loading: return .gray
        }
    }
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .loading: return "ellipsis.circle.fill"
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

struct AlertAIAssistantModal: View {
    let alert: AlertItem
    @Binding var isPresented: Bool
    
    @State private var analysisText = ""
    @State private var recommendedSolutions: [SolutionOption] = []
    @State private var isAnalyzing = false
    @State private var customRequest = ""
    @State private var showingGeneratedScript = false
    @State private var generatedScriptContent = ""
    @State private var generatedScriptName = ""
    
    @StateObject private var ollamaService = OllamaScriptGenerationService.shared
    @ObservedObject private var scriptManager = ScriptManagerViewModel.shared
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Alert Header
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: alertIcon)
                                .foregroundColor(alert.severity.color)
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(alert.title)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Text(alert.severity.label.uppercased())
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(alert.severity.color.opacity(0.2))
                                    .foregroundColor(alert.severity.color)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                            if isAnalyzing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    
                    // AI Analysis Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "brain.head.profile")
                                .foregroundColor(.blue)
                                .font(.title3)
                            Text("AI Analysis")
                                .font(.headline)
                            Spacer()
                        }
                        
                        if analysisText.isEmpty && !isAnalyzing {
                            VStack(spacing: 12) {
                                Text("Get AI-powered analysis and solutions for this system alert.")
                                    .foregroundColor(.secondary)
                                
                                Button("Analyze Alert") {
                                    analyzeAlert()
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if isAnalyzing {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI is analyzing the alert and generating solutions...")
                                    .foregroundColor(.secondary)
                            }
                            .padding()
                        } else {
                            Text(analysisText)
                                .font(.body)
                                .padding()
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                    )
                }
                .padding()
            }
            .navigationTitle("AI Alert Assistant")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(width: 700, height: 800)
        .onAppear {
            // Auto-analyze the alert when modal appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if analysisText.isEmpty {
                    analyzeAlert()
                }
            }
        }
    }
    
    private var alertIcon: String {
        switch alert.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "exclamationmark.octagon.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }
    
    private func analyzeAlert() {
        isAnalyzing = true
        
        Task {
            do {
                let analysisPrompt = """
                Analyze this macOS system alert and provide detailed information:
                
                Alert: \(alert.title)
                Severity: \(alert.severity.label)
                
                Please provide:
                1. What this alert means and why it occurred
                2. Potential causes and implications
                3. Immediate risks or concerns
                4. Step-by-step solutions
                5. Prevention recommendations
                
                Focus on macOS-specific solutions and be practical for end users.
                """
                
                let response = try await ollamaService.generateDiagnosticScript(for: analysisPrompt)
                
                await MainActor.run {
                    analysisText = response.content
                    isAnalyzing = false
                }
                
            } catch {
                await MainActor.run {
                    analysisText = "Unable to analyze alert at this time. Please check if Ollama is running on your system."
                    isAnalyzing = false
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct SolutionOption: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let type: SolutionType
    let estimatedTime: String
    let difficulty: Difficulty
    
    enum SolutionType {
        case script
        case manual
        case setting
    }
    
    enum Difficulty {
        case easy
        case intermediate
        case advanced
        
        var color: Color {
            switch self {
            case .easy: return .green
            case .intermediate: return .orange
            case .advanced: return .red
            }
        }
        
        var label: String {
            switch self {
            case .easy: return "Easy"
            case .intermediate: return "Intermediate"
            case .advanced: return "Advanced"
            }
        }
    }
}

// MARK: - Task Status Card

struct TaskStatusCard: View {
    @ObservedObject var agentService: OdinAgentServiceV3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "list.bullet.clipboard")
                    .foregroundColor(.blue)
                Text("Task Status")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task {
                        await agentService.pollTasks()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Pending Tasks:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(agentService.pendingTasks.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                HStack {
                    Text("Executing Tasks:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(agentService.executingTasks.count)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }
                
                if !agentService.pendingTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Tasks:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(agentService.pendingTasks.prefix(3)) { task in
                            HStack {
                                Image(systemName: "circle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption2)
                                Text(task.displayName)
                                    .font(.caption)
                                Spacer()
                                Text(task.type)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                
                if !agentService.executingTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Currently Executing:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        ForEach(Array(agentService.executingTasks.values.prefix(3)), id: \.id) { taskStatus in
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundColor(.blue)
                                    .font(.caption2)
                                Text(taskStatus.message)
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(taskStatus.progress * 100))%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
} 