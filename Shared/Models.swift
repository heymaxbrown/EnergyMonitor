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
    public let idS: String
    public let energyLeft: Double
    public let totalPackEnergy: Double
    public let percentageCharged: Double
    public let batteryType: String
    public let backupCapable: Bool
    public let batteryPower: Double
    public let syncGridAlertEnabled: Bool
    public let breakerAlertEnabled: Bool
    
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
