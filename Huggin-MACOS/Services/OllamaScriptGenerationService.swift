import Foundation
import SwiftUI

// MARK: - Ollama Script Generation Service

@MainActor
public class OllamaScriptGenerationService: ObservableObject {
    static let shared = OllamaScriptGenerationService()
    
    @Published public var isGenerating = false
    @Published public var lastGeneratedScript: GeneratedScript?
    
    private let ollamaService = OllamaService.shared
    
    private init() {}
    
    // MARK: - Script Generation Methods
    
    public func generateInstallationScript(for request: String) async throws -> GeneratedScript {
        isGenerating = true
        defer { isGenerating = false }
        
        let softwareName = extractSoftwareName(from: request)
        let prompt = buildInstallationPrompt(for: softwareName)
        
        do {
            let response = try await ollamaService.sendMessage(prompt)
            let script = parseScriptResponse(response, originalRequest: request)
            
            lastGeneratedScript = script
            return script
            
        } catch {
            print("Ollama service failed, generating fallback script: \(error.localizedDescription)")
            // Generate fallback script if Ollama is not available
            let fallbackScript = generateFallbackInstallationScript(for: request)
            lastGeneratedScript = fallbackScript
            return fallbackScript
        }
    }
    
    public func generateMaintenanceScript(for task: String) async throws -> GeneratedScript {
        isGenerating = true
        defer { isGenerating = false }
        
        let prompt = buildMaintenancePrompt(for: task)
        
        do {
            let response = try await ollamaService.sendMessage(prompt)
            let script = parseScriptResponse(response, originalRequest: task)
            
            lastGeneratedScript = script
            return script
            
        } catch {
            print("Ollama service failed, generating fallback script: \(error.localizedDescription)")
            // Generate fallback script if Ollama is not available
            let fallbackScript = generateFallbackMaintenanceScript(for: task)
            lastGeneratedScript = fallbackScript
            return fallbackScript
        }
    }
    
    public func generateDiagnosticScript(for issue: String) async throws -> GeneratedScript {
        isGenerating = true
        defer { isGenerating = false }
        
        let prompt = buildDiagnosticPrompt(for: issue)
        
        do {
            let response = try await ollamaService.sendMessage(prompt)
            let script = parseScriptResponse(response, originalRequest: issue)
            
            lastGeneratedScript = script
            return script
            
        } catch {
            print("Ollama service failed, generating fallback script: \(error.localizedDescription)")
            // Generate fallback script if Ollama is not available
            let fallbackScript = generateFallbackDiagnosticScript(for: issue)
            lastGeneratedScript = fallbackScript
            return fallbackScript
        }
    }
    
    public func addScriptToManager(_ script: GeneratedScript) {
        // This will be called from the UI with access to the actual ScriptManagerViewModel
        // The ScriptPreviewSheet will handle the actual addition
        print("Script queued for addition to manager: \(script.name)")
    }
    
    // MARK: - Intent Detection
    
    public func detectInstallationIntent(in message: String) -> InstallationIntent? {
        let installKeywords = ["install", "setup", "add", "get", "download", "brew install"]
        let message_lower = message.lowercased()
        
        // Check for installation keywords
        guard installKeywords.contains(where: { message_lower.contains($0) }) else {
            return nil
        }
        
        // Extract software name
        let softwareName = extractSoftwareName(from: message)
        
        // Determine installation method
        let method = determineInstallationMethod(from: message)
        
        return InstallationIntent(
            softwareName: softwareName,
            method: method,
            originalRequest: message
        )
    }
    
    public func detectMaintenanceIntent(in message: String) -> MaintenanceIntent? {
        let maintenanceKeywords = ["clean", "update", "upgrade", "maintenance", "optimize", "fix"]
        let message_lower = message.lowercased()
        
        guard maintenanceKeywords.contains(where: { message_lower.contains($0) }) else {
            return nil
        }
        
        let taskType = determineMaintenanceTask(from: message)
        
        return MaintenanceIntent(
            taskType: taskType,
            originalRequest: message
        )
    }
    
    // MARK: - Private Methods
    
