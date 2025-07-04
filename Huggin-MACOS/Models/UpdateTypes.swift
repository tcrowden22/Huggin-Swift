import Foundation

public struct HomebrewUpdate: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let currentVersion: String
    public let newVersion: String
    public let size: Int64
    
    public init(name: String, currentVersion: String, newVersion: String, size: Int64 = 0) {
        self.id = name
        self.name = name
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.size = size
    }
    
    public static func == (lhs: HomebrewUpdate, rhs: HomebrewUpdate) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct AppStoreUpdate: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let currentVersion: String
    public let newVersion: String
    public let size: Int64
    
    public init(name: String, currentVersion: String, newVersion: String, size: Int64 = 0) {
        self.id = name
        self.name = name
        self.currentVersion = currentVersion
        self.newVersion = newVersion
        self.size = size
    }
    
    public static func == (lhs: AppStoreUpdate, rhs: AppStoreUpdate) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct SoftwareUpdate: Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let size: Int64
    public let isInstalled: Bool
    
    public init(id: String, name: String, version: String, description: String, size: Int64, isInstalled: Bool) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.size = size
        self.isInstalled = isInstalled
    }
}

public struct SoftwareItem: Identifiable {
    public let id = UUID()
    public let name: String
    public let version: String
    public let path: String
    public let isSystem: Bool
    
    public init(name: String, version: String, path: String, isSystem: Bool) {
        self.name = name
        self.version = version
        self.path = path
        self.isSystem = isSystem
    }
} 