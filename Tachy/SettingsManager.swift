import Foundation
import Security

class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard
    private let keychainService = "com.tachy.keys"

    // MARK: - API Keys (stored in Keychain)

    var openAIKey: String {
        get { getKeychainValue(key: "openai_api_key") ?? "" }
        set { setKeychainValue(key: "openai_api_key", value: newValue) }
    }

    // MARK: - Settings (stored in UserDefaults)

    var autoPaste: Bool {
        get { defaults.object(forKey: "auto_paste") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "auto_paste") }
    }

    var showNotifications: Bool {
        get { defaults.object(forKey: "show_notifications") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "show_notifications") }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: "launch_at_login") }
        set { defaults.set(newValue, forKey: "launch_at_login") }
    }

    var useLiveTranscription: Bool {
        get { defaults.object(forKey: "use_live_transcription") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "use_live_transcription") }
    }

    // MARK: - Keychain

    private func setKeychainValue(key: String, value: String) {
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    private func getKeychainValue(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
