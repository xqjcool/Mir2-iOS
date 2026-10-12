import XCTest
@testable import MirNavigation

final class BlendTests: XCTestCase {
    func testAnimationClockAndAtlasBudget() {
        let item = StreamItem(id: "light", file: "atlas.png",
                              rect: StreamRect(x: -53, y: -181, width: 100, height: 100),
                              z: 1000, frameCount: 10, frameDuration: 0.05)
        XCTAssertEqual(item.bytes, 400000)
        XCTAssertEqual(item.textureHeight, 1000)
        XCTAssertEqual(item.frame(at: 0), 0)
        XCTAssertEqual(item.frame(at: 0.051), 1)
        XCTAssertEqual(item.frame(at: 0.451), 9)
        XCTAssertEqual(item.frame(at: 0.501), 0)
        let catalog = StreamCatalog([item])
        XCTAssertEqual(catalog.query(StreamRect(x: -50,y: -180,width: 10,height: 10)), ["light"])
        XCTAssertTrue(catalog.query(StreamRect(x: 0,y: 100,width: 10,height: 10)).isEmpty)
    }
}
