import XCTest
@testable import MirNavigation

final class NavigationTests: XCTestCase {
    func testStraightAndSameCell() {
        let grid = NavigationGrid(width: 3, height: 1, mask: [true, true, true])
        XCTAssertEqual(grid.path(from: Cell(x: 0,y: 0), to: Cell(x: 2,y: 0)), [Cell(x: 1,y: 0),Cell(x: 2,y: 0)])
        XCTAssertEqual(grid.path(from: Cell(x: 0,y: 0), to: Cell(x: 0,y: 0)), [])
    }
    func testNoCornerCutting() {
        let grid = NavigationGrid(width: 2, height: 2, mask: [true,false,false,true])
        XCTAssertNil(grid.path(from: Cell(x: 0,y: 0), to: Cell(x: 1,y: 1)))
    }
    func testDetourAndBlockedDestination() {
        let grid = NavigationGrid(width: 3,height: 3,mask: [true,false,true,true,false,true,true,true,true])
        let route = grid.path(from: Cell(x: 0,y: 0),to: Cell(x: 2,y: 0))
        XCTAssertEqual(route?.count, 6)
        XCTAssertNil(grid.path(from: Cell(x: 0,y: 0),to: Cell(x: 1,y: 0)))
    }
    func testBoundsAndInvalidMask() {
        let grid = NavigationGrid(width: 2,height: 1,mask: [true,true])
        for cell in [Cell(x: -1,y: 0),Cell(x: 2,y: 0),Cell(x: 0,y: 1)] { XCTAssertFalse(grid.canWalk(cell)) }
        XCTAssertFalse(NavigationGrid(width: 2,height: 2,mask: [true]).canWalk(Cell(x: 0,y: 0)))
    }
    func testDemoMapRoutes() throws {
        struct Map: Decodable { let width,height: Int; let walkable: [Bool]; let spawn: Cell }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let map = try JSONDecoder().decode(Map.self,from: Data(contentsOf: root.appendingPathComponent("GameData/scene.json")))
        let grid = NavigationGrid(width: map.width,height: map.height,mask: map.walkable)
        XCTAssertTrue(grid.canWalk(map.spawn))
        var successes = 0
        for y in stride(from: 0,to: map.height,by: max(5,map.height/10)) { for x in stride(from: 0,to: map.width,by: max(5,map.width/12)) {
            let target = Cell(x: x,y: y)
            guard let route = grid.path(from: map.spawn,to: target) else { continue }
            var last = map.spawn
            for step in route { XCTAssertTrue(grid.neighbors(last).contains(step)); last = step }
            XCTAssertEqual(last,target); successes += 1
        }}
        XCTAssertGreaterThan(successes, 20)
    }
}
