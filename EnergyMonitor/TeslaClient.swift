import Foundation

final class TeslaClient {
    // Change to your region base (NA/EU/CN)
    private let base = URL(string: "https://fleet-api.prd.na.vn.cloud.tesla.com")!
    private let tokenProvider: () -> String
    private let authService: TeslaAuthService?

    init(tokenProvider: @escaping () -> String, authService: TeslaAuthService? = nil) {
        self.tokenProvider = tokenProvider
        self.authService = authService
    }

    func liveStatus(siteID: String) async throws -> LiveStatus {
        return try await performRequest(
            endpoint: "/api/1/energy_sites/\(siteID)/live_status",
            method: "GET"
        ) { data in
            struct Resp: Codable {
                struct Wrapper: Codable {
                    let solar_power: Double
                    let load_power: Double
                    let grid_power: Double
                    let battery_power: Double
                    let percentage_charged: Double
                }
                let response: Wrapper
            }
            let r = try JSONDecoder().decode(Resp.self, from: data).response
            return LiveStatus(
                solarPower: r.solar_power,
                loadPower: r.load_power,
                gridPower: r.grid_power,
                batteryPower: r.battery_power,
                batterySoC: r.percentage_charged,
                timestamp: Date()
            )
        }
    }
    
    func setBackupReserve(siteID: String, percentage: Double) async throws {
        try await performRequest(
            endpoint: "/api/1/energy_sites/\(siteID)/backup",
            method: "POST",
            body: ["backup_reserve_percent": percentage]
        ) { _ in
            return () // Void response
        }
    }
    
    func setOperationMode(siteID: String, mode: String) async throws {
        try await performRequest(
            endpoint: "/api/1/energy_sites/\(siteID)/operation",
            method: "POST",
            body: ["default_real_mode": mode]
        ) { _ in
            return () // Void response
        }
    }
    
    // MARK: - Private Methods
    
    private func performRequest<T>(
        endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        responseHandler: @escaping (Data) throws -> T
    ) async throws -> T {
        // Ensure we have a valid token
        if let authService = authService {
            let tokenValid = await authService.refreshTokenIfNeeded()
            guard tokenValid else {
                throw TeslaError.authenticationRequired
            }
        }
        
        guard let url = URL(string: endpoint, relativeTo: base) else {
            throw TeslaError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tokenProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw TeslaError.invalidResponse
            }
            
            // Handle different HTTP status codes
            switch httpResponse.statusCode {
            case 200...299:
                return try responseHandler(data)
            case 401:
                // Token expired or invalid
                if let authService = authService {
                    await authService.signOut()
                }
                throw TeslaError.authenticationRequired
            case 403:
                throw TeslaError.forbidden
            case 404:
                throw TeslaError.notFound
            case 429:
                throw TeslaError.rateLimited
            case 500...599:
                throw TeslaError.serverError(httpResponse.statusCode)
            default:
                throw TeslaError.httpError(httpResponse.statusCode)
            }
            
        } catch let error as TeslaError {
            throw error
        } catch {
            throw TeslaError.networkError(error)
        }
    }
}

// MARK: - Error Types

enum TeslaError: LocalizedError {
    case authenticationRequired
    case invalidURL
    case invalidResponse
    case forbidden
    case notFound
    case rateLimited
    case serverError(Int)
    case httpError(Int)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            return "Authentication required. Please sign in to Tesla."
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .forbidden:
            return "Access forbidden. Check your permissions."
        case .notFound:
            return "Resource not found"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .serverError(let code):
            return "Server error (\(code))"
        case .httpError(let code):
            return "HTTP error (\(code))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

