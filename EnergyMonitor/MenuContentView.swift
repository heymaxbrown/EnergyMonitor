import SwiftUI
import Charts
import Combine

struct MenuContentView: View {
    @Binding var lastError: String?
    @ObservedObject var authService: TeslaAuthService
    let onShowAuth: () -> Void
    
    @State private var samples: [SamplePoint] = PowerCache.load()
    @State private var timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Authentication Status
            HStack {
                switch authService.authState {
                case .authenticated(let userInfo):
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(userInfo.email ?? "Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Logout") {
                        authService.logout()
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)
                case .authenticating:
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Connecting...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .error(let message):
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Error: \(message)")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                default:
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.slash.fill")
                            .foregroundColor(.orange)
                        Text("Not Connected")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Settings") {
                    // Open the authentication window
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title == "Tesla Authentication" }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        // Create a new window
                        let window = NSWindow(
                            contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                            styleMask: [.titled, .closable, .miniaturizable],
                            backing: .buffered,
                            defer: false
                        )
                        window.title = "Tesla Authentication"
                        window.contentView = NSHostingView(rootView: AuthenticationView(authService: authService))
                        window.center()
                        window.makeKeyAndOrderFront(nil)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            
            // Main Content
            switch authService.authState {
            case .authenticated:
                authenticatedContentView
            default:
                notAuthenticatedContentView
            }
        }
        .padding(12)
        .onReceive(timer) { _ in samples = PowerCache.load() }
    }
    
    // MARK: - Authenticated Content View
    
    private var authenticatedContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                BatteryRing(percent: samples.last?.soc ?? 0, state: batteryStateText)
                VStack(alignment: .leading) {
                    HStack {
                        StatRow(icon: "sun.max.fill", label: "Solar",  value: Fmt.wattString(samples.last?.solar ?? 0))
                        StatRow(icon: "house.fill",   label: "Home",   value: Fmt.wattString(samples.last?.home  ?? 0))
                    }
                    HStack {
                        StatRow(icon: "bolt.horizontal.fill", label: "Grid",    value: Fmt.wattString(samples.last?.grid ?? 0))
                        StatRow(icon: "battery.100",          label: "Battery", value: Fmt.wattString(samples.last?.battery ?? 0))
                    }
                }
            }

            Chart(samples) {
                LineMark(x: .value("Time", $0.t), y: .value("Solar", $0.solar))
                LineMark(x: .value("Time", $0.t), y: .value("Home",  $0.home))
                LineMark(x: .value("Time", $0.t), y: .value("Battery", $0.battery))
                RuleMark(y: .value("Zero", 0)).foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [3,3]))
                LineMark(x: .value("Time", $0.t), y: .value("Grid", $0.grid))
            }
            .frame(height: 140)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Updated \(authService.lastRefreshTime.formatted(date: .omitted, time: .standard))")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("Next refresh in \(authService.nextRefreshIn)s")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Open Dashboard") { NSApp.activate(ignoringOtherApps: true) }
            }

            if let err = lastError {
                Text("Error: \(err)").font(.caption).foregroundStyle(.red)
            }
        }
    }
    
    // MARK: - Not Authenticated Content View
    
    private var notAuthenticatedContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Connect to Tesla")
                    .font(.headline)
                
                Text("Sign in to your Tesla account to monitor your energy system")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button("Sign in with Tesla") {
                // Open the authentication window
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.title == "Tesla Authentication" }) {
                    window.makeKeyAndOrderFront(nil)
                } else {
                    // Create a new window
                    let window = NSWindow(
                        contentRect: NSRect(x: 0, y: 0, width: 400, height: 500),
                        styleMask: [.titled, .closable, .miniaturizable],
                        backing: .buffered,
                        defer: false
                    )
                    window.title = "Tesla Authentication"
                    window.contentView = NSHostingView(rootView: AuthenticationView(authService: authService))
                    window.center()
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            
            if let err = lastError {
                Text("Error: \(err)").font(.caption).foregroundStyle(.red)
            }
        }
    }

    var batteryStateText: String {
        guard let last = samples.last else { return "—" }
        if last.battery > 0 { return "Discharging " + Fmt.wattString(last.battery) }
        if last.battery < 0 { return "Charging " + Fmt.wattString(-last.battery) }
        return "Idle"
    }
}

struct StatRow: View {
    let icon: String; let label: String; let value: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(label + ":").foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }.font(.subheadline)
    }
}

struct BatteryRing: View {
    let percent: Double
    let state: String
    var body: some View {
        VStack {
            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.15)
                Circle().trim(from: 0, to: CGFloat(max(0,min(1, percent/100))))
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent))%").font(.headline).monospacedDigit()
            }.frame(width: 64, height: 64)
            Text(state).font(.caption)
        }
    }
}

