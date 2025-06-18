import Foundation
import AppKit

struct SecurityStatus {
    let isSecure: Bool
    let details: String?
    let recommendation: String?
}

@MainActor
class SecurityStatusProvider: ObservableObject {
    @Published var antivirusStatus: SecurityStatus = SecurityStatus(isSecure: false, details: nil, recommendation: nil)
    @Published var firewallStatus: SecurityStatus = SecurityStatus(isSecure: false, details: nil, recommendation: nil)
    @Published var diskEncryptionStatus: SecurityStatus = SecurityStatus(isSecure: false, details: nil, recommendation: nil)
    
    func checkSecurityStatus() async {
        // Check Antivirus
        await checkAntivirus()
        
        // Check Firewall
        await checkFirewall()
        
        // Check Disk Encryption
        await checkDiskEncryption()
    }
    
    private func checkAntivirus() async {
        // Check for common antivirus software
        let commonAV = ["com.symantec.norton", "com.mcafee", "com.avast", "com.bitdefender"]
        var foundAV = false
        var avName = ""
        
        for bundleId in commonAV {
            if let _ = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                foundAV = true
                avName = bundleId.components(separatedBy: ".").last?.capitalized ?? ""
                break
            }
        }
        
        if foundAV {
            antivirusStatus = SecurityStatus(
                isSecure: true,
                details: "\(avName) Antivirus is installed",
                recommendation: nil
            )
        } else {
            antivirusStatus = SecurityStatus(
                isSecure: false,
                details: "No antivirus software detected",
                recommendation: "Consider installing antivirus software for better protection"
            )
        }
    }
    
    private func checkFirewall() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/libexec/ApplicationFirewall/socketfilterfw")
        process.arguments = ["--getglobalstate"]
        
        do {
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let isEnabled = output.contains("enabled")
                firewallStatus = SecurityStatus(
                    isSecure: isEnabled,
                    details: isEnabled ? "Firewall is enabled" : "Firewall is disabled",
                    recommendation: isEnabled ? nil : "Enable the firewall in System Settings > Network > Firewall"
                )
            }
        } catch {
            firewallStatus = SecurityStatus(
                isSecure: false,
                details: "Unable to check firewall status",
                recommendation: "Check firewall settings manually in System Settings"
            )
        }
    }
    
    private func checkDiskEncryption() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/fdesetup")
        process.arguments = ["status"]
        
        do {
            let pipe = Pipe()
            process.standardOutput = pipe
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                let isEnabled = output.contains("FileVault is On")
                diskEncryptionStatus = SecurityStatus(
                    isSecure: isEnabled,
                    details: isEnabled ? "FileVault is enabled" : "FileVault is disabled",
                    recommendation: isEnabled ? nil : "Enable FileVault in System Settings > Privacy & Security > FileVault"
                )
            }
        } catch {
            diskEncryptionStatus = SecurityStatus(
                isSecure: false,
                details: "Unable to check FileVault status",
                recommendation: "Check FileVault settings manually in System Settings"
            )
        }
    }
} 