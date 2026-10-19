import Foundation

public struct WeatherInventory {
    public private(set) var samples: [WeatherSample] = []
    public init(samples: [WeatherSample] = []) { self.samples = samples.filter(\.isValid) }
    public mutating func merge(_ incoming: [WeatherSample]) {
        for sample in incoming where sample.isValid {
            if let index = samples.firstIndex(where:{ $0.coordinate == sample.coordinate }) {
                if sample.validAt >= samples[index].validAt { samples[index] = sample }
            } else { samples.append(sample) }
        }
    }
    public func usable(at date: Date) -> [WeatherSample] { samples.filter { $0.usable(at:date) } }
    public func nearest(to coordinate: GeoCoordinate, at date: Date) -> WeatherSample? {
        RegionalWeather(samples:samples,at:date).nearest(to:coordinate)
    }
}