    private func buildInstallationPrompt(for software: String) -> String {
        return """
        You are an expert macOS system administrator. Create a bash script to install "\(software)" on macOS.
        
        Requirements:
        1. **macOS ONLY**: Use only macOS/Unix commands and package managers
        2. **Homebrew preferred**: Use Homebrew (brew) as the primary installation method
        3. **PATH setup**: Always ensure proper PATH includes /opt/homebrew/bin and /usr/local/bin
        4. **Error handling**: Check if commands exist before using them
        5. **Safe installation**: Check if already installed before attempting installation
        6. **Verification**: Verify successful installation after completion and FAIL if not found
        7. **Alternative methods**: Provide fallback options (cask, App Store, direct download)
        8. **GUI app launching**: For GUI applications, use 'open -a "AppName"' to launch, NOT command line
        9. **Corruption handling**: If installation claims success but app is missing, suggest reinstallation
        
        IMPORTANT: This script will run on macOS. Do not use Windows package managers or commands.
        
        Use these macOS installation methods:
        - brew install --cask (for GUI applications like browsers, editors, etc.)
        - brew install (for CLI tools only)
        - mas install (for App Store apps, if mas is available)
        - Direct download with curl/wget if needed
        
        For GUI applications like Slack, Discord, Chrome, etc.:
        - ALWAYS use 'brew install --cask appname' to install
        - Use 'open -a "App Name"' to launch (NOT 'appname' command)
        - Check for app in /Applications/AppName.app before launching
        - NEVER try to copy .app files manually - use Homebrew cask instead
        
        Common GUI applications and their cask names:
        - Slack: brew install --cask slack
        - Discord: brew install --cask discord
        - Chrome: brew install --cask google-chrome
        - Firefox: brew install --cask firefox
        - VS Code: brew install --cask visual-studio-code
        
        Return ONLY the bash script code, starting with #!/bin/bash. No explanations or markdown.
        """
    }
    
    private func buildMaintenancePrompt(for task: String) -> String {
        return """
        You are an expert macOS system administrator. Create a bash script for this maintenance task: "\(task)"
        
        Requirements:
        1. **macOS ONLY**: Use only macOS/Unix commands and tools
        2. **Safe operations**: Only perform safe, non-destructive maintenance tasks
        3. **System tools**: Use built-in macOS tools like diskutil, launchctl, system_profiler
        4. **Homebrew maintenance**: Include Homebrew cleanup if Homebrew is available
        5. **Permission awareness**: Check permissions before making changes
        6. **Informative output**: Show what is being done and the results
        7. **Error handling**: Include proper error checking and recovery
        
        IMPORTANT: This script will run on macOS. Do not use Windows commands or tools.
        
        Common macOS maintenance commands:
        - diskutil (disk operations)
        - launchctl (service management)
        - system_profiler (system information)
        - softwareupdate (system updates)
        - brew cleanup (if Homebrew available)
        - periodic daily/weekly/monthly (system maintenance)
        - mdutil (Spotlight maintenance)
        - dscacheutil (DNS cache)
        
        Return ONLY the bash script code, starting with #!/bin/bash. No explanations or markdown.
        """
    }
    
    private func buildDiagnosticPrompt(for issue: String) -> String {
        return """
        You are an expert macOS system administrator. A user is experiencing this issue: "\(issue)"
        
        Create a bash script that diagnoses and potentially fixes the issue. Follow these guidelines:
        
        1. **macOS ONLY**: Use only macOS/Unix commands. NEVER use Windows commands like 'systeminfo', 'dir', 'cls', etc.
        2. **Safe macOS commands**: Use sw_vers, system_profiler, ps, top, df, vm_stat, networksetup, scutil, etc.
        3. **Gather information**: Check system status, logs, configurations using macOS tools
        4. **Non-destructive**: Only make safe changes, avoid data loss
        5. **Informative output**: Show what was found and what was done
        6. **Step-by-step**: Break down the diagnostic process
        7. **PATH awareness**: Always check and set proper PATH for Homebrew and common tools
        8. **Command existence**: Always check if commands exist before using them
        
        IMPORTANT: This script will run on macOS. Do not use any Windows commands or syntax.
        
        Common macOS diagnostic commands to use:
        - sw_vers (system version, NOT systeminfo)
        - system_profiler (hardware info)
        - ps aux (processes, NOT tasklist)
        - df -h (disk usage, NOT dir)
        - vm_stat (memory, NOT systeminfo)
        - networksetup (network config)
        - scutil (system configuration)
        - launchctl (services)
        - brew (if available)
        - softwareupdate (system updates)
        
        Return ONLY the bash script code, starting with #!/bin/bash. No explanations or markdown.
        """
    }
    
