import SwiftUI

// MARK: - Script Manager Main View

struct ScriptManagerView: View {
    @ObservedObject private var viewModel = ScriptManagerViewModel.shared
    @State private var showingAddScript = false
    @State private var showingEditScript = false
    @State private var scriptToEdit: ScriptItem?
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with script list
            ScriptListView(
                viewModel: viewModel,
                showingAddScript: $showingAddScript,
                showingEditScript: $showingEditScript,
                scriptToEdit: $scriptToEdit
            )
        } detail: {
            // Detail view with script output
            ScriptDetailView(viewModel: viewModel)
        }
        .navigationTitle("Script Manager")
        .sheet(isPresented: $showingAddScript) {
            ScriptEditorSheet(
                viewModel: viewModel,
                isPresented: $showingAddScript
            )
        }
        .sheet(isPresented: $showingEditScript) {
            if let script = scriptToEdit {
                ScriptEditorSheet(
                    viewModel: viewModel,
                    isPresented: $showingEditScript,
                    editingScript: script
                )
            }
        }
        .alert("Script Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
            }
        }
        .onAppear {
            print("🔍 ScriptManagerView appeared")
            print("🔍 Current script count: \(viewModel.scripts.count)")
            viewModel.refreshScripts()
            
            // Force a small delay and then refresh again if still empty
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if viewModel.scripts.isEmpty {
                    print("🔍 Scripts still empty after delay, forcing reload...")
                    viewModel.refreshScripts()
                }
            }
        }
    }
}

// MARK: - Script List Sidebar

struct ScriptListView: View {
    @ObservedObject var viewModel: ScriptManagerViewModel
    @Binding var showingAddScript: Bool
    @Binding var showingEditScript: Bool
    @Binding var scriptToEdit: ScriptItem?
    
