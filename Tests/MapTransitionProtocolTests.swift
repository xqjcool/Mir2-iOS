import XCTest
@testable import MirNavigation

final class MapTransitionProtocolTests:XCTestCase {
    func testCapturedThreeShopRoundTrips() throws {
        // Real SM_CHANGEMAP frames from the local server roundtrip probe.
        let fixtures:[(String,String,UInt16,UInt16)] = [
            ("734373557a726a6966645c676464686b6061586b633f","0103",6,12),
            ("734373557a726a6976653d5f6564686b603f","0",334,301),
            ("734373557a726a69656477636464686b6061586b613e","0105",9,23),
            ("734373557a726a695c656d636564686b603f","0",296,285),
            ("734373557a726a69656477636464686b6061586b623e","0106",9,23),
            ("734373557a726a69606557676564686b603f","0",308,311)
        ]
        for (hex,map,x,y) in fixtures {
            let chars=Array(hex)
            let bytes=stride(from:0,to:chars.count,by:2).map { UInt8(String(chars[$0...($0+1)]),radix:16)! }
            let packet=try MirWire.packet(bytes)
            XCTAssertEqual(packet.id,634)
            XCTAssertEqual(String(decoding:packet.body,as:UTF8.self),map)
            XCTAssertEqual(packet.x,x);XCTAssertEqual(packet.y,y)
        }
    }
    func testCapturedIndoorLoginMap() throws {
        let hex="4c7748646d636867666476636464686b6061586b623e"
        let chars=Array(hex)
        let bytes=stride(from:0,to:chars.count,by:2).map { UInt8(String(chars[$0...($0+1)]),radix:16)! }
        let packet=try MirWire.packet(bytes)
        XCTAssertEqual(packet.id,51)
        XCTAssertEqual(String(decoding:packet.body,as:UTF8.self),"0106")
        XCTAssertEqual(packet.x,10);XCTAssertEqual(packet.y,22)
    }
}
