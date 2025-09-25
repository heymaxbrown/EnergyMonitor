import SwiftUI
import Combine

@main
struct EnergyMonitorApp: App {
    @StateObject private var authService: TeslaAuthService
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()
    @State private var lastError: String? = nil
    @State private var showingAuthWindow = false
    
    private var client: TeslaClient {
        TeslaClient(
            tokenProvider: { SecureTokenStore.shared.accessToken ?? "" },
            authService: authService
        )
    }
    
    init() {
        // Initialize auth service with stored credentials or default
        let clientId = SecureTokenStore.shared.clientId ?? ""
        let clientSecret = SecureTokenStore.shared.clientSecret ?? ""
        print("DEBUG: App init with clientId: '\(clientId)' and clientSecret: '\(clientSecret.prefix(10))...'")
        let config = TeslaAuthConfig(clientId: clientId, clientSecret: clientSecret)
        _authService = StateObject(wrappedValue: TeslaAuthService(config: config))
    }

    var body: some Scene {
        MenuBarExtra("Energy", systemImage: "bolt.fill") {
            MenuContentView(
                lastError: $lastError,
                authService: authService,
                onShowAuth: { showingAuthWindow = true }
            )
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Dashboard") {
            DashboardView()
                .onReceive(timer) { _ in
                    Task { await refresh() }
                }
        }
        .defaultSize(CGSize(width: 760, height: 420))
        .commands {
            CommandMenu("Energy") {
                Button("Refresh Now") { Task { await refresh() } }
                    .keyboardShortcut("r")
                
                Divider()
                
                Button("Tesla Settings") { 
                    // This will be handled by the MenuContentView
                }
                    .keyboardShortcut(",", modifiers: [.command])
            }
        }
        
        WindowGroup("Tesla Authentication") {
            AuthenticationView(authService: authService)
        }
        .defaultSize(CGSize(width: 400, height: 500))
        .handlesExternalEvents(matching: Set(arrayLiteral: "tesla-auth"))
        .windowResizability(.contentSize)
    }

    private func refresh() async {
        do {
            guard let siteID = SecureTokenStore.shared.siteID else { return }
            let live = try await client.liveStatus(siteID: siteID)
            PowerCache.append(live)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

