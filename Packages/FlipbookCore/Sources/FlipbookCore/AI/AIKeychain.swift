import Foundation
import Security

/// Stores each provider's API key in the login Keychain — never in SwiftData, UserDefaults,
/// or plain files. Keys are secrets the user brings (BYOK); they stay on-device and are only
/// ever sent to that provider's API over TLS. One key per provider, so several can stay
/// configured and the user can switch between them freely.
public enum AIKeychain {
    private static let service = "com.flipbook.app.ai"

    private static func account(for provider: AIProvider) -> String {
        "api-key-\(provider.rawValue)"
    }

    public static func save(_ key: String, for provider: AIProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else {
            delete(for: provider)
            return
        }
        // Upsert: clear any existing item first so attributes stay clean.
        delete(for: provider)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func load(for provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    public static func delete(for provider: AIProvider) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(for: provider),
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static func hasKey(for provider: AIProvider) -> Bool {
        load(for: provider) != nil
    }
}
