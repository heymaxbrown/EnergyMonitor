import Foundation

// MARK: - Tesla API Models

public struct LiveStatus: Codable {
    public let solarPower: Double     // W
    public let loadPower: Double      // W (home)
    public let gridPower: Double      // W (+ import, - export)
    public let batteryPower: Double   // W (+ discharging, - charging)
    public let batterySoC: Double     // 0..100
    public let timestamp: Date
}

public struct SamplePoint: Identifiable, Codable {
    public let id = UUID()
    public let t: Date
    public let solar: Double
    public let home: Double
    public let grid: Double
    public let battery: Double
    public let soc: Double
}

// MARK: - Enhanced Energy Models

public struct EnergyFlow: Codable {
    public let solarToHome: Double      // Solar power going to home
    public let solarToBattery: Double   // Solar power going to battery
    public let solarToGrid: Double      // Solar power going to grid (export)
    public let batteryToHome: Double    // Battery power going to home
    public let gridToHome: Double       // Grid power going to home (import)
    public let gridToBattery: Double    // Grid power going to battery
    
    public init(solarPower: Double, loadPower: Double, gridPower: Double, batteryPower: Double) {
        // Calculate energy flow based on power values
        let solar = max(0, solarPower)
        let home = max(0, loadPower)
        let grid = gridPower // Can be positive (import) or negative (export)
        let battery = batteryPower // Can be positive (discharging) or negative (charging)
        
        // Solar to home (limited by home demand and solar availability)
        self.solarToHome = min(solar, home)
        
        // Remaining solar after home needs
        let solarExcess = max(0, solar - home)
        
        if battery < 0 { // Battery is charging
            // Solar excess goes to battery first, then grid
            self.solarToBattery = min(solarExcess, abs(battery))
            self.solarToGrid = max(0, solarExcess - abs(battery))
            self.gridToBattery = max(0, abs(battery) - solarExcess)
            self.batteryToHome = 0
            self.gridToHome = max(0, home - solar)
        } else { // Battery is discharging
            // Battery helps power home
            self.solarToBattery = 0
            self.gridToBattery = 0
            self.batteryToHome = min(battery, max(0, home - solar))
            self.solarToGrid = max(0, solar - home)
            self.gridToHome = max(0, home - solar - battery)
        }
    }
}

public struct BatteryStatus: Codable {
    public let state: BatteryState
    public let power: Double           // Positive = discharging, Negative = charging
    public let soc: Double            // State of charge percentage
    public let etaToFull: TimeInterval?    // Estimated time to full charge
    public let etaToEmpty: TimeInterval?   // Estimated time to empty
    
    public enum BatteryState: String, Codable {
        case charging = "charging"
        case discharging = "discharging"
        case idle = "idle"
    }
    
    public init(soc: Double, power: Double) {
        self.soc = soc
        self.power = power
        
        if abs(power) < 0.1 { // Less than 100W
            self.state = .idle
        } else if power < 0 {
            self.state = .charging
        } else {
            self.state = .discharging
        }
        
        // Simple ETA calculations (would need historical data for better accuracy)
        self.etaToFull = nil
        self.etaToEmpty = nil
    }
}

public struct EnergySummary: Codable {
    public let siteName: String
    public let siteId: Int
    public let todayGenerated: Double    // kWh generated today
    public let todayConsumed: Double     // kWh consumed today
    public let todayExported: Double     // kWh exported today
    public let todayImported: Double     // kWh imported today
    public let lastUpdated: Date
    
    public init(siteName: String, siteId: Int) {
        self.siteName = siteName
        self.siteId = siteId
        self.todayGenerated = 0
        self.todayConsumed = 0
        self.todayExported = 0
        self.todayImported = 0
        self.lastUpdated = Date()
    }
}

public struct MenuBarDisplay: Codable {
    public let homeLoad: Double          // Primary display value
    public let statusIndicators: [StatusIndicator]
    public let colorState: ColorState
    public let tooltipText: String
    
    public enum ColorState: String, Codable {
        case normal = "normal"
        case exporting = "exporting"     // Green dot
        case importing = "importing"     // Amber dot
    }
    
    public struct StatusIndicator: Codable {
        public let type: IndicatorType
        public let isActive: Bool
        
        public enum IndicatorType: String, Codable {
            case solar = "solar"         // ☀️ when solarPower > 0
            case batteryCharging = "batteryCharging"    // 🔋▼ when charging
            case batteryDischarging = "batteryDischarging" // 🔋▲ when discharging
            case gridImport = "gridImport"    // ⇅▲ when importing
            case gridExport = "gridExport"    // ⇅▼ when exporting
        }
    }
    
