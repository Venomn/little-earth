import Foundation
import simd

public struct RegionalWeather {
    private let samples: [WeatherSample]
    private let vectors: [SIMD3<Double>]
    private let coverageLimit = 1-cos(12*Double.pi/180)
    public init(samples: [WeatherSample], at date: Date) {
        self.samples = samples.filter { $0.usable(at:date) }
        vectors = self.samples.map { $0.coordinate.vector }
    }
    public func nearest(to point: GeoCoordinate) -> WeatherSample? {
        let n = point.vector
        guard let index = vectors.indices.min(by:{ 1-simd_dot(n,vectors[$0]) < 1-simd_dot(n,vectors[$1]) }),
              1-simd_dot(n,vectors[index]) <= coverageLimit else { return nil }
        return samples[index]
    }
    public func cloudCover(at point: GeoCoordinate) -> Double? {
        let n = point.vector
        var neighbors = [(Double,Int)]()
        for (index,v) in vectors.enumerated() {
            let distance = max(0,1-simd_dot(n,v))
            if distance < 0.075 { neighbors.append((distance,index)) }
        }
        neighbors.sort { $0.0 < $1.0 }
        guard let closest = neighbors.first, closest.0 <= coverageLimit else { return nil }
        var sum = 0.0, weights = 0.0
        for (distance,index) in neighbors.prefix(4) {
            let weight = 1/max(0.002,distance)
            sum += samples[index].cloudCover*weight; weights += weight
        }
        return sum/weights
    }
}

public enum WeatherGeometry {
    public static func precipitationPosition(at point: GeoCoordinate, progress: Double, offset: Double) -> SIMD3<Double> {
        let n = point.vector
        let tangent = simd_normalize(simd_cross(n,abs(n.y) > 0.95 ? SIMD3<Double>(1,0,0):SIMD3<Double>(0,1,0)))
        return n*(1.12-0.075*max(0,min(1,progress)))+tangent*offset
    }
}
