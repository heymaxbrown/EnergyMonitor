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
            // Real-time Status Display (prominent at top)
            if let display = authService.currentMenuBarDisplay {
                VStack(alignment: .leading, spacing: 6) {
                    // Main power display
                    HStack {
                        Text("⚡")
                            .font(.title2)
                        Text(String(format: "%.1f kW", display.homeLoad / 1000.0))
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // Status indicators
                        HStack(spacing: 4) {
                            ForEach(display.statusIndicators, id: \.type) { indicator in
                                switch indicator.type {
                                case .solar: Text("☀️").font(.caption)
                                case .batteryCharging: Text("🔋▼").font(.caption)
                                case .batteryDischarging: Text("🔋▲").font(.caption)
                                case .gridImport: Text("⇅▲").font(.caption)
                                case .gridExport: Text("⇅▼").font(.caption)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        // Color status dot
                        Circle()
                            .fill(display.colorState == .exporting ? .green : 
                                  display.colorState == .importing ? .orange : .secondary)
                            .frame(width: 8, height: 8)
                    }
                    
                    // Tooltip-style summary
                    Text(display.tooltipText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Enhanced Energy Display
            if authService.currentMenuBarDisplay != nil {
                VStack(alignment: .leading, spacing: 8) {
                    // At-a-glance cards
                    HStack(spacing: 12) {
                        // Battery Card
                        if let batteryStatus = authService.currentBatteryStatus {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Battery")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text("\(Int(batteryStatus.soc))%")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                Text(batteryStatus.state.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Flow Summary
                        if let energyFlow = authService.currentEnergyFlow {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Flow")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if energyFlow.solarToHome > 0 {
                                    HStack(spacing: 4) {
                                        Text("☀️")
                                        Text("→")
                                        Text("🏠")
                                        Text(String(format: "%.1f kW", energyFlow.solarToHome / 1000.0))
                                            .font(.caption)
                                    }
                                }
                                
                                if energyFlow.solarToGrid > 0 {
                                    HStack(spacing: 4) {
                                        Text("☀️")
                                        Text("→")
                                        Text("🔌")
                                        Text(String(format: "%.1f kW", energyFlow.solarToGrid / 1000.0))
                                            .font(.caption)
                                    }
                                }
                                
                                if energyFlow.batteryToHome > 0 {
                                    HStack(spacing: 4) {
                                        Text("🔋")
                                        Text("→")
                                        Text("🏠")
                                        Text(String(format: "%.1f kW", energyFlow.batteryToHome / 1000.0))
                                            .font(.caption)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            
            HStack(spacing: 12) {
                BatteryRing(percent: samples.last?.soc ?? 0, state: batteryStateText)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        StatRow(icon: "sun.max.fill", label: "Solar",  value: Fmt.wattString(samples.last?.solar ?? 0))
                        StatRow(icon: "house.fill",   label: "Home",   value: Fmt.wattString(samples.last?.home  ?? 0))
                    }
                    HStack(spacing: 12) {
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
        HStack(spacing: 4) {
            Image(systemName: icon)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(label + ":")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption)
                    .monospacedDigit()
            }
            Spacer()
        }
        .frame(minWidth: 80)
    }
}

struct BatteryRing: View {
    let percent: Double
    let state: String
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(lineWidth: 8).opacity(0.15)
                Circle().trim(from: 0, to: CGFloat(max(0,min(1, percent/100))))
                    .stroke(style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(percent))%").font(.headline).monospacedDigit()
            }.frame(width: 64, height: 64)
            Text(state)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 80)
        }
    }
}

