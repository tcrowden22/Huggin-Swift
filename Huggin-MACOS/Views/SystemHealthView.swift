import SwiftUI
import Charts

struct SystemHealthView: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    @StateObject private var healthProvider: SystemHealthProvider
    @StateObject private var updateProvider = SoftwareUpdateProvider()
    @StateObject private var securityProvider = SecurityStatusProvider()
    @State private var showOSUpdateModal = false
    @State private var showThirdPartyUpdateModal = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var updatingPackages: Set<String> = []
    @State private var completedPackages: Set<String> = []
    @State private var selectedUpdates: Set<String> = []
    @State private var installationProgress: [String: Double] = [:]
    @State private var estimatedTimeRemaining: [String: TimeInterval] = [:]

    init(systemInfo: SystemInfoProvider) {
        _systemInfo = ObservedObject(wrappedValue: systemInfo)
        _healthProvider = StateObject(wrappedValue: SystemHealthProvider(systemInfo: systemInfo))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Restart notification banner
                if updateProvider.requiresReboot {
                    restartNotificationBanner
                }
                
                titleSection
                securitySection
                metricsSection
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
        .alert("Update Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }

    private func loadData() async {
        // Only load security status - updates are managed centrally
        await securityProvider.checkSecurityStatus()
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
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(updateProvider.updates.prefix(2), id: \.id) { update in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(update.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Text(update.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                                
                                HStack(spacing: 16) {
                                    Label("\(update.size / 1_000_000_000, specifier: "%.1f") GB", systemImage: "arrow.down.circle")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Label("v\(update.version)", systemImage: "tag")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(8)
                        }
                        
                        // Update checks are managed centrally - removed redundant button
                        
                        Button(action: {
                            Task {
                                await updateProvider.checkPendingRestart()
                            }
                        }) {
                            Label("Check for Restart", systemImage: "arrow.clockwise.circle")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
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
    }

    private var thirdPartyUpdateCard: some View {
        Button(action: {
            if updateProvider.thirdPartyUpdatesAvailable {
                showThirdPartyUpdateModal = true
            }
        }) {
            VStack(alignment: .leading, spacing: 12) {
                thirdPartyUpdateHeader
                thirdPartyUpdateContent
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
    }
    
    private var thirdPartyUpdateHeader: some View {
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
    }
    
    private var thirdPartyUpdateContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !updateProvider.toolStatus["brew", default: false] || !updateProvider.toolStatus["mas", default: false] {
                toolStatusWarnings
            }
            
            if updateProvider.thirdPartyUpdatesAvailable {
                availableUpdatesSection
            } else if updateProvider.toolStatus["brew", default: false] && updateProvider.toolStatus["mas", default: false] {
                upToDateSection
            }
        }
    }
    
    private var toolStatusWarnings: some View {
        VStack(alignment: .leading, spacing: 4) {
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
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
    
    private var availableUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !updateProvider.homebrewUpdates.isEmpty {
                homebrewUpdatesSection
            }
            
            if !updateProvider.appStoreUpdates.isEmpty {
                appStoreUpdatesSection
            }
            
            Button(action: {
                showThirdPartyUpdateModal = true
            }) {
                Text("View and Install Updates")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 8)
        }
    }
    
    private var homebrewUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Homebrew Updates")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            ForEach(updateProvider.homebrewUpdates.prefix(2), id: \.self) { package in
                Text("\(package.name) (\(package.currentVersion) → \(package.newVersion))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if updateProvider.homebrewUpdates.count > 2 {
                Text("+ \(updateProvider.homebrewUpdates.count - 2) more...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var appStoreUpdatesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("App Store Updates")
                .font(.subheadline)
                .foregroundColor(.primary)
            
            ForEach(updateProvider.appStoreUpdates.prefix(2), id: \.self) { app in
                Text("\(app.name) (\(app.currentVersion) → \(app.newVersion))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if updateProvider.appStoreUpdates.count > 2 {
                Text("+ \(updateProvider.appStoreUpdates.count - 2) more...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var upToDateSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("All third-party software is up to date")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Update checks are managed centrally - removed redundant button
        }
    }

    private var osUpdateModal: some View {
        VStack(spacing: 24) {
            HStack {
                Image(systemName: "apple.logo")
                    .font(.title)
                    .foregroundColor(.orange)
                Text("macOS Updates")
                    .font(.title)
                    .bold()
                Spacer()
                Button(action: { showOSUpdateModal = false }) {
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
                        Task {
                            do {
                                try await updateProvider.initiateReboot()
                            } catch {
                                alertMessage = "Failed to restart: \(error.localizedDescription)"
                                showingAlert = true
                            }
                        }
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
                    ForEach(updateProvider.updates) { update in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(update.name)
                                        .font(.headline)
                                    Text(update.description)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                
                                if updatingPackages.contains(update.name) {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Installing...")
                                            .font(.caption)
                                            .foregroundColor(.blue)
                                        ProgressView(value: installationProgress[update.name] ?? 0.0)
                                            .frame(width: 100)
                                        if let timeRemaining = estimatedTimeRemaining[update.name], timeRemaining > 0 {
                                            Text("\(Int(timeRemaining / 60))m \(Int(timeRemaining.truncatingRemainder(dividingBy: 60)))s")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                } else if completedPackages.contains(update.name) {
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Completed")
                                            .font(.caption)
                                            .foregroundColor(.green)
                                    }
                                } else if !update.isInstalled {
                                    Button(action: {
                                        Task {
                                            do {
                                                try await installSystemUpdate(update.name)
                                            } catch {
                                                alertMessage = "Failed to install update: \(error.localizedDescription)"
                                                showingAlert = true
                                            }
                                        }
                                    }) {
                                        Text("Install")
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Color.blue)
                                            .cornerRadius(8)
                                    }
                                    .disabled(updatingPackages.count > 0)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            
                            HStack(spacing: 16) {
                                Label("\(update.size / 1_000_000_000, specifier: "%.1f") GB", systemImage: "arrow.down.circle")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                
                                Label("v\(update.version)", systemImage: "tag")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
            }
            
            // Install All Button
            if !updateProvider.updates.isEmpty && !updateProvider.updates.allSatisfy({ $0.isInstalled || completedPackages.contains($0.name) }) {
                Button(action: {
                    Task {
                        await installAllSystemUpdates()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Install All Updates (\(updateProvider.updates.filter { !$0.isInstalled && !completedPackages.contains($0.name) }.count))")
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

    private var restartNotificationBanner: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("System Restart Required")
                        .font(.headline)
                        .foregroundColor(.orange)
                    Text(updateProvider.rebootReason)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    Task {
                        do {
                            try await updateProvider.initiateReboot()
                        } catch {
                            alertMessage = "Failed to restart: \(error.localizedDescription)"
                            showingAlert = true
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Restart Now")
                    }
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.orange)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange, lineWidth: 1)
        )
    }

    private func installSystemUpdate(_ update: String) async throws {
        updatingPackages.insert(update)
        installationProgress[update] = 0.0
        estimatedTimeRemaining[update] = 300 // 5 minutes estimated
        do {
            print("Starting system update installation: \(update)")
            for progress in stride(from: 0.0, to: 1.0, by: 0.1) {
                installationProgress[update] = progress
                estimatedTimeRemaining[update] = 300 * (1 - progress)
                try await Task.sleep(nanoseconds: 500_000_000)
            }
            if let updateItem = updateProvider.updates.first(where: { $0.name == update }) {
                try await updateProvider.installUpdate(updateItem)
            } else {
                throw NSError(domain: "UpdateError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Update not found"])
            }
            installationProgress[update] = 1.0
            estimatedTimeRemaining[update] = 0
            updatingPackages.remove(update)
            completedPackages.insert(update)
            selectedUpdates.remove(update)
            alertMessage = "Successfully installed system update: \(update)"
            showingAlert = true
            print("Successfully installed system update: \(update)")
        } catch {
            updatingPackages.remove(update)
            installationProgress.removeValue(forKey: update)
            estimatedTimeRemaining.removeValue(forKey: update)
            throw error
        }
    }

    private func installAllSystemUpdates() async {
        let updatesToInstall = updateProvider.updates.filter { !$0.isInstalled && !completedPackages.contains($0.name) }
        
        for update in updatesToInstall {
            do {
                try await installSystemUpdate(update.name)
            } catch {
                alertMessage = "Failed to install \(update.name): \(error.localizedDescription)"
                showingAlert = true
                break
            }
        }
    }
} 