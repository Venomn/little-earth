import XCTest
@testable import EarthCore

final class GlobeSizingTests: XCTestCase {
    func testScreenEdgesNegativeDisplaysAndSmallScreensKeepASquareVisible() throws {
        for screen in [CGRect(x:-1440,y:40,width:1440,height:860),CGRect(x:0,y:0,width:150,height:100)] {
            let initial = CGRect(x:screen.maxX-240,y:screen.maxY-240,width:240,height:240)
            for width: CGFloat in [100,180,317,660,1000] {
                let resized = GlobeSizing.fitting(CGRect(x:initial.minX,y:initial.minY,width:width,height:width),to:screen)
                XCTAssertTrue(screen.contains(resized))
                XCTAssertEqual(resized.width,resized.height)
            }
        }
    }

    func testCustomSizeSurvivesRestorationAndInvalidPreferencesAreBounded() {
        for width: CGFloat in [180,240,317.25,330,489.5,660] {
            XCTAssertEqual(GlobeSizing.restoredWidth(savedGlobeSize:Double(width/1.5)),width,accuracy:0.0001)
        }
        for invalid in [0.0,-1,.nan,.infinity] {
            XCTAssertEqual(GlobeSizing.restoredWidth(savedGlobeSize:invalid),240)
        }
        XCTAssertEqual(GlobeSizing.restoredWidth(savedGlobeSize:999999),660)
        XCTAssertEqual(GlobeSizing.restoredWidth(savedGlobeSize:1),180)
    }
}
