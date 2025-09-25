import Foundation
import Combine
import CryptoKit
import AuthenticationServices

@MainActor
final class TeslaAuthService: NSObject, ObservableObject {
    @Published var authState: TeslaAuthState = .notAuthenticated
    @Published var userInfo: TeslaUserInfo?
    @Published var energySites: [TeslaEnergySite] = []
    
    private var config: TeslaAuthConfig
    private var authSession: ASWebAuthenticationSession?
    
    init(config: TeslaAuthConfig) {
        self.config = config
        super.init()
        checkExistingAuth()
    }
    
    func updateConfig(_ newConfig: TeslaAuthConfig) {
        print("DEBUG: Updating config with clientId: '\(newConfig.clientId)'")
        self.config = newConfig
    }
    
    func resetErrorState() {
        if case .error = authState {
            authState = .notAuthenticated
        }
    }
    
    // MARK: - Authentication Flow
    
    func startAuthentication() {
        print("DEBUG: Starting authentication with clientId: '\(config.clientId)'")
        guard !config.clientId.isEmpty else {
            authState = .error("Client ID is required. Please enter your Tesla API Client ID first.")
            return
        }
        
        authState = .authenticating
        
        // Generate PKCE parameters
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateState()
        
        // Store PKCE parameters securely
        SecureTokenStore.shared.codeVerifier = codeVerifier
        SecureTokenStore.shared.state = state
        
        // Build authorization URL
        var components = URLComponents(string: "https://auth.tesla.com/oauth2/v3/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        print("DEBUG: OAuth URL components:")
        print("  - client_id: \(config.clientId)")
        print("  - redirect_uri: \(config.redirectURI)")
        print("  - scope: \(config.scope)")
        
        guard let authURL = components.url else {
            authState = .error("Failed to create authorization URL")
            return
        }
        
        // Start web authentication session
        authSession = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "http"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                if let error = error {
                    self?.authState = .error("Authentication failed: \(error.localizedDescription)")
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self?.authState = .error("No callback URL received")
                    return
                }
                
                await self?.handleCallback(callbackURL)
            }
        }
        
