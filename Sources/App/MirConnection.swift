import Foundation
import Network
import Combine
import CoreFoundation

// All state and NWConnection callbacks are serialized on the main queue.
final class MirConnection: ObservableObject {
    @Published var status = "输入局域网地址和测试账号"
    @Published var online = false
    @Published var busy = false
    @Published var logURL: URL?
    typealias Character = MirWire.CharacterSelection
    @Published var screen = "login"
    @Published var characters:[Character] = []
    @Published var selectedName = ""
    @Published var npcText = ""
    @Published var inventory=MirEquipment.State()
    @Published var skills:[MirEquipment.Skill]=[]
    @Published var equipmentMessage="点击背包中的装备穿戴"
    @Published var abilityText=""
    @Published var goldBalance:Int32=0
    @Published var actionLocked=false
    @Published var warrior=MirSkills.WarriorState()
    @Published var skillReady:[Int:Double]=[:]
    @Published var automaticSkills=Set<Int>()
    @Published var quickSlots:[Int]=[]
    @Published var mana:Int?
    @Published var vitals:MirVitals?
    @Published var attackMode:Int?
    var attackModeName:String {
        let names=["全体","和平","夫妻","师徒","组队","行会","红名"]
        guard let mode=attackMode,names.indices.contains(mode) else { return "未知" }
        return names[mode]
    }
    private var modeRequestedAt = -Double.infinity
    func cycleAttackMode() {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,!dealOpen,!tradeBusy,now-modeRequestedAt>=1 else { return }
        modeRequestedAt=now
        raw(MirWire.command(3030)+MirWire.encode(legacyBytes("@AttackMode")))
    }
    @Published var usePending:Int32?
    @Published var messages:[String]=[]
    struct ChatEntry { let text:String;let channel:String }
    @Published var chatEntries:[ChatEntry]=[]
    @Published var chatChannel="当前"
    func displayedChat()->[String] {
        chatEntries.filter { chatChannel=="综合" || $0.channel==chatChannel }.map { chatChannel=="综合" ? "[\($0.channel)] "+$0.text : $0.text }
    }
    @Published var guildMessages:[String]=[]
    @Published var guildName=""
    @Published var chatFeedback=""
    @discardableResult func sendChat(_ text:String,guild:Bool)->Bool {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard online,!value.isEmpty else { chatFeedback="请输入聊天内容";return false }
        guard !guild || !guildName.isEmpty else { chatFeedback="尚未加入行会，不能发送行会消息";return false }
        let payload=(guild ? "!~" : "")+value
        guard legacyBytes(payload).count<=120,!value.contains("\n"),!value.contains("\r") else { chatFeedback="消息过长或包含换行，请缩短后发送";return false }
        send(3030,body:payload);chatFeedback="已发送请求，消息以服务器回传为准";return true
    }
    private var useTimeout:DispatchWorkItem?
    private var lastUse = -Double.infinity
    func message(_ text:String,channel:String="系统") {
        guard !text.isEmpty else { return }
        messages.append(text);if messages.count>80 { messages.removeFirst(messages.count-80) }
        chatEntries.append(ChatEntry(text:text,channel:channel));if chatEntries.count>200 { chatEntries.removeFirst(chatEntries.count-200) }
    }
    func useItem(_ item:MirEquipment.Item) {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,!dealOpen,!npcOpen,!tradeBusy,usePending==nil,inventory.pending==nil,inventory.bag[item.id] != nil,[0,1,2,3,4,31].contains(item.mode),now-lastUse>=0.8 else { return }
        usePending=item.id;lastUse=now
        raw(MirWire.command(1006,actor:UInt32(bitPattern:item.id))+MirWire.encode(item.nameBytes))
        let work=DispatchWorkItem { [weak self] in self?.fail("使用物品确认超时，请重新登录同步背包") }
        useTimeout=work;DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:work)
    }
    private var nextAutoDrink:Double=0
    func autoDrink() {
        let now=ProcessInfo.processInfo.systemUptime
        guard now>=nextAutoDrink else { return };nextAutoDrink=now+0.5
        guard online,let v=vitals,v.hp>0,usePending==nil,now-lastUse>=2 else { return }
        let defaults=UserDefaults.standard
        let hpEnabled=defaults.object(forKey:"auto.hp") as? Bool ?? true
        let mpEnabled=defaults.object(forKey:"auto.mp") as? Bool ?? true
        let lowHP=hpEnabled && v.maxHP>0 && Double(v.hp)/Double(v.maxHP)<=0.35
        let lowMP=mpEnabled && v.maxMP>0 && Double(v.mp)/Double(v.maxMP)<=0.25
        guard lowHP || lowMP else { return }
        let items=inventory.bag.values.sorted { $0.id<$1.id }
        let hp=items.first { [0,1,2,3].contains($0.mode) && itemName($0).contains("金创药") }
        let mp=items.first { [0,1,2,3].contains($0.mode) && itemName($0).contains("魔法药") }
        if lowHP,let item=hp { useItem(item) }
        else if lowMP,let item=mp { useItem(item) }
    }
    func mine(x:Int,y:Int,direction:Int)->Bool {
        guard online,!awaitingAttack,!actionLocked,!dealOpen,!npcOpen,!tradeBusy,(0...65535).contains(x),(0...65535).contains(y),(0...7).contains(direction) else { return false }
        awaitingAttack=true
        raw(MirWire.command(3015,actor:UInt32(x)|(UInt32(y)<<16),y:UInt16(direction)))
        log("mining request x=\(x) y=\(y) direction=\(direction)");return true
    }
    func say(_ text:String) {
        let value=text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard online,!value.isEmpty,legacyBytes(value).count<=120,!value.contains("\n"),!value.contains("\r") else { return }
        send(3030,body:value)
    }

    var quickSkillSlots:[MirEquipment.Skill?] {
        let available=skills.filter(\.castable)
        if quickSlots.isEmpty { return (0..<4).map { available.indices.contains($0) ? available[$0] : nil } }
        return (0..<4).map { slot in
            guard quickSlots.indices.contains(slot) else { return nil }
            return available.first { $0.id==quickSlots[slot] }
        }
    }
    var quickSkills:[MirEquipment.Skill] { quickSkillSlots.compactMap{$0} }
    func setQuickSkill(_ id:Int,slot:Int) {
        guard (0..<4).contains(slot),skills.contains(where:{$0.id==id && $0.castable}) else { return }
        var ids=quickSkillSlots.map{$0?.id ?? 0}
        if let old=ids.firstIndex(of:id) { ids.swapAt(old,slot) } else { ids[slot]=id }
        quickSlots=ids
        UserDefaults.standard.set(ids,forKey:"mir.quick.\(account).\(character)")
    }
    @Published var inspectedName=""
    @Published var inspectedGuild=""
    @Published var inspectedItems:[Int:MirEquipment.Item]=[:]
    @Published var peerMessage=""
    @Published var dealOpen=false
    @Published var dealPartner=""
    @Published var dealOwn:[Int32:MirEquipment.Item]=[:]
    @Published var dealRemote:[Int32:MirEquipment.Item]=[:]
    @Published var dealOwnGold=0
    @Published var dealRemoteGold=0
    @Published var dealConfirmed=false
    @Published var dealRevision=0
    private var dealChangedAt=0.0
    private var dealPendingItem:MirEquipment.Item?
    func inspectPlayer(id:Int32,x:Int,y:Int) {
        guard !dealOpen,beginTrade("inspect") else { return }
        inspectedName="";inspectedGuild="";inspectedItems=[:];peerMessage="正在读取对方装备…"
        raw(MirWire.command(82,actor:UInt32(bitPattern:id),x:UInt16(x),y:UInt16(y)))
    }
    func facePlayer(x:Int,y:Int,direction:Int)->Bool {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,!dealOpen,!tradeBusy,!awaitingAttack,now-lastMovement>=0.65 else { return false }
        lastMovement=now
        raw(MirWire.command(3010,actor:UInt32(x)|(UInt32(y)<<16),y:UInt16(direction)));return true
    }
    func requestPeerTrade(name:String) {
        guard !dealOpen,beginTrade("peer-request") else { return }
        peerMessage="等待服务器开启交易"
        raw(MirWire.command(1025)+MirWire.encode(legacyBytes(name)))
    }
    func offerPeerItem(_ item:MirEquipment.Item,remove:Bool=false) {
        guard dealOpen else { peerMessage="交易已结束，请重新发起";return }
        guard !dealConfirmed else { peerMessage="已经确认报价；如需修改请取消交易后重开";return }
        guard remove ? dealOwn[item.id] != nil : inventory.bag[item.id] != nil else { peerMessage="该物品已不在背包或交易栏中";return }
        guard remove || dealOwn.count<12 else { peerMessage="交易栏最多放入12件物品";return }
        guard beginTrade(remove ? "peer-remove" : "peer-add",item:item.id) else { peerMessage="正在等待动作或物品操作确认，请稍后再放入";return }
        dealPendingItem=item
        raw(MirWire.command(remove ? 1027 : 1026,actor:UInt32(bitPattern:item.id))+MirWire.encode(item.nameBytes))
    }
    func offerPeerGold(_ text:String) {
        guard dealOpen,!dealConfirmed,let amount=Int(text),amount>=0,amount<=Int(goldBalance)+dealOwnGold,amount<=Int(Int32.max) else { peerMessage="请输入可用范围内的整数金币";return }
        guard beginTrade("peer-gold") else { return }
        raw(MirWire.command(1029,actor:UInt32(amount)))
    }
    func confirmPeerTrade(revision:Int) {
        guard dealOpen,!tradeBusy,!dealConfirmed else { return }
        guard revision==dealRevision else { peerMessage="交易内容已变化，请重新核对";return }
        guard ProcessInfo.processInfo.systemUptime-dealChangedAt>=3 else { peerMessage="交易内容刚变化，请等待3秒再确认";return }
        dealConfirmed=true;peerMessage="已确认，等待对方；仍可取消交易";raw(MirWire.command(1030))
    }
    func cancelPeerTrade() {
        guard dealOpen,!tradeBusy,beginTrade("peer-cancel") else { return }
        raw(MirWire.command(1028))
    }
    private func peerChanged() {
        dealRevision+=1;dealChangedAt=ProcessInfo.processInfo.systemUptime
        if dealConfirmed && !tradeBusy { cancelPeerTrade() }
    }
    private func receivePeer(_ p:MirWire.Packet) {
        switch p.id {
        case 751:
            guard tradeOperation=="inspect" else { return }
            guard let state=MirPeerInspection.decode(p.body) else { finishTrade("装备数据格式不匹配");peerMessage=tradeMessage;return }
            inspectedName=legacyText(state.name);inspectedGuild=legacyText(state.guild);inspectedItems=state.equipment
            finishTrade("装备已读取");peerMessage="装备由服务器返回"
        case 673:
            if tradeBusy && tradeOperation != "peer-request" || inventory.pending != nil || usePending != nil { raw(MirWire.command(1028));return }
            finishTrade("");dealOpen=true;dealPartner=legacyText(p.body);dealOwn=[:];dealRemote=[:];dealOwnGold=0;dealRemoteGold=0;dealConfirmed=false;dealPendingItem=nil;peerChanged();peerMessage="放入物品或金币，核对双方内容后确认"
        case 674:
            if tradeOperation=="peer-request" { finishTrade("交易未开启");peerMessage="请双方相邻并面对面，确认对方未在交易中" }
        case 675,677:
            guard dealOpen,let item=dealPendingItem,tradeOperation==(p.id==675 ? "peer-add" : "peer-remove") else { return }
            if p.id==675 { dealOwn[item.id]=item;inventory.bag.removeValue(forKey:item.id) }
            else { dealOwn.removeValue(forKey:item.id);inventory.bag[item.id]=item }
            dealPendingItem=nil;finishTrade("");peerChanged();peerMessage="服务器已更新交易物品"
        case 676,678:
            if tradeOperation.hasPrefix("peer-") { dealPendingItem=nil;finishTrade("");peerMessage="操作被拒绝，可能对方已确认或物品不可交易" }
        case 682,683:
            guard dealOpen,let item=MirEquipment.item(p.body) else { return }
            if p.id==682 { dealRemote[item.id]=item } else { dealRemote.removeValue(forKey:item.id) }
            peerChanged();peerMessage="对方更改了物品，请重新核对"
        case 684,685:
            guard dealOpen else { return }
            dealOwnGold=Int(p.actor);goldBalance=Int32(bitPattern:UInt32(p.x)|(UInt32(p.y)<<16))
            if tradeOperation=="peer-gold" { finishTrade("") };peerChanged();peerMessage=p.id==684 ? "金币已更新" : "金币修改被拒绝"
        case 686:
            guard dealOpen else { return };dealRemoteGold=Int(p.actor);peerChanged();peerMessage="对方更改了金币，请重新核对"
        case 681,687:
            guard dealOpen else { return }
            if p.id==681 { for (id,item) in dealOwn { inventory.bag[id]=item };goldBalance+=Int32(dealOwnGold) }
            finishTrade("");dealOpen=false;dealConfirmed=false;dealOwn=[:];dealRemote=[:];dealOwnGold=0;dealRemoteGold=0;dealPendingItem=nil
            peerMessage=p.id==687 ? "服务器确认交易成功" : "交易已取消，物品和金币已退回";message(peerMessage)
        default:break
        }
    }
    private var equipmentTimeout:DispatchWorkItem?
    private var lastMovement = -Double.infinity
    func itemName(_ item:MirEquipment.Item)->String { legacyText(item.nameBytes) }
    func skillName(_ skill:MirEquipment.Skill)->String { legacyText(skill.nameBytes) }
    private var npcID:Int32=0
    @Published var shopMode=""
    @Published var shopGoods:[MirShop.Good]=[]
    @Published var shopDetails:[MirEquipment.Item]=[]
    @Published var tradeBusy=false
    @Published var tradeMessage=""
    @Published var saleItem:Int32?
    @Published var salePrice:Int?
    @Published var playerSex=0
    @Published var playerHair=0
    private var tradeOperation=""
    private var tradeItem:Int32?
    private var tradeTimeout:DispatchWorkItem?
    private var lastButch = -Double.infinity
    var npcOpen:Bool { !npcText.isEmpty || !shopMode.isEmpty }
    var npcLinks:[MirShop.Link] { MirShop.links(npcText) }
    private func beginTrade(_ operation:String,item:Int32?=nil)->Bool {
        guard online,!tradeBusy,!actionLocked,usePending==nil,inventory.pending==nil,(!dealOpen || operation.hasPrefix("peer-")) else { return false }
        tradeOperation=operation;tradeItem=item;tradeBusy=true;tradeMessage="等待服务器确认…"
        let work=DispatchWorkItem { [weak self] in
            if operation=="inspect" || operation=="peer-request" { self?.finishTrade("请求未得到响应");self?.peerMessage="对方可能已离开、拒绝交易或距离过远，请重新选择" }
            else { self?.fail("交易确认超时，已停止操作；请重新登录同步背包") }
        }
        tradeTimeout=work;DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:work);return true
    }
    private func finishTrade(_ message:String) {
        tradeTimeout?.cancel();tradeTimeout=nil;tradeBusy=false;tradeOperation="";tradeItem=nil;tradeMessage=message
    }
    func drop(_ item:MirEquipment.Item) {
        guard inventory.bag[item.id] != nil,beginTrade("drop",item:item.id) else { return }
        raw(MirWire.command(1000,actor:UInt32(bitPattern:item.id))+MirWire.encode(item.nameBytes))
        log("drop request item=\(item.id)")
    }
    func selectNPC(_ command:String) {
        guard online,!tradeBusy,npcLinks.contains(where:{$0.command==command}) || command=="@buy" || command=="@sell" else { return }
        if command=="@exit" { closeNPC();return }
        guard !command.hasPrefix("@@") else { tradeMessage="此对话需要输入，暂未接入";return }
        shopMode="";shopGoods=[];shopDetails=[];saleItem=nil;salePrice=nil
        raw(MirWire.command(1011,actor:UInt32(bitPattern:npcID))+MirWire.encode(legacyBytes(command)))
    }
    func browse(_ good:MirShop.Good) {
        guard good.submenu>0,beginTrade("details") else { return }
        raw(MirWire.command(1015,actor:UInt32(bitPattern:npcID))+MirWire.encode(legacyBytes(good.name)))
    }
    func buy(name:String,index:Int32=0) {
        guard beginTrade("buy",item:index) else { return }
        let id=UInt32(bitPattern:index)
        raw(MirWire.command(1014,actor:UInt32(bitPattern:npcID),x:UInt16(truncatingIfNeeded:id),y:UInt16(truncatingIfNeeded:id>>16))+MirWire.encode(legacyBytes(name)))
        log("buy request merchant=\(npcID) item=\(index)")
    }
    func quote(_ item:MirEquipment.Item) {
        guard inventory.bag[item.id] != nil,beginTrade("quote",item:item.id) else { return }
        saleItem=nil;salePrice=nil;itemTrade(1012,item:item)
    }
    func sellQuoted() {
        guard let id=saleItem,let price=salePrice,price>0,let item=inventory.bag[id],beginTrade("sell",item:id) else { return }
        itemTrade(1013,item:item)
    }
    private func itemTrade(_ command:UInt16,item:MirEquipment.Item) {
        let id=UInt32(bitPattern:item.id)
        raw(MirWire.command(command,actor:UInt32(bitPattern:npcID),x:UInt16(truncatingIfNeeded:id),y:UInt16(truncatingIfNeeded:id>>16))+MirWire.encode(item.nameBytes))
        log("shop request command=\(command) item=\(item.id)")
    }
    func butcher(target:Int32,x:Int,y:Int,direction:Int)->Bool {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,!tradeBusy,!actionLocked,inventory.pending==nil,now-lastButch>=0.65,(0...65535).contains(x),(0...65535).contains(y),(0...7).contains(direction) else { return false }
        lastButch=now
        raw(MirWire.command(1007,actor:UInt32(bitPattern:target),x:UInt16(x),y:UInt16(y),series:UInt16(direction)))
        log("butcher target=\(target) x=\(x) y=\(y)");return true
    }
    private func legacyText(_ bytes:[UInt8])->String {
        let code=String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(bytes:bytes,encoding:code) ?? String(decoding:bytes,as:UTF8.self)
    }
    private func legacyBytes(_ text:String)->[UInt8] {
        let code=String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return Array(text.data(using:code) ?? Data(text.utf8))
    }
    var onPacket: ((MirWire.Packet) -> Void)?
    var onWalkAck: (() -> Void)?
    var onWalkRejected: (() -> Void)?
    var onAttackAck: (() -> Void)?
    private var awaitingAttack = false
    private var playerActor:Int32?
    var onDisconnect: (() -> Void)?
    private var connection: NWConnection?
    private var generation = 0, sequence = 0
    private var framer = MirWire.Framer()
    private var phase = "", host = "", account = "", password = "", character = "", ticket = ""
    private var timeout: DispatchWorkItem?
    private var logger: FileHandle?

    func log(_ text: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        if let data = line.data(using:.utf8) { try? logger?.write(contentsOf:data) }
    }
    func login(host: String, account: String, password: String, character: String = "") {
        disconnect()
        guard !host.isEmpty, !account.isEmpty, !password.isEmpty,
              [account,password,character].allSatisfy({ $0.utf8.allSatisfy { (33...126).contains($0) && $0 != 47 } }) else {
            status = "请填写地址、账号、密码、角色；本测试版使用英文或数字账号与角色名"; return
        }
        self.host=host;self.account=account;self.password=password;self.character=character
        let url = FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("online-\(Int(Date().timeIntervalSince1970)).log")
        FileManager.default.createFile(atPath:url.path,contents:nil)
        logger=try? FileHandle(forWritingTo:url);logURL=url
        busy=true;log("login started")
        connect(port:7000, phase:"login")
    }
    func disconnect() {
        log("disconnect requested online=\(online) awaitingAttack=\(awaitingAttack)")
        generation += 1;timeout?.cancel();timeout=nil
        useTimeout?.cancel();useTimeout=nil;usePending=nil;vitals=nil;attackMode=nil
        guildName="";guildMessages=[];chatFeedback=""
        connection?.cancel();connection=nil;online=false;busy=false;password="";ticket="";awaitingAttack=false
        equipmentTimeout?.cancel();equipmentTimeout=nil;inventory=MirEquipment.State();skills=[];abilityText="";goldBalance=0;actionLocked=false;playerActor=nil
        warrior=MirSkills.WarriorState();skillReady=[:];automaticSkills=[];mana=nil
        tradeTimeout?.cancel();tradeTimeout=nil;tradeBusy=false;tradeOperation="";tradeItem=nil
        dealOpen=false;dealConfirmed=false;dealOwn=[:];dealRemote=[:];dealPendingItem=nil;dealOwnGold=0;dealRemoteGold=0;dealPartner="";peerMessage="";inspectedItems=[:];inspectedName="";inspectedGuild=""
        shopMode="";shopGoods=[];shopDetails=[];saleItem=nil;salePrice=nil;tradeMessage=""
        onDisconnect?();log("disconnected");try? logger?.close();logger=nil
        screen="login";characters=[];selectedName="";npcText=""
    }
    private func fail(_ text: String) { log("failure phase=\(phase): \(text)");disconnect();status=text }
    private func armTimeout() {
        timeout?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fail("服务器响应超时，请检查网络后重新登录") }
        timeout=work;DispatchQueue.main.asyncAfter(deadline:.now()+20,execute:work)
    }
    private func connect(port: UInt16, phase: String) {
        generation += 1;let token=generation
        connection?.cancel();framer=MirWire.Framer();sequence=0;self.phase=phase
        status = phase == "login" ? "连接登录服务…" : phase == "select" ? "读取角色…" : "进入比奇…"
        let c=NWConnection(host:NWEndpoint.Host(host),port:NWEndpoint.Port(rawValue:port)!,using:.tcp)
        connection=c;armTimeout()
        c.stateUpdateHandler={ [weak self, weak c] state in
            guard let self=self, let c=c, self.generation==token else { return }
            switch state {
            case .ready:
                self.receive(c, token:token)
                if phase == "login" { self.send(2001,body:self.account+"/"+self.password);self.password="" }
                else if phase == "select" { self.send(100,body:self.account+"/"+self.ticket) }
                else { self.raw(MirWire.encode(self.legacyBytes("**\(self.account)/\(self.character)/\(self.ticket)/1200409180/1200409180"))) }
            case .failed(let error):self.fail("连接失败：\(error.localizedDescription)。请确认电脑与手机在同一 Wi-Fi")
            default:break
            }
        }
        c.start(queue:.main)
    }
    private func receive(_ c: NWConnection, token:Int) {
        c.receive(minimumIncompleteLength:1,maximumLength:65536) { [weak self, weak c] data,_,done,error in
            guard let self=self,let c=c,self.generation==token else { return }
            if let data=data,!data.isEmpty {
                do {
                    if data.contains(42) { c.send(content:Data([42]),completion:.contentProcessed({_ in})) }
                    for frame in try self.framer.feed(Array(data).filter{$0 != 42}) {
                        if frame.starts(with:Array("+GD/".utf8)) {
                            if self.awaitingAttack { self.awaitingAttack=false;self.log("attack accepted");self.onAttackAck?() }
                            else { self.log("walk accepted");self.onWalkAck?() };continue
                        }
                        if frame.starts(with:Array("+FL/".utf8)) { self.awaitingAttack=false;self.log("action rejected");self.onWalkRejected?();continue }
                        if frame == Array("=DIG".utf8) || frame == Array("=DIG/".utf8) {
                            self.log("mining success notice");continue
                        }
                        if self.warrior.receive(frame,now:ProcessInfo.processInfo.systemUptime) {
                            self.log("warrior state updated");continue
                        }
                        if frame.first==43 {
                            self.log("unhandled control notice bytes=\(frame.count)");continue
                        }
                        let p: MirWire.Packet
                        do { p = try MirWire.packet(frame) }
                        catch {
                            // Never log raw login/selection bodies: they can contain tickets.
                            var messageID = "unknown"
                            if frame.count >= 16, let header = try? MirWire.decode(Array(frame.prefix(16))), header.count == 12 {
                                messageID = String(UInt16(header[4]) | (UInt16(header[5]) << 8))
                            }
                            self.log("parse failure phase=\(self.phase) id=\(messageID) frameBytes=\(frame.count) error=\(error)")
                            throw error
                        }
                        if self.phase == "game" { self.log("recv id=\(p.id) actor=\(p.actor) x=\(p.x) y=\(p.y)") }
                        else { self.log("recv id=\(p.id)") }
                        self.handle(p)
                        if self.generation != token { return }
                    }
                } catch { self.log("receive failure phase=\(self.phase) chunkBytes=\(data.count) error=\(error)");self.fail("服务器数据格式无法解析，请导出日志检查");return }
            }
            if done || error != nil {
                self.log("transport closed phase=\(self.phase) eof=\(done) error=\(String(describing:error))")
                self.fail("连接已断开，请重新登录");return
            }
            self.receive(c,token:token)
        }
    }
    private func handle(_ p:MirWire.Packet) {
        if p.id==50,p.body.count>=4 { playerSex=Int(p.body[3])%2;playerHair=Int(p.body[2]) }
        if p.id==51 || p.id==634 || p.id==633 { awaitingAttack=false }
        receivePeer(p)
        receiveInventory(p)
        if p.id == 28 && p.actor==playerActor { awaitingAttack=false }
        switch p.id {
        case 529:timeout?.cancel();busy=false;screen="servers";status="请选择服务器"
        case 530:
            let parts=String(decoding:p.body,as:UTF8.self).split(separator:"/")
            guard parts.count>=3, let port=UInt16(parts[1]),port==7100 else { fail("选服地址无效");return }
            ticket=String(parts[2]);connect(port:port,phase:"select")
        case 520:
            guard let list=MirWire.characterList(legacyText(p.body),expectedCount:Int(p.actor)) else { fail("角色列表格式无效");return }
            characters=list;selectedName=list.first?.name ?? "";timeout?.cancel();busy=false;screen="characters";status=list.count==2 ? "请选择人物（两个角色栏均已使用）" : "请选择人物，或创建新人物"
        case 521,523:send(100,body:account+"/"+ticket);armTimeout()
        case 524:timeout?.cancel();busy=false;status="删除失败：请确认角色未在线，并符合服务器删除等级限制"
        case 522:timeout?.cancel();busy=false;status="创建失败：请检查名称是否重复或角色栏是否已满"
        case 750:guildName=legacyText(p.body).components(separatedBy:"/").first ?? ""
        case 104:
            let text=legacyText(p.body);guildMessages.append(text)
            if guildMessages.count>80 { guildMessages.removeFirst(guildMessages.count-80) }
            message(text,channel:"行会");onPacket?(p)
        case 40,100,101,102,103:
            message(legacyText(p.body),channel:MirChatChannel.name(for:p.id));onPacket?(p)
        case 766,767:
            tradeMessage=legacyText(p.body);equipmentMessage=tradeMessage
            message(tradeMessage)
            log("server hint id=\(p.id) text=\(tradeMessage.prefix(240))")
            onPacket?(p)
        case 643:
            npcID=p.actor
            npcText=legacyText(p.body).split(separator:"/",maxSplits:1,omittingEmptySubsequences:false).joined(separator:"\n\n").replacingOccurrences(of:"\\",with:"\n")
        case 644:npcText="";shopMode="";saleItem=nil;salePrice=nil
        case 645:
            guard let goods=MirShop.goods(legacyText(p.body),count:Int(p.x)) else { fail("商店商品列表格式不匹配，请导出日志");return }
            npcID=p.actor;shopGoods=goods;shopDetails=[];shopMode="buy"
        case 646:npcID=p.actor;shopMode="sell";saleItem=nil;salePrice=nil
        case 652:
            guard tradeOperation=="details",p.actor==npcID else { break }
            let items=p.bodyParts.compactMap(MirEquipment.item)
            guard items.count==Int(p.x) else { fail("商店装备列表格式不匹配，请导出日志");return }
            shopDetails=items;finishTrade("请选择一件装备购买")
        case 647:
            if tradeOperation=="quote" { saleItem=tradeItem;salePrice=Int(p.actor);finishTrade(p.actor>0 ? "服务器已报价，确认后出售" : "此商店不收购这件物品") }
        case 648,649:
            if tradeOperation=="sell" {
                if p.id==648 { if let id=tradeItem { inventory.bag.removeValue(forKey:id) };goldBalance=p.actor }
                saleItem=nil;salePrice=nil;finishTrade(p.id==648 ? "出售成功，金币已同步" : "出售失败，物品保留")
            }
        case 650,651:
            if tradeOperation=="buy" {
                if p.id==650 { goldBalance=p.actor };finishTrade(p.id==650 ? "购买成功，物品由服务器入包" : "购买失败：库存、金币、负重或背包空间不足")
                shopDetails=[];selectNPC("@buy")
            }
        case 600,601:
            if tradeOperation=="drop",tradeItem==p.actor {
                if p.id==600 { inventory.bag.removeValue(forKey:p.actor) }
                finishTrade(p.id==600 ? "物品已丢到地面" : "此物品或当前位置不允许丢弃")
                equipmentMessage=tradeMessage
            }
        case 525:connect(port:7200,phase:"game")
        case 658:send(1018);armTimeout()
        case 50:quickSlots=UserDefaults.standard.array(forKey:"mir.quick.\(account).\(character)") as? [Int] ?? [];playerActor=p.actor;timeout?.cancel();busy=false;online=true;screen="world";status="已联网 · 点击地图行走";onPacket?(p);send(81)
        case 503:fail(p.actor == -3 ? "旧会话正在退出，请稍等 10 秒后再登录" : "账号或密码不正确")
        case 527,526:fail("角色认证或进入游戏失败，请稍后重试")
        default:onPacket?(p)
        }
    }
    private func raw(_ bytes:[UInt8]) {
        sequence=sequence%9+1
        let token=generation
        connection?.send(content:Data([35,UInt8(48+sequence)]+bytes+[33]),completion:.contentProcessed({ [weak self] error in
            guard let self=self,self.generation==token else { return }
            if error != nil { self.fail("发送失败，请重新登录") }
        }))
    }
    private func send(_ id:UInt16,body:String="") { raw(MirWire.command(id)+MirWire.encode(legacyBytes(body))) }
    func chooseServer() {
        guard screen=="servers",!busy else { return }
        busy=true;send(104,body:"MirTest");armTimeout()
    }
    func talk(to actor:Int32) {
        guard online else { return }
        raw(MirWire.command(1010,actor:UInt32(bitPattern:actor)))
    }
    func closeNPC() {
        guard !tradeBusy else { return };shopMode="";shopGoods=[];shopDetails=[];saleItem=nil;salePrice=nil
        raw(MirWire.command(1011,actor:UInt32(bitPattern:npcID),body:"@exit"));npcText=""
    }
    func enterSelectedCharacter() {
        guard screen=="characters",!busy,characters.contains(where:{$0.name==selectedName}) else { return }
        character=selectedName;busy=true;send(103,body:account+"/"+character);armTimeout()
    }
    func deleteCharacter(name:String) {
        guard screen=="characters",!busy,!online,characters.contains(where:{$0.name==name}) else { return }
        busy=true;status="正在删除人物";send(102,body:name);armTimeout()
    }
    func createCharacter(name:String,job:Int,sex:Int) {
        guard screen=="characters",!busy,characters.count<2 else { return }
        guard name.count>=3,legacyBytes(name).count<=14,name.unicodeScalars.allSatisfy({ (48...57).contains($0.value)||(65...90).contains($0.value)||(97...122).contains($0.value)||(0x4E00...0x9FFF).contains($0.value) }),(0...2).contains(job),(0...1).contains(sex) else {
            status="人物名至少 3 个字，最多 7 个汉字或 14 位字母数字";return
        }
        busy=true;send(101,body:account+"/"+name+"/0/\(job)/\(sex)");armTimeout()
    }
    private var lastDoorRequest: TimeInterval = -10
    func openDoor(x:Int,y:Int,index:Int) {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,(0...65535).contains(x),(0...65535).contains(y),(1...127).contains(index),now-lastDoorRequest>=0.8 else { return }
        lastDoorRequest=now
        log("door request x=\(x) y=\(y) index=\(index)")
        raw(MirWire.command(1002,actor:UInt32(index),x:UInt16(x),y:UInt16(y)))
    }
    func walk(x:Int,y:Int,direction:Int,running:Bool=false)->Bool {
        let now=ProcessInfo.processInfo.systemUptime
        guard online,(0...65535).contains(x),(0...65535).contains(y),(0...7).contains(direction),now-lastMovement>=0.1 else { return false }
        lastMovement=now
        log("move request running=\(running) x=\(x) y=\(y)")
        raw(MirWire.command(running ? 3013 : 3011,actor:UInt32(x)|(UInt32(y)<<16),y:UInt16(direction)))
        return true
    }
    func attack(x:Int,y:Int,direction:Int,distance:Int=1) {
        guard online,!awaitingAttack,(0...65535).contains(x),(0...65535).contains(y),(0...7).contains(direction) else { return }
        awaitingAttack=true;log("attack request x=\(x) y=\(y) direction=\(direction)")
        let hit=warrior.hit(distance:distance,now:ProcessInfo.processInfo.systemUptime)
        if hit==3025 { warrior.fireUntil=0 };if hit==3018 { warrior.power=false }
        log("hit command=\(hit)")
        raw(MirWire.command(hit,actor:UInt32(x)|(UInt32(y)<<16),y:UInt16(direction)))
    }
    func pickup(x:Int,y:Int) {
        guard online,(0...65535).contains(x),(0...65535).contains(y) else { return }
        log("pickup request x=\(x) y=\(y)")
        raw(MirWire.command(1001,x:UInt16(x),y:UInt16(y)))
    }
    func changeEquipment(_ item:MirEquipment.Item,slot:Int,takingOff:Bool) {
        guard online,!dealOpen,!tradeBusy,usePending==nil,!actionLocked,inventory.begin(item,slot:slot,takingOff:takingOff) else { return }
        tradeMessage="";equipmentMessage="等待服务器确认…"
        raw(MirWire.command(takingOff ? 1004 : 1003,actor:UInt32(bitPattern:item.id),x:UInt16(slot))+MirWire.encode(item.nameBytes))
        log("equipment request item=\(item.id) slot=\(slot) off=\(takingOff)")
        let work=DispatchWorkItem { [weak self] in
            self?.fail("装备确认超时，请重新登录以同步背包；未重复发送操作")
        }
        equipmentTimeout=work;DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:work)
    }
    private func receiveInventory(_ p:MirWire.Packet) {
        switch p.id {
        case 635,636:
            if let id=usePending {
                useTimeout?.cancel();useTimeout=nil;usePending=nil
                if p.id==635 { inventory.bag.removeValue(forKey:id) }
                message(p.id==635 ? "服务器确认使用物品" : "物品使用失败，请检查状态、等级或使用间隔")
            }
        case 201:
            let items=p.bodyParts.compactMap(MirEquipment.item)
            guard items.count==p.bodyParts.count else { equipmentMessage="背包格式不匹配，请导出日志";log("invalid bag item layout");return }
            inventory.bag=Dictionary(items.map{($0.id,$0)},uniquingKeysWith:{$1})
        case 200:
            if let item=MirEquipment.item(p.body) { inventory.bag[item.id]=item }
        case 203:
            if let item=MirEquipment.item(p.body) { inventory.upsert(item) }
        case 202:
            if let item=MirEquipment.item(p.body) { inventory.bag.removeValue(forKey:item.id) }
        case 621:
            var equipment:[Int:MirEquipment.Item]=[:]
            for i in stride(from:0,to:p.bodyParts.count,by:2) {
                guard i+1<p.bodyParts.count,let slot=Int(String(decoding:p.bodyParts[i],as:UTF8.self)),MirEquipment.slotNames.indices.contains(slot),let item=MirEquipment.item(p.bodyParts[i+1]) else { log("invalid equipment layout");return }
                equipment[slot]=item
            }
            inventory.equipped=equipment
        case 615,616,619,620:
            let success=p.id==615 || p.id==619
            if inventory.finish(takingOff:p.id==619 || p.id==620,success:success) {
                equipmentTimeout?.cancel();equipmentTimeout=nil
                equipmentMessage=success ? "服务器已确认，装备属性已同步" : "操作失败：等级、职业、负重或背包空间不符合要求（\(p.actor)）"
            }
        case 622:
            if var v=vitals { v.weight=max(0,Int(p.actor));v.wearWeight=Int(p.x);v.handWeight=Int(p.y);vitals=v }
        case 52:
            goldBalance=p.actor
            if p.body.count==40 {
                let b=p.body
                vitals=MirVitals.decode(b);mana=vitals?.mp
                abilityText="等级 \(b[0])  攻击 \(MirEquipment.range(MirEquipment.word(b,6)))  魔法 \(MirEquipment.range(MirEquipment.word(b,8)))  道术 \(MirEquipment.range(MirEquipment.word(b,10)))\n防御 \(MirEquipment.range(MirEquipment.word(b,2)))  魔防 \(MirEquipment.range(MirEquipment.word(b,4)))"
            }
        case 44,45:
            // SM_WINEXP/SM_LEVELUP carry the authoritative total XP in Recog, not an actor ID.
            if var state=vitals {
                state.experience=max(0,Int(p.actor))
                if p.id==45 { state.level=Int(p.x) }
                vitals=state
            }
        case 213:attackMode=Int(p.actor)
        case 31,53,32,34:
            if p.actor==playerActor {
                vitals?.apply(id:p.id,x:p.x,y:p.y,series:p.series)
                mana=vitals?.mp
            }
        case 653:goldBalance=p.actor
        case 211:skills=p.bodyParts.compactMap(MirEquipment.skill)
        case 210:
            if let skill=MirEquipment.skill(p.body) { skills.removeAll{$0.id==skill.id};skills.append(skill) }
        case 640:
            if let index=skills.firstIndex(where:{$0.id==Int(p.actor)}) {
                skills[index].level=Int(p.x);skills[index].training=Int(UInt32(p.y) | UInt32(p.series)<<16)
            }
        case 212:skills.removeAll{$0.id==Int(p.actor)}
        default:break
        }
    }
    func cast(_ skill:MirEquipment.Skill,x:Int,y:Int,target:Int32) {
        guard online,!awaitingAttack,skill.castable,skills.contains(where:{$0.id==skill.id}),(0...65535).contains(x),(0...65535).contains(y) else { return }
        awaitingAttack=true
        let id=UInt32(bitPattern:target)
        raw(MirWire.command(3017,actor:UInt32(x)|(UInt32(y)<<16),x:UInt16(truncatingIfNeeded:id),y:UInt16(skill.id),series:UInt16(truncatingIfNeeded:id>>16)))
        log("skill request id=\(skill.id) target=\(target)")
    }

}
