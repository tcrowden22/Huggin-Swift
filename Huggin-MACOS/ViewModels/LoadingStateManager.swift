import Foundation

@MainActor
class LoadingStateManager: ObservableObject {
    @Published var isLoading: Bool = true
    @Published var loadingProgress: Double = 0.0
    @Published var loadingMessage: String = "Initializing..."
    
    private let systemHealthProvider: SystemHealthProvider
    private let updateManager: UpdateManagerService
    private let systemInfo: SystemInfoProvider
    
    init(systemHealthProvider: SystemHealthProvider, updateManager: UpdateManagerService, systemInfo: SystemInfoProvider) {
        self.systemHealthProvider = systemHealthProvider
        self.updateManager = updateManager
        self.systemInfo = systemInfo
    }
    
    func startLoading() async {
        await MainActor.run {
            isLoading = true
            loadingProgress = 0.0
            loadingMessage = "Initializing..."
        }
        
        // Start all initialization tasks in background without waiting
        Task {
            await self.initializeSystemHealth()
        }
        Task {
            await self.checkForUpdates()
        }
        Task {
            await self.initializeMetrics()
        }
        
        // Quick UI update and stop loading immediately
        await MainActor.run {
            self.loadingProgress = 1.0
            self.loadingMessage = "Ready"
            self.isLoading = false
        }
    }
    
    func stopLoading() {
        isLoading = false
        loadingProgress = 1.0
        loadingMessage = "Ready"
    }
    
    private func initializeSystemHealth() async {
        loadingMessage = "Checking system health..."
        loadingProgress = 0.3
        // System health initialization is handled by SystemHealthProvider
    }
    
    private func checkForUpdates() async {
        loadingMessage = "Checking for updates..."
        loadingProgress = 0.6
        // Only check for updates during startup - subsequent checks will be handled by background timers
        await updateManager.checkForUpdates()
        print("✅ Initial update check completed during startup")
    }
    
    private func initializeMetrics() async {
        loadingMessage = "Initializing system metrics..."
        loadingProgress = 0.9
        // Metrics initialization is handled by SystemInfoProvider
    }
} 