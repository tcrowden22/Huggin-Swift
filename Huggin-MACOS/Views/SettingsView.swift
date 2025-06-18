import SwiftUI

struct SettingsView: View {
    let userInfo: UserInfo
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Settings")
                    .font(.title)
                    .bold()
                Spacer()
                Button("Close") { dismiss() }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("User: ")
                    .font(.headline)
                Text(userInfo.fullName)
                    .font(.body)
                Text("Role: ")
                    .font(.headline)
                Text(userInfo.role)
                    .font(.body)
                if let org = userInfo.organization {
                    Text("Organization: ")
                        .font(.headline)
                    Text(org)
                        .font(.body)
                }
            }
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 250)
    }
} 