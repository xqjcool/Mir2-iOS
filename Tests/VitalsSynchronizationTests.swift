import XCTest
@testable import MirNavigation
final class VitalsSynchronizationTests:XCTestCase {
    func testDamageRecoveryManaAndDeath() {
        var state=MirVitals(level:7,hp:50,mp:30,maxHP:50,maxMP:40,experience:0,maxExperience:100)
        state.apply(id:31,x:27,y:50,series:23)
        XCTAssertEqual(state.hp,27);XCTAssertEqual(state.maxHP,50)
        XCTAssertEqual(state.mp,30);XCTAssertEqual(state.maxMP,40)
        state.apply(id:53,x:35,y:12,series:50)
        XCTAssertEqual(state.hp,35);XCTAssertEqual(state.mp,12)
        XCTAssertEqual(state.maxMP,40)
        state.apply(id:32,x:0,y:0,series:0)
        XCTAssertEqual(state.hp,0);XCTAssertEqual(state.maxHP,50)
        state.apply(id:53,x:50,y:40,series:50)
        XCTAssertEqual(state.hp,50);XCTAssertEqual(state.mp,40)
    }
    func testUnrelatedMessageDoesNotChangeVitals() {
        var state=MirVitals(level:1,hp:12,mp:8,maxHP:15,maxMP:10,experience:0,maxExperience:100)
        let before=state
        state.apply(id:14,x:99,y:99,series:99)
        XCTAssertEqual(state,before)
    }
}
