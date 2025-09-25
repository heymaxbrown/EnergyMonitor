import Foundation
import Security

final class SecureTokenStore {
    static let shared = SecureTokenStore()
    private init() {}
    
    private let service = "com.energymonitor.tesla"
    
    // MARK: - OAuth Tokens
    
    var accessToken: String? {
        get { getFromKeychain(key: "access_token") }
        set { setInKeychain(key: "access_token", value: newValue) }
    }
    
    var refreshToken: String? {
        get { getFromKeychain(key: "refresh_token") }
        set { setInKeychain(key: "refresh_token", value: newValue) }
    }
    
    var tokenExpiry: Date? {
        get {
            guard let timeIntervalString = getFromKeychain(key: "token_expiry"),
                  let timeInterval = TimeInterval(timeIntervalString) else { return nil }
            return Date(timeIntervalSince1970: timeInterval)
        }
        set {
            if let date = newValue {
                setInKeychain(key: "token_expiry", value: String(date.timeIntervalSince1970))
            } else {
                deleteFromKeychain(key: "token_expiry")
            }
        }
    }
    
    // MARK: - PKCE Parameters (temporary storage)
    
    var codeVerifier: String? {
        get { getFromKeychain(key: "code_verifier") }
        set { setInKeychain(key: "code_verifier", value: newValue) }
    }
    
    var state: String? {
        get { getFromKeychain(key: "state") }
        set { setInKeychain(key: "state", value: newValue) }
    }
    
    // MARK: - Configuration
    
    var siteID: String? {
        get { UserDefaults.standard.string(forKey: "energy_site_id") }
        set { UserDefaults.standard.set(newValue, forKey: "energy_site_id") }
    }
    
    var clientId: String? {
        get { 
            let value = UserDefaults.standard.string(forKey: "tesla_client_id")
            print("DEBUG: SecureTokenStore getting clientId: '\(value ?? "nil")'")
            return value
        }
        set { 
            print("DEBUG: SecureTokenStore setting clientId: '\(newValue ?? "nil")'")
            UserDefaults.standard.set(newValue, forKey: "tesla_client_id")
        }
    }
    
    var clientSecret: String? {
        get { getFromKeychain(key: "client_secret") }
        set { setInKeychain(key: "client_secret", value: newValue) }
    }
    
    // MARK: - Keychain Operations
    
    private func getFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    private func setInKeychain(key: String, value: String?) {
        // First, delete any existing item
        deleteFromKeychain(key: key)
        
        guard let value = value else { return }
        
        let data = value.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data
        ]
        
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
    
    func clearTokens() {
        deleteFromKeychain(key: "access_token")
        deleteFromKeychain(key: "refresh_token")
        deleteFromKeychain(key: "token_expiry")
        deleteFromKeychain(key: "code_verifier")
        deleteFromKeychain(key: "state")
        deleteFromKeychain(key: "client_secret")
    }
    
    // MARK: - Legacy Support (for backward compatibility)
    
    var isAuthenticated: Bool {
        return accessToken != nil && refreshToken != nil
    }
    
    var hasValidToken: Bool {
        guard let expiry = tokenExpiry else { return false }
        return expiry.timeIntervalSinceNow > 0
    }
}

