import XCTest
@testable import MirNavigation

final class ShopProtocolTests:XCTestCase {
    func testGoodsAndDialogCommands() {
        let goods=MirShop.goods("木剑/1/50/20/蜡烛/0/10/9/",count:2)
        XCTAssertEqual(goods?.count,2)
        XCTAssertEqual(goods?.first?.submenu,1)
        XCTAssertEqual(goods?.last?.price,10)
        XCTAssertNil(MirShop.goods("蜡烛/0/10/",count:1))
        XCTAssertNil(MirShop.goods("蜡烛/0/-10/9/",count:1))
        XCTAssertNil(MirShop.goods("蜡烛/0/10/9/",count:2))
        XCTAssertEqual(MirShop.goods("",count:0)?.count,0)
        let links=MirShop.links("欢迎！<购买/@buy> <卖肉/@sell> <离开/@exit>")
        XCTAssertEqual(links.map(\.command),["@buy","@sell","@exit"])
    }
    func testDetailedGoodsRequiresBothEncodingLayers() throws {
        let one=[UInt8](repeating:7,count:124)
        let two=[UInt8](repeating:12,count:124)
        let inner=MirWire.encode(one)+[47]+MirWire.encode(two)+[47]
        let raw=MirWire.command(652,actor:123,x:2)+MirWire.encode(inner)
        let packet=try MirWire.packet(raw)
        XCTAssertEqual(packet.bodyParts,[one,two])
        XCTAssertEqual(packet.actor,123)
        XCTAssertThrowsError(try MirWire.packet(MirWire.command(652)+MirWire.encode([47,47])))
    }
    func testDropAndButchHeadersPreserveSignedIdentityAndCoordinates() throws {
        let drop=try MirWire.packet(MirWire.command(1000,actor:0xFEDCBA98))
        XCTAssertEqual(UInt32(bitPattern:drop.actor),0xFEDCBA98)
        let cut=try MirWire.packet(MirWire.command(1007,actor:19,x:292,y:604,series:7))
        XCTAssertEqual(cut.id,1007);XCTAssertEqual(cut.actor,19)
        XCTAssertEqual(cut.x,292);XCTAssertEqual(cut.y,604);XCTAssertEqual(cut.series,7)
    }
}
