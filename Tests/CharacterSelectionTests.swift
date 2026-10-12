import XCTest
@testable import MirNavigation
final class CharacterSelectionTests:XCTestCase {
    func testTwoSlotsAndChineseName() {
        let characters=MirWire.characterList("*ProbeBeta/0/0/2/0/经典道士/2/0/1/1/",expectedCount:2)
        XCTAssertEqual(characters?.map(\.name),["ProbeBeta","经典道士"])
        XCTAssertEqual(characters?.last?.job,2)
        XCTAssertEqual(characters?.last?.sex,1)
    }
    func testEmptyAndMalformedLists() {
        XCTAssertEqual(MirWire.characterList("",expectedCount:0),[])
        XCTAssertNil(MirWire.characterList("A/0/0/1/",expectedCount:1))
        XCTAssertNil(MirWire.characterList("A/7/0/1/0/",expectedCount:1))
        XCTAssertNil(MirWire.characterList("A/0/0/1/0/",expectedCount:2))
        XCTAssertNil(MirWire.characterList("A/0/0/1/0/A/0/0/1/0/",expectedCount:2))
    }
}
