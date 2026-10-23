import Foundation
import Security

/// Minimal Keychain wrapper for the user's Claude API key.
enum Keychain {
    private static let service = "io.github.deborahdore.ServiceBook"

    static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String?, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // Never synced to iCloud or restored to another device.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// Settings for the Claude connection (UserDefaults keys + accessors).
enum AppSettings {
    static let apiKeyAccount = "anthropic-api-key"
    static let modelKey = "claudeModel"
    static let modelMaxTokensKey = "claudeModelMaxTokens"
    static let maxSearchesKey = "claudeMaxSearches"
    static let useRegionKey = "claudeUseRegion"
    static let usageKey = "claudeUsageTotal"
    static let importsKey = "claudeImportCount"
    static let connectionOKKey = "claudeConnectionOK"
    static let notificationsKey = "notificationsEnabled"

    static let defaultModel = "claude-sonnet-5-5"
    /// Shown when the model list can't be loaded.
    static let fallbackModels: [ModelInfo] = [
        ModelInfo(id: "claude-sonnet-5-5", displayName: "Claude Sonnet 5.5", supportsWebSearch: true, supportsPDF: true, maxTokens: nil),
        ModelInfo(id: "claude-opus-5-5", displayName: "Claude Opus 5.5", supportsWebSearch: true, supportsPDF: true, maxTokens: nil),
        ModelInfo(id: "claude-haiku-5-5", displayName: "Claude Haiku 5.5", supportsWebSearch: true, supportsPDF: true, maxTokens: nil),
    ]

    static var apiKey: String? {
        let k = Keychain.get(apiKeyAccount)
        return (k?.isEmpty ?? true) ? nil : k
    }

    static var hasKey: Bool { apiKey != nil }

    static var model: String {
        let m = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return m.isEmpty ? defaultModel : m
    }

    /// Output limit for one request: the model's own limit when known, capped at 32k.
    static var maxTokens: Int {
        let m = UserDefaults.standard.integer(forKey: modelMaxTokensKey)
        return m > 0 ? min(m, 32_000) : 16_000
    }

    static var maxSearches: Int {
        let n = UserDefaults.standard.integer(forKey: maxSearchesKey)
        return n > 0 ? n : 8
    }

    static var useRegion: Bool {
        UserDefaults.standard.object(forKey: useRegionKey) as? Bool ?? true
    }

    static var regionCode: String? { Locale.current.region?.identifier }

    static var client: ClaudeClient? {
        guard let key = apiKey else { return nil }
        return ClaudeClient(apiKey: key, model: model, maxTokens: maxTokens)
    }

    static var totalUsage: AIUsage {
        guard let data = UserDefaults.standard.data(forKey: usageKey),
              let u = try? JSONDecoder().decode(AIUsage.self, from: data) else { return AIUsage() }
        return u
    }

    static var importCount: Int { UserDefaults.standard.integer(forKey: importsKey) }

    static func record(_ usage: AIUsage) {
        var total = totalUsage
        total.add(usage)
        if let data = try? JSONEncoder().encode(total) { UserDefaults.standard.set(data, forKey: usageKey) }
        UserDefaults.standard.set(importCount + 1, forKey: importsKey)
    }

    static func resetUsage() {
        UserDefaults.standard.removeObject(forKey: usageKey)
        UserDefaults.standard.removeObject(forKey: importsKey)
    }
}
