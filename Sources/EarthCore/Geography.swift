import Foundation
import simd

public struct GeoCoordinate: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
    public var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
    public var vector: SIMD3<Double> {
        let a = latitude * .pi/180, b = longitude * .pi/180
        return SIMD3(sin(b)*cos(a),sin(a),cos(b)*cos(a))
    }
    public init(vector: SIMD3<Double>) {
        let n = simd_normalize(vector)
        latitude = asin(max(-1,min(1,n.y)))*180 / .pi
        longitude = atan2(n.x,n.z)*180 / .pi
    }
    public func distance(to other: Self) -> Double {
        acos(max(-1,min(1,simd_dot(vector,other.vector))))*180 / .pi
    }
    public var label: String {
        String(format:"%.1f°%@ %.1f°%@",abs(latitude),latitude >= 0 ? "N":"S",abs(longitude),longitude >= 0 ? "E":"W")
    }
}

public enum SolarPosition {
    /// Low-order solar ephemeris in Earth-fixed coordinates, adequate for a
    /// desktop terminator. UTC Julian days, solar right ascension minus GMST.
    public static func coordinate(at date: Date) -> GeoCoordinate {
        let d = date.timeIntervalSince1970 / 86400 + 2440587.5 - 2451545
        let rad = Double.pi/180
        let g = (357.529 + 0.98560028*d)*rad
        let q = 280.459 + 0.98564736*d
        let l = (q + 1.915*sin(g) + 0.020*sin(2*g))*rad
        let e = (23.439 - 0.00000036*d)*rad
        let ra = atan2(cos(e)*sin(l),cos(l))/rad
        let dec = asin(sin(e)*sin(l))/rad
        var lon = (ra - (280.46061837 + 360.98564736629*d)).truncatingRemainder(dividingBy:360)
        if lon > 180 { lon -= 360 }; if lon < -180 { lon += 360 }
        return GeoCoordinate(latitude:dec,longitude:lon)
    }
}

public enum WeatherGrid {
    public static let coordinates: [GeoCoordinate] = {
        var result = [GeoCoordinate]()
        for band in 0..<12 {
            let lat = -82.5 + Double(band)*15
            let count = max(4,Int((24*cos(lat * .pi/180)).rounded()))
            for i in 0..<count {
                result.append(GeoCoordinate(latitude:lat,longitude:-180+(Double(i)+0.5)*360/Double(count)))
            }
        }
        return result
    }()
}
