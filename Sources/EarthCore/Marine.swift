import Foundation

public struct MarineEntry: Codable {
    public let id: String
    public let regionIDs: [String]
    public let latitudeRange: [Double]
    public let english: CultureText
    public let chinese: CultureText
    public let sourceURL: String
    public func text(in language: AppLanguage) -> CultureText {
        language == .english ? english:chinese
    }
}

public struct MarineStory {
    public let region: Place
    public let entry: MarineEntry
}

/// Regional educational profiles, never observations of fish at a clicked point.
public struct MarineCatalog {
    public let entries: [MarineEntry]
    private let marine: PlaceAtlas
    private let land: PlaceAtlas
    public init(data: Data) throws {
        marine = try PlaceAtlas(data:CoreResources.data("marine-regions.geojson"),idKey:"id",chineseNameKey:"name_zh",englishNameKey:"name_en")
        land = try PlaceAtlas.bundled()
        let values = try JSONDecoder().decode([MarineEntry].self,from:data)
        guard !values.isEmpty, Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ entry in
            !entry.id.isEmpty && !entry.regionIDs.isEmpty && !entry.regionIDs.contains("Caspian Sea") &&
            entry.english.isValid && entry.chinese.isValid && entry.latitudeRange.count == 2 &&
            entry.latitudeRange.allSatisfy { $0.isFinite && (-90...90).contains($0) } &&
            entry.latitudeRange[0] < entry.latitudeRange[1] &&
            URL(string:entry.sourceURL)?.scheme == "https" && URL(string:entry.sourceURL)?.host != nil
        }) else { throw CultureError.invalidData }
        entries = values
    }
    public static func bundled() throws -> MarineCatalog { try MarineCatalog(data:CoreResources.data("marine.json")) }
    public func region(at point: GeoCoordinate) -> Place? {
        guard point.isValid, !land.containsRegion(at:point),
              let region = marine.place(at:point), region.id != "Caspian Sea" else { return nil }
        return region
    }
    public func story(at point: GeoCoordinate) -> MarineStory? {
        guard let region = region(at:point) else { return nil }
        let matches = entries.filter {
            $0.regionIDs.contains(region.id) && point.latitude >= $0.latitudeRange[0] && point.latitude < $0.latitudeRange[1]
        }
        // No nearest-basin borrowing and no arbitrary choice for conflicting profiles.
        guard matches.count == 1 else { return nil }
        return MarineStory(region:region,entry:matches[0])
    }
}
