import Foundation

enum MirWire {
    enum Fault: Error { case malformed, oversized }
    struct CharacterSelection:Identifiable,Equatable {
        var id:String { name }
        let name:String
        let job,hair,level,sex:Int
    }
    static func characterList(_ text:String, expectedCount:Int)->[CharacterSelection]? {
        if text.isEmpty { return expectedCount==0 ? [] : nil }
        var fields=text.split(separator:"/",omittingEmptySubsequences:false)
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard (0...2).contains(expectedCount),fields.count==expectedCount*5 else { return nil }
        var result:[CharacterSelection]=[]
        for i in stride(from:0,to:fields.count,by:5) {
            let name=String(fields[i]).trimmingCharacters(in:CharacterSet(charactersIn:"*"))
            guard !name.isEmpty,let job=Int(fields[i+1]),(0...2).contains(job),let hair=Int(fields[i+2]),(0...255).contains(hair),let level=Int(fields[i+3]),level>=0,let sex=Int(fields[i+4]),(0...1).contains(sex) else { return nil }
            result.append(CharacterSelection(name:name,job:job,hair:hair,level:level,sex:sex))
        }
        guard Set(result.map(\.name)).count==result.count else { return nil }
        return result
    }
    struct Packet {
        let actor: Int32
        let id, x, y, series: UInt16
        let body: [UInt8]
        // Separately encoded records; SM_ADJUST_BONUS contains three records.
        let bodyParts: [[UInt8]]
    }
    static func encode(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        var no: Int = 2
        var rem: Int = 0
        for byte in raw {
            let c = Int(byte) ^ 172
            if no == 6 {
                let low: Int = c & 63
                let high: Int = (c >> 2) & 48
                let tail: Int = rem | high
                out.append(UInt8(low + 60))
                out.append(UInt8(tail + 60))
                rem = 0
            } else {
                let t: Int = c >> 2
                let high: Int = t & 60
                let low: Int = c & 3
                let encoded: Int = high | low
                out.append(UInt8(encoded + 60))
                rem = (rem << 2) | (t & 3)
            }
            no = no % 6 + 2
        }
        if no != 2 { out.append(UInt8(rem + 60)) }
        return out
    }
    static func decode(_ bytes: [UInt8]) throws -> [UInt8] {
        guard bytes.allSatisfy({ (60...123).contains($0) }) else { throw Fault.malformed }
        var out: [UInt8] = []
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let end: Int = min(i + 4, bytes.count)
            let b: [Int] = bytes[i..<end].map { Int($0) - 60 }
            guard b.count >= 2, let r = b.last else { throw Fault.malformed }
            let firstHigh: Int = (b[0] << 2) & 240
            let firstMiddle: Int
            if b.count > 2 {
                firstMiddle = r & 12
            } else {
                firstMiddle = (r << 2) & 12
            }
            let firstLow: Int = b[0] & 3
            let firstCombined: Int = firstHigh | firstMiddle | firstLow
            out.append(UInt8(firstCombined ^ 172))
            if b.count > 2 {
                let secondHigh: Int = (b[1] << 2) & 240
                let secondMiddle: Int = (r << 2) & 12
                let secondLow: Int = b[1] & 3
                let secondCombined: Int = secondHigh | secondMiddle | secondLow
                out.append(UInt8(secondCombined ^ 172))
            }
            if b.count == 4 {
                let thirdHigh: Int = (r << 2) & 192
                let thirdCombined: Int = b[2] | thirdHigh
                out.append(UInt8(thirdCombined ^ 172))
            }
        }
        return out
    }
    static func command(_ id: UInt16, actor: UInt32 = 0, x: UInt16 = 0, y: UInt16 = 0, series: UInt16 = 0, body: String = "") -> [UInt8] {
        var raw = (0..<4).map { UInt8(truncatingIfNeeded: actor >> ($0*8)) }
        for w in [id,x,y,series] { raw += [UInt8(truncatingIfNeeded:w), UInt8(w>>8)] }
        return encode(raw) + encode(Array(body.utf8)) // This test build uses ASCII account/character names.
    }
    static func packet(_ raw: [UInt8]) throws -> Packet {
        guard raw.count >= 16 else { throw Fault.malformed }
        let h = try decode(Array(raw.prefix(16)))
        guard h.count == 12 else { throw Fault.malformed }
        func word(_ i: Int) -> UInt16 { UInt16(h[i]) | UInt16(h[i+1]) << 8 }
        let actor = UInt32(word(0)) | UInt32(word(2)) << 16
        let id = word(4)
        let encodedBody = Array(raw.dropFirst(16))
        let parts: [[UInt8]]
        if id == 17 {
            // RM_SPELL sends the magic ID as plain decimal text, not EDCode.
            guard !encodedBody.isEmpty,encodedBody.allSatisfy({ (48...57).contains($0) }) else { throw Fault.malformed }
            parts = [encodedBody]
        } else if id == 811 {
            // OpenMir2 SendAdjustBonus encodes each structure independently.
            // '/' is a record separator, outside the EDCode alphabet.
            let records = encodedBody.split(separator:47, omittingEmptySubsequences:false)
            guard records.count == 3, records.allSatisfy({ !$0.isEmpty }) else { throw Fault.malformed }
            parts = try records.map { try decode(Array($0)) }
        } else if id == 652 {
            // OpenMir2 encodes the complete string of separately encoded item records.
            let inner=try decode(encodedBody)
            var records=inner.split(separator:47,omittingEmptySubsequences:false)
            if records.last?.isEmpty == true { records.removeLast() }
            guard records.allSatisfy({ !$0.isEmpty }) else { throw Fault.malformed }
            parts=try records.map { try decode(Array($0)) }
        } else if id == 201 || id == 211 {
            // Bag/skill lists contain separately encoded records and a trailing '/'.
            var records=encodedBody.split(separator:47,omittingEmptySubsequences:false)
            if records.last?.isEmpty == true { records.removeLast() }
            guard records.allSatisfy({ !$0.isEmpty }) else { throw Fault.malformed }
            parts=try records.map { try decode(Array($0)) }
        } else if id == 621 {
            // Equipped items alternate an ASCII slot number and encoded ClientItem.
            var records=encodedBody.split(separator:47,omittingEmptySubsequences:false)
            if records.last?.isEmpty == true { records.removeLast() }
            guard records.count % 2 == 0 else { throw Fault.malformed }
            var decoded:[[UInt8]]=[]
            for index in stride(from:0,to:records.count,by:2) {
                guard !records[index].isEmpty, records[index].allSatisfy({ (48...57).contains($0) }), !records[index+1].isEmpty else { throw Fault.malformed }
                decoded.append(Array(records[index]));decoded.append(try decode(Array(records[index+1])))
            }
            parts=decoded
        } else if (id == 10 || id == 50), !encodedBody.isEmpty {
            // CharDesc (8 decoded bytes) followed by an independently encoded name.
            guard encodedBody.count >= 11 else { throw Fault.malformed }
            parts = [try decode(Array(encodedBody.prefix(11))), try decode(Array(encodedBody.dropFirst(11)))]
        } else {
            parts = [try decode(encodedBody)]
        }
        return Packet(actor: Int32(bitPattern:actor), id:id, x:word(6), y:word(8), series:word(10), body:parts.flatMap { $0 }, bodyParts:parts)
    }
    struct Framer {
        private var buffer: [UInt8] = []
        mutating func feed(_ bytes: [UInt8]) throws -> [[UInt8]] {
            buffer += bytes
            guard buffer.count <= 1_048_576 else { throw Fault.oversized }
            var frames: [[UInt8]] = []
            while let start = buffer.firstIndex(of:35) {
                if start > 0 { buffer.removeFirst(start) }
                guard let end = buffer.firstIndex(of:33) else { break }
                frames.append(Array(buffer[1..<end])); buffer.removeFirst(end+1)
            }
            if !buffer.contains(35) { buffer.removeAll() }
            return frames
        }
    }
}