    public init(from liveStatus: LiveStatus) {
        self.homeLoad = liveStatus.loadPower
        
        // Calculate status indicators
        var indicators: [StatusIndicator] = []
        
        if liveStatus.solarPower > 0.1 {
            indicators.append(StatusIndicator(type: .solar, isActive: true))
        }
        
        if abs(liveStatus.batteryPower) > 0.1 {
            if liveStatus.batteryPower < 0 {
                indicators.append(StatusIndicator(type: .batteryCharging, isActive: true))
            } else {
                indicators.append(StatusIndicator(type: .batteryDischarging, isActive: true))
            }
        }
        
        if abs(liveStatus.gridPower) > 0.1 {
            if liveStatus.gridPower > 0 {
                indicators.append(StatusIndicator(type: .gridImport, isActive: true))
            } else {
                indicators.append(StatusIndicator(type: .gridExport, isActive: true))
            }
        }
        
        self.statusIndicators = indicators
        
        // Determine color state
        if liveStatus.gridPower < -0.1 {
            self.colorState = .exporting
        } else if liveStatus.gridPower > 0.1 {
            self.colorState = .importing
        } else {
            self.colorState = .normal
        }
        
        // Create tooltip text
        let solarText = String(format: "%.1f", liveStatus.solarPower)
        let homeText = String(format: "%.1f", liveStatus.loadPower)
        let gridText = String(format: "%.1f", abs(liveStatus.gridPower))
        let gridDirection = liveStatus.gridPower < 0 ? "export" : "import"
        let batteryText = String(format: "%.0f%%", liveStatus.batterySoC)
        let batteryDirection = liveStatus.batteryPower < 0 ? "charging" : "discharging"
        let batteryPowerText = String(format: "%.1f", abs(liveStatus.batteryPower))
        
        self.tooltipText = "Solar \(solarText) kW · Home \(homeText) kW · Grid \(gridText) kW (\(gridDirection)) · Battery \(batteryText) (\(batteryDirection) \(batteryPowerText) kW)"
    }
}

// MARK: - Tesla OAuth2 Models

public struct TeslaAuthConfig {
    public let clientId: String
    public let clientSecret: String
    public let redirectURI: String
    public let scope: String
    
    public init(clientId: String, clientSecret: String, redirectURI: String = "http://localhost:1717/callback", scope: String = "openid offline_access user_data energy_device_data energy_cmds") {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.redirectURI = redirectURI
        self.scope = scope
    }
}

public struct TeslaTokenResponse: Codable {
    public let accessToken: String
    public let refreshToken: String
    public let idToken: String?
    public let expiresIn: Int
    public let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case idToken = "id_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

public struct TeslaPartnerTokenResponse: Codable {
    public let accessToken: String
    public let expiresIn: Int
    public let tokenType: String
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

public struct TeslaUserInfo: Codable {
    public let sub: String
    public let email: String?
    public let givenName: String?
    public let familyName: String?
    
    enum CodingKeys: String, CodingKey {
        case sub
        case email
        case givenName = "given_name"
        case familyName = "family_name"
    }
}

// Fleet API specific user info response structure
public struct TeslaFleetUserInfoResponse: Codable {
    public let response: TeslaFleetUserInfo
}

public struct TeslaFleetUserInfo: Codable {
    public let email: String
    public let fullName: String
    public let profileImageUrl: String?
    public let vaultUuid: String
    
    enum CodingKeys: String, CodingKey {
        case email
        case fullName = "full_name"
        case profileImageUrl = "profile_image_url"
        case vaultUuid = "vault_uuid"
    }
}

public struct TeslaVehicle: Codable, Identifiable {
    public let id: Int
    public let vehicleId: Int
    public let vin: String
    public let displayName: String
    public let optionCodes: String
    public let color: String?
    public let tokens: [String]
    public let state: String
    public let inService: Bool
    public let idS: String
    public let calendarEnabled: Bool
    public let apiVersion: Int
    public let backseatToken: String?
    public let backseatTokenUpdatedAt: Int?
    
    enum CodingKeys: String, CodingKey {
        case id
        case vehicleId = "vehicle_id"
        case vin
        case displayName = "display_name"
        case optionCodes = "option_codes"
        case color
        case tokens
        case state
        case inService = "in_service"
        case idS = "id_s"
        case calendarEnabled = "calendar_enabled"
        case apiVersion = "api_version"
        case backseatToken = "backseat_token"
        case backseatTokenUpdatedAt = "backseat_token_updated_at"
    }
}

public struct TeslaEnergySite: Codable, Identifiable {
    public let id: String
    public let energySiteId: Int
    public let resourceType: String
    public let siteName: String
    public let idS: String?
    public let energyLeft: Double?
    public let totalPackEnergy: Double?
    public let percentageCharged: Double?
    public let batteryType: String?
    public let backupCapable: Bool?
    public let batteryPower: Double?
    public let syncGridAlertEnabled: Bool?
    public let breakerAlertEnabled: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id
        case energySiteId = "energy_site_id"
        case resourceType = "resource_type"
        case siteName = "site_name"
        case idS = "id_s"
        case energyLeft = "energy_left"
        case totalPackEnergy = "total_pack_energy"
        case percentageCharged = "percentage_charged"
        case batteryType = "battery_type"
        case backupCapable = "backup_capable"
        case batteryPower = "battery_power"
        case syncGridAlertEnabled = "sync_grid_alert_enabled"
        case breakerAlertEnabled = "breaker_alert_enabled"
    }
}

// MARK: - Authentication State

public enum TeslaAuthState {
    case notAuthenticated
    case authenticating
    case authenticated(TeslaUserInfo)
    case error(String)
}

public enum TeslaAuthError: Error, LocalizedError {
    case networkError(String)
    case authenticationFailed(String)
    case invalidResponse
    case tokenExpired
    
    public var errorDescription: String? {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .tokenExpired:
            return "Token has expired"
        }
    }
}
