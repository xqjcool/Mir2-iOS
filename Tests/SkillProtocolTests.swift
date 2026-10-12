import XCTest
@testable import MirNavigation

final class SkillProtocolTests:XCTestCase {
    func testAutomaticRotationDoesNotStarveLaterSkills() {
        XCTAssertEqual(MirSkills.nextAutomatic([31,11,13],after:nil),11)
        XCTAssertEqual(MirSkills.nextAutomatic([31,11,13],after:11),13)
        XCTAssertEqual(MirSkills.nextAutomatic([31,11,13],after:13),31)
        XCTAssertEqual(MirSkills.nextAutomatic([31,11,13],after:31),11)
        // A skill on cooldown can disappear without restarting from the first ID.
        XCTAssertEqual(MirSkills.nextAutomatic([31,11],after:13),31)
        XCTAssertEqual(MirSkills.nextAutomatic([11],after:11),11)
        XCTAssertNil(MirSkills.nextAutomatic([],after:11))
    }
    func testActualOpenMir2Headers() throws {
        let ready=try MirWire.packet(Array("idhkdihk<ekWdehi11".utf8))
        let impact=try MirWire.packet(Array("idhkdrjh<ekWdgajodhkd?".utf8))
        XCTAssertEqual(ready.id,17);XCTAssertEqual(ready.body,Array("11".utf8))
        XCTAssertEqual(impact.id,638);XCTAssertEqual(impact.series,0x0907)
        XCTAssertEqual(impact.body,[99,0,0,0])
    }
    func testPlainDecimalSpellBodyAndAdjacentEncodedPacket() throws {
        // Matches PlayObject.Message RM_SPELL: header encoded, magic ID plain.
        let spell=MirWire.command(17,actor:17,x:420,y:195,series:9)+Array("11".utf8)
        let hit=MirWire.command(638,actor:17,x:420,y:195,series:0x0907)+MirWire.encode([99,0,0,0])
        let stream=[UInt8(35)]+spell+[33,35]+hit+[33]
        for split in 0...stream.count {
            var framer=MirWire.Framer()
            let frames=try framer.feed(Array(stream.prefix(split)))+framer.feed(Array(stream.dropFirst(split)))
            XCTAssertEqual(frames.count,2)
            let ready=try MirWire.packet(frames[0]),fire=try MirWire.packet(frames[1])
            XCTAssertEqual(ready.body,Array("11".utf8));XCTAssertEqual(ready.series,9)
            XCTAssertEqual(fire.series,0x0907);XCTAssertEqual(fire.body,[99,0,0,0])
        }
        XCTAssertThrowsError(try MirWire.packet(MirWire.command(17)+[255]))
    }
    func testWarriorRequiresServerNoticeAndConsumesReadyTime() {
        var state=MirSkills.WarriorState()
        XCTAssertEqual(state.hit(distance:1,now:100),3014)
        XCTAssertTrue(state.receive(Array("+LNG".utf8),now:100))
        XCTAssertEqual(state.hit(distance:2,now:100),3019)
        XCTAssertTrue(state.receive(Array("+WID/".utf8),now:100))
        XCTAssertEqual(state.hit(distance:1,now:100),3024)
        XCTAssertTrue(state.receive(Array("+FIR".utf8),now:100))
        XCTAssertEqual(state.hit(distance:1,now:109),3025)
        XCTAssertEqual(state.hit(distance:1,now:110),3024)
        XCTAssertTrue(state.receive(Array("+UWID".utf8),now:111))
        XCTAssertEqual(state.hit(distance:1,now:111),3014)
        XCTAssertFalse(state.receive(Array("+FL/".utf8),now:111))
    }
    func testOriginalDirectionAndSpecialTargetModes() {
        XCTAssertEqual(MirSkills.direction16(dx:48,dy:0),4)
        XCTAssertEqual(MirSkills.direction16(dx:0,dy:-32),0)
        XCTAssertEqual(MirSkills.direction16(dx:-48,dy:32),10)
        XCTAssertEqual(MirSkills.direction16(dx:48,dy:-32),2)
        XCTAssertTrue(MirSkills.ground(22));XCTAssertFalse(MirSkills.ground(11))
        XCTAssertTrue(MirSkills.warrior(26));XCTAssertTrue(MirSkills.selfCast(31))
        XCTAssertNil(MirSkills.base(0));XCTAssertNil(MirSkills.base(255))
    }
}
