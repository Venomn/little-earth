import Foundation

public struct Place: Equatable {
    public let id: String
    public let name: String
    public let englishName: String
    public func name(in language: AppLanguage) -> String { language == .english ? englishName:name }
}

// Natural Earth's generalized outlines are for region discovery, not precise borders.
public struct PlaceAtlas {
    private struct Area {
        let place: Place
        let polygons: [[[[Double]]]]
    }
    private let areas: [Area]
    public init(data: Data, idKey: String = "ADM0_A3", chineseNameKey: String = "NAME_ZH", englishNameKey: String = "NAME_EN") throws {
        guard let root = try JSONSerialization.jsonObject(with:data) as? [String:Any],
              let features = root["features"] as? [[String:Any]] else { throw CultureError.invalidData }
        areas = try features.map { feature in
            guard let properties = feature["properties"] as? [String:Any],
                  let id = properties[idKey] as? String,
                  let name = properties[chineseNameKey] as? String,
                  let geometry = feature["geometry"] as? [String:Any] else { throw CultureError.invalidData }
            let polygons: [[[[Double]]]]
            if geometry["type"] as? String == "Polygon", let rings = geometry["coordinates"] as? [[[Double]]] { polygons = [rings] }
            else if geometry["type"] as? String == "MultiPolygon", let values = geometry["coordinates"] as? [[[[Double]]]] { polygons = values }
            else { throw CultureError.invalidData }
            guard polygons.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.count >= 4 && $0.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isFinite) } } }) else { throw CultureError.invalidData }
            return Area(place:Place(id:id,name:name,englishName:(properties[englishNameKey] as? String) ?? (properties["NAME"] as? String) ?? id),polygons:polygons)
        }
    }
    public static func bundled() throws -> PlaceAtlas { try PlaceAtlas(data:CoreResources.data("countries.geojson")) }
    public func place(at point: GeoCoordinate) -> Place? {
        guard point.isValid else { return nil }
        let matches = matchingAreas(at:point)
        return matches.count == 1 ? matches[0].place : nil
    }
    // Includes ambiguous overlaps: unresolved land must not become ocean content.
    public func containsRegion(at point: GeoCoordinate) -> Bool {
        point.isValid && !matchingAreas(at:point).isEmpty
    }
    private func matchingAreas(at point: GeoCoordinate) -> [Area] {
        areas.filter { area in area.polygons.contains { polygon in
            Self.contains(point,in:polygon[0]) && !polygon.dropFirst().contains { Self.contains(point,in:$0) }
        } }
    }
    private static func contains(_ point: GeoCoordinate, in ring: [[Double]]) -> Bool {
        // Unwrap adjacent vertices, then put the query on that same longitude branch.
        var vertices = [(Double,Double)](), previous = ring[0][0], previousLatitude = ring[0][1]
        for vertex in ring {
            var longitude = vertex[0]
            // A map edge across a pole closes a full polar cap. Unwrapping it
            // like an ordinary dateline crossing collapses the top of the cap.
            let polarClosure = abs(previousLatitude) == 90 && vertex[1] == previousLatitude
            if !polarClosure {
                while longitude - previous > 180 { longitude -= 360 }
                while longitude - previous < -180 { longitude += 360 }
            }
            vertices.append((longitude,vertex[1])); previous = longitude; previousLatitude = vertex[1]
        }
        let center = (vertices.map(\.0).min()! + vertices.map(\.0).max()!)/2
        var x = point.longitude
        while x-center > 180 { x -= 360 }
        while x-center < -180 { x += 360 }
        let y = point.latitude
        var inside = false
        for i in 1..<vertices.count {
            let a = vertices[i-1], b = vertices[i]
            if (a.1 > y) != (b.1 > y), x < (b.0-a.0)*(y-a.1)/(b.1-a.1)+a.0 { inside.toggle() }
        }
        return inside
    }
}

