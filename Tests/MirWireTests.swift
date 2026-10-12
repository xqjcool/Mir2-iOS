import XCTest
@testable import MirNavigation
final class MirWireTests: XCTestCase {
    func testCodecRoundTrip() throws {
        for n in 0...1024 {
            let bytes=(0..<n).map { UInt8(truncatingIfNeeded:$0) }
            XCTAssertEqual(try MirWire.decode(MirWire.encode(bytes)),bytes)
        }
    }
    func testGoldenServerLogon() throws {
        let p=try MirWire.packet(Array("tNikdbhkIeVGddhj".utf8))
        XCTAssertEqual(p.actor,123456);XCTAssertEqual(p.id,50)
        XCTAssertEqual(p.x,405);XCTAssertEqual(p.y,182);XCTAssertEqual(p.series,4)
    }
    func testFragmentedAndCoalescedFrames() throws {
        var f=MirWire.Framer()
        XCTAssertTrue(try f.feed(Array("$#abc".utf8)).isEmpty)
        XCTAssertEqual(try f.feed(Array("!$#def!".utf8)),[Array("abc".utf8),Array("def".utf8)])
    }
    func testInvalidEncodingRejected() {
        XCTAssertThrowsError(try MirWire.decode([59,60]))
        XCTAssertThrowsError(try MirWire.decode([60]))
        XCTAssertThrowsError(try MirWire.packet([60]))
    }
    func testBonusRecordsAreDecodedSeparately() throws {
        let records: [[UInt8]] = [[1,2,3,4], [5,6], [7,8,9,10,11]]
        let body = records.map { MirWire.encode($0) }.enumerated().flatMap { index, bytes in
            index == 0 ? bytes : [UInt8(47)] + bytes
        }
        let p = try MirWire.packet(MirWire.command(811) + body)
        XCTAssertEqual(p.id,811)
        XCTAssertEqual(p.bodyParts,records)
        XCTAssertThrowsError(try MirWire.packet(MirWire.command(811) + MirWire.encode([1,2])))
        // Do not relax the alphabet check for ordinary packets.
        XCTAssertThrowsError(try MirWire.packet(MirWire.command(50) + body))
    }
    func testMonsterFeatureAndNameHaveSeparateEncoding() throws {
        let feature: [UInt8] = [18,0,27,0,0,0,0,0]
        // A body whose independently encoded pieces cannot be decoded together.
        let name: [UInt8] = [181,190,178,221,200,203,92,50,53,53]
        let raw=MirWire.command(10)+MirWire.encode(feature)+MirWire.encode(name)
        let p=try MirWire.packet(raw)
        XCTAssertEqual(p.bodyParts,[feature,name])
        XCTAssertEqual(Array(p.body.prefix(4)),[18,0,27,0])
    }
    func testInventorySurvivesRelogin() throws {
        let items:[[UInt8]]=[[1,2,3,4,5],[6,7]]
        var body:[UInt8]=[]
        for item in items { body += MirWire.encode(item)+[47] }
        XCTAssertEqual(try MirWire.packet(MirWire.command(201)+body).bodyParts,items)
        XCTAssertThrowsError(try MirWire.packet(MirWire.command(201)+[47,47]))
        let worn=Array("1/".utf8)+MirWire.encode(items[0])+[47]
        XCTAssertEqual(try MirWire.packet(MirWire.command(621)+worn).bodyParts,[Array("1".utf8),items[0]])
    }
}
