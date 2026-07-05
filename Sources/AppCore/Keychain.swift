import Foundation
import Security

/// Minimal Keychain wrapper for service credentials (generic passwords).
/// Sandboxed app → items are scoped to this app; no user prompts.
public enum Keychain {
    private static func query(_ service: String, _ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public static func get(service: String, account: String) -> String? {
        var q = query(service, account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func set(_ value: String, service: String, account: String) -> Bool {
        guard !value.isEmpty else { delete(service: service, account: account); return true }
        let data = Data(value.utf8)
        var status = SecItemUpdate(query(service, account) as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(service, account)
            q[kSecValueData as String] = data
            status = SecItemAdd(q as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    public static func delete(service: String, account: String) {
        SecItemDelete(query(service, account) as CFDictionary)
    }
}