public enum CultureError: Error { case invalidData, missingResource(String) }
enum CoreResources {
    static func data(_ name: String) throws -> Data {
        // Installed apps place SwiftPM bundles in Contents/Resources.
        let installed = Bundle.main.resourceURL?.appendingPathComponent("LittleEarth_EarthCore.bundle/Resources/\(name)")
        if let installed, FileManager.default.fileExists(atPath:installed.path) { return try Data(contentsOf:installed) }
        guard let url = Bundle.module.url(forResource:name,withExtension:nil,subdirectory:"Resources") else { throw CultureError.missingResource(name) }
        return try Data(contentsOf:url)
    }
}

public struct CultureText: Codable {
    public let regionLabel: String
    public let theme: String
    public let title: String
    public let body: String
    public let sourceName: String
    var isValid: Bool { [regionLabel,theme,title,body,sourceName].allSatisfy { !$0.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty } && body.count <= 420 }
}

public struct CultureEntry: Codable {
    public let id: String
    public let placeIDs: [String]
    public let regionLabel: String
    public let timeZone: String
    public let theme: String
    public let title: String
    public let body: String
    public let sourceName: String
    public let sourceURL: String
    public let months: [Int]
    public let window: [Int]?
    public let bounds: [Double]?
    public let priority: Int
    public let english: CultureText
    public func text(in language: AppLanguage) -> CultureText {
        language == .english ? english:CultureText(regionLabel:regionLabel,theme:theme,title:title,body:body,sourceName:sourceName)
    }

    func matches(_ point: GeoCoordinate, date: Date) -> Bool {
        if let bounds, !(bounds[0]...bounds[2]).contains(point.longitude) || !(bounds[1]...bounds[3]).contains(point.latitude) { return false }
        var calendar = Calendar(identifier:.gregorian)
        calendar.timeZone = TimeZone(identifier:timeZone)!
        let month = calendar.component(.month,from:date), day = calendar.component(.day,from:date)
        if !months.isEmpty && !months.contains(month) { return false }
        if let window {
            let value = month*100+day
            return window[0] <= window[1] ? (window[0]...window[1]).contains(value) : value >= window[0] || value <= window[1]
        }
        return true
    }
}

public struct CultureCatalog {
    public let entries: [CultureEntry]
    public init(data: Data) throws {
        let values = try JSONDecoder().decode([CultureEntry].self,from:data)
        guard Set(values.map(\.id)).count == values.count, values.allSatisfy({ entry in
            entry.english.isValid && !entry.id.isEmpty && !entry.placeIDs.isEmpty && !entry.regionLabel.isEmpty && !entry.title.isEmpty && !entry.body.isEmpty && entry.body.count <= 110 && !entry.sourceName.isEmpty &&
            URL(string:entry.sourceURL)?.scheme == "https" && URL(string:entry.sourceURL)?.host != nil && TimeZone(identifier:entry.timeZone) != nil &&
            entry.months.allSatisfy { (1...12).contains($0) } &&
            (entry.window.map { $0.count == 2 && $0.allSatisfy { value in
                var calendar = Calendar(identifier:.gregorian); calendar.timeZone = TimeZone(secondsFromGMT:0)!
                guard let date = calendar.date(from:DateComponents(year:2000,month:value/100,day:value%100)) else { return false }
                return calendar.component(.month,from:date) == value/100 && calendar.component(.day,from:date) == value%100
            } } ?? true) &&
            (entry.bounds.map { $0.count == 4 && $0.allSatisfy(\.isFinite) && $0[0] <= $0[2] && $0[1] <= $0[3] && $0[0] >= -180 && $0[2] <= 180 && $0[1] >= -90 && $0[3] <= 90 } ?? true)
        }) else { throw CultureError.invalidData }
        entries = values.sorted { $0.priority == $1.priority ? $0.id < $1.id : $0.priority > $1.priority }
    }
    public static func bundled() throws -> CultureCatalog { try CultureCatalog(data:CoreResources.data("culture.json")) }
    public func story(placeID: String, at point: GeoCoordinate, date: Date) -> CultureEntry? {
        guard point.isValid, date.timeIntervalSince1970.isFinite else { return nil }
        return entries.first { $0.placeIDs.contains(placeID) && $0.matches(point,date:date) }
    }
}
