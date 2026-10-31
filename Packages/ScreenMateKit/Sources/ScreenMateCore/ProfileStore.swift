import Foundation
import Security

/// JSON file of saved Macs. Contains no secrets.
public struct ProfileFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// `Application Support/ScreenMate/profiles.json` in the app container.
    public static func standard() throws -> ProfileFile {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return ProfileFile(url: base
            .appendingPathComponent("ScreenMate", isDirectory: true)
            .appendingPathComponent("profiles.json"))
    }

    /// Saved profiles; `nil` when nothing was ever saved (first launch).
    public func load() throws -> [ConnectionProfile]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode([ConnectionProfile].self, from: data)
    }

    public func save(_ profiles: [ConnectionProfile]) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try Self.encoder.encode(profiles)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// Where optional saved passwords live.
public protocol PasswordStore: Sendable {
    func password(for profileID: UUID) throws -> String?
    func setPassword(_ password: String, for profileID: UUID) throws
    func removePassword(for profileID: UUID) throws
}

public struct PasswordStoreError: Error, Equatable, Sendable {
    public let status: OSStatus
}

/// iOS Keychain generic passwords, readable only while this device is
/// unlocked and never migrated to another device or backup.
public struct KeychainPasswordStore: PasswordStore {
    public let service: String

    public init(service: String = "ScreenMate.mac-account") {
        self.service = service
    }

    private func baseQuery(_ profileID: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileID.uuidString,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    public func password(for profileID: UUID) throws -> String? {
        var query = baseQuery(profileID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw PasswordStoreError(status: status)
        }
        return String(data: data, encoding: .utf8)
    }

    public func setPassword(_ password: String, for profileID: UUID) throws {
        let data = Data(password.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(baseQuery(profileID) as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw PasswordStoreError(status: status) }
        var add = baseQuery(profileID)
        add.merge(update) { $1 }
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw PasswordStoreError(status: addStatus) }
    }

    public func removePassword(for profileID: UUID) throws {
        let status = SecItemDelete(baseQuery(profileID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw PasswordStoreError(status: status)
        }
    }
}

/// Test and preview stand-in.
public final class InMemoryPasswordStore: PasswordStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [UUID: String] = [:]

    public init() {}

    public func password(for profileID: UUID) throws -> String? {
        lock.withLock { storage[profileID] }
    }

    public func setPassword(_ password: String, for profileID: UUID) throws {
        lock.withLock { storage[profileID] = password }
    }

    public func removePassword(for profileID: UUID) throws {
        lock.withLock { _ = storage.removeValue(forKey: profileID) }
    }
}
