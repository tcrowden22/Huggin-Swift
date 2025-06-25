import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case dashboard
    case hardware
    case software
    case system
    case scripts
    case odin
    case support
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .hardware: return "Hardware"
        case .software: return "Software"
        case .system: return "System Health"
        case .scripts: return "Scripts"
        case .odin: return "ODIN Agent"
        case .support: return "Support"
        }
    }
    
    var icon: String {
        switch self {
        case .dashboard: return "gauge"
        case .hardware: return "desktopcomputer"
        case .software: return "app.badge"
        case .system: return "chart.line.uptrend.xyaxis"
        case .scripts: return "doc.text"
        case .odin: return "network"
        case .support: return "bubble.left.and.bubble.right"
        }
    }
}

struct ContentView: View {
    @State private var selectedTab: SidebarItem = .dashboard
    @StateObject private var systemInfo = SystemInfoProvider()
    @StateObject private var userInfoProvider = UserInfoProvider()
    @StateObject private var supportViewModel = SupportViewModel()
    @StateObject private var globalScriptStore = GlobalScriptStore.shared
    @State private var showSettings = false
    
    var body: some View {
        NavigationSplitView {
            ZStack {
                // Gradient background: black at top, purple at bottom
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.black,
                        Color.purple.opacity(0.8)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Huginn Title
                    HStack(spacing: 10) {
                        Image("icon_128x128")
                            .resizable()
                            .frame(width: 36, height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        Text("Huginn")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                    
                    // Navigation List
                    VStack(spacing: 4) {
                        ForEach(SidebarItem.allCases) { item in
                            Button(action: {
                                selectedTab = item
                            }) {
                                                            HStack(spacing: 12) {
                                ZStack {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 16))
                                        .foregroundColor(selectedTab == item ? .white : .gray)
                                        .frame(width: 24)
                                    
                                    // Show badge for Scripts tab when new scripts are available
                                    if item == .scripts && globalScriptStore.hasPendingScripts {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 8, height: 8)
                                            .offset(x: 8, y: -8)
                                    }
                                }
                                
                                Text(item.title)
                                    .font(.system(size: 14))
                                    .foregroundColor(selectedTab == item ? .white : .gray)
                                Spacer()
                            }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(selectedTab == item ? Color.blue.opacity(0.25) : Color.clear)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    
                    Spacer()
                    
                    Divider()
                        .background(Color.white.opacity(0.1))
                        .padding(.vertical, 8)
                    
                    // User Info
                    Button(action: { showSettings = true }) {
                        HStack(alignment: .center, spacing: 10) {
                            Image(systemName: "person.crop.circle")
                                .resizable()
                                .frame(width: 32, height: 32)
                                .foregroundColor(.gray)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(userInfoProvider.userInfo.fullName)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 8, height: 8)
                                }
                                Text(userInfoProvider.userInfo.role)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                            }
                        }
                        .padding([.leading, .bottom], 16)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .sheet(isPresented: $showSettings) {
                        SettingsView(userInfo: userInfoProvider.userInfo)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(minWidth: 240)
        } detail: {
            ZStack {
                Color.black.ignoresSafeArea()
                switch selectedTab {
                case .dashboard:
                    DashboardView(onNavigateToSupport: {
                        selectedTab = .support
                    })
                case .hardware:
                    HardwareView(systemInfo: systemInfo)
                case .software:
                    SoftwareView()
                case .system:
                    SystemHealthView(systemInfo: systemInfo)
                case .scripts:
                    ScriptManagerView()
                case .odin:
                    OdinSettingsViewV3()
                case .support:
                    SupportView(viewModel: supportViewModel)
                }
            }
        }
    }
} 