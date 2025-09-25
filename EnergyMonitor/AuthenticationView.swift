import SwiftUI

struct AuthenticationView: View {
    @ObservedObject var authService: TeslaAuthService
    @State private var clientId: String = ""
    @State private var clientSecret: String = ""
    @State private var showingClientIdInput = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Energy Monitor")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Connect to your Tesla Energy system")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Authentication State
            switch authService.authState {
            case .notAuthenticated:
                notAuthenticatedView
            case .authenticating:
                authenticatingView
            case .authenticated(let userInfo):
                authenticatedView(userInfo: userInfo)
            case .error(let message):
                errorView(message: message)
            }
            
            Spacer()
        }
        .padding(32)
        .frame(width: 400, height: 500)
        .onAppear {
            loadClientId()
        }
    }
    
    // MARK: - Not Authenticated View
    
    private var notAuthenticatedView: some View {
        VStack(spacing: 16) {
            if clientId.isEmpty || clientSecret.isEmpty || showingClientIdInput {
                clientIdSetupView
            } else {
                VStack(spacing: 12) {
                    Text("Ready to connect")
                        .font(.headline)
                    
                    Text("Click below to sign in with your Tesla account")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    Button("Sign in with Tesla") {
                        authService.startAuthentication()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button("Change API Credentials") {
                        showingClientIdInput = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }
    
    // MARK: - Client ID Setup View
    
    private var clientIdSetupView: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tesla API Credentials")
                    .font(.headline)
                
                Text("Enter your Tesla API Client ID and Client Secret to get started. You can get these from the Tesla Developer Portal.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 12) {
                TextField("Client ID", text: $clientId)
                    .textFieldStyle(.roundedBorder)
                
                SecureField("Client Secret", text: $clientSecret)
                    .textFieldStyle(.roundedBorder)
                
                HStack {
                Button("Save") {
                    print("DEBUG: Save button clicked")
                    saveClientId()
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientId.isEmpty || clientSecret.isEmpty)
                    
                    Button("Cancel") {
                        clientId = ""
                        clientSecret = ""
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("How to get your API credentials:")
                    .font(.caption)
                    .fontWeight(.semibold)
                
                Text("1. Visit developer.tesla.com")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("2. Create an application")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("3. Copy your Client ID and Client Secret")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)
        }
    }
    
    // MARK: - Authenticating View
    
    private var authenticatingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Signing in...")
                .font(.headline)
            
            Text("Please complete the authentication in your browser")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    // MARK: - Authenticated View
    
    private func authenticatedView(userInfo: TeslaUserInfo) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                
                Text("Connected!")
                    .font(.headline)
                
                if let email = userInfo.email {
                    Text(email)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            if !authService.energySites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Energy Sites Found:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    ForEach(authService.energySites) { site in
                        HStack {
                            Image(systemName: "house.fill")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(site.siteName)
                                    .font(.subheadline)
                                Text("ID: \(site.energySiteId)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            
            Button("Sign Out") {
                Task {
                    await authService.signOut()
                }
            }
            .buttonStyle(.bordered)
        }
    }
    
    // MARK: - Error View
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)
                
                Text("Authentication Failed")
                    .font(.headline)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            VStack(spacing: 12) {
                Button("Try Again") {
                    authService.startAuthentication()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Check Client ID") {
                    authService.resetErrorState()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadClientId() {
        clientId = SecureTokenStore.shared.clientId ?? ""
        clientSecret = SecureTokenStore.shared.clientSecret ?? ""
    }
    
    private func saveClientId() {
        guard !clientId.isEmpty && !clientSecret.isEmpty else { 
            print("DEBUG: saveClientId called but clientId or clientSecret is empty")
            return 
        }
        
        print("DEBUG: Saving clientId: '\(clientId)' and clientSecret: '\(clientSecret.prefix(10))...'")
        SecureTokenStore.shared.clientId = clientId
        SecureTokenStore.shared.clientSecret = clientSecret
        
        // Verify it was saved
        let savedClientId = SecureTokenStore.shared.clientId
        let savedClientSecret = SecureTokenStore.shared.clientSecret
        print("DEBUG: Verified saved clientId: '\(savedClientId ?? "nil")' and clientSecret: '\(savedClientSecret?.prefix(10) ?? "nil")...'")
        
        let newConfig = TeslaAuthConfig(clientId: clientId, clientSecret: clientSecret)
        authService.updateConfig(newConfig)
        showingClientIdInput = false
        
        // Reset any error state since we now have valid credentials
        authService.resetErrorState()
        
        // Automatically start authentication after saving credentials
        print("DEBUG: Starting authentication after saving credentials")
        authService.startAuthentication()
    }
}

// MARK: - Preview

struct AuthenticationView_Previews: PreviewProvider {
    static var previews: some View {
        let config = TeslaAuthConfig(clientId: "test-client-id", clientSecret: "test-client-secret")
        let authService = TeslaAuthService(config: config)
        
        AuthenticationView(authService: authService)
    }
}
