import XCTest
import Security
@testable import LittleEarth

final class VesselKeychainTests: XCTestCase {
    func testOnlyMissingItemIsUnconfigured() throws {
        XCTAssertNil(try VesselKeychain.decode(status:errSecItemNotFound,data:nil))
        for status in [errSecAuthFailed,errSecInteractionNotAllowed,errSecUserCanceled,errSecNotAvailable] {
            XCTAssertThrowsError(try VesselKeychain.decode(status:status,data:nil)) { error in
                XCTAssertEqual((error as? VesselKeychain.ReadError)?.status,status)
            }
        }
    }
    func testSuccessfulReadRequiresValidNonemptyUTF8() throws {
        XCTAssertEqual(try VesselKeychain.decode(status:errSecSuccess,data:Data("test-fixture".utf8)),"test-fixture")
        for data: Data? in [nil,Data(),Data([0xff])] {
            XCTAssertThrowsError(try VesselKeychain.decode(status:errSecSuccess,data:data))
        }
    }
}
