import Foundation
import Security

enum KeychainError: Error { case status(OSStatus) }

enum Keychain {
    static let service = "net.outofajam.SteamShelf"
    static let apiKeyAccount = "steam-web-api-key"
    static let aiKeyAccount = "anthropic-api-key"
    /// One key per AI service; Anthropic keeps its original account name so existing keys carry over.
    static func aiKeyAccount(for providerID: String) -> String {
        providerID == "anthropic" ? aiKeyAccount : "ai-key-\(providerID)"
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    /// Delete-then-add. Uses the file-based login keychain (no data-protection keychain: it needs a team ID).
    static func save(_ value: String, account: String) throws {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
