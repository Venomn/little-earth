import XCTest
@testable import EarthCore

private final class WeatherURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int,Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status,data) = try Self.handler(request)
            client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:status,httpVersion:nil,headerFields:nil)!,cacheStoragePolicy:.notAllowed)
            client?.urlProtocol(self,didLoad:data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self,didFailWithError:error) }
    }
    override func stopLoading() {}
}
final class WeatherClientTests: XCTestCase {
    func client() -> (WeatherClient,URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherURLProtocol.self]
        let session = URLSession(configuration:configuration)
        return (WeatherClient(session:session),session)
    }
    func testHTTPFailureRetainsSuccessfulBatchWithoutInventingMissingRegions() async {
        let (client,session) = client(); defer { session.invalidateAndCancel() }
        var calls = 0
        WeatherURLProtocol.handler = { request in
            calls += 1
            if calls == 2 { return (503,Data()) }
            let q = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
            let lat = q.first { $0.name == "latitude" }!.value!.split(separator:",")
            let lon = q.first { $0.name == "longitude" }!.value!.split(separator:",")
            let rows = zip(lat,lon).map { a,b in
                """
                {"latitude":\(a),"longitude":\(b),"current_units":{"temperature_2m":"°C","cloud_cover":"%","rain":"mm","showers":"mm","snowfall":"cm"},"current":{"time":1800000000,"interval":900,"temperature_2m":10,"cloud_cover":80,"rain":0,"showers":0,"snowfall":0,"weather_code":3}}
                """
            }
            return (200,Data(("["+rows.joined(separator:",")+"]").utf8))
        }
        let result = await client.fetch(points:Array(WeatherGrid.coordinates.prefix(25)))
        XCTAssertEqual(result.samples.count,24)
        XCTAssertEqual(result.failedBatches,1)
        XCTAssertEqual(calls,2)
    }
    func testRateLimitStopsRemainingRequests() async {
        let (client,session) = client(); defer { session.invalidateAndCancel() }
        var calls = 0
        WeatherURLProtocol.handler = { _ in calls += 1; return (429,Data()) }
        let result = await client.fetch(points:Array(WeatherGrid.coordinates.prefix(48)))
        XCTAssertTrue(result.samples.isEmpty)
        XCTAssertEqual(result.failedBatches,1)
        XCTAssertEqual(calls,1)
    }
    func testInventoryKeepsNewerDataAndDoesNotSubstituteFarAwayWeather() throws {
        let tests = WeatherTests()
        let coordinate = GeoCoordinate(latitude:0,longitude:0)
        let sample = try XCTUnwrap(WeatherParser.parse(Data(tests.row(lat:0,lon:0).utf8),requested:[coordinate],fetchedAt:tests.now).first)
        var inventory = WeatherInventory(samples:[sample])
        let old = tests.row(lat:0,lon:0).replacingOccurrences(of:"1800000000",with:"1799990000").replacingOccurrences(of:"\"cloud_cover\":80",with:"\"cloud_cover\":0")
        inventory.merge(try WeatherParser.parse(Data(old.utf8),requested:[coordinate],fetchedAt:tests.now.addingTimeInterval(100)))
        XCTAssertEqual(inventory.nearest(to:coordinate,at:tests.now)?.cloudCover,80)
        XCTAssertNil(inventory.nearest(to:.init(latitude:45,longitude:120),at:tests.now))
        XCTAssertTrue(inventory.usable(at:tests.now.addingTimeInterval(10801)).isEmpty)
    }
}
