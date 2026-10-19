import Foundation
import CoreFoundation

public struct VesselSample: Codable, Equatable, Sendable {
    public let mmsi: String
    public let name: String?
    public let coordinate: GeoCoordinate
    public let speedKnots: Double?
    public let courseDegrees: Double?
    public let headingDegrees: Double?
    public let receivedAt: Date
    public let reportedAt: Date?
    public init(mmsi: String, name: String?, coordinate: GeoCoordinate, speedKnots: Double?,
                courseDegrees: Double?, headingDegrees: Double?, receivedAt: Date, reportedAt: Date? = nil) {
        self.mmsi = mmsi; self.name = name; self.coordinate = coordinate
        self.speedKnots = speedKnots; self.courseDegrees = courseDegrees; self.headingDegrees = headingDegrees
        self.receivedAt = receivedAt; self.reportedAt = reportedAt
    }
    public func usable(at date: Date) -> Bool { VesselFreshness.isValid(self,at:date) }
}

/// Never carries provider text: service errors may echo credentials or subscription data.
public enum AISParseError: Error, Equatable, Sendable { case malformedFrame, serviceRejected }

public enum AISParser {
    /// Only current position bodies are accepted. MetaData coordinates are last-known
    /// context, not evidence that this message contains a valid position.
    public static func parse(_ data: Data, receivedAt: Date) throws -> VesselSample? {
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw AISParseError.malformedFrame }
        guard let envelope = object as? [String: Any] else { throw AISParseError.malformedFrame }
        if envelope.keys.contains(where: { $0.lowercased() == "error" }) {
            throw AISParseError.serviceRejected
        }
        guard let type = envelope["MessageType"] as? String else { throw AISParseError.malformedFrame }
        if type.lowercased() == "error" { throw AISParseError.serviceRejected }
        guard ["PositionReport", "StandardClassBPositionReport", "ExtendedClassBPositionReport"].contains(type)
        else { return nil }
        guard let messages = envelope["Message"] as? [String: Any],
              let position = messages[type] as? [String: Any],
              let metadata = envelope["MetaData"] as? [String: Any] else {
            throw AISParseError.malformedFrame
        }
        guard let valid = position["Valid"] as? NSNumber, CFGetTypeID(valid) == CFBooleanGetTypeID(), valid.boolValue,
              let id = mmsi(position["UserID"]), id == mmsi(metadata["MMSI"]),
              let latitude = number(position["Latitude"]), let longitude = number(position["Longitude"])
        else { return nil }
        let coordinate = GeoCoordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { return nil }

        var reportedAt: Date?
        if let rawTimestamp = metadata["time_utc"] {
            guard let text = rawTimestamp as? String, let timestamp = timestamp(text) else { return nil }
            reportedAt = timestamp
        }
        let name = (metadata["ShipName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "@")))
        let sample = VesselSample(mmsi: id, name: name.flatMap { $0.isEmpty ? nil : $0 },
                                  coordinate: coordinate,
                                  speedKnots: motion(position["Sog"], below: 102.3),
                                  courseDegrees: motion(position["Cog"], below: 360),
                                  headingDegrees: motion(position["TrueHeading"], below: 360),
                                  receivedAt: receivedAt, reportedAt: reportedAt)
        return VesselFreshness.isValid(sample, at: receivedAt) ? sample : nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func mmsi(_ value: Any?) -> String? {
        if let text = value as? String { return VesselFreshness.validMMSI(text) ? text : nil }
        guard let number = number(value), number.rounded() == number,
              number >= 100_000_000, number <= 999_999_999 else { return nil }
        return String(Int(number))
    }

    private static func motion(_ value: Any?, below upperBound: Double) -> Double? {
        guard let value = number(value), value >= 0, value < upperBound else { return nil }
        return value
    }

    private static func timestamp(_ text: String) -> Date? {
        // AISStream has emitted Go's UTC string as well as ISO-8601 timestamps.
        var normalized = text
        if normalized.hasSuffix(" +0000 UTC") {
            normalized = String(normalized.dropLast(" +0000 UTC".count)) + "Z"
            if let separator = normalized.firstIndex(of: " ") { normalized.replaceSubrange(separator...separator, with: "T") }
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: normalized) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: normalized)
    }
}

/// The parser and both inventory read boundaries share the same freshness rules.
private enum VesselFreshness {
    static let lifetime: TimeInterval = 15 * 60
    static let futureTolerance: TimeInterval = 60

    static func validMMSI(_ value: String) -> Bool {
        value.utf8.count == 9 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    static func isValid(_ sample: VesselSample, at now: Date) -> Bool {
        guard validMMSI(sample.mmsi), sample.coordinate.isValid, now.timeIntervalSince1970.isFinite,
              recent(sample.receivedAt, at: now) else { return false }
        if let reported = sample.reportedAt {
            return recent(reported, at: now) && recent(reported, at: sample.receivedAt)
        }
        return true
    }

    private static func recent(_ timestamp: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age.isFinite && age >= -futureTolerance && age <= lifetime
    }

    static func eventTime(_ sample: VesselSample) -> Date { sample.reportedAt ?? sample.receivedAt }
}

public struct VesselInventory: Sendable {
    private var samples: [String: VesselSample] = [:]
    private static let capacity = 2_000
    public init() {}

    public mutating func merge(_ sample: VesselSample, at: Date) {
        samples = samples.filter { VesselFreshness.isValid($0.value, at: at) }
        guard VesselFreshness.isValid(sample, at: at) else { return }
        if let previous = samples[sample.mmsi] {
            let incomingTime = VesselFreshness.eventTime(sample), previousTime = VesselFreshness.eventTime(previous)
            guard incomingTime > previousTime ||
                    (incomingTime == previousTime && sample.receivedAt > previous.receivedAt) else { return }
        }
        samples[sample.mmsi] = sample
        if samples.count > Self.capacity {
            // Evict oldest event, with deterministic MMSI tie-breaking.
            let oldest = samples.values.min {
                let left = VesselFreshness.eventTime($0), right = VesselFreshness.eventTime($1)
                return left == right ? $0.mmsi < $1.mmsi : left < right
            }
            if let oldest { samples.removeValue(forKey: oldest.mmsi) }
        }
    }

    public mutating func clear() { samples.removeAll(keepingCapacity: false) }

    /// Fifteen-degree spherical spacing leaves breathing room around felt boats,
    /// including dense European waters, the dateline and poles. Stable MMSI order
    /// prevents arbitrary dictionary churn or reshuffling on timestamp updates.
    /// Sparsification affects rendering only; sample(mmsi:at:) retains every vessel.
    public func visible(at: Date, limit: Int = 28) -> [VesselSample] {
        guard limit > 0 else { return [] }
        let candidates = samples.values.filter { VesselFreshness.isValid($0, at: at) }.sorted { $0.mmsi < $1.mmsi }
        var result: [VesselSample] = []
        for candidate in candidates {
            guard result.allSatisfy({ $0.coordinate.distance(to: candidate.coordinate) >= 15 }) else { continue }
            result.append(candidate)
            if result.count >= limit { break }
        }
        return result
    }

    public func sample(mmsi: String, at: Date) -> VesselSample? {
        guard let sample = samples[mmsi], VesselFreshness.isValid(sample, at: at) else { return nil }
        return sample
    }
}
