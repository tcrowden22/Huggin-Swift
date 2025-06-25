import Foundation

public struct HuginnHomebrewUpdate: Identifiable, Hashable {
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
    
    public static func == (lhs: HuginnHomebrewUpdate, rhs: HuginnHomebrewUpdate) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct HuginnAppStoreUpdate: Identifiable, Hashable {
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
    
    public static func == (lhs: HuginnAppStoreUpdate, rhs: HuginnAppStoreUpdate) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct HuginnSoftwareUpdate: Identifiable {
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