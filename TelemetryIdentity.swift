import Foundation
import Security

struct TelemetryConsent: Codable {
    static let currentVersion = "central-gameplay-and-history-v2"
    var status: String
    var version: String
    var effectiveAt: Date?
    static var supplied: TelemetryConsent? {
        guard let data = UserDefaults.standard.data(forKey: "difficulty.telemetry.consent") else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
    static func set(status: String, version: String = currentVersion, now: Date = Date()) throws {
        let value = Self(status: status, version: version, effectiveAt: now)
        UserDefaults.standard.set(try JSONEncoder().encode(value), forKey: "difficulty.telemetry.consent")
    }
}

/// Keychain values contain only this app's random identity and collector credential.
struct TelemetryIdentity: Codable {
    var installationID: UUID
    var credential: String?
    var enrollmentKey: String?
    static func load() throws -> Self {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.philipp.zipgame.telemetry", kSecAttrAccount as String: "installation",
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try JSONDecoder().decode(Self.self, from: data) }
        guard status == errSecItemNotFound else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
        let identity = Self(installationID: UUID(), credential: nil, enrollmentKey: UUID().uuidString + UUID().uuidString)
        try identity.save(); return identity
    }
    func save() throws {
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "local.philipp.zipgame.telemetry", kSecAttrAccount as String: "installation"]
        let data = try JSONEncoder().encode(self)
        var status = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var attributes = key; attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(attributes as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }
}
