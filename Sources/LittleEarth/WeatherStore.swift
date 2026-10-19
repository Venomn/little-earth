import Foundation
import EarthCore

@MainActor final class WeatherStore {
    private(set) var inventory = WeatherInventory()
    private var gate = WeatherRefreshGate()
    var loading: Bool { gate.isLoading }
    private(set) var offline = false
    private var active = false
    private var task: Task<Void,Never>?
    private var timer: Timer?
    var onChange: (() -> Void)?
    private let cacheURL: URL

    init() {
        let directory = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("LittleEarth",isDirectory:true)
        cacheURL = directory.appendingPathComponent("weather-v1.json")
        if let data = try? Data(contentsOf:cacheURL), let cache = try? WeatherSnapshot.decode(data) {
            inventory = WeatherInventory(samples:cache.samples)
            gate = WeatherRefreshGate(lastCompleted:cache.samples.map(\.fetchedAt).max())
            offline = true
        }
    }
    func setActive(_ value: Bool) {
        guard value != active else { return }
        active = value
        if value {
            refresh()
            timer = Timer.scheduledTimer(withTimeInterval:60,repeats:true) { [weak self] _ in
                Task { @MainActor in self?.refresh(); self?.onChange?() }
            }
        } else {
            gate.cancel(); task?.cancel(); task = nil
            timer?.invalidate(); timer = nil
        }
    }
    func refresh(force: Bool = false) {
        guard active, task == nil else { return }
        guard let token = gate.begin(at:Date(),force:force) else { return }
        onChange?()
        task = Task { [weak self] in
            let result = await WeatherClient().fetch()
            guard let self, !Task.isCancelled, self.gate.complete(token) else { return }
            self.inventory.merge(result.samples)
            self.offline = !result.isComplete(for:WeatherGrid.coordinates,at:Date())
            self.task = nil
            let snapshot = WeatherSnapshot(samples:self.inventory.samples)
            do {
                try FileManager.default.createDirectory(at:self.cacheURL.deletingLastPathComponent(),withIntermediateDirectories:true)
                try JSONEncoder().encode(snapshot).write(to:self.cacheURL,options:.atomic)
            } catch { NSLog("LittleEarth weather cache write unavailable: %@",error.localizedDescription) }
            self.onChange?()
        }
    }
    func statusText(in language: AppLanguage) -> String {
        let strings = L10n(language)
        let samples = inventory.usable(at:Date())
        if loading { return strings.text(.updatingWeather) }
        if samples.isEmpty { return strings.text(.weatherUnavailable) }
        if offline { return strings.text(.cachedWeather) }
        if samples.count < WeatherGrid.coordinates.count { return strings.text(.partialWeather) }
        if samples.contains(where:{ Date().timeIntervalSince($0.validAt) > 5400 }) { return strings.text(.olderWeather) }
        let time = samples.map(\.validAt).min()!
        return strings.format(.globalWeather,strings.date(time,includeDate:false))
    }
}
