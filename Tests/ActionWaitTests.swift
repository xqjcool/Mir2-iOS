import XCTest
@testable import MirNavigation
final class ActionWaitTests:XCTestCase {
    func testShortDelayDoesNotDisconnect() {
        XCTAssertEqual(MirActionWait.decision(elapsed:4.99),.waiting)
        XCTAssertEqual(MirActionWait.decision(elapsed:5),.delayed)
        XCTAssertEqual(MirActionWait.decision(elapsed:12),.delayed)
        XCTAssertEqual(MirActionWait.decision(elapsed:19.99),.delayed)
        XCTAssertEqual(MirActionWait.decision(elapsed:20),.expired)
    }
}
