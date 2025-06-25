import SwiftUI
import Charts

struct StatusCard: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(String(format: "%.1f%@", value, unit))
                .font(.title2)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SystemInfoCard: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Information")
                .font(.headline)
            
            Text(systemInfo.systemSummary)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct ActiveAlertsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Alerts")
                .font(.headline)
            
            Text("No active alerts")
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .tint(color)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct SecurityCard: View {
    let title: String
    let status: SecurityInfo
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(status.isSecure ? .green : .orange)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: status.isSecure ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(status.isSecure ? .green : .orange)
            }
            
            if let details = status.details {
                Text(details)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let recommendation = status.recommendation {
                Text(recommendation)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct HealthLineGraph: View {
    let title: String
    let data: [DataPoint]
    let color: Color
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
            
            if !data.isEmpty {
                Chart {
                    ForEach(data) { point in
                        LineMark(
                            x: .value("Time", point.time),
                            y: .value("Value", point.value)
                        )
                        .foregroundStyle(color)
                    }
                }
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: Decimal.FormatStyle.Percent.percent.scale(1))
                    }
                }
            } else {
                Text("No data available")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let currentValue = data.last?.value {
                Text("\(Int(currentValue))\(unit)")
                    .font(.title2)
                    .bold()
                    .foregroundColor(color)
            }
        }
    }
}

struct UpdateDetailModal: View {
    let title: String
    let icon: String
    let updates: [String]
    let homebrewUpdates: [HomebrewUpdate]
    let appStoreUpdates: [AppStoreUpdate]
    let onClose: () -> Void
    let updateProvider: SoftwareUpdateProvider
    
    @State private var selectedUpdates: Set<String> = []
    @State private var updatingPackages: Set<String> = []
    @State private var completedPackages: Set<String> = []
    @State private var installationProgress: [String: Double] = [:]
    @State private var estimatedTimeRemaining: [String: TimeInterval] = [:]
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var showHomebrewSection = true
    @State private var showAppStoreSection = true
    @State private var sortOrder: SortOrder = .name
    @State private var showingRebootAlert = false
    
