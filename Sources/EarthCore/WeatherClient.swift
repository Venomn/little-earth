import Foundation

public struct WeatherFetchResult: Sendable {
    public let samples: [WeatherSample]
    public let failedBatches: Int
    public func isComplete(for requested: [GeoCoordinate], at date: Date) -> Bool {
        failedBatches == 0 && requested.allSatisfy { point in samples.contains { $0.coordinate == point && $0.usable(at:date) } }
    }
}
public struct WeatherClient {
    private let session: URLSession
    public init(session: URLSession = .shared) { self.session = session }
    public static func url(for points: [GeoCoordinate]) -> URL {
        var url = URLComponents(string:"https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name:"latitude",value:points.map { String($0.latitude) }.joined(separator:",")),
            URLQueryItem(name:"longitude",value:points.map { String($0.longitude) }.joined(separator:",")),
            URLQueryItem(name:"current",value:"temperature_2m,cloud_cover,rain,showers,snowfall,weather_code"),
            URLQueryItem(name:"timeformat",value:"unixtime"), URLQueryItem(name:"timezone",value:"GMT"),
            URLQueryItem(name:"cell_selection",value:"nearest"), URLQueryItem(name:"forecast_days",value:"1")]
        return url.url!
    }
    public func fetch(points: [GeoCoordinate] = WeatherGrid.coordinates) async -> WeatherFetchResult {
        var samples = [WeatherSample](), failed = 0
        for start in stride(from:0,to:points.count,by:24) {
            if Task.isCancelled { break }
            let batch = Array(points[start..<min(start+24,points.count)])
            do {
                var request = URLRequest(url:Self.url(for:batch),cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:25)
                request.setValue("LittleEarth/0.3 personal desktop companion",forHTTPHeaderField:"User-Agent")
                let (data,response) = try await session.data(for:request)
                guard let response = response as? HTTPURLResponse else { throw WeatherError.invalidResponse }
                guard response.statusCode == 200 else { throw WeatherError.http(response.statusCode) }
                samples += try WeatherParser.parse(data,requested:batch,fetchedAt:Date())
            } catch {
                failed += 1
                if case WeatherError.http(429) = error { break }
            }
        }
        return WeatherFetchResult(samples:samples,failedBatches:failed)
    }
}
