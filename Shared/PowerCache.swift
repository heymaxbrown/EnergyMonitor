import Foundation

public enum PowerCache {
    static let suite: UserDefaults = {
        if let s = UserDefaults(suiteName: AppGroup.identifier) {
            return s
        }
        // Fallback to standard defaults to avoid crashes when the App Group isn't configured (e.g., during development)
        return UserDefaults.standard
    }()
    private static let key = "samples_v1"

    public static func append(_ s: LiveStatus, bufferSeconds: TimeInterval = 30*60) {
        var pts = load()
        pts.append(SamplePoint(t: s.timestamp,
                               solar: s.solarPower,
                               home: s.loadPower,
                               grid: s.gridPower,
                               battery: s.batteryPower,
                               soc: s.batterySoC))
        let cutoff = Date().addingTimeInterval(-bufferSeconds)
        pts = pts.filter { $0.t >= cutoff }
        if let data = try? JSONEncoder().encode(pts) {
            suite.set(data, forKey: key)
        }
    }

    public static func load() -> [SamplePoint] {
        guard let data = suite.data(forKey: key),
              let pts = try? JSONDecoder().decode([SamplePoint].self, from: data) else { return [] }
        return pts.sorted(by: { $0.t < $1.t })
    }

    public static func clear() { suite.removeObject(forKey: key) }
}

