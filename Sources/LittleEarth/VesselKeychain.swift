import Foundation
import Security
import LocalAuthentication

enum VesselKeychain {
    private static var query: [String:Any] {
        [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:"com.littleearth.companion.aisstream",kSecAttrAccount as String:"api-key"]
    }
    static func read(allowInteraction: Bool = false) throws -> String? {
        var request = query
        let context = LAContext()
        context.interactionNotAllowed = !allowInteraction
        request[kSecUseAuthenticationContext as String] = context
        // This existing item lives in the macOS login keychain. Retain the
        // per-query legacy flag as well as LAContext so background reads never
        // summon an ACL prompt for an older, pre-update item.
        request[kSecUseAuthenticationUI as String] = allowInteraction ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary,&result)
        return try decode(status:status,data:result as? Data)
    }
    static func decode(status: OSStatus, data: Data?) throws -> String? {
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw ReadError(status:status) }
        guard let data, let key = String(data:data,encoding:.utf8), !key.isEmpty else {
            throw ReadError(status:errSecDecode)
        }
        return key
    }
    struct ReadError: Error {
        let status: OSStatus
    }
    static func save(_ key: String) throws {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary,nil) == errSecSuccess else { throw StorageError.unavailable }
        } else if status != errSecSuccess { throw StorageError.unavailable }
    }
    static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StorageError.unavailable }
    }
    enum StorageError: Error { case unavailable }
}
