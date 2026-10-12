import XCTest
@testable import MirNavigation

final class EquipmentInputTests:XCTestCase {
    private func bytes(_ hex:String)->[UInt8] {
        let a=Array(hex);return stride(from:0,to:a.count,by:2).map{UInt8(String(a[$0...($0+1)]),radix:16)!}
    }
    private var one:MirEquipment.Item { MirEquipment.item(bytes("04c4bebda300000000000000000000050107000000001e00a00f00000000020500000000000100003200000005000000000000000000000000000000000000000000000064fb000000000000000000000000000000000000000000000000000000000000891caf6b780aa00f00000000000000000000000000000000"))! }
    private var two:MirEquipment.Item { MirEquipment.item(bytes("04c4bebda300000000000000000000050107000000001e00a00f00000000020500000000000100003200000005000000000000000000000000000000000000000000000064fb00000000000000000000000000000000000000000000000000000000000063a0ca6c380ea00f00000000000000000000000000000000"))! }
    func testRealItemLayoutAndTruncation() {
        let item=one
        XCTAssertEqual(item.mode,5);XCTAssertEqual(item.looks,30);XCTAssertEqual(item.slots,[1])
        XCTAssertGreaterThan(item.id,0);XCTAssertEqual(item.dc,1282)
        let raw=bytes("04c4bebda300000000000000000000050107000000001e00a00f00000000020500000000000100003200000005000000000000000000000000000000000000000000000064fb000000000000000000000000000000000000000000000000000000000000891caf6b780aa00f00000000000000000000000000000000")
        for size in 0..<124 { XCTAssertNil(MirEquipment.item(Array(raw.prefix(size)))) }
        var invalid=raw;invalid[0]=15;XCTAssertNil(MirEquipment.item(invalid))
    }
    func testServerConfirmedEquipSwapAndUnequip() {
        var s=MirEquipment.State();s.bag=[one.id:one,two.id:two]
        XCTAssertFalse(s.begin(one,slot:13,takingOff:false))
        XCTAssertTrue(s.begin(one,slot:1,takingOff:false))
        XCTAssertNil(s.equipped[1]);XCTAssertNotNil(s.bag[one.id])
        XCTAssertFalse(s.begin(two,slot:1,takingOff:false))
        XCTAssertTrue(s.finish(takingOff:false,success:true));XCTAssertNil(s.bag[one.id])
        XCTAssertTrue(s.begin(two,slot:1,takingOff:false))
        // SM_ADDITEM returns the old weapon before SM_TAKEON_OK.
        s.bag[one.id]=one
        XCTAssertTrue(s.finish(takingOff:false,success:true))
        XCTAssertEqual(s.equipped[1]?.id,two.id);XCTAssertNotNil(s.bag[one.id])
        XCTAssertTrue(s.begin(two,slot:1,takingOff:true));s.bag[two.id]=two
        XCTAssertTrue(s.finish(takingOff:true,success:true));XCTAssertNil(s.equipped[1]);XCTAssertEqual(s.bag.count,2)
        XCTAssertFalse(s.finish(takingOff:true,success:false))
    }
    func testFailurePreservesConfirmedState() {
        var s=MirEquipment.State();s.bag[one.id]=one
        XCTAssertTrue(s.begin(one,slot:1,takingOff:false));XCTAssertTrue(s.finish(takingOff:false,success:false))
        XCTAssertNil(s.equipped[1]);XCTAssertNotNil(s.bag[one.id]);XCTAssertNil(s.pending)
    }
    func testActualCSharpSkillSerializer() {
        let skill=MirEquipment.skill(bytes("310200007b0000000b0006c0d7b5e7caf500000000000000000000001400000000000000000000000000000000000000000000000000000008070000000000000000000000000000000000000000000000000000"))
        XCTAssertEqual(skill?.id,11);XCTAssertEqual(skill?.level,2);XCTAssertEqual(skill?.cost,20);XCTAssertEqual(skill?.delayMS,2600);XCTAssertEqual(skill?.castable,true)
    }
    func testEightDirectionsAndDeadZone() {
        XCTAssertNil(MirTouchInput.direction(x:0,y:0));XCTAssertNil(MirTouchInput.direction(x:0.1,y:0.1))
        XCTAssertNil(MirTouchInput.direction(x:Double.nan,y:0))
        for (i,d) in MirTouchInput.directions.enumerated() { XCTAssertEqual(MirTouchInput.direction(x:Double(d.x),y:Double(d.y)),i) }
        XCTAssertFalse(MirTouchInput.running(x:0.5,y:0));XCTAssertTrue(MirTouchInput.running(x:1,y:0))
    }
    func testFullMapNavigation() {
        let grid=NavigationGrid(width:700,height:700,mask:[Bool](repeating:true,count:490000))
        let route=grid.path(from:Cell(x:0,y:0),to:Cell(x:699,y:699))
        XCTAssertEqual(route?.count,699);XCTAssertEqual(route?.last,Cell(x:699,y:699))
    }
}