// OpenMir2 ClientItem.WritePacket: 124 bytes, not a native Swift struct layout.
enum MirEquipment {
    static let slotNames = ["衣服","武器","照明","项链","头盔","左手镯","右手镯","左戒指","右戒指","护符","腰带","鞋","宝石"]
    struct Item: Identifiable, Equatable {
        let id:Int32
        let nameBytes:[UInt8]
        let mode,shape,looks,durability,maxDurability,ac,mac,dc,mc,sc,need,needLevel:Int
        var slots:[Int] {
            switch mode {
            case 10,11:return [0]
            case 5,6:return [1]
            case 28,29,30:return [2]
            case 19,20,21:return [3]
            case 15:return [4]
            case 24,26:return [5,6]
            case 25:return [9,5]
            case 22,23:return [7,8]
            case 51:return [9]
            case 54,64:return [10]
            case 52,62:return [11]
            case 53,63:return [12]
            default:return []
            }
        }
    }
    static func word(_ b:[UInt8],_ i:Int)->Int { Int(b[i]) | Int(b[i+1]) << 8 }
    static func integer(_ b:[UInt8],_ i:Int)->Int32 { Int32(bitPattern:UInt32(word(b,i)) | UInt32(word(b,i+2)) << 16) }
    static func item(_ b:[UInt8])->Item? {
        guard b.count==124,b[0]>0,b[0]<=14 else { return nil }
        return Item(id:integer(b,100),nameBytes:Array(b[1...Int(b[0])]),mode:Int(b[15]),shape:Int(b[16]),looks:word(b,22),durability:word(b,104),maxDurability:word(b,106),ac:word(b,26),mac:word(b,28),dc:word(b,30),mc:word(b,32),sc:word(b,34),need:Int(b[36]),needLevel:Int(b[37]))
    }
    static func range(_ value:Int)->String { "\(value & 255)–\(value >> 8)" }
    struct Skill:Identifiable,Equatable {
        let id,level,cost,delayMS:Int
        var effect:Int = 0
        let nameBytes:[UInt8]
        // Warrior readiness is confirmed by +LNG/+WID/+FIR before choosing a hit packet.
        var castable:Bool { [1,2,5,6,8,9,10,11,12,13,14,15,16,17,18,19,20,22,23,24,25,26,28,29,30,31,32,33].contains(id) }
    }
    static func skill(_ b:[UInt8])->Skill? {
        guard b.count==84,b[10]>0,b[10]<=14 else { return nil }
        return Skill(id:word(b,8),level:Int(b[1]),cost:word(b,28),delayMS:max(1400,Int(integer(b,56))+800),effect:Int(b[26]),nameBytes:Array(b[11...10+Int(b[10])]))
    }
    struct Pending {
        let item:Item
        let slot:Int
        let takingOff:Bool
    }
    struct State {
        var bag:[Int32:Item]=[:]
        var equipped:[Int:Item]=[:]
        var pending:Pending?
        mutating func begin(_ item:Item,slot:Int,takingOff:Bool)->Bool {
            guard pending==nil,slotNames.indices.contains(slot) else { return false }
            guard takingOff ? equipped[slot]?.id==item.id : (bag[item.id] != nil && item.slots.contains(slot)) else { return false }
            pending=Pending(item:item,slot:slot,takingOff:takingOff);return true
        }
        mutating func finish(takingOff:Bool,success:Bool)->Bool {
            guard let request=pending,request.takingOff==takingOff else { return false }
            pending=nil
            if success {
                if takingOff { equipped.removeValue(forKey:request.slot);bag[request.item.id]=request.item }
                else { equipped[request.slot]=request.item;bag.removeValue(forKey:request.item.id) }
            }
            return true
        }
        mutating func upsert(_ item:Item) {
            if let slot=equipped.first(where:{$0.value.id==item.id})?.key { equipped[slot]=item }
            else { bag[item.id]=item }
        }
    }
}

