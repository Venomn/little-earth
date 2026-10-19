import Foundation

public struct CityLight: Decodable {
    public let name: String
    public let latitude: Double
    public let longitude: Double
    public let population: Double
    public var coordinate: GeoCoordinate { GeoCoordinate(latitude:latitude,longitude:longitude) }
}

public struct CityLightCatalog {
    public let cities: [CityLight]
    public init(data: Data) throws {
        let values = try JSONDecoder().decode([CityLight].self,from:data)
        guard !values.isEmpty, values.allSatisfy({ !$0.name.isEmpty && $0.coordinate.isValid && $0.population.isFinite && $0.population >= 0 }) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        cities = values
    }
    public static func bundled() throws -> CityLightCatalog {
        try CityLightCatalog(data:CoreResources.data("cities.json"))
    }
}
