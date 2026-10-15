import Foundation
import Security

/// Session token in the Keychain, shared with the widget and the notification
/// extension through a keychain access group. Readable after the first unlock,
/// which is what lets the lock-screen rating work while the phone stays locked.
enum TokenStore {
    private static let service = "locket.session"
    private static let account = "token"

    static var token: String? {
        get { read(group: sharedGroup) ?? read(group: nil) }
        set {
            delete(group: sharedGroup)
            delete(group: nil)
            guard let newValue else { return }
            if !save(newValue, group: sharedGroup) {
                // Fallback when keychain sharing isn't available (e.g. unsigned simulator builds).
                _ = save(newValue, group: nil)
            }
        }
    }

    private static var sharedGroup: String? {
        AppConfig.keychainGroup.isEmpty ? nil : AppConfig.keychainGroup
    }

    private static func query(group: String?) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        if let group { query[kSecAttrAccessGroup as String] = group }
        return query
    }

    private static func read(group: String?) -> String? {
        var query = query(group: group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func save(_ token: String, group: String?) -> Bool {
        var query = query(group: group)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func delete(group: String?) {
        SecItemDelete(query(group: group) as CFDictionary)
    }
}
