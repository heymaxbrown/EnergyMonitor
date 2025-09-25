import Foundation

public enum Fmt {
    public static func wattString(_ w: Double) -> String {
        let absw = abs(w)
        if absw >= 1000 { return String(format: "%0.1f kW", w/1000.0) }
        return String(format: "%0.0f W", w)
    }
}
