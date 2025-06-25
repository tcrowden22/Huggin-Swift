import Foundation
import IOKit
import IOKit.usb
import IOKit.graphics

@MainActor
class USBDevicesProvider: ObservableObject, @unchecked Sendable {
    struct USBDevice: Identifiable, Hashable, Sendable {
        let id = UUID()
        let name: String
        let vendor: String
        let product: String
        let serialNumber: String
        let isConnected: Bool
        
        var description: String {
            "\(name) (\(vendor))"
        }
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
        
        static func == (lhs: USBDevice, rhs: USBDevice) -> Bool {
            lhs.id == rhs.id
        }
    }
    
    @Published var devices: [USBDevice] = []
    private nonisolated(unsafe) var timer: Timer?
    
    init() {
        // Start timer without immediate fetch to reduce startup load
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchDevices()
            }
        }
        
        // Trigger first fetch after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            self.fetchDevices()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func fetchDevices() {
        var devices: [USBDevice] = []
        
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName)
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if result == kIOReturnSuccess {
            var device = IOIteratorNext(iterator)
            while device != 0 {
                if let name = getDeviceProperty(device, kUSBProductString),
                   let vendor = getDeviceProperty(device, kUSBVendorString),
                   let product = getDeviceProperty(device, kUSBProductString),
                   let serial = getDeviceProperty(device, kUSBSerialNumberString) {
                    devices.append(USBDevice(
                        name: name,
                        vendor: vendor,
                        product: product,
                        serialNumber: serial,
                        isConnected: true
                    ))
                }
                IOObjectRelease(device)
                device = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        self.devices = devices
    }
    
    private func getDeviceProperty(_ device: io_object_t, _ key: String) -> String? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, 0)
        if result == kIOReturnSuccess,
           let properties = properties?.takeRetainedValue() as? [String: Any],
           let value = properties[key] as? String {
            return value
        }
        return nil
    }
}

@MainActor
class MonitorsProvider: ObservableObject, @unchecked Sendable {
    struct Monitor: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let resolution: String
        let refreshRate: Double
        let isBuiltIn: Bool
    }
    
    @Published var monitors: [Monitor] = []
    private nonisolated(unsafe) var timer: Timer?
    
    init() {
        // Start timer without immediate fetch to reduce startup load
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchMonitors()
            }
        }
        
        // Trigger first fetch after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000) // 0.7 seconds
            self.fetchMonitors()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func fetchMonitors() {
        var monitors: [Monitor] = []
        
        let matchingDict = IOServiceMatching("IODisplayConnect")
        var iterator: io_iterator_t = 0
        
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        if result == kIOReturnSuccess {
            var device = IOIteratorNext(iterator)
            while device != 0 {
                if let name = getDeviceProperty(device, "DisplayProductName"),
                   let resolution = getDeviceProperty(device, "DisplayResolution"),
                   let refreshRate = getDeviceProperty(device, "DisplayRefreshRate"),
                   let isBuiltIn = getDeviceProperty(device, "DisplayIsBuiltIn") {
                    monitors.append(Monitor(
                        name: name,
                        resolution: resolution,
                        refreshRate: Double(refreshRate) ?? 0.0,
                        isBuiltIn: isBuiltIn == "1"
                    ))
                }
                IOObjectRelease(device)
                device = IOIteratorNext(iterator)
            }
            IOObjectRelease(iterator)
        }
        
        self.monitors = monitors
    }
    
    private func getDeviceProperty(_ device: io_object_t, _ key: String) -> String? {
        var properties: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(device, &properties, kCFAllocatorDefault, 0)
        if result == kIOReturnSuccess,
           let properties = properties?.takeRetainedValue() as? [String: Any],
           let value = properties[key] as? String {
            return value
        }
        return nil
    }
}

@MainActor
class StorageProvider: ObservableObject, @unchecked Sendable {
    struct Volume: Identifiable, Sendable {
        let id = UUID()
        let name: String
        let total: String
        let free: String
        let used: String
        let type: String
    }
    
    @Published var volumes: [Volume] = []
    private nonisolated(unsafe) var timer: Timer?
    
    init() {
        // Start timer without immediate fetch to reduce startup load
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchVolumes()
            }
        }
        
        // Trigger first fetch after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1.0 seconds
            self.fetchVolumes()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func fetchVolumes() {
        var result: [Volume] = []
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        
        for url in fm.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? [] {
            let name = (try? url.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? url.lastPathComponent
            let total = (try? url.resourceValues(forKeys: [.volumeTotalCapacityKey]).volumeTotalCapacity).map { "\($0 / 1024 / 1024 / 1024) GB" } ?? "-"
            let free = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map { "\($0 / 1024 / 1024 / 1024) GB" } ?? "-"
            let used = (try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]))
                .flatMap { vals in
                    if let total = vals.volumeTotalCapacity, let free = vals.volumeAvailableCapacity {
                        return "\((total - free) / 1024 / 1024 / 1024) GB"
                    }
                    return nil
                } ?? "-"
            let isInternal = (try? url.resourceValues(forKeys: [.volumeIsInternalKey]).volumeIsInternal) ?? false
            let isRemovable = (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]).volumeIsRemovable) ?? false
            let isEjectable = (try? url.resourceValues(forKeys: [.volumeIsEjectableKey]).volumeIsEjectable) ?? false
            let type = isInternal ? "Internal" : isRemovable ? "Removable" : isEjectable ? "Ejectable" : "-"
            result.append(Volume(name: name, total: total, free: free, used: used, type: type))
        }
        
        self.volumes = result
    }
}

@MainActor
class ProcessMemoryInfoProvider: ObservableObject, @unchecked Sendable {
    struct ProcessInfo: Identifiable, Sendable {
        let id = UUID()
        let pid: String
        let command: String
        let rss: String // in KB
    }
    
    @Published var processes: [ProcessInfo] = []
    private nonisolated(unsafe) var timer: Timer?
    
    init() {
        // Start timer without immediate fetch to reduce startup load
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.fetchProcesses()
            }
        }
        
        // Trigger first fetch after a delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000) // 1.2 seconds
            self.fetchProcesses()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
    
    private func fetchProcesses() {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-axo", "pid,comm,rss"]
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
        } catch {
            return
        }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return }
        
        let lines = output.split(separator: "\n").dropFirst()
        let newProcesses = lines.compactMap { line -> ProcessInfo? in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3 else { return nil }
            let pid = String(parts[0])
            let command = String(parts[1])
            let rss = String(parts[2])
            return ProcessInfo(pid: pid, command: command, rss: rss)
        }
        
        self.processes = newProcesses
    }
}

@MainActor
class HardwareProviders: ObservableObject {
    @Published var usbDevicesProvider = USBDevicesProvider()
    @Published var monitorsProvider = MonitorsProvider()
    @Published var storageProvider = StorageProvider()
    @Published var processMemoryInfoProvider = ProcessMemoryInfoProvider()
    
    func loadHardwareData() async {
        // The individual providers handle their own loading via timers
        // This method can be used for manual refresh if needed
        await withTaskGroup(of: Void.self) { group in
            // The providers are already running their own timers
            // This is just a placeholder for any additional initialization
        }
    }
} 
