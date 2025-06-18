import SwiftUI

struct HomebaseView: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    @StateObject private var updateProvider: SoftwareUpdateProvider
    @State private var showUpdateModal = false
    
    init(systemInfo: SystemInfoProvider) {
        _systemInfo = ObservedObject(wrappedValue: systemInfo)
        _updateProvider = StateObject(wrappedValue: SoftwareUpdateProvider())
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title and Update Status
                HStack {
                    Text("Homebase")
                        .font(.largeTitle)
                        .bold()
                        .foregroundColor(.black)
                    Spacer()
                    if updateProvider.hasUpdates {
                        Button(action: {
                            showUpdateModal = true
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Updates Available")
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                
                // Active Alerts Section
                if updateProvider.hasUpdates {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Active Alerts")
                            .font(.title2)
                            .bold()
                            .foregroundColor(.black)
                        
                        VStack(spacing: 12) {
                            if updateProvider.osUpdateAvailable {
                                AlertCard(
                                    title: "macOS Updates",
                                    message: "\(updateProvider.updates.count) system updates available",
                                    icon: "apple.logo",
                                    color: .orange
                                )
                            }
                            
                            if updateProvider.thirdPartyUpdatesAvailable {
                                if !updateProvider.homebrewUpdates.isEmpty {
                                    AlertCard(
                                        title: "Homebrew Updates",
                                        message: "\(updateProvider.homebrewUpdates.count) packages need updates",
                                        icon: "app.badge",
                                        color: .orange
                                    )
                                }
                                
                                if !updateProvider.appStoreUpdates.isEmpty {
                                    AlertCard(
                                        title: "App Store Updates",
                                        message: "\(updateProvider.appStoreUpdates.count) apps need updates",
                                        icon: "app.badge",
                                        color: .orange
                                    )
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                }
            }
            .padding()
        }
        .background(Color.clear)
        .task {
            _ = try? await updateProvider.checkForUpdates()
        }
        .sheet(isPresented: $showUpdateModal) {
            UpdateDetailModal(
                title: "System Updates",
                icon: "arrow.triangle.2.circlepath",
                updates: updateProvider.updates.map { $0.name },
                homebrewUpdates: updateProvider.homebrewUpdates,
                appStoreUpdates: updateProvider.appStoreUpdates,
                onClose: { showUpdateModal = false },
                updateProvider: updateProvider
            )
        }
    }
}

struct AlertCard: View {
    let title: String
    let message: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 2)
    }
} 