    enum SortOrder {
        case name, size
    }
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.title)
                    .bold()
                Spacer()
                Menu {
                    Button(action: { sortOrder = .name }) {
                        Label("Sort by Name", systemImage: "textformat")
                    }
                    Button(action: { sortOrder = .size }) {
                        Label("Sort by Size", systemImage: "arrow.up.arrow.down")
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Reboot Notification
            if updateProvider.requiresReboot {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("System Restart Required")
                            .font(.headline)
                            .foregroundColor(.orange)
                    }
                    Text(updateProvider.rebootReason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button(action: {
                        showingRebootAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Restart Now")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color.orange.opacity(0.1))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange, lineWidth: 1)
                )
            }
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Homebrew Updates Section
                    if !homebrewUpdates.isEmpty {
                        UpdateSection(
                            title: "Homebrew Updates",
                            icon: "terminal",
                            isExpanded: $showHomebrewSection
                        ) {
                            ForEach(homebrewUpdates.sorted { sortOrder == .name ? $0.name < $1.name : $0.size > $1.size }) { package in
                                UpdateItemRow(
                                    title: package.name,
                                    currentVersion: package.currentVersion,
                                    newVersion: package.newVersion,
                                    source: .homebrew,
                                    isSelected: selectedUpdates.contains(package.name),
                                    isUpdating: updatingPackages.contains(package.name),
                                    isCompleted: completedPackages.contains(package.name),
                                    progress: installationProgress[package.name] ?? 0.0,
                                    timeRemaining: estimatedTimeRemaining[package.name] ?? 0,
                                    onToggle: { isSelected in
                                        if isSelected {
                                            selectedUpdates.insert(package.name)
                                        } else {
                                            selectedUpdates.remove(package.name)
                                        }
                                    },
                                    onInstall: {
                                        Task {
                                            await installHomebrewPackage(package)
                                        }
                                    }
                                )
                            }
                        }
                    }
                    
                    // App Store Updates Section
                    if !appStoreUpdates.isEmpty {
                        UpdateSection(
                            title: "App Store Updates",
                            icon: "app.badge",
                            isExpanded: $showAppStoreSection
                        ) {
                            ForEach(appStoreUpdates.sorted { sortOrder == .name ? $0.name < $1.name : $0.size > $1.size }) { app in
                                UpdateItemRow(
                                    title: app.name,
                                    currentVersion: app.currentVersion,
                                    newVersion: app.newVersion,
                                    source: .appStore,
                                    isSelected: selectedUpdates.contains(app.name),
                                    isUpdating: updatingPackages.contains(app.name),
                                    isCompleted: completedPackages.contains(app.name),
                                    progress: installationProgress[app.name] ?? 0.0,
                                    timeRemaining: estimatedTimeRemaining[app.name] ?? 0,
                                    onToggle: { isSelected in
                                        if isSelected {
                                            selectedUpdates.insert(app.name)
                                        } else {
                                            selectedUpdates.remove(app.name)
                                        }
                                    },
                                    onInstall: {
                                        Task {
                                            await installAppStoreApp(app)
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Install Selected Button
            if !selectedUpdates.isEmpty {
                Button(action: {
                    Task {
                        await installSelectedUpdates()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Install Selected (\(selectedUpdates.count))")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(updatingPackages.count > 0)
            }
        }
        .padding()
        .frame(width: 600, height: 600)
        .background(Color(.windowBackgroundColor))
        .alert("Installation Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("System Restart", isPresented: $showingRebootAlert) {
            Button("Restart Now", role: .destructive) {
                updateProvider.performReboot()
            }
            Button("Later", role: .cancel) { }
        } message: {
            Text("A system restart is required to complete the installation. Would you like to restart now?")
        }
    }
    
    private func installHomebrewPackage(_ package: HomebrewUpdate) async {
        updatingPackages.insert(package.name)
        installationProgress[package.name] = 0.0
        estimatedTimeRemaining[package.name] = 120 // 2 minutes estimated
        
        do {
            print("Starting Homebrew update for package: \(package.name)")
            for progress in stride(from: 0.0, to: 1.0, by: 0.1) {
                installationProgress[package.name] = progress
                estimatedTimeRemaining[package.name] = 120 * (1 - progress)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            
            try await updateProvider.updateHomebrewPackage(package)
            
            installationProgress[package.name] = 1.0
            estimatedTimeRemaining[package.name] = 0
            updatingPackages.remove(package.name)
            completedPackages.insert(package.name)
            selectedUpdates.remove(package.name)
            
            alertMessage = "Successfully updated \(package.name) via Homebrew"
            showingAlert = true
            print("Successfully updated \(package.name) via Homebrew")
        } catch {
            updatingPackages.remove(package.name)
            installationProgress.removeValue(forKey: package.name)
            estimatedTimeRemaining.removeValue(forKey: package.name)
            
            alertMessage = "Failed to update \(package.name): \(error.localizedDescription)"
            showingAlert = true
            print("Failed to update \(package.name): \(error)")
        }
    }
    
    private func installAppStoreApp(_ app: AppStoreUpdate) async {
        updatingPackages.insert(app.name)
        installationProgress[app.name] = 0.0
        estimatedTimeRemaining[app.name] = 180 // 3 minutes estimated
        
        do {
            print("Starting App Store update for app: \(app.name)")
            for progress in stride(from: 0.0, to: 1.0, by: 0.1) {
                installationProgress[app.name] = progress
                estimatedTimeRemaining[app.name] = 180 * (1 - progress)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            
            try await updateProvider.updateAppStoreApp(app)
            
            installationProgress[app.name] = 1.0
            estimatedTimeRemaining[app.name] = 0
            updatingPackages.remove(app.name)
            completedPackages.insert(app.name)
            selectedUpdates.remove(app.name)
            
            alertMessage = "Successfully updated \(app.name) from App Store"
            showingAlert = true
            print("Successfully updated \(app.name) from App Store")
        } catch {
            updatingPackages.remove(app.name)
            installationProgress.removeValue(forKey: app.name)
            estimatedTimeRemaining.removeValue(forKey: app.name)
            
            alertMessage = "Failed to update \(app.name): \(error.localizedDescription)"
            showingAlert = true
            print("Failed to update \(app.name): \(error)")
        }
    }
    
    private func installSelectedUpdates() async {
        for updateName in selectedUpdates {
            if let homebrewPackage = homebrewUpdates.first(where: { $0.name == updateName }) {
                await installHomebrewPackage(homebrewPackage)
            } else if let appStoreApp = appStoreUpdates.first(where: { $0.name == updateName }) {
                await installAppStoreApp(appStoreApp)
            }
        }
    }
}

struct UpdateSection<Content: View>: View {
    let title: String
    let icon: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: Content
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: { isExpanded.toggle() }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded {
                content
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .animation(.spring(), value: isExpanded)
    }
}

struct UpdateItemRow: View {
    let title: String
    let currentVersion: String
    let newVersion: String
    let source: UpdateSource
    let isSelected: Bool
    let isUpdating: Bool
    let isCompleted: Bool
    let progress: Double
    let timeRemaining: TimeInterval
    let onToggle: (Bool) -> Void
    let onInstall: () -> Void
    
    enum UpdateSource {
        case homebrew, appStore
        
        var icon: String {
            switch self {
            case .homebrew: return "terminal"
            case .appStore: return "app.badge"
            }
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            if !isUpdating && !isCompleted {
                Toggle(isOn: Binding(
                    get: { isSelected },
                    set: { onToggle($0) }
                )) {
                    EmptyView()
                }
                .labelsHidden()
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Image(systemName: source.icon)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if isUpdating {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                        
                        HStack {
                            Text("\(Int(progress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            if timeRemaining > 0 {
                                Text("\(Int(timeRemaining))s remaining")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(currentVersion)
                            .strikethrough()
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(newVersion)
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    .help("Update available: \(currentVersion) → \(newVersion)")
                }
            }
            
            Spacer()
            
            if isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isUpdating {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.7)
            } else {
                Button(action: onInstall) {
                    Text("Install")
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(isSelected && !isUpdating && !isCompleted ? Color.blue.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
    }
}

#Preview {
    VStack {
        StatusCard(title: "CPU", value: 45.5, unit: "%")
        SystemInfoCard(systemInfo: SystemInfoProvider())
        ActiveAlertsCard()
        MetricCard(
            title: "CPU Usage",
            value: "45.5%",
            subtitle: "4 cores active",
            icon: "cpu",
            color: .blue,
            progress: 0.455
        )
    }
    .padding()
} 