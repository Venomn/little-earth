import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"
    public static let preferenceKey = "appLanguage"
    public static func saved(in defaults: UserDefaults = .standard) -> Self {
        defaults.string(forKey:preferenceKey).flatMap(Self.init(rawValue:)) ?? .english
    }
    public func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue,forKey:Self.preferenceKey) }
    public var locale: Locale { Locale(identifier:self == .english ? "en_US":"zh_Hans_CN") }
    public var displayName: String { self == .english ? "English":"简体中文" }
}

public enum UIString: String, CaseIterable {
    case shipsSetup
    case shipsOff
    case shipsPaused
    case shipsConnecting
    case shipsConnected
    case shipsRetrying
    case shipsRetrySaved
    case shipsKeyUnavailable
    case shipsRejected
    case shipsSetupTitle
    case shipsSetupBody
    case shipsSave
    case cancel
    case shipsAccount
    case shipsRemove
    case shipsKeyError
    case shipsKeyErrorBody
    case shipsTheme
    case shipsUnnamed
    case shipsData
    case shipsReceived
    case shipsReported
    case shipsUnknown
    case shipsCaveat
    case shipsSource
    case appName
    case menuHint
    case showEarth
    case hideEarth
    case resetPosition
    case alwaysOnTop
    case size
    case sizeHelp
    case small
    case standard
    case large
    case language
    case refreshWeather
    case weatherSource
    case quit
    case updatingWeather
    case weatherUnavailable
    case cachedWeather
    case partialWeather
    case olderWeather
    case globalWeather
    case weatherHelp
    case globeAccessibility
    case globeHelp
    case expandWeather
    case collapseWeather
    case cultureSource
    case cultureSourceHelp
    case day
    case night
    case olderSuffix
    case compactWeather
    case compactUnavailable
    case wandering
    case cultureUnavailable
    case marineTheme
    case marineMissingTitle
    case marineMissingBody
    case oceanTitle
    case missingStoryTitle
    case cultureUnavailableBody
    case oceanBody
    case missingStoryBody
    case weatherMissingDetails
    case weatherMeasurements
    case weatherProvenance
    case clear
    case partlyCloudy
    case overcast
    case fog
    case drizzle
    case rain
    case snow
    case thunderstorm
    case weatherCode
    case previewNoWeather
    case previewUpdated
}

public struct L10n {
    public let language: AppLanguage
    public init(_ language: AppLanguage) { self.language = language }
    private static let tables: [AppLanguage:[String:String]] = {
        do { return try Dictionary(uniqueKeysWithValues:AppLanguage.allCases.map { language in
            (language,try JSONDecoder().decode([String:String].self,from:CoreResources.data("ui-\(language.rawValue).json")))
        }) } catch { fatalError("Missing bundled localization: \(error)") }
    }()
    public func text(_ key: UIString) -> String {
        Self.tables[language]?[key.rawValue] ?? Self.tables[.english]![key.rawValue]!
    }
    public func format(_ key: UIString, _ arguments: CVarArg...) -> String {
        String(format:text(key),locale:language.locale,arguments:arguments)
    }
    public func date(_ value: Date, includeDate: Bool = true, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale; formatter.timeZone = timeZone
        formatter.dateStyle = includeDate ? .medium:.none; formatter.timeStyle = .short
        return formatter.string(from:value)
    }
    public func weatherDescription(code: Int) -> String {
        switch code {
        case 0: return text(.clear)
        case 1,2: return text(.partlyCloudy)
        case 3: return text(.overcast)
        case 45,48: return text(.fog)
        case 51...57: return text(.drizzle)
        case 61...67,80...82: return text(.rain)
        case 71...77,85,86: return text(.snow)
        case 95...99: return text(.thunderstorm)
        default: return format(.weatherCode,code)
        }
    }
    public static func validateResources() throws {
        let pattern = try NSRegularExpression(pattern:"%(?:[0-9]+\\$)?[0-9.]*[@dif%]")
        func placeholders(_ value: String) -> [String] {
            pattern.matches(in:value,range:NSRange(value.startIndex...,in:value)).map { (value as NSString).substring(with:$0.range) }
        }
        for key in UIString.allCases {
            guard let english = tables[.english]?[key.rawValue], !english.isEmpty else { throw CultureError.invalidData }
            for language in AppLanguage.allCases {
                guard let translated = tables[language]?[key.rawValue], !translated.isEmpty,
                      placeholders(english) == placeholders(translated) else { throw CultureError.invalidData }
            }
        }
    }
}
