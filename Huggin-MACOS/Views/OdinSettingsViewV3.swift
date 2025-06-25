import SwiftUI

/// ODIN Settings View using simplified serial number authentication
struct OdinSettingsViewV3: View {
    
    // MARK: - Dependencies
    @StateObject private var agentService = OdinAgentServiceV3.shared
    
    // MARK: - UI State
    @State private var enrollmentToken: String = ""
    @State private var isEnrolling: Bool = false
    @State private var showingAlert: Bool = false
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showingResetConfirmation: Bool = false
    @State private var showingDeviceDataModal: Bool = false
    @State private var deviceDataStatus = DeviceDataStatus()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                StatusSection(agentService: agentService)
                EnrollmentSection(
                    agentService: agentService,
                    enrollmentToken: $enrollmentToken,
                    isEnrolling: $isEnrolling,
                    showingAlert: $showingAlert,
                    alertTitle: $alertTitle,
                    alertMessage: $alertMessage
                )
                ManagementSection(
                    agentService: agentService,
                    showingResetConfirmation: $showingResetConfirmation,
                    showingAlert: $showingAlert,
                    alertTitle: $alertTitle,
                    alertMessage: $alertMessage,
                    showingDeviceDataModal: $showingDeviceDataModal,
                    deviceDataStatus: $deviceDataStatus
                )
                ActivitySection(agentService: agentService)
            }
            .padding()
        }
        .background(Color(NSColor.windowBackgroundColor))
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .alert("Reset Agent", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                Task {
                    await agentService.resetAgent()
                }
            }
        } message: {
            Text("This will clear the agent enrollment and stop all background services. Are you sure?")
        }
        .sheet(isPresented: $showingDeviceDataModal) {
            DeviceDataModal(status: $deviceDataStatus)
        }
        .onAppear {
            // Start the agent service when view appears
            Task {
                await agentService.checkEnrollmentStatus()
            }
        }
        .task {
            // Ensure service is started and configured
            await agentService.checkEnrollmentStatus()
        }
    }
}

// MARK: - Device Data Status Model

struct DeviceDataStatus {
    var isRunning = false
    var currentStep = ""
    var progress = 0.0
    var logs: [String] = []
    var isComplete = false
    var success = false
    var errorMessage = ""
    
    mutating func addLog(_ message: String) {
        logs.append("\(Date().formatted(date: .omitted, time: .standard)): \(message)")
        if logs.count > 50 {
            logs.removeFirst()
        }
    }
    
    mutating func reset() {
        isRunning = false
        currentStep = ""
        progress = 0.0
        logs.removeAll()
        isComplete = false
        success = false
        errorMessage = ""
    }
}

// MARK: - Device Data Modal