    var body: some View {
        VStack(spacing: 0) {
            // Enhanced Header with prominent Add Script button
            VStack(spacing: 12) {
                HStack {
                    Text("Scripts")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    // Refresh button
                    Button(action: {
                        viewModel.refreshScripts()
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if viewModel.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                // Prominent Add Script button
                Button(action: {
                    showingAddScript = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title3)
                        Text("Create New Script")
                            .font(.headline)
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            
            Divider()
            
            // Script list
            if (viewModel.systemScripts.isEmpty && viewModel.userScripts.isEmpty) && !viewModel.isLoading {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Scripts Yet")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Create your first script to get started with automation")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    VStack(spacing: 8) {
                        Button("Create Your First Script") {
                            showingAddScript = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $viewModel.selectedScript) {
                    // System Scripts Section
                    if !viewModel.systemScripts.isEmpty {
                        Section("🛠️ System Scripts") {
                            ForEach(viewModel.systemScripts, id: \.id) { script in
                                ScriptRowView(
                                    script: script,
                                    viewModel: viewModel,
                                    isSystemScript: true,
                                    onEdit: {
                                        scriptToEdit = script
                                        showingEditScript = true
                                    }
                                )
                                .onTapGesture {
                                    viewModel.selectedScript = script
                                }
                            }
                        }
                    }
                    
                    // User Scripts Section
                    if !viewModel.userScripts.isEmpty {
                        Section("👤 My Scripts") {
                            ForEach(viewModel.userScripts, id: \.id) { script in
                                ScriptRowView(
                                    script: script,
                                    viewModel: viewModel,
                                    isSystemScript: false,
                                    onEdit: {
                                        scriptToEdit = script
                                        showingEditScript = true
                                    }
                                )
                                .onTapGesture {
                                    viewModel.selectedScript = script
                                }
                            }
                        }
                    }
                    
                    // Empty user scripts section with add button
                    if viewModel.userScripts.isEmpty {
                        Section("👤 My Scripts") {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Create your first custom script")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                showingAddScript = true
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
        .frame(minWidth: 300)
    }
}

// MARK: - Script Row View

struct ScriptRowView: View {
    let script: ScriptItem
    @ObservedObject var viewModel: ScriptManagerViewModel
    let isSystemScript: Bool
    let onEdit: () -> Void
    
    @State private var showingDeleteConfirmation = false
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 8) {
            // Script header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(script.name)
                        .font(.headline)
                        .lineLimit(1)
                    
                    Text(script.statusDescription)
                        .font(.caption)
                        .foregroundColor(statusColor)
                }
                
                Spacer()
                
                // Action buttons
                HStack(spacing: 8) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                    
                    Button(action: { showingDeleteConfirmation = true }) {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    
                    if script.isRunning {
                        Button("Stop") {
                            viewModel.stopScript(script)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundColor(.red)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.orange.opacity(0.6), lineWidth: 2)
                                .scaleEffect(1.1)
                                .opacity(0.8)
                                .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: script.isRunning)
                        )
                    } else {
                        Button("Run") {
                            viewModel.runScript(script)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
            }
            
            // Script output preview
            if !script.output.isEmpty {
                DisclosureGroup("Output Preview") {
                    Text(script.lastThreeLines)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
            }
            
            // Last run info
            if let lastRun = script.lastRun {
                Text("Last run: \(dateFormatter.string(from: lastRun))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(viewModel.selectedScript?.id == script.id ? 
                      Color.blue.opacity(0.1) : Color.clear)
        )
        .contextMenu {
            Button("Edit") { onEdit() }
            if !isSystemScript {
                Button("Duplicate") {
                    viewModel.createScript(
                        name: "\(script.name) Copy",
                        content: script.content,
                        description: script.description.isEmpty ? "Copy of \(script.name)" : script.description
                    )
                }
                Divider()
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
            } else {
                Button("Copy to My Scripts") {
                    let cleanName = script.name.replacingOccurrences(of: "🛠️ ", with: "").replacingOccurrences(of: "🌐 ", with: "").replacingOccurrences(of: "🔧 ", with: "").replacingOccurrences(of: "🔄 ", with: "").replacingOccurrences(of: "🖥️ ", with: "").replacingOccurrences(of: "🔐 ", with: "").replacingOccurrences(of: "🖨️ ", with: "").replacingOccurrences(of: "🔊 ", with: "").replacingOccurrences(of: "📱 ", with: "")
                    viewModel.createScript(
                        name: cleanName,
                        content: script.content,
                        description: script.description
                    )
                }
            }
        }
        .alert("Delete Script", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            if !isSystemScript {
                Button("Delete", role: .destructive) {
                    viewModel.deleteScript(script)
                }
            }
        } message: {
            if !isSystemScript {
                Text("Are you sure you want to delete '\(script.name)'? This action cannot be undone.")
            } else {
                Text("System scripts cannot be deleted. You can copy them to My Scripts to create a custom version.")
            }
        }
    }
    
    private var statusColor: Color {
        if script.isRunning {
            return .orange
        } else if script.hasError {
            return .red
        } else if script.isCompleted {
            return .green
        } else {
            return .secondary
        }
    }
}

// MARK: - Script Detail View

struct ScriptDetailView: View {
    @ObservedObject var viewModel: ScriptManagerViewModel
    
    var body: some View {
        Group {
            if let selectedScript = viewModel.selectedScript {
                VStack(spacing: 0) {
                    // Header
                    ScriptDetailHeader(script: selectedScript, viewModel: viewModel)
                    
                    Divider()
                    
                    // Description section
                    if !selectedScript.description.isEmpty {
                        ScriptDescriptionView(script: selectedScript)
                        Divider()
                    }
                    
                    // Output view
                    ScriptOutputView(script: selectedScript, viewModel: viewModel)
                }
                .transition(.opacity.combined(with: .slide))
                .animation(.easeInOut(duration: 0.3), value: viewModel.selectedScript?.id)
            } else {
                ContentUnavailableView(
                    "Select a Script",
                    systemImage: "doc.text",
                    description: Text("Choose a script from the sidebar to view its description, output and controls")
                )
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: viewModel.selectedScript?.id)
            }
        }
        .frame(minWidth: 400)
    }
}

// MARK: - Script Detail Header

struct ScriptDetailHeader: View {
    let script: ScriptItem
    @ObservedObject var viewModel: ScriptManagerViewModel
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(script.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 16) {
                        Label(script.statusDescription, systemImage: statusIcon)
                            .foregroundColor(statusColor)
                            .font(.subheadline)
                        
                        if let lastRun = script.lastRun {
                            Label(dateFormatter.string(from: lastRun), systemImage: "clock")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        
                        if script.isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                
                Spacer()
                
                // Control buttons
                HStack(spacing: 12) {
                    if script.isRunning {
                        Button("Stop Script") {
                            viewModel.stopScript(script)
                        }
                        .buttonStyle(.bordered)
                        .foregroundColor(.red)
                    } else {
                        Button("Run Script") {
                            viewModel.runScript(script)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var statusIcon: String {
        if script.isRunning {
            return "play.circle.fill"
        } else if script.hasError {
            return "exclamationmark.triangle.fill"
        } else if script.isCompleted {
            return "checkmark.circle.fill"
        } else {
            return "circle"
        }
    }
    
    private var statusColor: Color {
        if script.isRunning {
            return .orange
        } else if script.hasError {
            return .red
        } else if script.isCompleted {
            return .green
        } else {
            return .secondary
        }
    }
}

// MARK: - Script Description View

struct ScriptDescriptionView: View {
    let script: ScriptItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
                    .font(.title3)
                Text("What this script does")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            
            Text(script.description)
                .font(.body)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(nil)
        }
        .padding()
        .background(Color.blue.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Script Output View

struct ScriptOutputView: View {
    let script: ScriptItem
    @ObservedObject var viewModel: ScriptManagerViewModel
    @State private var showingAIFixer = false
    @State private var aiFixRequest = ""
    @State private var isFixingScript = false
    @StateObject private var ollamaService = OllamaScriptGenerationService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            // Output header
            HStack {
                Text("Output")
                    .font(.headline)
                
                Spacer()
                
                if script.isRunning {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Running...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .border(Color(NSColor.separatorColor), width: 0.5)
            
            // AI Script Fixer Section (shown when script has failed)
            if script.hasError && !script.isRunning {
                aiScriptFixerSection
            }
            
            // Live output display
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if script.output.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "terminal")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("No output yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Run the script to see output here")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 50)
                        } else {
                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(outputLines, id: \.offset) { line in
                                    Text(line.element.isEmpty ? " " : line.element)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(line.element.hasPrefix("STDERR:") ? .red : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(line.offset)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.textBackgroundColor))
                .onChange(of: script.output) {
                    // Auto-scroll to bottom when new output appears
                    if !outputLines.isEmpty {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo(outputLines.count - 1, anchor: .bottom)
                        }
                    }
                }
                .onAppear {
                    // Scroll to bottom when view appears
                    if !outputLines.isEmpty {
                        proxy.scrollTo(outputLines.count - 1, anchor: .bottom)
                    }
                }
            }
        }
        .background(Color(NSColor.textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
        .sheet(isPresented: $showingAIFixer) {
            AIScriptFixerSheet(
                script: script,
                aiFixRequest: $aiFixRequest,
                isPresented: $showingAIFixer,
                viewModel: viewModel
            )
        }
    }
    
    // MARK: - AI Script Fixer Section
    
    private var aiScriptFixerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("Script Failed - AI Assistant Available")
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                if isFixingScript {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            // Error summary
            if let exitCode = script.exitCode, exitCode != 0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Exit Code: \(exitCode)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            
            // Quick fix and detailed fix options
            HStack(spacing: 12) {
                Button(action: quickFixScript) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                        Text("Quick Fix")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isFixingScript)
                
                Button(action: { showingAIFixer = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                        Text("Detailed Fix")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isFixingScript)
                
                Spacer()
                
                Text("AI can analyze the error and suggest fixes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
    
    // MARK: - Helper Methods
    
    private func quickFixScript() {
        isFixingScript = true
        
        Task {
            do {
                // Create a quick fix request based on the error
                let errorAnalysis = analyzeScriptError()
                let fixRequest = "Fix this script error: \(errorAnalysis). Script failed with exit code \(script.exitCode ?? -1). Output: \(script.output.suffix(500))"
                
                let fixedScript = try await ollamaService.generateDiagnosticScript(for: fixRequest)
                
                await MainActor.run {
                    // Update the existing script using the passed view model
                    viewModel.updateScript(script, name: "Fixed: \(script.name)", content: fixedScript.content)
                    isFixingScript = false
                }
                
            } catch {
                await MainActor.run {
                    print("Quick fix failed: \(error.localizedDescription)")
                    
                    // If Ollama is not available, provide a basic fallback fix
                    if error.localizedDescription.contains("Connection refused") || error.localizedDescription.contains("11434") {
                        let fallbackFix = generateFallbackFix()
                        viewModel.updateScript(script, name: "Fixed: \(script.name)", content: fallbackFix)
                    }
                    
                    isFixingScript = false
                }
            }
        }
    }
    
    private func findScriptManager() -> ScriptManagerViewModel? {
        // No longer needed since we pass the view model directly
        return viewModel
    }
    
    private func generateFallbackFix() -> String {
        let errorAnalysis = analyzeScriptError()
        
        var fixedScript = script.content
        
        // Apply basic fixes based on error analysis
        if errorAnalysis.contains("command not found") {
            // Add PATH setup
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Enhanced PATH for common tools
            export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
            
            # Check if command exists before running
            command_exists() {
                command -v "$1" >/dev/null 2>&1
            }
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            """
        } else if errorAnalysis.contains("permission denied") {
            // Add permission fixes
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Fix common permission issues
            # Make sure we have write permissions where needed
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            """
        } else {
            // Generic error handling improvement
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Enhanced error handling
            trap 'echo "Error on line $LINENO. Exit code: $?" >&2' ERR
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            """
        }
        
        return fixedScript
    }
    
    private func analyzeScriptError() -> String {
        let output = script.output.lowercased()
        let exitCode = script.exitCode ?? -1
        
        // Analyze common error patterns
        if output.contains("command not found") {
            return "Command not found error - missing executable or PATH issue"
        } else if output.contains("permission denied") {
            return "Permission denied error - need to fix file permissions"
        } else if output.contains("no such file or directory") {
            return "File not found error - missing file or incorrect path"
        } else if output.contains("network") || output.contains("connection") {
            return "Network connectivity issue"
        } else if exitCode == 127 {
            return "Command not found (exit code 127)"
        } else if exitCode == 126 {
            return "Permission denied (exit code 126)"
        } else if exitCode == 2 {
            return "General error (exit code 2)"
        } else {
            return "Script execution failed with exit code \(exitCode)"
        }
    }
    
    private var outputLines: [(offset: Int, element: String)] {
        Array(script.output.components(separatedBy: .newlines).enumerated())
    }
}

// MARK: - Script Editor Sheet

struct ScriptEditorSheet: View {
    @ObservedObject var viewModel: ScriptManagerViewModel
    @Binding var isPresented: Bool
    var editingScript: ScriptItem?
    
    @State private var scriptName: String = ""
    @State private var scriptDescription: String = ""
    @State private var scriptContent: String = ""
    @State private var showingDeleteConfirmation = false
    
    // Ollama integration states
    @State private var ollamaRequest: String = ""
    @State private var isGeneratingScript = false
    @State private var showingOllamaArea = true
    @StateObject private var ollamaService = OllamaScriptGenerationService.shared
    
    var isEditing: Bool { editingScript != nil }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Script name section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Script Name")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Enter a descriptive name for your script", text: $scriptName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                // Script description section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description (Optional)")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    TextField("Briefly describe what this script does", text: $scriptDescription)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }
                
                // Toggle between Ollama and manual editing
                Picker("Creation Method", selection: $showingOllamaArea) {
                    Text("AI Assistant").tag(true)
                    Text("Manual Editing").tag(false)
                }
                .pickerStyle(.segmented)
                
                if showingOllamaArea {
                    // Ollama-powered script customization area
                    ollamaScriptCustomizationArea
                } else {
                    // Manual script editing area
                    manualScriptEditingArea
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(isEditing ? "Edit Script" : "New Script")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Create") {
                        saveScript()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(scriptName.isEmpty || scriptContent.isEmpty)
                }
                
                if isEditing {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Delete", role: .destructive) {
                            showingDeleteConfirmation = true
                        }
                    }
                }
            }
        }
        .frame(width: 700, height: 600)
        .onAppear {
            if let script = editingScript {
                scriptName = script.name
                scriptDescription = script.description
                scriptContent = script.content
                showingOllamaArea = false // Default to manual editing for existing scripts
                ollamaRequest = "" // Clear any previous AI request
            } else {
                scriptName = ""
                scriptDescription = ""
                scriptContent = "#!/bin/bash\n\necho \"Hello from Huginn Script Manager!\"\n"
                ollamaRequest = ""
                showingOllamaArea = true // Default to AI for new scripts
            }
        }
        .alert("Delete Script", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                if let script = editingScript {
                    viewModel.deleteScript(script)
                    isPresented = false
                }
            }
        } message: {
            Text("Are you sure you want to delete this script? This action cannot be undone.")
        }
    }
    
    // MARK: - Ollama Script Customization Area
    
    private var ollamaScriptCustomizationArea: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "brain.head.profile")
                        .foregroundColor(.blue)
                        .font(.title2)
                    Text("AI Script Assistant")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    if ollamaService.isGenerating {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                Text(isEditing ? "Describe changes you want to make to this script, and I'll help update it." : "Describe what you want your script to do, and I'll create it for you.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Request input area
            VStack(alignment: .leading, spacing: 8) {
                Text(isEditing ? "What changes do you want to make?" : "What should this script do?")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                TextEditor(text: $ollamaRequest)
                    .font(.body)
                    .frame(minHeight: 80)
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                    .overlay(
                        Group {
                            if ollamaRequest.isEmpty {
                                VStack {
                                    HStack {
                                        Text(isEditing ? 
                                             "Examples:\n• Add error handling and logging\n• Make it work on both Intel and Apple Silicon\n• Add a progress indicator\n• Include cleanup after installation" :
                                             "Examples:\n• Install Docker and set it up\n• Clean up old log files\n• Check system health and performance\n• Download and install VS Code")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.leading, 12)
                                            .padding(.top, 12)
                                        Spacer()
                                    }
                                    Spacer()
                                }
                            }
                        }
                    )
            }
            
            // Generate button
            HStack {
                Spacer()
                
                Button(action: generateScript) {
                    HStack(spacing: 8) {
                        if isGeneratingScript {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text(isGeneratingScript ? "Generating..." : (isEditing ? "Update Script" : "Generate Script"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(ollamaRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingScript)
                
                if !scriptContent.isEmpty && scriptContent != "#!/bin/bash\n\necho \"Hello from Huginn Script Manager!\"\n" {
                    Button(isEditing ? "Regenerate Changes" : "Regenerate") {
                        generateScript()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isGeneratingScript)
                }
            }
            
            // Generated script preview
            if !scriptContent.isEmpty && scriptContent != "#!/bin/bash\n\necho \"Hello from Huginn Script Manager!\"\n" {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Generated Script")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Button("Edit Manually") {
                            showingOllamaArea = false
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    
                    ScrollView {
                        Text(scriptContent)
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                            )
                    }
                    .frame(maxHeight: 150)
                }
            }
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    
    // MARK: - Manual Script Editing Area
    
    private var manualScriptEditingArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Script Content")
                    .font(.headline)
                
                Spacer()
                
                Button("Use AI Assistant") {
                    showingOllamaArea = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            
            TextEditor(text: $scriptContent)
                .font(.system(.body, design: .monospaced))
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            
            Text("Use bash syntax. The script will be executed with /bin/bash.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateScript() {
        guard !ollamaRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        isGeneratingScript = true
        
        Task {
            do {
                // Determine the type of script based on the request
                let request = ollamaRequest.trimmingCharacters(in: .whitespacesAndNewlines)
                let generatedScript: GeneratedScript
                
                if ollamaService.detectInstallationIntent(in: request) != nil {
                    generatedScript = try await ollamaService.generateInstallationScript(for: request)
                } else if ollamaService.detectMaintenanceIntent(in: request) != nil {
                    generatedScript = try await ollamaService.generateMaintenanceScript(for: request)
                } else {
                    generatedScript = try await ollamaService.generateDiagnosticScript(for: request)
                }
                
                await MainActor.run {
                    scriptContent = generatedScript.content
                    if scriptName.isEmpty {
                        scriptName = generatedScript.name
                    }
                    isGeneratingScript = false
                }
                
            } catch {
                await MainActor.run {
                    // Handle error - could show an alert or generate a fallback
                    print("Script generation failed: \(error.localizedDescription)")
                    isGeneratingScript = false
                }
            }
        }
    }
    
    private func saveScript() {
        if let script = editingScript {
            viewModel.updateScript(script, name: scriptName, content: scriptContent, description: scriptDescription)
        } else {
            viewModel.createScript(name: scriptName, content: scriptContent, description: scriptDescription)
        }
        isPresented = false
    }
}

// MARK: - AI Script Fixer Sheet

struct AIScriptFixerSheet: View {
    let script: ScriptItem
    @Binding var aiFixRequest: String
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: ScriptManagerViewModel
    
    @State private var isGeneratingFix = false
    @State private var fixedScriptContent = ""
    @State private var showingFixedScript = false
    @StateObject private var ollamaService = OllamaScriptGenerationService.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "brain.head.profile")
                            .foregroundColor(.blue)
                            .font(.title2)
                        Text("AI Script Fixer")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Spacer()
                        if isGeneratingFix {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    
                    Text("The AI has access to your script content, output, and error information to provide targeted fixes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Error Information Display
                VStack(alignment: .leading, spacing: 12) {
                    Text("Error Information")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Script:")
                                .fontWeight(.medium)
                            Text(script.name)
                                .foregroundColor(.secondary)
                            Spacer()
                            if let exitCode = script.exitCode {
                                Label("Exit Code: \(exitCode)", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        
                        DisclosureGroup("Script Output (Last 1000 characters)") {
                            ScrollView {
                                Text(String(script.output.suffix(1000)))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(8)
                                    .background(Color(NSColor.controlBackgroundColor))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                    )
                            }
                            .frame(maxHeight: 150)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
                
                // Fix Request Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Describe the fix you need")
                        .font(.headline)
                    
                    TextEditor(text: $aiFixRequest)
                        .font(.body)
                        .frame(minHeight: 100)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .overlay(
                            Group {
                                if aiFixRequest.isEmpty {
                                    VStack {
                                        HStack {
                                            Text("Examples:\n• Fix the permission error\n• Make it work on Apple Silicon\n• Add better error handling\n• Fix the PATH issue")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                                .padding(.leading, 12)
                                                .padding(.top, 12)
                                            Spacer()
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        )
                }
                
                // Generate Fix Button
                HStack {
                    Spacer()
                    
                    Button(action: generateFix) {
                        HStack(spacing: 8) {
                            if isGeneratingFix {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGeneratingFix ? "Analyzing & Fixing..." : "Generate Fix")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(aiFixRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGeneratingFix)
                }
                
                // Fixed Script Preview
                if showingFixedScript && !fixedScriptContent.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fixed Script")
                                .font(.headline)
                            Spacer()
                            Button("Save as New Script") {
                                saveFixedScript()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        
                        ScrollView {
                            Text(fixedScriptContent)
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                                )
                        }
                        .frame(maxHeight: 200)
                    }
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Fix Script")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                }
            }
        }
        .frame(width: 600, height: 700)
        .onAppear {
            // Pre-populate with intelligent fix request based on error analysis
            if aiFixRequest.isEmpty {
                aiFixRequest = generateInitialFixRequest()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func generateFix() {
        isGeneratingFix = true
        
        Task {
            do {
                // Create comprehensive fix request with all available information
                let comprehensiveRequest = """
                SCRIPT TO FIX:
                \(script.content)
                
                ERROR INFORMATION:
                - Exit Code: \(script.exitCode ?? -1)
                - Output: \(script.output)
                
                USER REQUEST:
                \(aiFixRequest)
                
                Please provide a fixed version of this script that addresses the error and user requirements.
                """
                
                let fixedScript = try await ollamaService.generateDiagnosticScript(for: comprehensiveRequest)
                
                await MainActor.run {
                    fixedScriptContent = fixedScript.content
                    showingFixedScript = true
                    isGeneratingFix = false
                }
                
            } catch {
                await MainActor.run {
                    print("Fix generation failed: \(error.localizedDescription)")
                    
                    // If Ollama is not available, provide a fallback fix
                    if error.localizedDescription.contains("Connection refused") || error.localizedDescription.contains("11434") {
                        fixedScriptContent = generateDetailedFallbackFix()
                        showingFixedScript = true
                    }
                    
                    isGeneratingFix = false
                }
            }
        }
    }
    
    private func saveFixedScript() {
        // Update the existing script using the passed view model
        viewModel.updateScript(script, name: "Fixed: \(script.name)", content: fixedScriptContent)
        isPresented = false
    }
    
    private func generateDetailedFallbackFix() -> String {
        let output = script.output.lowercased()
        let userRequest = aiFixRequest.lowercased()
        
        var fixedScript = script.content
        
        // Apply fixes based on user request and error analysis
        if userRequest.contains("permission") || output.contains("permission denied") {
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Enhanced permission handling
            # Check and fix permissions as needed
            
            echo "Checking permissions..."
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            
            echo "Script completed successfully"
            """
        } else if userRequest.contains("path") || output.contains("command not found") {
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Enhanced PATH setup for macOS
            export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:$PATH"
            
            # Function to check if command exists
            command_exists() {
                command -v "$1" >/dev/null 2>&1
            }
            
            echo "PATH setup complete: $PATH"
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            """
        } else if userRequest.contains("error handling") || userRequest.contains("logging") {
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Enhanced error handling and logging
            trap 'echo "Error on line $LINENO. Exit code: $?" >&2; exit 1' ERR
            
            # Logging function
            log() {
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
            }
            
            log "Script started"
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            
            log "Script completed successfully"
            """
        } else {
            // Generic improvement
            fixedScript = """
            #!/bin/bash
            set -e
            
            # Improved script with better error handling
            trap 'echo "Error occurred. Check the output above." >&2' ERR
            
            echo "Starting improved script..."
            
            \(script.content.replacingOccurrences(of: "#!/bin/bash", with: ""))
            
            echo "Script completed successfully"
            """
        }
        
        return fixedScript
    }
    
    private func generateInitialFixRequest() -> String {
        let output = script.output.lowercased()
        let exitCode = script.exitCode ?? -1
        
        // Generate intelligent initial request based on error patterns
        if output.contains("command not found") {
            return "Fix the 'command not found' error by ensuring the required commands are available or installing missing dependencies"
        } else if output.contains("permission denied") {
            return "Fix the permission denied error by adding proper file permissions or using sudo where appropriate"
        } else if output.contains("no such file or directory") {
            return "Fix the file not found error by correcting file paths or creating missing directories"
        } else if exitCode == 127 {
            return "Fix the command not found error (exit code 127) by checking PATH or installing missing tools"
        } else if exitCode == 126 {
            return "Fix the permission denied error (exit code 126) by making the script executable or adjusting permissions"
        } else {
            return "Analyze the error and provide a working version of this script"
        }
    }
}

// MARK: - Previews

#Preview("Script Manager") {
    ScriptManagerView()
        .frame(width: 1200, height: 800)
}

#Preview("Script List") {
    NavigationSplitView {
        ScriptListView(
            viewModel: ScriptManagerViewModel(),
            showingAddScript: .constant(false),
            showingEditScript: .constant(false),
            scriptToEdit: .constant(nil)
        )
    } detail: {
        Text("Select a script")
    }
    .frame(width: 800, height: 600)
}

#Preview("Script Editor") {
    ScriptEditorSheet(
        viewModel: ScriptManagerViewModel(),
        isPresented: .constant(true)
    )
} 