    private func parseScriptResponse(_ response: String, originalRequest: String) -> GeneratedScript {
        // Extract script content (remove any markdown formatting)
        var scriptContent = response
        
        // Remove markdown code blocks if present - handle multiple patterns
        if scriptContent.contains("```bash") {
            scriptContent = scriptContent
                .replacingOccurrences(of: "```bash\n", with: "")
                .replacingOccurrences(of: "```bash", with: "")
                .replacingOccurrences(of: "```", with: "")
        } else if scriptContent.contains("```") {
            // Handle generic code blocks
            scriptContent = scriptContent
                .replacingOccurrences(of: "```\n", with: "")
                .replacingOccurrences(of: "```", with: "")
        }
        
        // Remove any remaining markdown artifacts
        scriptContent = scriptContent
            .replacingOccurrences(of: "```%", with: "")
            .replacingOccurrences(of: "```sh", with: "")
            .replacingOccurrences(of: "```shell", with: "")
        
        // Clean up multiple newlines and trim
        scriptContent = scriptContent
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ensure it starts with shebang
        if !scriptContent.hasPrefix("#!/bin/bash") {
            scriptContent = "#!/bin/bash\n\n" + scriptContent
        }
        
        // Remove duplicate shebangs
        let lines = scriptContent.components(separatedBy: .newlines)
        var cleanedLines: [String] = []
        var foundShebang = false
        
        for line in lines {
            if line.hasPrefix("#!/bin/bash") {
                if !foundShebang {
                    cleanedLines.append(line)
                    foundShebang = true
                }
                // Skip duplicate shebangs
            } else {
                cleanedLines.append(line)
            }
        }
        
        scriptContent = cleanedLines.joined(separator: "\n")
        
        // Validate and fix Windows commands
        scriptContent = validateAndFixMacOSScript(scriptContent)
        
        // Generate appropriate name
        let scriptName = generateScriptName(from: originalRequest)
        
        // Analyze the script for metadata
        let estimatedDuration = estimateExecutionTime(scriptContent)
        let riskLevel = assessRiskLevel(scriptContent)
        
        return GeneratedScript(
            name: scriptName,
            content: scriptContent,
            originalRequest: originalRequest,
            generatedAt: Date(),
            estimatedDuration: estimatedDuration,
            riskLevel: riskLevel
        )
    }
    
