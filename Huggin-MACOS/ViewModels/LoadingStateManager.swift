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
        isLoading = true
        loadingProgress = 0.0
        loadingMessage = "Initializing..."
        
        // Start all initialization tasks
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.initializeSystemHealth()
            }
            group.addTask {
                await self.checkForUpdates()
            }
            group.addTask {
                await self.initializeMetrics()
            }
            
            // Wait for all tasks to complete
            await group.waitForAll()
        }
        
        // Finalize loading
        loadingProgress = 1.0
        loadingMessage = "Ready"
        isLoading = false
    }
    
    private func initializeSystemHealth() async {
        loadingMessage = "Checking system health..."
        loadingProgress = 0.3
        // System health initialization is handled by SystemHealthProvider
    }
    
    private func checkForUpdates() async {
        loadingMessage = "Checking for updates..."
        loadingProgress = 0.6
        await updateManager.checkForUpdates()
    }
    
    private func initializeMetrics() async {
        loadingMessage = "Initializing system metrics..."
        loadingProgress = 0.9
        // Metrics initialization is handled by SystemInfoProvider
    }
} 