struct DeviceDataModal: View {
    @Binding var status: DeviceDataStatus
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Image(systemName: "laptopcomputer")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Device Data Collection")
                    .font(.title2)
                    .bold()
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            }
            
            // Status Section
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if status.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Collecting device data...")
                            .font(.headline)
                            .foregroundColor(.blue)
                    } else if status.isComplete {
                        Image(systemName: status.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(status.success ? .green : .red)
                        Text(status.success ? "Device data sent successfully" : "Failed to send device data")
                            .font(.headline)
                            .foregroundColor(status.success ? .green : .red)
                    } else {
                        Text("Ready to collect device data")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !status.currentStep.isEmpty {
                    Text(status.currentStep)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if status.isRunning {
                    ProgressView(value: status.progress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            // Logs Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Collection Logs")
                    .font(.headline)
                
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if status.logs.isEmpty {
                            Text("No logs yet...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            ForEach(status.logs, id: \.self) { log in
                                Text(log)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 1)
                            }
                        }
                    }
                }
                .frame(maxHeight: 300)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
            
            // Error Section
            if !status.errorMessage.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error Details")
                        .font(.headline)
                        .foregroundColor(.red)
                    
                    Text(status.errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            
            Spacer()
            
            // Action Buttons
            HStack {
                Button("Close") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                
                if !status.isRunning && !status.isComplete {
                    Button("Start Collection") {
                        startDeviceDataCollection()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func startDeviceDataCollection() {
        status.reset()
        status.isRunning = true
        status.addLog("Starting device data collection...")
        
        Task {
            await OdinAgentServiceV3.shared.sendDeviceDataWithStatus { step, progress in
                Task { @MainActor in
                    status.currentStep = step
                    status.progress = progress
                    status.addLog(step)
                }
            } completion: { success, error in
                Task { @MainActor in
                    status.isRunning = false
                    status.isComplete = true
                    status.success = success
                    if let error = error {
                        status.errorMessage = error.localizedDescription
                        status.addLog("Error: \(error.localizedDescription)")
                    } else {
                        status.addLog("Device data collection completed successfully")
                    }
                }
            }
        }
    }
}

// MARK: - Agent Status Section

struct StatusSection: View {
    @ObservedObject var agentService: OdinAgentServiceV3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Status")
                .font(.headline)
                .foregroundColor(.primary)
            
            HStack {
                // Connection Status
                HStack {
                    Image(systemName: agentService.connectionStatus.icon)
                        .foregroundColor(getStatusColor(agentService.connectionStatus))
                    
                    Text(agentService.connectionStatus.rawValue)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                // Serial Number Info
                let status = agentService.getAgentStatus()
                if status.enrolled, let serialNumber = status.serialNumber {
                    VStack(alignment: .trailing) {
                        Text("Serial: \(String(serialNumber.suffix(8)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Enrolled \(status.daysSinceEnrollment) days ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Health Status
            if agentService.connectionStatus == .authenticated {
                HStack {
                    Image(systemName: "heart.fill")
                        .foregroundColor(getHealthColor(agentService.agentHealth.isHealthy))
                    
                    Text("Health: \(agentService.agentHealth.healthStatus)")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    VStack(alignment: .trailing) {
                        Text("Uptime: \(agentService.agentHealth.uptime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Last Activity: \(agentService.lastActivity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Tasks Status
            if agentService.taskCount > 0 {
                HStack {
                    Image(systemName: "list.bullet")
                        .foregroundColor(.orange)
                    
                    Text("\(agentService.taskCount) pending tasks")
                        .fontWeight(.medium)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Enrollment Section

struct EnrollmentSection: View {
    @ObservedObject var agentService: OdinAgentServiceV3
    @Binding var enrollmentToken: String
    @Binding var isEnrolling: Bool
    @Binding var showingAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertMessage: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Enrollment")
                .font(.headline)
                .foregroundColor(.primary)
            
            let status = agentService.getAgentStatus()
            
            if !status.enrolled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Enter the enrollment token from your ODIN console:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    HStack {
                        SecureField("Enrollment Token", text: $enrollmentToken)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        Button(action: enrollAgent) {
                            if isEnrolling {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Enrolling...")
                                }
                            } else {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Enroll")
                                }
                            }
                        }
                        .disabled(enrollmentToken.isEmpty || isEnrolling)
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Text("💡 The enrollment token is provided by your administrator in the ODIN console.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Text("Agent is enrolled and ready")
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    if let serialNumber = status.serialNumber {
                        Text("Serial: \(serialNumber)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func enrollAgent() {
        guard !enrollmentToken.isEmpty else { return }
        
        isEnrolling = true
        
        Task {
            let success = await agentService.enrollAgent(with: enrollmentToken)
            
            await MainActor.run {
                isEnrolling = false
                
                if success {
                    alertTitle = "Enrollment Successful"
                    alertMessage = "Agent has been enrolled successfully and background services are now running."
                    enrollmentToken = ""
                } else {
                    alertTitle = "Enrollment Failed"
                    alertMessage = "Failed to enroll agent. Please check your token and try again."
                }
                
                showingAlert = true
            }
        }
    }
}

// MARK: - Management Section

struct ManagementSection: View {
    @ObservedObject var agentService: OdinAgentServiceV3
    @Binding var showingResetConfirmation: Bool
    @Binding var showingAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertMessage: String
    @Binding var showingDeviceDataModal: Bool
    @Binding var deviceDataStatus: DeviceDataStatus
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent Management")
                .font(.headline)
                .foregroundColor(.primary)
            
            let status = agentService.getAgentStatus()
            
            HStack {
                // Manual Check-in
                Button(action: performCheckIn) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Check In")
                    }
                }
                .disabled(!status.enrolled)
                .buttonStyle(.bordered)
                
                // Send Telemetry
                Button(action: sendTelemetry) {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Send Telemetry")
                    }
                }
                .disabled(!status.enrolled)
                .buttonStyle(.bordered)
                
                // Send Device Data
                Button(action: { showingDeviceDataModal = true }) {
                    HStack {
                        Image(systemName: "laptopcomputer")
                        Text("Send Device Data")
                    }
                }
                .disabled(!status.enrolled)
                .buttonStyle(.bordered)
                
                Spacer()
                
                // Reset Agent
                Button(action: { showingResetConfirmation = true }) {
                    HStack {
                        Image(systemName: "trash")
                        Text("Reset")
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            // Information
            Text("🔄 Check In: Manually check for new tasks")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("📡 Send Telemetry: Manually send system information")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("💻 Send Device Data: Manually send comprehensive device data")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("🗑️ Reset: Clear enrollment and stop services")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
    
    private func performCheckIn() {
        Task {
            await agentService.performCheckIn()
            
            await MainActor.run {
                alertTitle = "Check-in Complete"
                alertMessage = "Agent check-in completed successfully."
                showingAlert = true
            }
        }
    }
    
    private func sendTelemetry() {
        Task {
            await agentService.sendTelemetry()
            
            await MainActor.run {
                alertTitle = "Telemetry Sent"
                alertMessage = "System telemetry has been sent to ODIN."
                showingAlert = true
            }
        }
    }
}

// MARK: - Activity Section

struct ActivitySection: View {
    @ObservedObject var agentService: OdinAgentServiceV3
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
                .foregroundColor(.primary)
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if agentService.recentNotifications.isEmpty {
                        Text("No recent activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(agentService.recentNotifications) { notification in
                            Text(notification.formattedString)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.vertical, 1)
                        }
                    }
                }
            }
            .frame(maxHeight: 150)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

// MARK: - Preview

// MARK: - Helper Functions

func getStatusColor(_ status: OdinAgentServiceV3.ConnectionStatus) -> Color {
    switch status {
    case .disconnected: return .secondary
    case .connecting: return .blue
    case .connected: return .green
    case .authenticated: return .green
    case .error: return .red
    }
}

func getHealthColor(_ isHealthy: Bool) -> Color {
    return isHealthy ? .green : .orange
}

struct OdinSettingsViewV3_Previews: PreviewProvider {
    static var previews: some View {
        OdinSettingsViewV3()
            .frame(width: 600, height: 800)
    }
} 