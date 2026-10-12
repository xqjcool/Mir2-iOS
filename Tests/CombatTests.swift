import XCTest
@testable import MirNavigation

final class CombatTests: XCTestCase {
    func testThreeHitsAndNoDamageAfterDeath() {
        var c = Combat()
        for _ in 0..<13 {
            XCTAssertTrue(c.attack())
            XCTAssertFalse(c.attack())
            c.tick(0.26, adjacent: true, heroDamage: 2)
            c.tick(0.35, adjacent: true)
        }
        XCTAssertEqual(c.monsterHP, 0)
        let hp = c.heroHP
        c.tick(10, adjacent: true)
        XCTAssertEqual(c.heroHP, hp)
        XCTAssertFalse(c.attack())
    }
    func testMissAndSingleHit() {
        var c = Combat()
        XCTAssertTrue(c.attack())
        c.tick(0.3, adjacent: false)
        c.tick(0.4, adjacent: true)
        XCTAssertEqual(c.monsterHP,25)
        XCTAssertTrue(c.attack())
        c.tick(0.3, adjacent: true, heroDamage: 2)
        c.tick(0.2, adjacent: true)
        XCTAssertEqual(c.monsterHP,23)
    }
    func testHeroDeathAndReset() {
        var c = Combat()
        for _ in 0..<400 { c.tick(1.21, adjacent: true) }
        XCTAssertEqual(c.heroHP,0)
        XCTAssertFalse(c.attack())
        c = Combat()
        XCTAssertEqual(c.heroHP,100)
        XCTAssertEqual(c.monsterHP,25)
    }
}
