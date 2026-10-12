import XCTest
@testable import MirNavigation

final class LootTests: XCTestCase {
    func testPersistenceAndEquipment() throws {
        var bag = LootInventory()
        bag.equip(); XCTAssertFalse(bag.equipped)
        bag.collect(); bag.equip()
        let copy = try JSONDecoder().decode(LootInventory.self,from:JSONEncoder().encode(bag))
        XCTAssertEqual(copy.gold,3000); XCTAssertEqual(copy.swords,1); XCTAssertTrue(copy.equipped)
    }
    func testMonsterWindupAndMiss() {
        var c = Combat()
        c.tick(2.5,adjacent:true)
        XCTAssertEqual(c.heroHP,100)
        XCTAssertEqual(c.monsterSwings,1)
        c.tick(0.31,adjacent:false)
        XCTAssertEqual(c.heroHP,100)
        c.tick(2.5,adjacent:true)
        c.tick(0.31,adjacent:true,monsterDamage:2)
        XCTAssertEqual(c.heroHP,98)
    }
}