    private func validateAndFixMacOSScript(_ script: String) -> String {
        var fixedScript = script
        
        // Dictionary of Windows commands and their macOS equivalents
        let windowsToMacOSCommands = [
            "systeminfo": "sw_vers && system_profiler SPHardwareDataType",
            "tasklist": "ps aux",
            "dir": "ls -la",
            "cls": "clear",
            "type": "cat",
            "copy": "cp",
            "move": "mv",
            "del": "rm",
            "md": "mkdir",
            "rd": "rmdir",
            "findstr": "grep",
            "where": "which",
            "ipconfig": "ifconfig",
            "netstat": "netstat",
            "ping": "ping",
            "tracert": "traceroute"
        ]
        
        // Replace Windows commands with macOS equivalents
        for (windowsCmd, macosCmd) in windowsToMacOSCommands {
            // Replace standalone commands (with word boundaries)
            let pattern = "\\b\(windowsCmd)\\b"
            fixedScript = fixedScript.replacingOccurrences(
                of: pattern,
                with: macosCmd,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        
        // Fix old Homebrew cask syntax
        let homebrewFixes = [
            "brew cask install": "brew install --cask",
            "brew cask uninstall": "brew uninstall --cask",
            "brew cask list": "brew list --cask",
            "brew cask search": "brew search --cask",
            "brew cask info": "brew info --cask"
        ]
        
        for (oldSyntax, newSyntax) in homebrewFixes {
            fixedScript = fixedScript.replacingOccurrences(of: oldSyntax, with: newSyntax)
        }
        
        // Fix common GUI application launch mistakes
        let guiAppFixes = [
            "opera --version": "open -a \"Opera\"",
            "chrome --version": "open -a \"Google Chrome\"",
            "firefox --version": "open -a \"Firefox\"",
            "safari --version": "open -a \"Safari\"",
            "code --version": "open -a \"Visual Studio Code\"",
            "slack --version": "open -a \"Slack\"",
            "discord --version": "open -a \"Discord\""
        ]
        
        for (wrongLaunch, correctLaunch) in guiAppFixes {
            fixedScript = fixedScript.replacingOccurrences(of: wrongLaunch, with: correctLaunch)
        }
        
        // Fix common standalone GUI app commands that should use 'open -a'
        let standaloneAppFixes = [
            ("\\bopera\\b(?!\\s)", "open -a \"Opera\""),
            ("\\bchrome\\b(?!\\s)", "open -a \"Google Chrome\""),
            ("\\bfirefox\\b(?!\\s)", "open -a \"Firefox\""),
            ("\\bslack\\b(?!\\s)", "open -a \"Slack\""),
            ("\\bdiscord\\b(?!\\s)", "open -a \"Discord\"")
        ]
        
        for (pattern, replacement) in standaloneAppFixes {
            fixedScript = fixedScript.replacingOccurrences(
                of: pattern,
                with: replacement,
                options: .regularExpression
            )
        }
        
        // Add warning if Windows commands or old Homebrew syntax were found and replaced
        if fixedScript != script {
            let warningComment = """
            # WARNING: This script contained outdated commands that have been automatically
            # converted to current macOS/Homebrew syntax. Please review the script before running.
            
            """
            fixedScript = fixedScript.replacingOccurrences(
                of: "#!/bin/bash\n",
                with: "#!/bin/bash\n\n\(warningComment)"
            )
        }
        
        return fixedScript
    }
    
    private func extractSoftwareName(from message: String) -> String {
        let messageLower = message.lowercased()
        
        // Common software names to look for first
        let knownSoftware = [
            "slack", "discord", "chrome", "firefox", "safari", "opera", "edge",
            "vscode", "code", "atom", "sublime", "vim", "emacs",
            "docker", "node", "npm", "yarn", "git", "python", "java", "go",
            "xcode", "android studio", "intellij", "pycharm",
            "photoshop", "illustrator", "sketch", "figma",
            "spotify", "vlc", "zoom", "teams", "skype",
            "homebrew", "brew", "mas", "wget", "curl"
        ]
        
        // Check for known software names first
        for software in knownSoftware {
            if messageLower.contains(software) {
                return software
            }
        }
        
        // Pattern-based extraction for "install X" format
        let patterns = [
            "install ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "brew install ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "get ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "setup ([a-zA-Z][a-zA-Z0-9\\-_]+)",
            "add ([a-zA-Z][a-zA-Z0-9\\-_]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: message) {
                let candidate = String(message[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Filter out common words that aren't software names
                let excludeWords = ["you", "me", "can", "please", "help", "the", "a", "an", "to", "for", "with", "and", "or", "but", "from", "on", "in", "at", "by"]
                if !excludeWords.contains(candidate.lowercased()) && candidate.count > 2 {
                    return candidate
                }
            }
        }
        
        // Last resort: look for words after install keywords that aren't common words
        let words = message.components(separatedBy: .whitespacesAndNewlines)
        let excludeWords = ["you", "me", "can", "please", "help", "the", "a", "an", "to", "for", "with", "and", "or", "but", "from", "on", "in", "at", "by", "install", "download", "get", "setup", "add"]
        
        var foundInstallKeyword = false
        for word in words {
            let cleanWord = word.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if ["install", "download", "get", "setup", "add"].contains(cleanWord) {
                foundInstallKeyword = true
                continue
            }
            
            if foundInstallKeyword && !excludeWords.contains(cleanWord) && cleanWord.count > 2 {
                return word.trimmingCharacters(in: .punctuationCharacters)
            }
        }
        
        // Fallback: return the whole message, but clean it up
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func determineInstallationMethod(from message: String) -> InstallationMethod {
        let message_lower = message.lowercased()
        
        if message_lower.contains("brew") || message_lower.contains("homebrew") {
            return .homebrew
        } else if message_lower.contains("app store") || message_lower.contains("mas") {
            return .appStore
        } else if message_lower.contains("dmg") || message_lower.contains("download") {
            return .directDownload
        } else {
            return .auto // Let the script decide
        }
    }
    
    private func determineMaintenanceTask(from message: String) -> MaintenanceTask {
        let message_lower = message.lowercased()
        
        if message_lower.contains("clean") {
            return .cleanup
        } else if message_lower.contains("update") || message_lower.contains("upgrade") {
            return .update
        } else if message_lower.contains("optimize") {
            return .optimize
        } else {
            return .general
        }
    }
    
    private func generateScriptName(from request: String) -> String {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        
        if request.lowercased().contains("install") {
            return "Install Script - \(timestamp)"
        } else if request.lowercased().contains("clean") || request.lowercased().contains("maintenance") {
            return "Maintenance Script - \(timestamp)"
        } else if request.lowercased().contains("fix") || request.lowercased().contains("diagnose") {
            return "Diagnostic Script - \(timestamp)"
        } else {
            return "Generated Script - \(timestamp)"
        }
    }
    
    private func estimateExecutionTime(_ scriptContent: String) -> TimeInterval {
        let lines = scriptContent.components(separatedBy: .newlines).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        // Basic estimation: 2 seconds per command, more for complex operations
        var estimate: TimeInterval = Double(lines.count) * 2.0
        
        // Adjust for known long-running operations
        if scriptContent.contains("brew install") {
            estimate += 30.0 // Homebrew installs take time
        }
        if scriptContent.contains("curl") || scriptContent.contains("wget") {
            estimate += 10.0 // Downloads take time
        }
        if scriptContent.contains("make") || scriptContent.contains("compile") {
            estimate += 60.0 // Compilation takes time
        }
        
        return estimate
    }
    
    private func assessRiskLevel(_ scriptContent: String) -> ScriptRiskLevel {
        let dangerousCommands = ["rm -rf", "sudo rm", "format", "mkfs", "dd if="]
        let moderateCommands = ["sudo", "curl", "wget", "chmod", "chown"]
        
        for dangerous in dangerousCommands {
            if scriptContent.contains(dangerous) {
                return .high
            }
        }
        
        for moderate in moderateCommands {
            if scriptContent.contains(moderate) {
                return .medium
            }
        }
        
        return .low
    }
    
    // MARK: - Fallback Script Generation
    
    private func generateFallbackInstallationScript(for request: String) -> GeneratedScript {
        let softwareName = extractSoftwareName(from: request)
        let method = determineInstallationMethod(from: request)
        
        let scriptContent = generateBasicInstallationScript(software: softwareName, method: method)
        
        return GeneratedScript(
            name: "Install Script - \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))",
            content: scriptContent,
            originalRequest: request,
            generatedAt: Date(),
            estimatedDuration: 60.0,
            riskLevel: .medium
        )
    }
    
    private func generateFallbackMaintenanceScript(for task: String) -> GeneratedScript {
        let taskType = determineMaintenanceTask(from: task)
        let scriptContent = generateBasicMaintenanceScript(taskType: taskType)
        
        return GeneratedScript(
            name: "Maintenance Script - \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))",
            content: scriptContent,
            originalRequest: task,
            generatedAt: Date(),
            estimatedDuration: 120.0,
            riskLevel: .low
        )
    }
    
    private func generateFallbackDiagnosticScript(for issue: String) -> GeneratedScript {
        let scriptContent = generateBasicDiagnosticScript(issue: issue)
        
        return GeneratedScript(
            name: "Diagnostic Script - \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))",
            content: scriptContent,
            originalRequest: issue,
            generatedAt: Date(),
            estimatedDuration: 30.0,
            riskLevel: .low
        )
    }
    
    private func generateBasicInstallationScript(software: String, method: InstallationMethod) -> String {
        switch method {
        case .homebrew:
            // Determine if it's a GUI app that needs cask installation
            let guiApps = ["slack", "discord", "chrome", "firefox", "opera", "edge", "safari", 
                          "vscode", "code", "atom", "sublime", "xcode", "android studio", "intellij", "pycharm",
                          "photoshop", "illustrator", "sketch", "figma", "spotify", "vlc", "zoom", "teams", "skype"]
            let softwareLower = software.lowercased()
            let isGuiApp = guiApps.contains { softwareLower.contains($0) }
            let installCommand = isGuiApp ? "brew install --cask \(software)" : "brew install \(software)"
            let checkCommand = isGuiApp ? "brew list --cask \(software)" : "brew list \(software)"
            
            return """
            #!/bin/bash
            set -e
            
            echo "Installing \(software) via Homebrew..."
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            # Set up common paths for Homebrew (handles sandboxed environments)
            export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
            
            # Robust Homebrew detection and setup
            if ! command -v brew &> /dev/null; then
                echo "Homebrew not found in PATH, checking common locations..."
                if [ -f "/opt/homebrew/bin/brew" ]; then
                    export PATH="/opt/homebrew/bin:$PATH"
                    echo "✅ Found Homebrew at /opt/homebrew/bin"
                elif [ -f "/usr/local/bin/brew" ]; then
                    export PATH="/usr/local/bin:$PATH"
                    echo "✅ Found Homebrew at /usr/local/bin"
                else
                    echo "❌ Error: Homebrew is not installed. Please install it first:"
                    echo "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
                    echo ""
                    echo "After installation, you may need to add Homebrew to your PATH:"
                    echo "echo 'export PATH=\"/opt/homebrew/bin:$PATH\"' >> ~/.zshrc"
                    exit 127
                fi
            else
                echo "✅ Homebrew is available at: $(which brew)"
            fi
            
            echo "Detected software type: \(isGuiApp ? "GUI application (using cask)" : "CLI tool")"
            
            # Check if software is already installed
            if \(checkCommand) &> /dev/null; then
                echo "\(software) is already installed."
                brew info \(isGuiApp ? "--cask " : "")\(software)
            else
                echo "Installing \(software)..."
                \(installCommand)
                echo "\(software) installation completed!"
            fi
            
            # Verify installation for GUI apps
            \(isGuiApp ? """
            # Check if the app was properly installed
            if [ -d "/Applications/\(software.capitalized).app" ]; then
                echo "✅ \(software.capitalized) is successfully installed in /Applications/"
                echo "You can launch it with: open -a \"\(software.capitalized)\""
            else
                echo "❌ Installation failed: \(software.capitalized).app not found in /Applications/"
                echo "This might indicate a corrupted installation. Try:"
                echo "  brew uninstall --cask \(software)"
                echo "  brew install --cask \(software)"
                exit 1
            fi
            """ : """
            if command -v \(software) &> /dev/null; then
                echo "✅ \(software) is now available in your PATH"
                \(software) --version 2>/dev/null || echo "Installation verified"
            else
                echo "❌ Installation failed: \(software) not found in PATH"
                echo "You may need to restart your terminal or check the installation."
                exit 1
            fi
            """)
            """
            
        case .appStore:
            return """
            #!/bin/bash
            set -e
            
            echo "Installing \(software) via App Store..."
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            # Check if mas (Mac App Store CLI) is installed
            if ! command -v mas &> /dev/null; then
                echo "Installing mas (Mac App Store CLI) first..."
                if command -v brew &> /dev/null; then
                    brew install mas
                else
                    echo "Error: Homebrew is required to install mas. Please install Homebrew first."
                    exit 1
                fi
            fi
            
            echo "Please search for '\(software)' in the App Store and note its ID."
            echo "Then run: mas install [APP_ID]"
            echo ""
            echo "Searching for \(software)..."
            mas search "\(software)" | head -5
            """
            
        case .directDownload:
            return """
            #!/bin/bash
            set -e
            
            echo "Direct download installation for \(software)"
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            echo "This script provides guidance for manually downloading \(software):"
            echo "1. Visit the official website for \(software)"
            echo "2. Download the latest .dmg or .pkg file"
            echo "3. Open the downloaded file and follow installation instructions"
            echo "4. Verify installation by opening the application"
            echo ""
            echo "For automated downloads, specific URLs would be needed."
            echo "Consider using Homebrew if available: brew install --cask \(software)"
            """
            
        case .auto:
            return """
            #!/bin/bash
            set -e
            
            echo "Auto-detecting installation method for \(software)..."
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            # Try Homebrew first
            if command -v brew &> /dev/null; then
                echo "Trying Homebrew installation..."
                if brew install \(software) 2>/dev/null; then
                    echo "✓ Successfully installed \(software) via Homebrew"
                    exit 0
                fi
                
                echo "Trying Homebrew cask installation..."
                if brew install --cask \(software) 2>/dev/null; then
                    echo "✓ Successfully installed \(software) via Homebrew cask"
                    exit 0
                fi
            fi
            
            echo "Homebrew installation failed. Please try:"
            echo "1. Manual download from official website"
            echo "2. Mac App Store if available"
            echo "3. Check if the software name is correct"
            """
        }
    }
    
    private func generateBasicMaintenanceScript(taskType: MaintenanceTask) -> String {
        switch taskType {
        case .cleanup:
            return """
            #!/bin/bash
            set -e
            
            echo "Basic macOS Cleanup Script"
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            echo "Cleaning up temporary files..."
            
            # Clean user cache (safe)
            echo "Clearing user caches..."
            rm -rf ~/Library/Caches/com.apple.Safari/WebKitCache
            rm -rf ~/Library/Caches/com.google.Chrome/Default/Cache
            
            # Clean Downloads folder of old files (older than 30 days)
            echo "Cleaning old downloads (30+ days old)..."
            find ~/Downloads -type f -mtime +30 -exec rm -f {} \\;
            
            # Empty Trash
            echo "Emptying Trash..."
            osascript -e 'tell application "Finder" to empty trash'
            
            # Clean system caches (requires admin)
            if [[ $EUID -eq 0 ]]; then
                echo "Cleaning system caches..."
                rm -rf /System/Library/Caches/*
                rm -rf /Library/Caches/*
            else
                echo "Run with sudo for system-wide cleanup"
            fi
            
            echo "Basic cleanup completed!"
            """
            
        case .update:
            return """
            #!/bin/bash
            set -e
            
            echo "Basic macOS Update Script"
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            # Update Homebrew packages
            if command -v brew &> /dev/null; then
                echo "Updating Homebrew packages..."
                brew update
                brew upgrade
                brew cleanup
            fi
            
            # Update Mac App Store apps
            if command -v mas &> /dev/null; then
                echo "Updating Mac App Store apps..."
                mas upgrade
            fi
            
            # Check for system updates
            echo "Checking for system updates..."
            softwareupdate -l
            
            echo "To install system updates, run:"
            echo "sudo softwareupdate -i -a"
            """
            
        case .optimize:
            return """
            #!/bin/bash
            set -e
            
            echo "Basic macOS Optimization Script"
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            # Rebuild LaunchServices database
            echo "Rebuilding LaunchServices database..."
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -kill -r -domain local -domain system -domain user
            
            # Clear DNS cache
            echo "Clearing DNS cache..."
            sudo dscacheutil -flushcache
            sudo killall -HUP mDNSResponder
            
            # Repair disk permissions (on older systems)
            echo "Note: On newer macOS versions, disk permissions are automatically repaired."
            
            # Reset Spotlight index
            echo "To reset Spotlight index, run:"
            echo "sudo mdutil -E /"
            
            echo "Basic optimization completed!"
            """
            
        case .general:
            return """
            #!/bin/bash
            set -e
            
            echo "General macOS Maintenance Script"
            echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
            echo ""
            
            echo "Performing general maintenance tasks..."
            
            # Check disk usage
            echo "Disk usage:"
            df -h
            
            # Check system uptime
            echo "System uptime:"
            uptime
            
            # Check memory usage
            echo "Memory usage:"
            vm_stat
            
            # List largest files in home directory
            echo "Largest files in home directory:"
            find ~ -type f -size +100M -exec ls -lh {} \\; 2>/dev/null | head -10
            
            echo "General maintenance check completed!"
            """
        }
    }
    
    private func generateBasicDiagnosticScript(issue: String) -> String {
        return """
        #!/bin/bash
        set -e
        
        echo "Basic Diagnostic Script for: \(issue)"
        echo "Note: This is a basic fallback script. For AI-enhanced scripts, ensure Ollama is running."
        echo ""
        
        echo "System Information:"
        echo "=================="
        
        # System version
        echo "macOS Version:"
        sw_vers
        echo ""
        
        # PATH and environment debugging
        echo "Environment Variables:"
        echo "PATH: $PATH"
        echo "SHELL: $SHELL"
        echo "HOME: $HOME"
        echo "USER: $(whoami)"
        echo ""
        
        # Check common command locations
        echo "Command Availability Check:"
        echo "which bash: $(which bash 2>/dev/null || echo 'NOT FOUND')"
        echo "which brew: $(which brew 2>/dev/null || echo 'NOT FOUND')"
        echo "which git: $(which git 2>/dev/null || echo 'NOT FOUND')"
        echo "which python3: $(which python3 2>/dev/null || echo 'NOT FOUND')"
        echo "which node: $(which node 2>/dev/null || echo 'NOT FOUND')"
        echo ""
        
        # Basic system info (avoiding problematic commands)
        echo "Basic System Info:"
        echo "Hostname: $(hostname)"
        echo "Current Date: $(date)"
        echo "Uptime: $(uptime)"
        echo ""
        
        # Disk usage
        echo "Disk Usage:"
        df -h
        echo ""
        
        # Memory usage (safe command)
        echo "Memory Usage:"
        vm_stat | head -10
        echo ""
        
        # Network connectivity (simple test)
        echo "Network Connectivity:"
        if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
            echo "✅ Internet connection: OK"
        else
            echo "❌ Internet connection: FAILED"
        fi
        echo ""
        
        # Process info (safe approach)
        echo "Top processes by CPU usage:"
        ps aux | head -10
        echo ""
        
        # Check for the specific issue mentioned
        echo "Issue-specific checks for: \(issue.lowercased())"
        if echo "\(issue.lowercased())" | grep -q "slack"; then
            echo "Checking Slack-related processes:"
            ps aux | grep -i slack | grep -v grep || echo "No Slack processes found"
        elif echo "\(issue.lowercased())" | grep -q "brew"; then
            echo "Checking Homebrew status:"
            if command -v brew >/dev/null 2>&1; then
                echo "✅ Homebrew is installed"
                brew --version | head -1
            else
                echo "❌ Homebrew not found"
            fi
        elif echo "\(issue.lowercased())" | grep -q "update"; then
            echo "Checking for system updates:"
            if command -v softwareupdate >/dev/null 2>&1; then
                echo "✅ softwareupdate command available"
                echo "Use 'softwareupdate --list' to check for updates"
            else
                echo "❌ softwareupdate command not found"
            fi
        fi
        
        echo ""
        echo "=== Diagnostic completed successfully ==="
        """
    }
}

// MARK: - Supporting Types

public struct GeneratedScript: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let content: String
    public let originalRequest: String
    public let generatedAt: Date
    public let estimatedDuration: TimeInterval
    public let riskLevel: ScriptRiskLevel
    
    public init(name: String, content: String, originalRequest: String, generatedAt: Date, estimatedDuration: TimeInterval, riskLevel: ScriptRiskLevel) {
        self.name = name
        self.content = content
        self.originalRequest = originalRequest
        self.generatedAt = generatedAt
        self.estimatedDuration = estimatedDuration
        self.riskLevel = riskLevel
    }
    
    public var formattedDuration: String {
        if estimatedDuration < 60 {
            return "\(Int(estimatedDuration))s"
        } else {
            return "\(Int(estimatedDuration / 60))m \(Int(estimatedDuration.truncatingRemainder(dividingBy: 60)))s"
        }
    }
}

public struct InstallationIntent: Sendable, Codable {
    public let softwareName: String
    public let method: InstallationMethod
    public let originalRequest: String
    
    public init(softwareName: String, method: InstallationMethod, originalRequest: String) {
        self.softwareName = softwareName
        self.method = method
        self.originalRequest = originalRequest
    }
}

public struct MaintenanceIntent: Sendable, Codable {
    public let taskType: MaintenanceTask
    public let originalRequest: String
    
    public init(taskType: MaintenanceTask, originalRequest: String) {
        self.taskType = taskType
        self.originalRequest = originalRequest
    }
}

public enum InstallationMethod: String, CaseIterable, Sendable, Codable {
    case homebrew = "Homebrew"
    case appStore = "App Store"
    case directDownload = "Direct Download"
    case auto = "Auto-detect"
}

public enum MaintenanceTask: String, CaseIterable, Sendable, Codable {
    case cleanup = "Cleanup"
    case update = "Update"
    case optimize = "Optimize"
    case general = "General"
}

public enum OllamaScriptError: LocalizedError, Sendable {
    case generationFailed(String)
    case parsingFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .generationFailed(let message):
            return "Script generation failed: \(message)"
        case .parsingFailed(let message):
            return "Script parsing failed: \(message)"
        }
    }
} 