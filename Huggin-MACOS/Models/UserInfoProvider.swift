import Foundation
import Combine

struct UserInfo: Sendable {
    let fullName: String
    let role: String
    let organization: String?
}

@MainActor
class UserInfoProvider: ObservableObject, @unchecked Sendable {
    @Published var userInfo: UserInfo
    
    init() {
        let fullName = NSFullUserName().isEmpty ? "User" : NSFullUserName()
        let role = "Admin" // You can make this dynamic if needed
        let organization: String? = nil // Set if you have org info
        self.userInfo = UserInfo(fullName: fullName, role: role, organization: organization)
    }
} 