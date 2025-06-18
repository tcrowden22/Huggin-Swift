import SwiftUI

struct StatusCard: View {
    let title: String
    let value: Double
    let unit: String
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(String(format: "%.1f%@", value, unit))
                .font(.title2)
                .bold()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct SystemInfoCard: View {
    @ObservedObject var systemInfo: SystemInfoProvider
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Information")
                .font(.headline)
            
            Text(systemInfo.systemSummary)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct ActiveAlertsCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Active Alerts")
                .font(.headline)
            
            Text("No active alerts")
                .font(.body)
                .foregroundColor(.secondary)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.windowBackgroundColor))
                .cornerRadius(10)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let icon: String
    let color: Color
    let progress: Double
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(value)
                .font(.title2)
                .bold()
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
            
            ProgressView(value: progress)
                .tint(color)
        }
        .padding()
        .background(Color(.windowBackgroundColor))
        .cornerRadius(12)
    }
}

#Preview {
    VStack {
        StatusCard(title: "CPU", value: 45.5, unit: "%")
        SystemInfoCard(systemInfo: SystemInfoProvider())
        ActiveAlertsCard()
        MetricCard(
            title: "CPU Usage",
            value: "45.5%",
            subtitle: "4 cores active",
            icon: "cpu",
            color: .blue,
            progress: 0.455
        )
    }
    .padding()
} 