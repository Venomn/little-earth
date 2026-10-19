import Foundation

public struct WeatherRefreshGate {
    public private(set) var isLoading = false
    private var generation = 0
    private var lastAttempt: Date?
    private var previousAttempt: Date?
    public init(lastCompleted: Date? = nil) { lastAttempt = lastCompleted }
    public mutating func begin(at date: Date, force: Bool = false) -> Int? {
        guard !isLoading else { return nil }
        if let lastAttempt, date.timeIntervalSince(lastAttempt) >= 0,
           date.timeIntervalSince(lastAttempt) < (force ? 600:3600) { return nil }
        previousAttempt = lastAttempt; lastAttempt = date
        generation += 1; isLoading = true
        return generation
    }
    public mutating func cancel() {
        if isLoading { lastAttempt = previousAttempt }
        generation += 1; isLoading = false
    }
    public mutating func complete(_ token: Int) -> Bool {
        guard isLoading, token == generation else { return false }
        isLoading = false; return true
    }
}