        authSession?.presentationContextProvider = self
        authSession?.start()
    }
    
    private func handleCallback(_ callbackURL: URL) async {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authState = .error("Invalid callback URL")
            return
        }
        
        // Extract authorization code and state
        guard let code = queryItems.first(where: { $0.name == "code" })?.value,
              let state = queryItems.first(where: { $0.name == "state" })?.value else {
            authState = .error("Missing authorization code or state")
            return
        }
        
        // Verify state parameter
        guard state == SecureTokenStore.shared.state else {
            authState = .error("Invalid state parameter")
            return
        }
        
        // Exchange code for tokens
        await exchangeCodeForTokens(code: code)
    }
    
    private func exchangeCodeForTokens(code: String) async {
        guard let codeVerifier = SecureTokenStore.shared.codeVerifier else {
            authState = .error("Missing code verifier")
            return
        }
        
        print("DEBUG: Starting token exchange...")
        print("DEBUG: Code: \(code)")
        print("DEBUG: Code verifier: \(codeVerifier)")
        print("DEBUG: Client ID: \(config.clientId)")
        print("DEBUG: Redirect URI: \(config.redirectURI)")
        
        var request = URLRequest(url: URL(string: "https://auth.tesla.com/oauth2/v3/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": config.redirectURI
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        print("DEBUG: Token exchange body: \(bodyString)")
        
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authState = .error("Invalid response from token server")
                return
            }
            
            print("DEBUG: Token exchange response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(TeslaTokenResponse.self, from: data)
                
                print("DEBUG: Token exchange successful!")
                print("DEBUG: Access token received: \(tokenResponse.accessToken.prefix(20))...")
                print("DEBUG: Refresh token received: \(tokenResponse.refreshToken.prefix(20))...")
                print("DEBUG: Token expires in: \(tokenResponse.expiresIn) seconds")
                
                // Store tokens securely
                SecureTokenStore.shared.accessToken = tokenResponse.accessToken
                SecureTokenStore.shared.refreshToken = tokenResponse.refreshToken
                SecureTokenStore.shared.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                
                // Clear PKCE parameters
                SecureTokenStore.shared.codeVerifier = nil
                SecureTokenStore.shared.state = nil
                
                // Fetch user info
                await fetchUserInfo()
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: Token exchange failed with status \(httpResponse.statusCode)")
                print("DEBUG: Error response: \(errorMessage)")
                authState = .error("Token exchange failed: HTTP \(httpResponse.statusCode) - \(errorMessage)")
            }
            
        } catch {
            print("DEBUG: Token exchange error: \(error)")
            authState = .error("Token exchange failed: \(error.localizedDescription)")
        }
    }
    
    private func fetchUserInfo() async {
        guard let accessToken = SecureTokenStore.shared.accessToken else {
            authState = .error("No access token available")
            return
        }
        
        // Use Fleet API endpoint
        var request = URLRequest(url: URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/users/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("TeslaEnergyMonitor/1.0", forHTTPHeaderField: "User-Agent")
        
        print("DEBUG: User info request - URL: \(request.url?.absoluteString ?? "nil")")
        print("DEBUG: User info request - Authorization header: Bearer \(accessToken.prefix(20))...")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                authState = .error("Invalid response from server")
                return
            }
            
            print("DEBUG: User info response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                let userInfo = try JSONDecoder().decode(TeslaUserInfo.self, from: data)
                self.userInfo = userInfo
                authState = .authenticated(userInfo)
                
                // Fetch energy sites
                await fetchEnergySites()
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: User info error response: \(errorMessage)")
                print("DEBUG: User info response headers: \(httpResponse.allHeaderFields)")
                authState = .error("Failed to fetch user info: HTTP \(httpResponse.statusCode) - \(errorMessage)")
            }
            
        } catch {
            authState = .error("Failed to fetch user info: \(error.localizedDescription)")
        }
    }
    
    private func fetchEnergySites() async {
        guard let accessToken = SecureTokenStore.shared.accessToken else { return }
        
        // Use Fleet API endpoint for energy sites
        var request = URLRequest(url: URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/products")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("DEBUG: Invalid response from energy sites API")
                return
            }
            
            print("DEBUG: Energy sites response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                struct ProductsResponse: Codable {
                    let response: [TeslaEnergySite]
                }
                
                let productsResponse = try JSONDecoder().decode(ProductsResponse.self, from: data)
                self.energySites = productsResponse.response.filter { $0.resourceType == "battery" }
                
                // Store the first energy site ID for backward compatibility
                if let firstSite = self.energySites.first {
                    SecureTokenStore.shared.siteID = String(firstSite.energySiteId)
                }
                
                print("DEBUG: Found \(self.energySites.count) energy sites")
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: Failed to fetch energy sites: HTTP \(httpResponse.statusCode) - \(errorMessage)")
            }
            
        } catch {
            print("DEBUG: Failed to fetch energy sites: \(error)")
        }
    }
    
    func refreshTokenIfNeeded() async -> Bool {
        guard let refreshToken = SecureTokenStore.shared.refreshToken,
              let expiry = SecureTokenStore.shared.tokenExpiry,
              expiry.timeIntervalSinceNow < 300 else { // Refresh if expires in less than 5 minutes
            return true
        }
        
        var request = URLRequest(url: URL(string: "https://auth.tesla.com/oauth2/v3/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "refresh_token",
            "client_id": config.clientId,
            "refresh_token": refreshToken
        ]
        
        request.httpBody = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  200...299 ~= httpResponse.statusCode else {
                // Refresh failed, need to re-authenticate
                await signOut()
                return false
            }
            
            let tokenResponse = try JSONDecoder().decode(TeslaTokenResponse.self, from: data)
            
            // Update stored tokens
            SecureTokenStore.shared.accessToken = tokenResponse.accessToken
            SecureTokenStore.shared.refreshToken = tokenResponse.refreshToken
            SecureTokenStore.shared.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
            
            return true
            
        } catch {
            // Refresh failed, need to re-authenticate
            await signOut()
            return false
        }
    }
    
    func signOut() async {
        SecureTokenStore.shared.clearTokens()
        authState = .notAuthenticated
        userInfo = nil
        energySites = []
    }
    
    private func checkExistingAuth() {
        if SecureTokenStore.shared.accessToken != nil {
            // We have a token, but need to verify it's still valid
            Task {
                if await refreshTokenIfNeeded() {
                    await fetchUserInfo()
                }
            }
        }
    }
    
    // MARK: - PKCE Helpers
    
    private func generateCodeVerifier() -> String {
        let data = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        return data.base64URLEncodedString()
    }
    
    private func generateCodeChallenge(from codeVerifier: String) -> String {
        let data = Data(codeVerifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64URLEncodedString()
    }
    
    private func generateState() -> String {
        let data = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return data.base64URLEncodedString()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension TeslaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.windows.first { $0.isKeyWindow } ?? NSApplication.shared.windows.first!
    }
}

// MARK: - Data Extensions

extension Data {
    func base64URLEncodedString() -> String {
        return base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
