//
//  Huggin_MACOSApp.swift
//  Huggin-MACOS
//
//  Created by TJ Crowden on 6/9/25.
//

import SwiftUI

@main
struct Huggin_MACOSApp: App {
    @StateObject private var odinService = OdinDirectService.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(odinService)
                .onAppear {
                    // ODIN service is managed by OdinAgentServiceV3 in the settings view
                    // No need to auto-start OdinDirectService
                    // initializeOdinService()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
#if os(macOS)
        MenuBarExtra {
            Button("Show Huginn") {
                NSApp.activate(ignoringOtherApps: true)
            }
            Divider()
            Button("Quit") {
                NSApp.terminate(nil)
            }
        } label: {
            Image("icon_32x32")
        }
        .menuBarExtraStyle(.window)
#endif
    }
    
    private func initializeOdinService() {
        Task {
            let settings = OdinSettings()
            
            print("🔵 APP: Initializing ODIN service on startup...")
            print("🔵 APP: ODIN enabled: \(settings.isEnabled)")
            print("🔵 APP: Auto start: \(settings.autoStart)")
            print("🔵 APP: Valid config: \(settings.isValidConfiguration)")
            
            // Auto-start ODIN service if enabled and configured
            if settings.isEnabled && settings.autoStart && settings.isValidConfiguration {
                print("🔵 APP: Auto-starting ODIN service...")
                await MainActor.run {
                    odinService.configure(settings: settings)
                }
                await odinService.startService()
            } else {
                print("🔵 APP: ODIN service not auto-started (enabled: \(settings.isEnabled), autoStart: \(settings.autoStart), validConfig: \(settings.isValidConfiguration))")
            }
        }
    }
}
