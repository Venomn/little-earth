import Foundation

public enum WeatherError: Error { case invalidResponse, invalidCache, http(Int) }

public struct WeatherSample: Codable, Equatable, Sendable {
    public let coordinate: GeoCoordinate
    public let temperature: Double
    public let cloudCover: Double
    public let rainMMPerHour: Double
    public let snowCMPerHour: Double
    public let code: Int
    public let validAt: Date
    public let fetchedAt: Date
    public var isValid: Bool {
        coordinate.isValid && temperature.isFinite && (-100...70).contains(temperature)
        && cloudCover.isFinite && (0...100).contains(cloudCover)
        && rainMMPerHour.isFinite && (0...2000).contains(rainMMPerHour)
        && snowCMPerHour.isFinite && (0...1000).contains(snowCMPerHour)
        && (0...99).contains(code) && validAt.timeIntervalSince1970.isFinite && fetchedAt.timeIntervalSince1970.isFinite
    }
    public func usable(at date: Date) -> Bool {
        let age = date.timeIntervalSince(validAt)
        return isValid && age >= -300 && age <= 10800
    }
    public func description(in language: AppLanguage) -> String { L10n(language).weatherDescription(code:code) }

}

public struct WeatherSnapshot: Codable {
    public let version: Int
    public let samples: [WeatherSample]
    public init(samples: [WeatherSample]) { version = 1; self.samples = samples }
    public static func decode(_ data: Data) throws -> Self {
        let value = try JSONDecoder().decode(Self.self,from:data)
        var coordinates = Set<String>()
        guard value.version == 1, value.samples.count <= 256,
              value.samples.allSatisfy({ $0.isValid && coordinates.insert($0.coordinate.label).inserted }) else { throw WeatherError.invalidCache }
        return value
    }
}

public enum WeatherParser {
    private struct Response: Decodable {
        let latitude: Double; let longitude: Double
        let current_units: [String:String]?
        let current: Current?
    }
    private struct Current: Decodable {
        let time: Double
        let interval: Double
        let temperature_2m: Double?
        let cloud_cover: Double?
        let rain: Double?
        let showers: Double?
        let snowfall: Double?
        let weather_code: Int?
    }
    public static func parse(_ data: Data, requested: [GeoCoordinate], fetchedAt: Date) throws -> [WeatherSample] {
        let decoder = JSONDecoder()
        let responses: [Response]
        if let array = try? decoder.decode([Response].self,from:data) { responses = array }
        else { responses = [try decoder.decode(Response.self,from:data)] }
        var used = Set<Int>(), samples = [WeatherSample]()
        for response in responses {
            let point = GeoCoordinate(latitude:response.latitude,longitude:response.longitude)
            guard point.isValid, let match = requested.indices.min(by:{ requested[$0].distance(to:point) < requested[$1].distance(to:point) }),
                  requested[match].distance(to:point) < 2, used.insert(match).inserted else { throw WeatherError.invalidResponse }
            guard let c = response.current, let units = response.current_units,
                  units["temperature_2m"] == "°C", units["cloud_cover"] == "%", units["rain"] == "mm", units["showers"] == "mm", units["snowfall"] == "cm",
                  c.interval.isFinite, c.interval > 0, c.interval <= 3600,
                  let temperature = c.temperature_2m, let cloud = c.cloud_cover,
                  let rain = c.rain, rain >= 0, let showers = c.showers, showers >= 0,
                  let snow = c.snowfall, snow >= 0, let code = c.weather_code else { continue }
            let sample = WeatherSample(coordinate:requested[match],temperature:temperature,cloudCover:cloud,
                                       rainMMPerHour:(rain+showers)*3600/c.interval,snowCMPerHour:snow*3600/c.interval,
                                       code:code,validAt:Date(timeIntervalSince1970:c.time),fetchedAt:fetchedAt)
            if sample.isValid { samples.append(sample) }
        }
        return samples
    }
}
