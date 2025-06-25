import Foundation
import SwiftUI

// MARK: - Script Manager ViewModel

@MainActor
public class ScriptManagerViewModel: ObservableObject {
    public static let shared = ScriptManagerViewModel()
    
    @Published public var systemScripts: [ScriptItem] = []
    @Published public var userScripts: [ScriptItem] = []
    @Published public var selectedScript: ScriptItem?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    
    // Legacy support - computed property that combines both
    public var scripts: [ScriptItem] {
        return systemScripts + userScripts
    }
    
    // Running processes tracking
    private var runningProcesses: [UUID: Process] = [:]
    
    public init() {
        print("ScriptManagerViewModel initializing...")
        
        // Load system scripts first
        loadSystemScripts()
        
        // Then load user scripts from disk
        loadUserScripts()
        
        setupNotifications()
        checkForPendingScripts()
        print("ScriptManagerViewModel initialization complete. System: \(systemScripts.count), User: \(userScripts.count)")
    }
    
    // MARK: - Public Methods
    
    public func loadUserScripts() {
        isLoading = true
        
        Task {
            do {
                let scriptsDirectory = try getScriptsDirectory()
                let scriptFiles = try FileManager.default.contentsOfDirectory(at: scriptsDirectory, includingPropertiesForKeys: nil)
                
                var loadedScripts: [ScriptItem] = []
                
                for scriptFile in scriptFiles where scriptFile.pathExtension == "sh" {
                    let content = try String(contentsOf: scriptFile)
                    let attributes = try FileManager.default.attributesOfItem(atPath: scriptFile.path)
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    
                    let script = ScriptItem(
                        name: scriptFile.deletingPathExtension().lastPathComponent,
                        content: content,
                        lastModified: modificationDate
                    )
                    loadedScripts.append(script)
                }
                
                await MainActor.run {
                    // Only append loaded scripts to user scripts
                    self.userScripts.append(contentsOf: loadedScripts)
                    self.userScripts = self.userScripts.sorted { $0.lastModified > $1.lastModified }
                    self.isLoading = false
                    print("Loaded \(loadedScripts.count) user scripts from storage, total user scripts: \(self.userScripts.count)")
                }
                
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = "Failed to load user scripts: \(error.localizedDescription)"
                    print("Failed to load user scripts: \(error.localizedDescription)")
                }
            }
        }
    }
    
    public func createScript(name: String, content: String, description: String = "") {
        let newScript = ScriptItem(
            name: name,
            content: content,
            description: description,
            lastModified: Date()
        )
        
        userScripts.append(newScript)
        selectedScript = newScript
        
        // Save to disk
        Task {
            await saveScriptToDisk(newScript)
        }
        
        print("Created new user script: \(name)")
    }
    
    public func updateScript(_ script: ScriptItem, name: String, content: String, description: String = "") {
        // Check if it's a system script or user script
        if systemScripts.contains(where: { $0.id == script.id }) {
            // Don't allow editing system scripts directly, create a copy as user script
            let newUserScript = ScriptItem(
                name: name,
                content: content,
                description: description,
                lastModified: Date()
            )
            userScripts.append(newUserScript)
            selectedScript = newUserScript
            
            // Save to disk
            Task {
                await saveScriptToDisk(newUserScript)
            }
            print("Created user copy of system script: \(name)")
            
        } else if let index = userScripts.firstIndex(where: { $0.id == script.id }) {
            let oldName = userScripts[index].name
            userScripts[index].name = name
            userScripts[index].content = content
            userScripts[index].description = description
            userScripts[index].lastModified = Date()
            
            if selectedScript?.id == script.id {
                selectedScript = userScripts[index]
            }
            
            // Update on disk
            Task {
                await updateScriptOnDisk(userScripts[index], oldName: oldName)
            }
            
            print("Updated user script: \(name)")
        }
    }
    
    public func deleteScript(_ script: ScriptItem) {
        // Only allow deleting user scripts, not system scripts
        if systemScripts.contains(where: { $0.id == script.id }) {
            print("Cannot delete system script: \(script.name)")
            return
        }
        
        userScripts.removeAll { $0.id == script.id }
        
        if selectedScript?.id == script.id {
            selectedScript = scripts.first
        }
        
        // Delete from disk
        Task {
            await deleteScriptFromDisk(script)
        }
        
        print("Deleted user script: \(script.name)")
    }
    
    public func runScript(_ script: ScriptItem) {
        guard let scriptInfo = findScript(with: script.id) else { return }
        guard !scriptInfo.script.isRunning else { return }
        
        // Automatically select this script to show output preview
        selectedScript = script
        
        // TODO: Integrate with Ollama-based script execution backend
        // - Send script to Ollama for analysis and enhancement
        // - Get AI-generated safety recommendations
        // - Allow user to review before execution
        // - Log execution request to audit trail
        
        updateScriptInArray(script) { scriptRef in
            scriptRef.isRunning = true
            scriptRef.output = "🚀 Starting script execution...\n\n"
            scriptRef.lastRun = Date()
            scriptRef.exitCode = nil
        }
        
        // Real process execution
        executeScriptProcess(script)
        
        print("Started running script: \(script.name) - Output will be shown in detail view")
    }
    
    public func stopScript(_ script: ScriptItem) {
        guard let scriptInfo = findScript(with: script.id) else { return }
        guard scriptInfo.script.isRunning else { return }
        
        // TODO: Integrate with process management
        // - Send SIGTERM first, then SIGKILL if needed
        // - Clean up temporary files
        // - Log termination to audit trail
        
        // Stop the running process
        if let process = runningProcesses[script.id] {
            process.terminate()
            runningProcesses.removeValue(forKey: script.id)
        }
        
        updateScriptInArray(script) { scriptRef in
            scriptRef.isRunning = false
            scriptRef.exitCode = -1 // Terminated
            scriptRef.output += "\n\n--- Script terminated by user ---"
        }
        
        print("Stopped script: \(script.name)")
    }
    
    public func refreshScripts() {
        print("Refreshing scripts...")
        // Force a UI update by triggering the @Published property
        objectWillChange.send()
        print("Scripts refreshed. System: \(systemScripts.count), User: \(userScripts.count)")
        
        // If we have no scripts at all, reload system scripts
        if systemScripts.isEmpty {
            print("No system scripts found, reloading...")
            loadSystemScripts()
        }
    }
    
    // MARK: - Private Methods
    
    private func findScript(with id: UUID) -> (script: ScriptItem, isSystem: Bool, index: Int)? {
        if let index = systemScripts.firstIndex(where: { $0.id == id }) {
            return (systemScripts[index], true, index)
        } else if let index = userScripts.firstIndex(where: { $0.id == id }) {
            return (userScripts[index], false, index)
        }
        return nil
    }
    
    private func updateScriptInArray(_ script: ScriptItem, update: (inout ScriptItem) -> Void) {
        if let systemIndex = systemScripts.firstIndex(where: { $0.id == script.id }) {
            update(&systemScripts[systemIndex])
            if selectedScript?.id == script.id {
                selectedScript = systemScripts[systemIndex]
            }
        } else if let userIndex = userScripts.firstIndex(where: { $0.id == script.id }) {
            update(&userScripts[userIndex])
            if selectedScript?.id == script.id {
                selectedScript = userScripts[userIndex]
            }
        }
    }
    
    private func executeScriptProcess(_ script: ScriptItem) {
        Task {
            do {
                // Create temporary script file with enhanced content
                let enhancedContent = enhanceScriptForExecution(script.content)
                let tempURL = try createTempScriptFile(content: enhancedContent)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                
                // Configure process
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/bash")
                process.arguments = [tempURL.path]
                
                // Setup enhanced environment for the process
                process.environment = createEnhancedEnvironment()
                
                // Setup pipes for output capture
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                // Store process for potential termination
                await MainActor.run {
                    self.runningProcesses[script.id] = process
                }
                
                // Start capturing output asynchronously
                startOutputCapture(for: script, outputPipe: outputPipe, errorPipe: errorPipe)
                
                // Start the process
                try process.run()
                
                // Wait for completion
                process.waitUntilExit()
                
                // Update final state
                await MainActor.run {
                    self.updateScriptInArray(script) { scriptRef in
                        scriptRef.isRunning = false
                        scriptRef.exitCode = process.terminationStatus
                        
                        // Enhanced error detection in output
                        let output = scriptRef.output.lowercased()
                        let hasErrorInOutput = output.contains("error:") ||
                                             output.contains("stderr:") ||
                                             output.contains("failed") ||
                                             output.contains("not found") ||
                                             output.contains("no such file") ||
                                             output.contains("permission denied") ||
                                             output.contains("command not found") ||
                                             output.contains("installation failed") ||
                                             output.contains("unable to") ||
                                             output.contains("cannot") ||
                                             output.contains("does not exist") ||
                                             output.contains("is not there")
                        
                        let statusMessage: String
                        if process.terminationStatus == 0 && !hasErrorInOutput {
                            statusMessage = "\n\n✅ Script completed successfully"
                        } else if process.terminationStatus == 0 && hasErrorInOutput {
                            statusMessage = "\n\n⚠️ Script completed with errors/warnings (exit code: 0, but errors detected in output)"
                            // Override exit code to indicate issues
                            scriptRef.exitCode = 1
                        } else {
                            statusMessage = "\n\n❌ Script failed with exit code \(process.terminationStatus)"
                        }
                        
                        scriptRef.output += statusMessage
                    }
                    
                    self.runningProcesses.removeValue(forKey: script.id)
                }
                
            } catch {
                await MainActor.run {
                    self.updateScriptInArray(script) { scriptRef in
                        scriptRef.isRunning = false
                        scriptRef.exitCode = -1
                        scriptRef.output += "\n\nError executing script: \(error.localizedDescription)"
                    }
                    
                    self.runningProcesses.removeValue(forKey: script.id)
                    self.errorMessage = "Failed to execute script: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func createTempScriptFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("huginn_script_\(UUID().uuidString).sh")
        
        try content.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make script executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        return scriptURL
    }
    
    private func enhanceScriptForExecution(_ originalContent: String) -> String {
        // Add PATH and environment setup to the script
        let pathSetup = """
        #!/bin/bash
        set -e
        
        # Enhanced PATH setup for macOS app execution - ensure Homebrew is found
        export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
        
        # Set up environment variables
        export HOMEBREW_NO_AUTO_UPDATE=1
        export HOMEBREW_NO_INSTALL_CLEANUP=1
        
        # Function to check if command exists
        command_exists() {
            command -v "$1" >/dev/null 2>&1
        }
        
        # Ensure Homebrew is accessible - override any script checks
        if ! command_exists brew; then
            if [ -f "/opt/homebrew/bin/brew" ]; then
                export PATH="/opt/homebrew/bin:$PATH"
                echo "✅ Found Homebrew at /opt/homebrew/bin/brew"
            elif [ -f "/usr/local/bin/brew" ]; then
                export PATH="/usr/local/bin:$PATH"
                echo "✅ Found Homebrew at /usr/local/bin/brew"
            else
                echo "❌ Homebrew not found in common locations"
                echo "Please install Homebrew first:"
                echo "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                exit 127
            fi
        else
            echo "✅ Homebrew is available at: $(which brew)"
        fi
        
        # Debug information
        echo "=== Huginn Script Execution Environment ==="
        echo "PATH: $PATH"
        echo "User: $(whoami)"
        echo "Working Directory: $(pwd)"
        echo "Available commands:"
        echo "  brew: $(which brew 2>/dev/null || echo 'NOT FOUND')"
        echo "  softwareupdate: $(which softwareupdate 2>/dev/null || echo 'NOT FOUND')"
        echo "=========================================="
        echo ""
        
        """
        
        // Remove existing shebang if present and add our enhanced version
        let cleanedContent = originalContent.replacingOccurrences(of: "#!/bin/bash", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return pathSetup + cleanedContent
    }
    
    private func createEnhancedEnvironment() -> [String: String] {
        var env = Foundation.ProcessInfo.processInfo.environment
        
        // Enhance PATH with common tool locations
        let commonPaths = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin", 
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        
        let enhancedPath = commonPaths.joined(separator: ":") + ":" + (env["PATH"] ?? "")
        env["PATH"] = enhancedPath
        
        // Set homebrew environment variables
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        
        // Set user home directory explicitly
        if let homeDir = FileManager.default.homeDirectoryForCurrentUser.path as String? {
            env["HOME"] = homeDir
        }
        
        return env
    }
    
    private func startOutputCapture(for script: ScriptItem, outputPipe: Pipe, errorPipe: Pipe) {
        // Capture stdout
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.updateScriptInArray(script) { scriptRef in
                        scriptRef.output += output
                    }
                }
            }
        }
        
        // Capture stderr
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let output = String(data: data, encoding: .utf8) {
                Task { @MainActor in
                    self.updateScriptInArray(script) { scriptRef in
                        scriptRef.output += "STDERR: " + output
                    }
                }
            }
        }
    }
    
    private func loadSystemScripts() {
        print("Loading system scripts...")
        
        let systemScriptsList = [
            // Network & Connectivity
            ScriptItem(
                name: "🌐 Fix Network Issues",
                content: """
#!/bin/bash
set -e

echo "=== Network Diagnostics & Fixes ==="
echo "This script will diagnose and attempt to fix common network issues"
echo ""

# Flush DNS cache
echo "1. Flushing DNS cache..."
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
echo "✅ DNS cache flushed"
echo ""

# Reset network settings
echo "2. Resetting network interfaces..."
sudo ifconfig en0 down
sudo ifconfig en0 up
echo "✅ Network interface reset"
echo ""

# Test connectivity
echo "3. Testing connectivity..."
if ping -c 3 8.8.8.8 >/dev/null 2>&1; then
    echo "✅ Internet connection: Working"
else
    echo "❌ Internet connection: Failed"
    echo "Try restarting your router or contact your ISP"
fi

if ping -c 3 google.com >/dev/null 2>&1; then
    echo "✅ DNS resolution: Working"
else
    echo "❌ DNS resolution: Failed"
    echo "Consider changing DNS servers to 8.8.8.8 and 8.8.4.4"
fi

echo ""
echo "=== Network fix completed ==="
""",
                description: "Diagnoses and fixes common network connectivity issues. Flushes DNS cache, resets network interfaces, and tests internet connectivity. Perfect for when websites won't load or network seems slow."
            ),
            
            ScriptItem(
                name: "🔧 System Cleanup",
                content: """
#!/bin/bash
set -e

echo "=== System Cleanup Tool ==="
echo "This will safely clean up temporary files and caches"
echo ""

# Calculate initial disk usage
initial_usage=$(df -h / | awk 'NR==2 {print $5}')
echo "Initial disk usage: $initial_usage"
echo ""

# Clean user caches
echo "1. Cleaning user caches..."
rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache 2>/dev/null || true
rm -rf ~/Library/Caches/com.google.Chrome/Default/Cache 2>/dev/null || true
rm -rf ~/Library/Caches/com.microsoft.VSCode 2>/dev/null || true
echo "✅ User caches cleaned"

# Clean Downloads folder (files older than 30 days)
echo "2. Cleaning old downloads..."
find ~/Downloads -type f -mtime +30 -delete 2>/dev/null || true
echo "✅ Old downloads cleaned"

# Empty Trash
echo "3. Emptying Trash..."
osascript -e 'tell application "Finder" to empty trash' 2>/dev/null || true
echo "✅ Trash emptied"

# Clean Homebrew if available
if command -v brew >/dev/null 2>&1; then
    echo "4. Cleaning Homebrew..."
    brew cleanup --prune=all 2>/dev/null || true
    echo "✅ Homebrew cleaned"
fi

# Show final disk usage
final_usage=$(df -h / | awk 'NR==2 {print $5}')
echo ""
echo "Final disk usage: $final_usage"
echo "=== Cleanup completed ==="
""",
                description: "Frees up disk space by safely cleaning temporary files, browser caches, old downloads (30+ days), and emptying the Trash. Also cleans Homebrew cache if installed. Shows before/after disk usage."
            ),
            
            ScriptItem(
                name: "🔄 Update Everything",
                content: """
#!/bin/bash
set -e

echo "=== System Update Tool ==="
echo "This will update macOS, Homebrew, and App Store apps"
echo ""

# Update Homebrew packages
if command -v brew >/dev/null 2>&1; then
    echo "1. Updating Homebrew packages..."
    brew update
    brew upgrade
    brew cleanup
    echo "✅ Homebrew updated"
else
    echo "ℹ️  Homebrew not installed"
fi

# Update Mac App Store apps
if command -v mas >/dev/null 2>&1; then
    echo "2. Updating Mac App Store apps..."
    mas upgrade
    echo "✅ App Store apps updated"
else
    echo "ℹ️  mas not installed (install with: brew install mas)"
fi

# Check for system updates
echo "3. Checking for macOS updates..."
softwareupdate --list
echo ""
echo "To install system updates, run: sudo softwareupdate -i -a"
echo ""

echo "=== Update check completed ==="
""",
                description: "Keeps your Mac up-to-date by updating Homebrew packages, Mac App Store apps, and checking for macOS system updates. One-click solution to update everything on your system."
            ),
            
            ScriptItem(
                name: "🖥️ System Information",
                content: """
#!/bin/bash

echo "=== Complete System Information ==="
echo ""

echo "📋 Basic System Info:"
echo "Hostname: $(hostname)"
echo "User: $(whoami)"
echo "macOS Version: $(sw_vers -productVersion)"
echo "Build: $(sw_vers -buildVersion)"
echo "Uptime: $(uptime | awk '{print $3, $4}' | sed 's/,//')"
echo ""

echo "💾 Memory Information:"
vm_stat | head -6
echo ""

echo "💽 Disk Usage:"
df -h / | awk 'NR==2 {printf "Used: %s / %s (%s full)\\n", $3, $2, $5}'
echo ""

echo "🔌 Hardware Info:"
system_profiler SPHardwareDataType | grep -E "(Model Name|Model Identifier|Processor|Memory|Serial Number)"
echo ""

echo "🌐 Network Info:"
ifconfig en0 | grep "inet " | awk '{print "IP Address: " $2}'
echo "External IP: $(curl -s ifconfig.me 2>/dev/null || echo 'Unable to determine')"
echo ""

echo "🔋 Battery Info:"
pmset -g batt | head -2
echo ""

echo "🏃 Top Processes by CPU:"
ps aux | sort -rk 3,3 | head -6 | awk '{printf "%-15s %s%%\\n", $11, $3}'
echo ""

echo "=== System information complete ==="
""",
                description: "Provides comprehensive system information including macOS version, hardware specs, memory usage, disk space, network details, battery status, and top CPU processes. Perfect for troubleshooting or system audits."
            ),
            
            ScriptItem(
                name: "🔐 Security Check",
                content: """
#!/bin/bash

echo "=== Security Status Check ==="
echo ""

echo "🔥 Firewall Status:"
if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate | grep -q "enabled"; then
    echo "✅ Firewall is enabled"
else
    echo "⚠️  Firewall is disabled - Enable in System Preferences > Security & Privacy"
fi
echo ""

echo "🛡️ Gatekeeper Status:"
if spctl --status | grep -q "enabled"; then
    echo "✅ Gatekeeper is enabled"
else
    echo "⚠️  Gatekeeper is disabled"
fi
echo ""

echo "🔒 FileVault Status:"
if fdesetup status | grep -q "On"; then
    echo "✅ FileVault is enabled"
else
    echo "⚠️  FileVault is disabled - Enable in System Preferences > Security & Privacy"
fi
echo ""

echo "🔄 Automatic Updates:"
if softwareupdate --schedule | grep -q "Automatic check is on"; then
    echo "✅ Automatic updates are enabled"
else
    echo "⚠️  Automatic updates are disabled"
fi
echo ""

echo "🔍 Recent Security Events:"
log show --predicate 'subsystem == "com.apple.securityd"' --last 1h | tail -5 2>/dev/null || echo "No recent security events"
echo ""

echo "=== Security check completed ==="
""",
                description: "Audits your Mac's security settings including firewall status, Gatekeeper protection, FileVault encryption, automatic updates, and recent security events. Helps ensure your system is properly secured."
            ),
            
            ScriptItem(
                name: "🖨️ Printer Troubleshoot",
                content: """
#!/bin/bash

echo "=== Printer Troubleshooting Tool ==="
echo ""

echo "📋 Current Printers:"
lpstat -p
echo ""

echo "🔍 Print Queue Status:"
lpstat -o
echo ""

echo "🧹 Clearing print queues..."
cancel -a
echo "✅ Print queues cleared"
echo ""

echo "🔄 Restarting print system..."
sudo launchctl stop org.cups.cupsd
sudo launchctl start org.cups.cupsd
echo "✅ Print system restarted"
echo ""

echo "🌐 Testing CUPS web interface..."
if curl -s http://localhost:631 >/dev/null; then
    echo "✅ CUPS is running - Access at http://localhost:631"
else
    echo "❌ CUPS is not responding"
fi
echo ""

echo "💡 Common Solutions:"
echo "1. Check printer power and connections"
echo "2. Remove and re-add the printer in System Preferences"
echo "3. Update printer drivers from manufacturer's website"
echo "4. Reset printing system: System Preferences > Printers > Right-click > Reset"
echo ""

echo "=== Printer troubleshooting completed ==="
""",
                description: "Fixes common printing problems by clearing print queues, restarting the print system, and testing CUPS. Includes step-by-step troubleshooting guide for when documents won't print or printers appear offline."
            ),
            
            ScriptItem(
                name: "🔊 Audio Fix",
                content: """
#!/bin/bash

echo "=== Audio Troubleshooting Tool ==="
echo ""

echo "🔊 Current Audio Devices:"
system_profiler SPAudioDataType | grep -A 2 "Audio Devices:"
echo ""

echo "🔄 Restarting Core Audio..."
sudo launchctl stop com.apple.audio.coreaudiod
sudo launchctl start com.apple.audio.coreaudiod
echo "✅ Core Audio restarted"
echo ""

echo "🎚️ Checking audio levels..."
osascript -e "get volume settings"
echo ""

echo "🔍 Testing audio output..."
say "Audio test - if you can hear this, your speakers are working"
echo "✅ Audio test completed"
echo ""

echo "💡 If audio still not working:"
echo "1. Check System Preferences > Sound > Output"
echo "2. Try different audio output device"
echo "3. Check cable connections"
echo "4. Restart your Mac"
echo ""

echo "=== Audio troubleshooting completed ==="
""",
                description: "Resolves audio issues by restarting Core Audio services, checking audio devices and levels, and performing a speaker test. Includes troubleshooting steps for when sound isn't working properly."
            ),
            
            ScriptItem(
                name: "📱 iOS Device Sync Fix",
                content: """
#!/bin/bash

echo "=== iOS Device Sync Troubleshooting ==="
echo ""

echo "🔄 Restarting device sync services..."
sudo launchctl stop com.apple.mobiledeviced
sudo launchctl start com.apple.mobiledeviced
echo "✅ Mobile device daemon restarted"
echo ""

echo "🧹 Clearing device sync cache..."
rm -rf ~/Library/Caches/com.apple.itunes.sync/ 2>/dev/null || true
rm -rf ~/Library/Caches/com.apple.MobileSync/ 2>/dev/null || true
echo "✅ Sync cache cleared"
echo ""

echo "📱 Checking connected devices..."
system_profiler SPUSBDataType | grep -A 5 "iPhone\\|iPad\\|iPod" || echo "No iOS devices detected"
echo ""

echo "💡 Troubleshooting steps:"
echo "1. Disconnect and reconnect your device"
echo "2. Trust this computer on your device"
echo "3. Try a different USB cable"
echo "4. Restart both devices"
echo "5. Update iTunes/Finder and iOS"
echo ""

echo "=== iOS sync troubleshooting completed ==="
""",
                description: "Fixes iPhone/iPad sync issues by restarting sync services, clearing sync caches, and detecting connected devices. Includes step-by-step guide for when your iOS device won't sync or isn't recognized."
            )
        ]
        
        systemScripts = systemScriptsList
        
        // Set the first system script as selected if nothing is selected
        if selectedScript == nil && !systemScripts.isEmpty {
            selectedScript = systemScripts.first
            print("Selected first system script: \(selectedScript?.name ?? "none")")
        }
        
        print("System scripts loaded. Total: \(systemScripts.count)")
        
        // Force UI update
        objectWillChange.send()
        print("Sent objectWillChange notification")
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: .newScriptAvailable,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.checkForPendingScripts()
            }
        }
    }
    
    private func checkForPendingScripts() {
        Task { @MainActor in
            let pendingScripts = await GlobalScriptStore.shared.consumePendingScripts()
            
            for generatedScript in pendingScripts {
                let scriptItem = ScriptItem(
                    name: generatedScript.name,
                    content: generatedScript.content,
                    description: "AI-generated script for: \(generatedScript.name)",
                    lastModified: generatedScript.generatedAt
                )
                
                userScripts.append(scriptItem)
                selectedScript = scriptItem
                
                print("Added generated script to user scripts: \(generatedScript.name)")
            }
        }
    }
    
    private func getScriptsDirectory() throws -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let huginnDirectory = documentsDirectory.appendingPathComponent("Huginn")
        let scriptsDirectory = huginnDirectory.appendingPathComponent("Scripts")
        
        // Create directories if they don't exist
        try FileManager.default.createDirectory(at: scriptsDirectory, withIntermediateDirectories: true, attributes: nil)
        
        return scriptsDirectory
    }
    
    private func saveScriptToDisk(_ script: ScriptItem) async {
        do {
            let scriptsDirectory = try getScriptsDirectory()
            let scriptURL = scriptsDirectory.appendingPathComponent("\(script.name).sh")
            
            try script.content.write(to: scriptURL, atomically: true, encoding: .utf8)
            
            // Make script executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            
            print("Saved script to: \(scriptURL.path)")
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to save script: \(error.localizedDescription)"
            }
        }
    }
    
    private func updateScriptOnDisk(_ script: ScriptItem, oldName: String) async {
        do {
            let scriptsDirectory = try getScriptsDirectory()
            let oldScriptURL = scriptsDirectory.appendingPathComponent("\(oldName).sh")
            let newScriptURL = scriptsDirectory.appendingPathComponent("\(script.name).sh")
            
            // If name changed, remove old file
            if oldName != script.name && FileManager.default.fileExists(atPath: oldScriptURL.path) {
                try FileManager.default.removeItem(at: oldScriptURL)
            }
            
            // Write updated content
            try script.content.write(to: newScriptURL, atomically: true, encoding: .utf8)
            
            // Make script executable
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: newScriptURL.path)
            
            print("Updated script at: \(newScriptURL.path)")
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to update script: \(error.localizedDescription)"
            }
        }
    }
    
    private func deleteScriptFromDisk(_ script: ScriptItem) async {
        do {
            let scriptsDirectory = try getScriptsDirectory()
            let scriptURL = scriptsDirectory.appendingPathComponent("\(script.name).sh")
            
            if FileManager.default.fileExists(atPath: scriptURL.path) {
                try FileManager.default.removeItem(at: scriptURL)
                print("Deleted script from: \(scriptURL.path)")
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to delete script: \(error.localizedDescription)"
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
} 