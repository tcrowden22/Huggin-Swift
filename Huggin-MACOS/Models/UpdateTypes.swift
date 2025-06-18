import Foundation

public struct UpdateItem: Identifiable {
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let size: Int64
    public var isInstalled: Bool
    public var isSelected: Bool
    
    public init(id: String, name: String, version: String, description: String, size: Int64, isInstalled: Bool, isSelected: Bool) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.size = size
        self.isInstalled = isInstalled
        self.isSelected = isSelected
    }
}

public struct SoftwareUpdate: Identifiable, Sendable {
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