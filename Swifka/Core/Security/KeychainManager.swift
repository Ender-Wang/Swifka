import Foundation
import Security

/// macOS Keychain storage for cluster SASL passwords (PLAIN/SCRAM).
///
/// Usernames, Kerberos principals, and keytab/krb5 paths live in `ClusterConfig` JSON — they are
/// identity or file references, not secrets. GSSAPI credentials remain in the keytab file on disk.
enum KeychainManager {
    static func save(password: String, for clusterId: UUID) throws {
        let data = Data(password.utf8)
        let account = clusterId.uuidString

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SwifkaError.keychainError("Failed to save password: \(status)")
        }
    }

    static func loadPassword(for clusterId: UUID) -> String? {
        let account = clusterId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for clusterId: UUID) {
        let account = clusterId.uuidString

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.keychainService,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}
