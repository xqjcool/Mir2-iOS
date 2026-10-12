import XCTest
@testable import MirNavigation

final class StreamingTests: XCTestCase {
    func testBoundaryAndTallObject() {
        let tall = StreamItem(id: "tree", file: "tree.png", rect: StreamRect(x: 500,y: 0,width: 60,height: 900),z: 2)
        let ground = StreamItem(id: "ground", file: "ground.png", rect: StreamRect(x: 0,y: 0,width: 512,height: 512),z: -100)
        let index = StreamCatalog([tall,ground])
        XCTAssertEqual(index.query(StreamRect(x: 520,y: 50,width: 10,height: 10)),["tree"])
        XCTAssertEqual(index.query(StreamRect(x: 560,y: 0,width: 1,height: 1)),[])
        XCTAssertEqual(index.query(StreamRect(x: -20,y: -20,width: 10,height: 10)),[])
    }
    func testLongTravelDoesNotRetainVisitedChunks() {
        let entries = (0..<1000).map { n in
            StreamItem(id: "\(n)",file: "\(n).png",rect: StreamRect(x: Double(n*512),y: 0,width: 512,height: 512),z: -100)
        }
        let index = StreamCatalog(entries)
        var active = Set<String>()
        for iteration in 0..<10000 {
            let n = iteration % 1000
            let view = StreamRect(x: Double(n*512),y: 0,width: 960,height: 540)
            active.formIntersection(index.query(view.expanded(384)))
            active.formUnion(index.query(view.expanded(128)))
            XCTAssertLessThanOrEqual(active.count, 5)
        }
        active.removeAll()
        XCTAssertEqual(active.count,0)
    }
    func testIndexMatchesBruteForceAtEdges() {
        let entries = (0..<200).map { i in
            StreamItem(id: "\(i)",file: "\(i).png",rect: StreamRect(x: Double(i*31-100),y: Double(i%9*85-80),width: 70,height: 300),z: 0)
        }
        let index = StreamCatalog(entries)
        for x in stride(from: -600,through: 7000,by: 123) {
            let view = StreamRect(x: Double(x),y: -20,width: 930,height: 600)
            XCTAssertEqual(index.query(view),Set(entries.filter { $0.rect.intersects(view) }.map(\.id)))
        }
    }
    func testActualAutomaticTourNeverCrossesObstacles() throws {
        struct Map: Decodable { let width,height: Int; let walkable: [Bool]; let spawn: Cell; let autoRoute: [Cell] }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let map = try JSONDecoder().decode(Map.self,from: Data(contentsOf: root.appendingPathComponent("GameData/scene.json")))
        let grid = NavigationGrid(width: map.width,height: map.height,mask: map.walkable)
        var cell = map.spawn
        XCTAssertGreaterThan(map.autoRoute.count,1000)
        for _ in 0..<10 {
            for next in map.autoRoute { XCTAssertTrue(grid.neighbors(cell).contains(next)); cell = next }
            XCTAssertEqual(cell,map.spawn)
        }
    }
}
