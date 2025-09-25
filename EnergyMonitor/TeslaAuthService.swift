import Foundation
import Combine
import CryptoKit
import AuthenticationServices

@MainActor
final class TeslaAuthService: NSObject, ObservableObject {
    @Published var authState: TeslaAuthState = .notAuthenticated
    @Published var userInfo: TeslaUserInfo?
    @Published var energySites: [TeslaEnergySite] = []
    @Published var lastRefreshTime: Date = Date()
    @Published var nextRefreshIn: Int = 30 // seconds until next refresh
    @Published var currentMenuBarDisplay: MenuBarDisplay?
    @Published var currentBatteryStatus: BatteryStatus?
    @Published var currentEnergyFlow: EnergyFlow?
    
    private var config: TeslaAuthConfig
    private var refreshTimer: Timer?
    
    init(config: TeslaAuthConfig) {
        self.config = config
        super.init()
        checkExistingAuth()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    func updateConfig(_ newConfig: TeslaAuthConfig) {
        print("DEBUG: Updating config with clientId: '\(newConfig.clientId)'")
        self.config = newConfig
    }
    
    func logout() {
        stopRefreshTimer()
        SecureTokenStore.shared.clearTokens()
        authState = .notAuthenticated
        userInfo = nil
        energySites = []
        nextRefreshIn = 30
        print("DEBUG: User logged out")
    }
    
    func resetErrorState() {
        if case .error = authState {
            authState = .notAuthenticated
        }
    }
    
    // MARK: - Partner Token Authentication
    
    func authenticateWithPartnerToken() async {
        print("DEBUG: Starting partner token authentication...")
        authState = .authenticating
        
        do {
            let partnerToken = try await generatePartnerToken()
            print("DEBUG: Partner token generated successfully")
            
            // Store the partner token
            SecureTokenStore.shared.accessToken = partnerToken.accessToken
            SecureTokenStore.shared.tokenExpiry = Date().addingTimeInterval(TimeInterval(partnerToken.expiresIn))
            
            // Try to fetch energy sites first
            await fetchEnergySites()
            
            // Create a minimal user info for authentication state
            // Even if no energy sites are found, we're still authenticated
            let userInfo = TeslaUserInfo(
                sub: "partner-token-user",
                email: "partner@tesla.com",
                givenName: "Partner",
                familyName: "User"
            )
            self.userInfo = userInfo
            authState = .authenticated(userInfo)
            
            // Start auto-refresh timer
            startRefreshTimer()
            
            if !self.energySites.isEmpty {
                print("DEBUG: Authentication successful with \(self.energySites.count) energy sites")
            } else {
                print("DEBUG: Authentication successful - no energy sites found (this is normal if you don't have Tesla energy products)")
            }
            
        } catch {
            print("DEBUG: Partner token generation failed: \(error)")
            authState = .error("Failed to generate partner token: \(error.localizedDescription)")
        }
    }
    
    private func generatePartnerToken() async throws -> TeslaPartnerTokenResponse {
        let url = URL(string: "https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "client_credentials",
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "scope": "openid user_data energy_device_data energy_cmds vehicle_device_data vehicle_cmds vehicle_charging_cmds",
            "audience": "https://fleet-api.prd.na.vn.cloud.tesla.com"
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        print("DEBUG: Partner token request body: \(bodyString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TeslaAuthError.networkError("Invalid response")
        }
        
        print("DEBUG: Partner token response status: \(httpResponse.statusCode)")
        print("DEBUG: Partner token response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
        
        if httpResponse.statusCode == 200 {
            do {
                let tokenResponse = try JSONDecoder().decode(TeslaPartnerTokenResponse.self, from: data)
                print("DEBUG: Partner token received: \(tokenResponse.accessToken.prefix(20))...")
                return tokenResponse
            } catch {
                print("DEBUG: JSON decode error: \(error)")
                print("DEBUG: Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                throw TeslaAuthError.authenticationFailed("Failed to parse partner token response: \(error.localizedDescription)")
            }
        } else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("DEBUG: Partner token failed with status \(httpResponse.statusCode): \(errorMessage)")
            throw TeslaAuthError.authenticationFailed("Partner token generation failed: \(errorMessage)")
        }
    }
    
    // MARK: - Authentication Flow
    
    func startAuthentication() {
        // Use OAuth flow that opens browser for user to sign in
        Task {
            await startOAuthFlow()
        }
    }
    
    private func startOAuthFlow() async {
        print("DEBUG: Starting OAuth flow...")
        authState = .authenticating
        
        // Generate PKCE parameters
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)
        let state = generateState()
        
        // Store PKCE parameters
        SecureTokenStore.shared.codeVerifier = codeVerifier
        SecureTokenStore.shared.state = state
        
        // Build OAuth URL
        var components = URLComponents(string: "https://auth.tesla.com/oauth2/v3/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientId),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        
        guard let authURL = components.url else {
            authState = .error("Failed to create authorization URL")
            return
        }
        
        print("DEBUG: OAuth URL: \(authURL)")
        
        // Start web authentication session
        let session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: "http"
        ) { [weak self] callbackURL, error in
            Task { @MainActor in
                if let error = error {
                    print("DEBUG: OAuth error: \(error)")
                    self?.authState = .error("Authentication failed: \(error.localizedDescription)")
                    return
                }
                
                guard let callbackURL = callbackURL else {
                    self?.authState = .error("No callback URL received")
                    return
                }
                
                print("DEBUG: OAuth callback URL: \(callbackURL)")
                await self?.handleCallback(callbackURL)
            }
        }
        
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = true  // Force fresh session to ensure login
        print("DEBUG: Starting OAuth session with ephemeral browser session")
        session.start()
    }
    
    private func handleCallback(_ url: URL) async {
        print("DEBUG: Handling OAuth callback...")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            authState = .error("Invalid callback URL")
            return
        }
        
        // Extract authorization code and state
        var code: String?
        var returnedState: String?
        
        for item in queryItems {
            if item.name == "code" {
                code = item.value
            } else if item.name == "state" {
                returnedState = item.value
            }
        }
        
        // Verify state
        guard let returnedState = returnedState,
              let storedState = SecureTokenStore.shared.state,
              returnedState == storedState else {
            authState = .error("Invalid state parameter")
            return
        }
        
        // Exchange code for tokens
        guard let code = code else {
            authState = .error("No authorization code received")
            return
        }
        
        await exchangeCodeForTokens(code: code)
    }
    
    private func exchangeCodeForTokens(code: String) async {
        print("DEBUG: Exchanging code for tokens...")
        
        let url = URL(string: "https://auth.tesla.com/oauth2/v3/token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "grant_type": "authorization_code",
            "client_id": config.clientId,
            "client_secret": config.clientSecret,
            "code": code,
            "code_verifier": SecureTokenStore.shared.codeVerifier ?? "",
            "redirect_uri": config.redirectURI
        ]
        
        let bodyString = body.map { "\($0.key)=\($0.value)" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        print("DEBUG: Token exchange request body: \(bodyString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TeslaAuthError.networkError("Invalid response")
            }
            
            print("DEBUG: Token exchange response status: \(httpResponse.statusCode)")
            print("DEBUG: Token exchange response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
            
            if httpResponse.statusCode == 200 {
                let tokenResponse = try JSONDecoder().decode(TeslaTokenResponse.self, from: data)
                
                // Store tokens
                SecureTokenStore.shared.accessToken = tokenResponse.accessToken
                SecureTokenStore.shared.refreshToken = tokenResponse.refreshToken
                SecureTokenStore.shared.tokenExpiry = Date().addingTimeInterval(TimeInterval(tokenResponse.expiresIn))
                
                print("DEBUG: Tokens stored successfully")
                
                // Fetch user info and energy sites
                await fetchUserInfo()
                await fetchEnergySites()
                
                // Set authenticated state if we have user info
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    if let userInfo = self.userInfo {
                        self.authState = .authenticated(userInfo)
                        print("DEBUG: Authentication successful with user: \(userInfo.email ?? "unknown")")
                    } else {
                        print("DEBUG: No user info available, but authentication succeeded")
                        // Create a minimal user info for authentication state
                        let minimalUserInfo = TeslaUserInfo(
                            sub: "authenticated-user",
                            email: "user@tesla.com",
                            givenName: "Tesla",
                            familyName: "User"
                        )
                        self.userInfo = minimalUserInfo
                        self.authState = .authenticated(minimalUserInfo)
                    }
                    
                    // Start auto-refresh timer
                    self.startRefreshTimer()
                }
                
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: Token exchange failed with status \(httpResponse.statusCode): \(errorMessage)")
                throw TeslaAuthError.authenticationFailed("Token exchange failed: \(errorMessage)")
            }
            
        } catch {
            print("DEBUG: Token exchange error: \(error)")
            authState = .error("Failed to exchange code for tokens: \(error.localizedDescription)")
        }
    }
    
    private func generateCodeVerifier() -> String {
        let data = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateCodeChallenge(from codeVerifier: String) -> String {
        let data = Data(codeVerifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    
    private func generateState() -> String {
        let data = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
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
                print("DEBUG: User info response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                
                do {
                    // Try Fleet API user info structure first
                    let fleetUserInfoResponse = try JSONDecoder().decode(TeslaFleetUserInfoResponse.self, from: data)
                    let fleetUserInfo = fleetUserInfoResponse.response
                    
                    // Convert Fleet API user info to standard TeslaUserInfo
                    let userInfo = TeslaUserInfo(
                        sub: fleetUserInfo.vaultUuid, // Use vault_uuid as sub
                        email: fleetUserInfo.email,
                        givenName: extractGivenName(from: fleetUserInfo.fullName),
                        familyName: extractFamilyName(from: fleetUserInfo.fullName)
                    )
                    self.userInfo = userInfo
                    print("DEBUG: Fleet API user info fetched successfully: \(userInfo.email ?? "unknown")")
                } catch {
                    print("DEBUG: Failed to decode Fleet API user info: \(error)")
                    
                    // Fallback: Try standard OAuth user info structure
                    do {
                        let userInfo = try JSONDecoder().decode(TeslaUserInfo.self, from: data)
                        self.userInfo = userInfo
                        print("DEBUG: Standard user info fetched successfully: \(userInfo.email ?? "unknown")")
                    } catch {
                        print("DEBUG: Failed to decode standard user info: \(error)")
                        print("DEBUG: Raw response data: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                        
                        // Try to extract email from the JWT token instead
                        if let accessToken = SecureTokenStore.shared.accessToken {
                            if let email = extractEmailFromToken(accessToken) {
                                let fallbackUserInfo = TeslaUserInfo(
                                    sub: "authenticated-user",
                                    email: email,
                                    givenName: "Tesla",
                                    familyName: "User"
                                )
                                self.userInfo = fallbackUserInfo
                                print("DEBUG: Using email from token: \(email)")
                            }
                        }
                    }
                }
                
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
                print("DEBUG: Energy sites raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                
                struct ProductsResponse: Codable {
                    let response: [TeslaEnergySite]
                }
                
                let productsResponse = try JSONDecoder().decode(ProductsResponse.self, from: data)
                self.energySites = productsResponse.response.filter { $0.resourceType == "battery" }
                
                // Store the first energy site ID for backward compatibility
                if let firstSite = self.energySites.first {
                    SecureTokenStore.shared.siteID = String(firstSite.energySiteId)
                    print("DEBUG: First energy site details:")
                    print("  - Site ID: \(firstSite.energySiteId)")
                    print("  - Site Name: \(firstSite.siteName)")
                    print("  - Energy Left: \(firstSite.energyLeft ?? 0)")
                    print("  - Total Pack Energy: \(firstSite.totalPackEnergy ?? 0)")
                    print("  - Percentage Charged: \(firstSite.percentageCharged ?? 0)")
                    print("  - Battery Power: \(firstSite.batteryPower ?? 0)")
                    print("  - Backup Capable: \(firstSite.backupCapable ?? false)")
                }
                
                print("DEBUG: Found \(self.energySites.count) energy sites")
                
                // Fetch live energy data for the first site to get complete data
                if let firstSite = self.energySites.first {
                    await fetchLiveEnergyData(siteId: firstSite.energySiteId)
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: Failed to fetch energy sites: HTTP \(httpResponse.statusCode) - \(errorMessage)")
            }
            
        } catch {
            print("DEBUG: Failed to fetch energy sites: \(error)")
        }
    }
    
    private func fetchLiveEnergyData(siteId: Int) async {
        guard let accessToken = SecureTokenStore.shared.accessToken else { return }
        
        // Use Fleet API endpoint for live energy data
        var request = URLRequest(url: URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com/api/1/energy_sites/\(siteId)/live_status")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("DEBUG: Invalid response from live energy data API")
                return
            }
            
            print("DEBUG: Live energy data response status: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode == 200 {
                print("DEBUG: Live energy data raw response: \(String(data: data, encoding: .utf8) ?? "Unable to decode")")
                
                // Parse the live energy data response
                struct LiveEnergyResponse: Codable {
                    let response: LiveEnergyData
                }
                
                struct LiveEnergyData: Codable {
                    let solarPower: Double?
                    let percentageCharged: Double?
                    let batteryPower: Double?
                    let loadPower: Double?
                    let gridStatus: String?
                    
                    enum CodingKeys: String, CodingKey {
                        case solarPower = "solar_power"
                        case percentageCharged = "percentage_charged"
                        case batteryPower = "battery_power"
                        case loadPower = "load_power"
                        case gridStatus = "grid_status"
                    }
                }
                
                do {
                    let liveResponse = try JSONDecoder().decode(LiveEnergyResponse.self, from: data)
                    let liveData = liveResponse.response
                    
                    // Calculate grid power (simplified - in reality this would be more complex)
                    let gridPower = (liveData.loadPower ?? 0) - (liveData.solarPower ?? 0) - (liveData.batteryPower ?? 0)
                    
                    // Store in PowerCache
                    let liveStatus = LiveStatus(
                        solarPower: liveData.solarPower ?? 0,
                        loadPower: liveData.loadPower ?? 0,
                        gridPower: gridPower,
                        batteryPower: liveData.batteryPower ?? 0,
                        batterySoC: liveData.percentageCharged ?? 0,
                        timestamp: Date()
                    )
                    
                    PowerCache.append(liveStatus)
                    
                    // Generate enhanced display data
                    self.currentMenuBarDisplay = MenuBarDisplay(from: liveStatus)
                    self.currentBatteryStatus = BatteryStatus(soc: liveData.percentageCharged ?? 0, power: liveData.batteryPower ?? 0)
                    self.currentEnergyFlow = EnergyFlow(
                        solarPower: liveData.solarPower ?? 0,
                        loadPower: liveData.loadPower ?? 0,
                        gridPower: gridPower,
                        batteryPower: liveData.batteryPower ?? 0
                    )
                    
                    print("DEBUG: Added live energy data to PowerCache:")
                    print("  - Solar: \(liveData.solarPower ?? 0)W")
                    print("  - Home: \(liveData.loadPower ?? 0)W")
                    print("  - Grid: \(gridPower)W")
                    print("  - Battery: \(liveData.batteryPower ?? 0)W")
                    print("  - SoC: \(liveData.percentageCharged ?? 0)%")
                    print("DEBUG: Generated menu bar display data")
                    
                } catch {
                    print("DEBUG: Failed to parse live energy data: \(error)")
                }
            } else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("DEBUG: Failed to fetch live energy data: HTTP \(httpResponse.statusCode) - \(errorMessage)")
            }
            
        } catch {
            print("DEBUG: Failed to fetch live energy data: \(error)")
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
        // Clear any existing tokens to force fresh authentication
        SecureTokenStore.shared.clearTokens()
        print("DEBUG: Cleared existing tokens, forcing fresh authentication")
    }
    
}

// MARK: - JWT Token Parsing
extension TeslaAuthService {
    private func extractEmailFromToken(_ token: String) -> String? {
        // JWT tokens have 3 parts separated by dots: header.payload.signature
        let parts = token.components(separatedBy: ".")
        guard parts.count == 3 else { return nil }
        
        // Decode the payload (second part)
        let payload = parts[1]
        
        // Add padding if needed for base64 decoding
        var paddedPayload = payload
        while paddedPayload.count % 4 != 0 {
            paddedPayload += "="
        }
        
        guard let data = Data(base64Encoded: paddedPayload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        
        return email
    }
    
    private func extractGivenName(from fullName: String) -> String? {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        return components.first
    }
    
    private func extractFamilyName(from fullName: String) -> String? {
        let components = fullName.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        guard components.count > 1 else { return nil }
        return components.dropFirst().joined(separator: " ")
    }
    
    // MARK: - Auto Refresh Timer
    
    private func startRefreshTimer() {
        stopRefreshTimer() // Stop any existing timer
        
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                
                self.nextRefreshIn -= 1
                
                if self.nextRefreshIn <= 0 {
                    await self.refreshEnergyData()
                    self.nextRefreshIn = 30 // Reset to 30 seconds
                }
            }
        }
        
        print("DEBUG: Started auto-refresh timer (30 seconds)")
    }
    
    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        print("DEBUG: Stopped auto-refresh timer")
    }
    
    func refreshEnergyData() async {
        guard case .authenticated = authState else { return }
        
        print("DEBUG: Auto-refreshing energy data...")
        lastRefreshTime = Date()
        
        // Fetch fresh energy data
        await fetchEnergySites()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension TeslaAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return ASPresentationAnchor()
    }
}
