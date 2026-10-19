import Foundation
import EarthCore

extension LocalVesselStore {
    func statusText(in language: AppLanguage) -> String {
        let strings = L10n(language)
        switch state {
        case .credentialUnavailable: return strings.text(.shipsKeyUnavailable)
        case .unconfigured: return strings.text(.shipsOff)
        case .paused: return strings.text(.shipsPaused)
        case .connecting: return strings.text(.shipsConnecting)
        case .connected: return strings.format(.shipsConnected,visible.count)
        case .retrying: return strings.text(.shipsRetrying)
        case .rejected: return strings.text(.shipsRejected)
        }
    }
}

enum VesselCard {
    static func make(_ sample: VesselSample, language: AppLanguage, weather: String, weatherDetails: String) -> PlaceCard {
        let strings = L10n(language)
        func value(_ number: Double?, suffix: String) -> String {
            number.map { String(format:"%.1f",locale:language.locale,$0)+suffix } ?? strings.text(.shipsUnknown)
        }
        let report = sample.reportedAt.map { strings.format(.shipsReported,strings.date($0)) }
            ?? strings.format(.shipsReceived,strings.date(sample.receivedAt))
        let body = strings.format(.shipsData,sample.mmsi,value(sample.speedKnots,suffix:language == .english ? " kn":" 节"),value(sample.courseDegrees,suffix:"°"),value(sample.headingDegrees,suffix:"°"),report,strings.text(.shipsCaveat))
        return PlaceCard(language:language,region:sample.coordinate.label,theme:strings.text(.shipsTheme),title:sample.name ?? strings.text(.shipsUnnamed),body:body,weather:weather,weatherDetails:weatherDetails,sourceName:strings.text(.shipsSource),sourceURL:URL(string:"https://www.aisstream.io/documentation/"))
    }
}