enum MirTouchInput {
    static let directions=[Cell(x:0,y:-1),Cell(x:1,y:-1),Cell(x:1,y:0),Cell(x:1,y:1),Cell(x:0,y:1),Cell(x:-1,y:1),Cell(x:-1,y:0),Cell(x:-1,y:-1)]
    static func direction(x:Double,y:Double)->Int? {
        guard x.isFinite,y.isFinite,hypot(x,y)>=0.18 else { return nil }
        let sector=Int((atan2(x,-y)/(Double.pi/4)).rounded())
        return (sector+8)%8
    }
    static func running(x:Double,y:Double)->Bool { hypot(x,y)>=0.78 }
}

// Original 1.76 protocol and effect indices; no local damage calculation.
enum MirSkills {
    // Stable ID order makes selection fair even when server list order changes.
    static func nextAutomatic(_ eligible:[Int],after previous:Int?)->Int? {
        let ordered=eligible.sorted()
        guard let previous=previous else { return ordered.first }
        return ordered.first(where:{$0>previous}) ?? ordered.first
    }
    static let effectBase = [0,200,400,600,0,900,920,940,20,940,940,940,0,1380,1500,1520,940,1560,1590,1620,1650,1680,0,0,0,3960,1790,0,3880,3920,3840]
    static func base(_ effect:Int)->Int? { (1...effectBase.count).contains(effect) ? effectBase[effect-1] : nil }
    static func warrior(_ id:Int)->Bool { [12,25,26].contains(id) }
    static func selfCast(_ id:Int)->Bool { [2,8,12,14,15,17,18,19,24,25,26,29,30,31].contains(id) }
    static func ground(_ id:Int)->Bool { [14,15,16,19,22,23,29,33].contains(id) }
    static func direction16(dx:Double,dy:Double)->Int {
        if dx==0 { return dy<0 ? 0 : 8 }
        if dy==0 { return dx<0 ? 12 : 4 }
        let x=abs(dx),y=abs(dy)
        var n=0
        if y>x/4 { n=1 };if y>x/1.9 { n=2 };if y>x*1.4 { n=3 };if y>x*4 { n=4 }
        return (dx>0 ? (dy>0 ? 4+n : 4-n) : (dy>0 ? 12-n : 12+n)) % 16
    }
    struct WarriorState {
        var thrust=false,halfMoon=false,power=false,fireUntil:Double=0
        mutating func receive(_ frame:[UInt8],now:Double)->Bool {
            let tag=String(decoding:frame,as:UTF8.self).trimmingCharacters(in:CharacterSet(charactersIn:"/"))
            switch tag {
            case "+PWR":power=true
            case "+LNG":thrust=true
            case "+ULNG":thrust=false
            case "+WID":halfMoon=true
            case "+UWID":halfMoon=false
            case "+FIR":fireUntil=now+10
            case "+UFIR":fireUntil=0
            default:return false
            }
            return true
        }
        func hit(distance:Int,now:Double)->UInt16 {
            if distance==1 && now<fireUntil { return 3025 }
            if thrust && distance==2 { return 3019 }
            if halfMoon && distance==1 { return 3024 }
            if power && distance==1 { return 3018 }
            return 3014
        }
    }
}

