//
//  Huggin_MACOSApp.swift
//  Huggin-MACOS
//
//  Created by TJ Crowden on 6/9/25.
//

import SwiftUI

@main
struct Huggin_MACOSApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
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
}
