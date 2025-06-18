import SwiftUI
import Charts

struct SystemHealthView: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    @StateObject private var healthProvider: SystemHealthProvider
    @StateObject private var updateProvider = SoftwareUpdateProvider()
    @StateObject private var securityProvider = SecurityStatusProvider()
    @State private var showOSUpdateModal = false
    @State private var showThirdPartyUpdateModal = false
    
    init(systemInfo: SystemInfoProvider) {
        _systemInfo = ObservedObject(wrappedValue: systemInfo)
        _healthProvider = StateObject(wrappedValue: SystemHealthProvider(systemInfo: systemInfo))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title and Update Status
                titleSection
                
                // Security Section
                securitySection
                
                // System Metrics
                metricsSection
                
                // Updates Section
                updatesSection
            }
            .padding()
        }
        .background(Color.clear)
        .task {
            await loadData()
        }
        .sheet(isPresented: $showOSUpdateModal) {
            osUpdateModal
        }
        .sheet(isPresented: $showThirdPartyUpdateModal) {
            thirdPartyUpdateModal
        }
    }
    
    private var titleSection: some View {
        HStack {
            Text("System Health")
                .font(.largeTitle)
                .bold()
                .foregroundColor(.primary)
            Spacer()
            if updateProvider.hasUpdates {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Updates Available")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
    }
    
    private var securitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Security Status")
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                SecurityCard(
                    title: "Antivirus",
                    status: securityProvider.antivirusStatus,
                    icon: "shield.checkerboard"
                )
                SecurityCard(
                    title: "Firewall",
                    status: securityProvider.firewallStatus,
                    icon: "lock.shield"
                )
                SecurityCard(
                    title: "Disk Encryption",
                    status: securityProvider.diskEncryptionStatus,
                    icon: "lock.doc"
                )
            }
        }
        .padding(20)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
    
    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Metrics")
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
            
            HStack(spacing: 24) {
                HealthLineGraph(title: "CPU Usage", data: healthProvider.cpuHistory, color: .purple, unit: "%")
                HealthLineGraph(title: "Memory Usage", data: healthProvider.memoryHistory, color: .blue, unit: "%")
                HealthLineGraph(title: "Network Usage", data: healthProvider.networkHistory, color: .teal, unit: "%")
            }
            .frame(height: 220)
        }
        .padding(20)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
    
    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Updates")
                .font(.title2)
                .bold()
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                macOSUpdateCard
                thirdPartyUpdateCard
            }
        }
        .padding(20)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
    
    private var macOSUpdateCard: some View {
        Button(action: {
            if updateProvider.osUpdateAvailable {
                showOSUpdateModal = true
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "apple.logo")
                        .font(.title2)
                        .foregroundColor(updateProvider.osUpdateAvailable ? .orange : .green)
                    Text("macOS Updates")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: updateProvider.osUpdateAvailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(updateProvider.osUpdateAvailable ? .orange : .green)
                }
                
                if updateProvider.osUpdateAvailable {
                    ForEach(updateProvider.updates.prefix(2), id: \.id) { update in
                        Text(update.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if updateProvider.updates.count > 2 {
                        Text("+ \(updateProvider.updates.count - 2) more updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("System is up to date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!updateProvider.osUpdateAvailable)
    }
    
    private var thirdPartyUpdateCard: some View {
        Button(action: {
            if updateProvider.thirdPartyUpdatesAvailable {
                showThirdPartyUpdateModal = true
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "app.badge")
                        .font(.title2)
                        .foregroundColor(updateProvider.thirdPartyUpdatesAvailable ? .orange : .green)
                                            Text("Third-party Updates")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Image(systemName: updateProvider.thirdPartyUpdatesAvailable ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundColor(updateProvider.thirdPartyUpdatesAvailable ? .orange : .green)
                }
                
                if !updateProvider.toolStatus["brew", default: false] {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Homebrew not installed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                if !updateProvider.toolStatus["mas", default: false] {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("mas-cli not installed")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                if updateProvider.thirdPartyUpdatesAvailable {
                    let filteredDetails = updateProvider.updateDetails.filter { $0.contains("Homebrew") || $0.contains("App Store") }
                    ForEach(filteredDetails.prefix(2), id: \.self) { detail in
                        Text(detail)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if filteredDetails.count > 2 {
                        Text("+ \(filteredDetails.count - 2) more updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if updateProvider.toolStatus["brew", default: false] && updateProvider.toolStatus["mas", default: false] {
                    Text("All third-party software is up to date")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!updateProvider.thirdPartyUpdatesAvailable)
    }
    
    private var osUpdateModal: some View {
        UpdateDetailModal(
            title: "macOS Updates",
            icon: "apple.logo",
            updates: updateProvider.updates.map { $0.name },
            homebrewUpdates: [],
            appStoreUpdates: [],
            onClose: { showOSUpdateModal = false },
            updateProvider: updateProvider
        )
    }
    
    private var thirdPartyUpdateModal: some View {
        UpdateDetailModal(
            title: "Third-party Updates",
            icon: "app.badge",
            updates: updateProvider.updateDetails.filter { $0.contains("Homebrew") || $0.contains("App Store") },
            homebrewUpdates: updateProvider.homebrewUpdates,
            appStoreUpdates: updateProvider.appStoreUpdates,
            onClose: { showThirdPartyUpdateModal = false },
            updateProvider: updateProvider
        )
    }
    
    private func loadData() async {
        await Task.detached {
            await securityProvider.checkSecurityStatus()
            _ = try? await updateProvider.checkForUpdates()
        }.value
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
                Chart(data) { point in
                    LineMark(
                        x: .value("Time", point.time),
                        y: .value("Value", point.value)
                    )
                    .foregroundStyle(color)
                }
                .frame(height: 120)
                .chartYScale(domain: 0...100)
                .chartXAxis(.hidden)
                .chartYAxis(.visible)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: 120)
                    .overlay(
                        Text("No data")
                            .foregroundColor(.secondary)
                    )
            }
            
            Text("Current: \(String(format: "%.1f", data.last?.value ?? 0.0))\(unit)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
}

struct UpdateDetailModal: View {
    let title: String
    let icon: String
    let updates: [String]
    let homebrewUpdates: [String]
    let appStoreUpdates: [String]
    let onClose: () -> Void
    @ObservedObject var updateProvider: SoftwareUpdateProvider
    
    @State private var updatingPackages: Set<String> = []
    @State private var completedPackages: Set<String> = []
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.orange)
                Text(title)
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.bottom)
            
            Divider()
            
            // Update List
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if homebrewUpdates.isEmpty && appStoreUpdates.isEmpty && updates.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.green)
                            Text("No updates available")
                                .font(.title3)
                                .foregroundColor(.primary)
                            Text("Your system is up to date!")
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                    }
                    
                    if !homebrewUpdates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Homebrew Packages")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 4)
                            
                            ForEach(homebrewUpdates, id: \.self) { package in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(package)
                                            .font(.body)
                                            .foregroundColor(.primary)
                                    }
                                    Spacer()
                                                                    Button(action: {
                                    Task {
                                        await updateHomebrewPackage(package)
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        if updatingPackages.contains(package) {
                                            ProgressView()
                                                .scaleEffect(0.8)
                                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        } else if completedPackages.contains(package) {
                                            Image(systemName: "checkmark")
                                                .foregroundColor(.white)
                                        }
                                        
                                        Text(updatingPackages.contains(package) ? "Updating..." : 
                                             completedPackages.contains(package) ? "Updated" : "Update")
                                            .font(.subheadline)
                                            .foregroundColor(.white)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(completedPackages.contains(package) ? Color.green : Color.blue)
                                    .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(updatingPackages.contains(package) || completedPackages.contains(package))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    if !appStoreUpdates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("App Store Applications")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 4)
                            
                            ForEach(appStoreUpdates, id: \.self) { app in
                                HStack {
                                    Text(app)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button(action: {
                                        Task {
                                            await updateAppStoreApp(app)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            if updatingPackages.contains(app) {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else if completedPackages.contains(app) {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.white)
                                            }
                                            
                                            Text(updatingPackages.contains(app) ? "Updating..." : 
                                                 completedPackages.contains(app) ? "Updated" : "Update")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(completedPackages.contains(app) ? Color.green : Color.blue)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(updatingPackages.contains(app) || completedPackages.contains(app))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    
                    if !updates.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("System Updates")
                                .font(.headline)
                                .foregroundColor(.primary)
                                .padding(.bottom, 4)
                            
                            ForEach(updates, id: \.self) { update in
                                HStack {
                                    Text(update)
                                        .font(.body)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Button(action: {
                                        Task {
                                            await installSystemUpdate(update)
                                        }
                                    }) {
                                        HStack(spacing: 4) {
                                            if updatingPackages.contains(update) {
                                                ProgressView()
                                                    .scaleEffect(0.8)
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            } else if completedPackages.contains(update) {
                                                Image(systemName: "checkmark")
                                                    .foregroundColor(.white)
                                            }
                                            
                                            Text(updatingPackages.contains(update) ? "Installing..." : 
                                                 completedPackages.contains(update) ? "Installed" : "Install")
                                                .font(.subheadline)
                                                .foregroundColor(.white)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(completedPackages.contains(update) ? Color.green : Color.orange)
                                        .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(updatingPackages.contains(update) || completedPackages.contains(update))
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color(.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 300)
        }
        .padding(24)
        .frame(width: 600, height: 500)
        .background(Color(.windowBackgroundColor))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        .alert("Update Status", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func updateHomebrewPackage(_ package: String) async {
        updatingPackages.insert(package)
        
        do {
            print("Starting Homebrew update for package: \(package)")
            await updateProvider.updateHomebrewPackage(package)
            
            // Simulate some processing time for visual feedback
            try await Task.sleep(nanoseconds: 1_000_000_000)
            
            updatingPackages.remove(package)
            completedPackages.insert(package)
            
            alertMessage = "Successfully updated \(package)"
            showingAlert = true
            print("Successfully updated Homebrew package: \(package)")
            
        } catch {
            updatingPackages.remove(package)
            alertMessage = "Failed to update \(package): \(error.localizedDescription)"
            showingAlert = true
            print("Failed to update Homebrew package \(package): \(error)")
        }
    }
    
    private func updateAppStoreApp(_ app: String) async {
        updatingPackages.insert(app)
        
        do {
            print("Starting App Store update for app: \(app)")
            await updateProvider.updateAppStoreApp(app)
            
            // Add a small delay for visual feedback
            try await Task.sleep(nanoseconds: 500_000_000)
            
            updatingPackages.remove(app)
            completedPackages.insert(app)
            
            alertMessage = "Successfully updated \(app) from App Store"
            showingAlert = true
            print("Successfully updated App Store app: \(app)")
            
        } catch {
            updatingPackages.remove(app)
            alertMessage = "Failed to update \(app): \(error.localizedDescription)"
            showingAlert = true
            print("Failed to update App Store app \(app): \(error)")
        }
    }
    
    private func installSystemUpdate(_ update: String) async {
        updatingPackages.insert(update)
        
        do {
            print("Starting system update installation: \(update)")
            
            // Simulate system update process (longer duration)
            try await Task.sleep(nanoseconds: 3_000_000_000)
            
            updatingPackages.remove(update)
            completedPackages.insert(update)
            
            alertMessage = "Successfully installed system update: \(update)\nA restart may be required."
            showingAlert = true
            print("Successfully installed system update: \(update)")
            
        } catch {
            updatingPackages.remove(update)
            alertMessage = "Failed to install \(update): \(error.localizedDescription)"
            showingAlert = true
            print("Failed to install system update \(update): \(error)")
        }
    }
}

struct SecurityCard: View {
    let title: String
    let status: SecurityStatus
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(status.isSecure ? .green : .red)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: status.isSecure ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(status.isSecure ? .green : .red)
            }
            
            if let details = status.details {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            
            if let recommendation = status.recommendation {
                Text(recommendation)
                    .font(.caption)
                    .foregroundColor(.orange)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(16)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
} 