enum MirShop {
    struct Good:Identifiable {
        var id:String { name }
        let name:String
        let submenu,price,stock:Int
    }
    static func goods(_ text:String,count:Int)->[Good]? {
        var fields=text.split(separator:"/",omittingEmptySubsequences:false)
        if fields.last?.isEmpty == true { fields.removeLast() }
        guard count>=0,count<=10000,fields.count==count*4 else { return nil }
        var result:[Good]=[]
        for i in stride(from:0,to:fields.count,by:4) {
            guard !fields[i].isEmpty,let sub=Int(fields[i+1]),let price=Int(fields[i+2]),let stock=Int(fields[i+3]),price>=0,stock>=0 else { return nil }
            result.append(Good(name:String(fields[i]),submenu:sub,price:price,stock:stock))
        }
        return result
    }
    struct Link:Identifiable {
        var id:String { label+command }
        let label,command:String
    }
    static func links(_ text:String)->[Link] {
        guard let re=try? NSRegularExpression(pattern:"<([^<>/]+)/(@[^<>]+)>") else { return [] }
        let ns=text as NSString
        return re.matches(in:text,range:NSRange(location:0,length:ns.length)).map {
            Link(label:ns.substring(with:$0.range(at:1)),command:ns.substring(with:$0.range(at:2)))
        }
    }
}
