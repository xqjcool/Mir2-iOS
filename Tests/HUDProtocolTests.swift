import XCTest
@testable import MirNavigation

final class HUDProtocolTests:XCTestCase {
    private func bytes(_ hex:String)->[UInt8] {
        let a=Array(hex)
        return stride(from:0,to:a.count,by:2).map { UInt8(String(a[$0...($0+1)]),radix:16)! }
    }
    func testCapturedAbilityUsesRealCurrentAndMaximumValues() {
        // Captured SM_ABILITY from equipment-initial-wire.json.
        let b=bytes("0600000000000101000000001d00200034002000000000002b0000005000000038003e000011000f")
        let state=MirVitals.decode(b)
        XCTAssertEqual(state?.level,6)
        XCTAssertEqual(state?.hp,29);XCTAssertEqual(state?.maxHP,52)
        XCTAssertEqual(state?.mp,32);XCTAssertEqual(state?.maxMP,32)
        XCTAssertEqual(state?.experience,43);XCTAssertEqual(state?.maxExperience,80)
        for length in 0..<40 { XCTAssertNil(MirVitals.decode(Array(b.prefix(length)))) }
        XCTAssertNil(MirVitals.decode(b+[0]))
    }
    func testAnotherCapturedCharacterDoesNotReusePreviousVitals() {
        let b=bytes("0a00000100000307000000004b002e0059002e0000000000240000002c0100004d00530000140714")
        let state=MirVitals.decode(b)
        XCTAssertEqual(state?.level,10)
        XCTAssertEqual(state?.hp,75);XCTAssertEqual(state?.maxHP,89)
        XCTAssertEqual(state?.mp,46);XCTAssertEqual(state?.maxExperience,300)
    }
}
