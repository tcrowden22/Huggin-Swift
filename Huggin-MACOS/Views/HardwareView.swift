import SwiftUI

struct HardwareView: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    @StateObject private var usbProvider = USBDevicesProvider()
    @StateObject private var monitorsProvider = MonitorsProvider()
    @StateObject private var storageProvider = StorageProvider()
    @StateObject private var processProvider = ProcessMemoryInfoProvider()
    @State private var showMemoryModal = false
    @State private var showUSBModal = false
    @State private var showMonitorsModal = false
    @State private var showStorageModal = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Title
                Text("Hardware")
                    .font(.largeTitle)
                    .bold()
                    .foregroundColor(.black)
                
                // Hardware Summary Cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    
                    // USB Devices Card
                    HardwareSummaryCard(
                        title: "USB Devices",
                        count: usbProvider.devices.count,
                        icon: "cable.connector",
                        color: .blue,
                        subtitle: usbProvider.devices.isEmpty ? "No devices" : "\(usbProvider.devices.count) connected"
                    ) {
                        showUSBModal = true
                    }
                    
                    // Displays Card
                    HardwareSummaryCard(
                        title: "Displays",
                        count: monitorsProvider.monitors.count,
                        icon: "display",
                        color: .green,
                        subtitle: monitorsProvider.monitors.isEmpty ? "No displays" : "\(monitorsProvider.monitors.count) detected"
                    ) {
                        showMonitorsModal = true
                    }
                    
                    // Storage Card
                    HardwareSummaryCard(
                        title: "Storage",
                        count: storageProvider.volumes.count,
                        icon: "internaldrive",
                        color: .orange,
                        subtitle: storageProvider.volumes.isEmpty ? "No volumes" : "\(storageProvider.volumes.count) volumes"
                    ) {
                        showStorageModal = true
                    }
                    
                    // Memory Processes Card
                    HardwareSummaryCard(
                        title: "Processes",
                        count: processProvider.processes.count,
                        icon: "memorychip",
                        color: .purple,
                        subtitle: processProvider.processes.isEmpty ? "No processes" : "\(processProvider.processes.count) running"
                    ) {
                        showMemoryModal = true
                    }
                }
                .padding()
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 600)
        .sheet(isPresented: $showUSBModal) {
            USBDetailModal(provider: usbProvider, isPresented: $showUSBModal)
        }
        .sheet(isPresented: $showMonitorsModal) {
            MonitorsDetailModal(provider: monitorsProvider, isPresented: $showMonitorsModal)
        }
        .sheet(isPresented: $showStorageModal) {
            StorageDetailModal(provider: storageProvider, isPresented: $showStorageModal)
        }
        .sheet(isPresented: $showMemoryModal) {
            MemoryDetailModal(systemInfo: systemInfo, isPresented: $showMemoryModal)
        }
    }
}

struct HardwareSummaryCard: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color
    let subtitle: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: icon)
                        .font(.title2)
                        .foregroundColor(color)
                    Spacer()
                    Text("\(count)")
                        .font(.title)
                        .bold()
                        .foregroundColor(.primary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(16)
            .frame(height: 120)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            // Add hover effect if needed
        }
    }
}

struct HardwareCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: icon)
                    .foregroundColor(color)
            }
            Text(value)
                .font(.title)
                .bold()
                .foregroundColor(color)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.black)
        }
        .padding()
        .frame(width: 240, height: 120)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
    }
}

struct MemoryDetailModal: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    @Binding var isPresented: Bool
    @StateObject private var processProvider = ProcessMemoryInfoProvider()
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Memory Details")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { isPresented = false }
            }
            Divider()
            Text("Total Memory: \(String(format: "%.1f GB", systemInfo.totalMemory))")
            Text("Used Memory: \(String(format: "%.1f GB", systemInfo.memoryUsage))")
            Text("\nTop Processes by Memory Usage:")
                .font(.headline)
            List(processProvider.processes.prefix(10)) { process in
                HStack {
                    Text(process.command)
                        .font(.subheadline)
                        .frame(maxWidth: 160, alignment: .leading)
                    Spacer()
                    Text("PID: \(process.pid)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                    Text("\(process.rss) KB")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
            .frame(height: 220)
            Spacer()
        }
        .padding(32)
        .frame(width: 500, height: 420)
    }
}

struct USBDetailModal: View {
    @ObservedObject var provider: USBDevicesProvider
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("USB Devices")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { isPresented = false }
            }
            Divider()
            
            if provider.devices.isEmpty {
                Text("No USB devices connected")
                    .foregroundColor(.secondary)
            } else {
                List(provider.devices) { device in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(device.name)
                            .font(.headline)
                        Text("Vendor: \(device.vendor)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Product: \(device.product)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Serial: \(device.serialNumber)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Spacer()
        }
        .padding(32)
        .frame(width: 500, height: 420)
    }
}

struct MonitorsDetailModal: View {
    @ObservedObject var provider: MonitorsProvider
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Monitors")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { isPresented = false }
            }
            Divider()
            if provider.monitors.isEmpty {
                Text("No monitors detected.")
            } else {
                List(provider.monitors) { monitor in
                    HStack {
                        Text(monitor.name)
                        Spacer()
                        Text(monitor.resolution)
                            .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 400, height: 300)
    }
}

struct StorageDetailModal: View {
    @ObservedObject var provider: StorageProvider
    @Binding var isPresented: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Storage Volumes")
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") { isPresented = false }
            }
            Divider()
            if provider.volumes.isEmpty {
                Text("No storage volumes found.")
            } else {
                List(provider.volumes) { volume in
                    VStack(alignment: .leading) {
                        Text(volume.name).bold()
                        HStack {
                            Text("Total: \(volume.total)")
                            Text("Used: \(volume.used)")
                            Text("Free: \(volume.free)")
                            Text("Type: \(volume.type)")
                        }
                        .font(.caption)
                        .foregroundColor(.gray)
                    }
                }
            }
            Spacer()
        }
        .padding(32)
        .frame(width: 500, height: 350)
    }
}

#Preview {
    HardwareView(systemInfo: SystemInfoProvider())
} 