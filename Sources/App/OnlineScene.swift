import SpriteKit
import UIKit
import CoreFoundation

final class OnlineScene: SKScene {
    private var map:SceneData
    private let root:URL, net:MirConnection
    private var mapID="0"
    var mapReport:((String,UIImage?)->Void)?
    private let cameraNode=SKCameraNode()
    private var streamer:SceneStreamer!
    private var built=false, clock=0.0, lastStream=0.0, nextStep=0.0
    private var playerID:Int32?
    private var route:[Cell]=[], pending:Cell?, requestedAt=0.0
    private var movementReadyAt=0.0
    private var attackReadyAt=0.0
    private let cache=NSCache<NSString,SKTexture>()
    private var weaponOrder:[[Int]]=[]
    private var actors:[Int32:Avatar]=[:]
    private var delayNotified=false
    private var attackPending=false, attackRequested=0.0, nextAttack=0.0, nextPickup=0.0
    private var selected:Int32? { didSet { refreshTargetMarker() } }
    private var selectedCorpse:Int32?
    private var stickDirection:Int?, stickRunning=false, autoAttack=false, routeRunning=false
    private var pendingDuration=0.54, pathGeneration=0, pathBusy=false
    private let navigationQueue=DispatchQueue(label:"mir.navigation",qos:.userInitiated)
    private var nextAuto=0.0, pickupSweep=false
    private var dropNames:[Int32:String]=[:]
    private var armedGroundSkill:MirEquipment.Skill?
    private var effectFrames:[String:[String:SceneData.Frame]]=[:]
    private let effectsRoot=SKNode()
    private var events:[Int32:SKNode]=[:]
    private var shields:[Int32:SKNode]=[:]
    private var predictingSpell=false
    private var lastSkillID:Int?
    private var lastAutoSkillID:Int?
    private var nextPerformanceLog=0.0
    private var transientEffects:[SKNode]=[]
    private var pickupAttempts:[Cell:Int]=[:]
    var autoPickup=true
    var classicMode=true
    private var attackHeld=false
    private var queuedSkill:MirEquipment.Skill?
    private var queuedAttack=false
    private var queuedGround:Cell?
    private var aimMarker:SKShapeNode?
    private var interactionSuspended=false
    func suspendControls(_ value:Bool) { interactionSuspended=value;if value { stopAutomation() } }
    var targetReport:((String)->Void)?
    var targetHealthReport:((Double?)->Void)?
    var positionReport:((Cell)->Void)?
    private let targetMarker=SKLabelNode(text:"▼")
    private func refreshTargetMarker() {
        targetMarker.removeFromParent()
        guard let id=selected,let actor=actors[id],!actor.dead else { return }
        targetMarker.fontSize=26;targetMarker.fontColor = .yellow
        targetMarker.position=CGPoint(x:0,y:76);targetMarker.zPosition=100
        actor.node.addChild(targetMarker)
    }
    func lockPlayer(_ target:PlayerTarget,attack:Bool=false) {
        guard let actor=actors[target.id],!actor.dead,!actor.monster,!actor.npc,target.id != playerID else { net.peerMessage="目标已离开或无法交互";return }
        stopAutomation();selected=target.id;targetHealthReport?(nil);targetReport?(actor.displayName)
        combatReport?("已锁定 \(actor.displayName)，点击右侧攻击或技能；伤害由服务端判定")
        if attack { autoAttack=true;queuedAttack=true }
    }
    struct NearbyTarget:Identifiable {
        let id:Int32;let name:String;let monster:Bool;let distance:Int
    }
    var nearbyTargets:[NearbyTarget] {
        guard let me=playerID.flatMap({ actors[$0] }) else { return [] }
        return actors.compactMap { id,actor -> NearbyTarget? in
            guard id != playerID,!actor.dead,!actor.npc else { return nil }
            return NearbyTarget(id:id,name:actor.displayName,monster:actor.monster,distance:max(abs(actor.cell.x-me.cell.x),abs(actor.cell.y-me.cell.y)))
        }.sorted { $0.distance == $1.distance ? $0.id<$1.id : $0.distance<$1.distance }
    }
    func chooseNearby(_ target:NearbyTarget) {
        guard let actor=actors[target.id],!actor.dead,!actor.npc else { combatReport?("目标已离开视野");return }
        stopAutomation();selected=target.id;targetHealthReport?(nil);targetReport?(actor.displayName)
        if !actor.monster { net.peerMessage="";net.inspectedName="";net.inspectedItems=[:];playerReport?(PlayerTarget(id:target.id,name:actor.displayName)) }
        else { combatReport?("已锁定 \(actor.displayName)，点击攻击或技能") }
    }
    struct PlayerTarget:Identifiable,Equatable { let id:Int32;let name:String }
    var playerReport:((PlayerTarget)->Void)?
    func inspect(_ target:PlayerTarget) {
        guard let actor=actors[target.id],!actor.monster,!actor.npc else { net.peerMessage="对方已离开视野";return }
        net.inspectPlayer(id:target.id,x:actor.cell.x+map.originX,y:actor.cell.y+map.originY)
    }
    func face(_ target:PlayerTarget,trade:Bool=false) {
        guard pending==nil,!attackPending,let id=playerID,let me=actors[id],let other=actors[target.id],!other.dead else { net.peerMessage="请等待当前动作结束，或重新选择对方";return }
        let dx=other.cell.x-me.cell.x,dy=other.cell.y-me.cell.y
        guard max(abs(dx),abs(dy))==1 else { net.peerMessage="请先走到对方相邻的一格，再点人物操作";return }
        let dir=MirTouchInput.direction(x:Double(dx),y:Double(dy)) ?? 0
        if trade {
            guard me.direction==dir,other.direction==(dir+4)%8 else { net.peerMessage="双方需分别点“面向对方”，再发起交易";return }
            net.requestPeerTrade(name:other.displayName)
        } else { guard net.facePlayer(x:me.cell.x+map.originX,y:me.cell.y+map.originY,direction:dir) else { net.peerMessage="请稍候再转向";return };me.direction=dir;net.peerMessage="已面向对方，请对方也面向你" }
    }
    private struct WorldNPC:Decodable { let x:Int;let y:Int;let name:String }
    private var knownNPCs:[WorldNPC]=[]
    var npcMarkers:[Cell] { Array(Set(knownNPCs.map { Cell(x:$0.x,y:$0.y) } + actors.values.filter{$0.npc}.map(\.cell))).sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x } }
    func npcName(near cell:Cell)->String? { knownNPCs.min { max(abs($0.x-cell.x),abs($0.y-cell.y)) < max(abs($1.x-cell.x),abs($1.y-cell.y)) }.flatMap { max(abs($0.x-cell.x),abs($0.y-cell.y))<=8 ? $0.name : nil } }
    var mapWidth:Int { map.width }
    var mapHeight:Int { map.height }
    var minimapImage:UIImage? {
        if mapID=="0", let image=UIImage(contentsOfFile:root.appendingPathComponent("classic-ui/bichon-minimap.png").path) { return image }
        let bytes: [UInt8] = map.walkable.flatMap { walkable -> [UInt8] in
            walkable ? [110, 95, 65, 255] : [18, 24, 22, 255]
        }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let image=CGImage(width:map.width,height:map.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:map.width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else { return nil }
        return UIImage(cgImage:image)
    }
    func stopAutomation() { cancelAim();queuedGround=nil;queuedSkill=nil;queuedAttack=false;armedGroundSkill=nil;stickDirection=nil;autoAttack=false;attackHeld=false;pickupSweep=false;route=[];pathGeneration+=1;pathBusy=false }
    func joystick(x:Double,y:Double) {
        let direction=MirTouchInput.direction(x:x,y:y)
        if direction != nil { queuedAttack=false;queuedSkill=nil;queuedGround=nil;armedGroundSkill=nil;autoAttack=false;pickupSweep=false;route=[];pathGeneration+=1;pathBusy=false }
        stickDirection=direction;stickRunning=MirTouchInput.running(x:x,y:y)
    }
    func navigate(to target:Cell,running:Bool=true) {
        guard let id=playerID,let a=actors[id],!a.dead else { return }
        stopAutomation();queuePath(to:target,running:running)
    }
    private func queuePath(to target:Cell,running:Bool) {
        guard !pathBusy,let id=playerID,let a=actors[id],!a.dead else { return }
        routeRunning=running;pathGeneration+=1;let token=pathGeneration
        let start=pending ?? a.cell, grid=map.grid;pathBusy=true
        navigationQueue.async { [weak self] in
            let path=grid.path(from:start,to:target)
            DispatchQueue.main.async {
                guard let self=self,self.pathGeneration==token,self.net.online else { return }
                self.pathBusy=false;self.route=path ?? []
                if path==nil { if self.autoAttack { self.stopAutomation() };self.nextAuto=self.clock+3;self.nextPickup=self.clock+3;self.combatReport?("此处不可到达") }
            }
        }
    }
    enum Input {
        case move(Double,Double), attack, holdAttack(Bool), skill(MirEquipment.Skill), pickup, stop
    }
    func input(_ command:Input) {
        // Cancellation is always accepted, including while a modal owns input.
        switch command {
        case .stop:stopAutomation();return
        case .holdAttack(false):attackHeld=false;return
        case let .move(x,y) where x==0 && y==0:stickDirection=nil;stickRunning=false;return
        default:break
        }
        guard net.online,!interactionSuspended,!net.npcOpen,!net.tradeBusy,!net.dealOpen else { return }
        switch command {
        case let .move(x,y):joystick(x:x,y:y)
        case .attack:toggleAutoAttack()
        case .holdAttack(let held):attackHeld=held;if held { attackSelected() }
        case .skill(let skill):stopAutomation();castSkill(skill)
        case .pickup:collectNearby()
        case .stop:stopAutomation()
        }
    }
    private func toggleAutoAttack() {
        if autoAttack { stopAutomation();combatReport?("自动攻击已停止");return }
        guard let id=playerID,let player=actors[id],!player.dead else { return }
        let nearest=actors.filter { $0.value.monster && !$0.value.dead && max(abs($0.value.cell.x-player.cell.x),abs($0.value.cell.y-player.cell.y))<=12 }.min {
            let left=max(abs($0.value.cell.x-player.cell.x),abs($0.value.cell.y-player.cell.y))
            let right=max(abs($1.value.cell.x-player.cell.x),abs($1.value.cell.y-player.cell.y))
            return left==right ? $0.key<$1.key : left<right
        }
        let chosen=selected.flatMap { key -> (key:Int32,value:Avatar)? in
            guard let actor=actors[key],!actor.dead,!actor.npc else { return nil }
            return (key,actor)
        } ?? nearest
        stopAutomation()
        guard let target=chosen else { selected=nil;targetReport?("");combatReport?("附近没有可攻击的怪物");return }
        selected=target.key;autoAttack=true;queuedAttack=true;targetHealthReport?(nil)
        targetReport?(target.value.displayName);combatReport?("自动追打 \(target.value.displayName)；推摇杆或再点攻击停止")
    }
    func collectNearby() { stopAutomation();pickupSweep=true;combatReport?("拾取周围物品；推摇杆取消") }
    func toggleAutoSkill(_ id:Int) {
        guard !MirSkills.warrior(id) else { combatReport?("剑术状态由服务器确认，点击开启或蓄力");return }
        if net.automaticSkills.contains(id) { net.automaticSkills.remove(id);combatReport?("已关闭技能自动释放") }
        else { net.automaticSkills.insert(id);combatReport?("自动追打时释放该技能") }
    }
    func cancelAim() { aimMarker?.removeFromParent();aimMarker=nil }
    private func aimedCell(dx:Double,dy:Double)->Cell? {
        guard let id=playerID,let a=actors[id],hypot(dx,dy)<=220 else { return nil }
        let cell=Cell(x:a.cell.x+Int((dx/22).rounded()),y:a.cell.y+Int((dy/22).rounded()))
        return contains(cell) ? cell : nil
    }
    func aimSkill(_ skill:MirEquipment.Skill,dx:Double,dy:Double,release:Bool=false) {
        guard net.online,!interactionSuspended,!net.npcOpen,MirSkills.ground(skill.id) else { return }
        cancelAim()
        guard let cell=aimedCell(dx:dx,dy:dy) else { if release { combatReport?("已取消施法") };return }
        if release {
            queuedSkill=skill;queuedGround=cell;queuedAttack=false
        } else {
            let ring=SKShapeNode(ellipseOf:CGSize(width:48,height:32));ring.strokeColor = .yellow;ring.lineWidth=2
            ring.position=point(cell);ring.zPosition=100000;addChild(ring);aimMarker=ring
        }
    }
    func castSkill(_ skill:MirEquipment.Skill) {
        queuedGround=nil
        guard skill.castable else { combatReport?("被动技能由服务器自动判定");return }
        guard net.online,!interactionSuspended,!net.npcOpen else { return }
        if attackPending || pending != nil || clock<nextAttack || ProcessInfo.processInfo.systemUptime<attackReadyAt {
            queuedSkill=skill;queuedAttack=false;combatReport?("当前动作结束后释放技能");return
        }
        autoAttack=false;attackHeld=false;route=[];pickupSweep=false
        let remaining=(net.skillReady[skill.id] ?? 0)-ProcessInfo.processInfo.systemUptime
        if remaining>0 { combatReport?(String(format:"技能冷却中，还需 %.1f 秒",remaining));return }
        if MirSkills.ground(skill.id) {
            armedGroundSkill=skill;combatReport?("点击地图释放 \(net.skillName(skill))；推摇杆取消");return
        }
        performSkill(skill,ground:nil)
    }
    private func performSkill(_ skill:MirEquipment.Skill,ground:Cell?) {
        guard net.online,!net.npcOpen,!interactionSuspended,net.inventory.pending==nil,!net.tradeBusy,!net.dealOpen,!attackPending,pending==nil,clock>=nextAttack,ProcessInfo.processInfo.systemUptime>=attackReadyAt,
              ProcessInfo.processInfo.systemUptime >= (net.skillReady[skill.id] ?? 0),
              let id=playerID,let a=actors[id],!a.dead else { return }
        let selfCast=MirSkills.selfCast(skill.id)
        if !classicMode && !selfCast && ground==nil && (selected==nil || actors[selected!]?.dead != false) {
            selected=actors.filter { $0.value.monster && !$0.value.dead }.min {
                max(abs($0.value.cell.x-a.cell.x),abs($0.value.cell.y-a.cell.y)) < max(abs($1.value.cell.x-a.cell.x),abs($1.value.cell.y-a.cell.y))
            }?.key
        }
        let targetID: Int32 = ground != nil ? 0 : (selfCast ? id : (selected ?? 0))
        guard let cell=ground ?? actors[targetID]?.cell else { combatReport?("附近没有目标，请先点选玩家或怪物");return }
        guard contains(cell),max(abs(cell.x-a.cell.x),abs(cell.y-a.cell.y))<=10 else { combatReport?("目标距离太远");return }
        route=[];pathGeneration+=1;pathBusy=false;armedGroundSkill=nil
        attackPending=true;attackRequested=clock;nextAttack=clock+1.5;nextStep=nextAttack
        net.skillReady[skill.id]=ProcessInfo.processInfo.systemUptime+Double(skill.delayMS)/1000
        if !MirSkills.warrior(skill.id) {
            a.direction=MirTouchInput.direction(x:Double(cell.x-a.cell.x),y:Double(cell.y-a.cell.y)) ?? a.direction
            predictingSpell=true;animate(a,"spell",duration:0.6);readyEffect(skill.effect,actor:a)
        }
        lastSkillID=skill.id
        net.cast(skill,x:cell.x+map.originX,y:cell.y+map.originY,target:targetID)
    }
    private var drops:[Int32:(cell:Cell,node:SKNode)]=[:]
    private var gold:Int32=0
    private var actorLibraries:[String:[String:[[SceneData.Frame]]]] = [:]
    var combatReport:((String)->Void)?
    var report:((String)->Void)?
    private final class Avatar {
        let node=SKNode(), image=SKSpriteNode(), weapon=SKSpriteNode(), hair=SKSpriteNode(), label=SKLabelNode(fontNamed:"Helvetica-Bold")
        var cell:Cell, direction=4, walkingUntil=0.0, lastFile=""
        var harvested=false
        var monster=false, dead=false, action="stand", actionAt=0.0, actionUntil=0.0
        var npc=false, appearanceKey="", displayName="角色", weaponVariant=0, hairVariant=0, sex=0, running=false
        init(_ cell:Cell) {
            self.cell=cell;image.anchorPoint = .zero;weapon.anchorPoint = .zero;hair.anchorPoint = .zero;node.addChild(image);node.addChild(weapon);node.addChild(hair);hair.zPosition=0.5
            label.fontSize=12;label.position.y=38;node.addChild(label)
        }
    }
    init(map:SceneData,root:URL,net:MirConnection) {
        self.map=map;self.root=root;self.net=net
        super.init(size:CGSize(width:960,height:540));scaleMode = .resizeFill
        if let data=try? Data(contentsOf:root.appendingPathComponent("actor-libraries.json")),let libraries=try? JSONDecoder().decode([String:[String:[[SceneData.Frame]]]].self,from:data) { actorLibraries=libraries }
        if map.width==700,map.height==700,map.originX==0,map.originY==0,let data=try? Data(contentsOf:root.appendingPathComponent("classic-ui/bichon-npcs.json")),let entries=try? JSONDecoder().decode([WorldNPC].self,from:data) { knownNPCs=entries }
        cache.totalCostLimit=64*1024*1024
        if let data=try? Data(contentsOf:root.appendingPathComponent("weapon-order.json")),let order=try? JSONDecoder().decode([[Int]].self,from:data) { weaponOrder=order }
        if let data=try? Data(contentsOf:root.appendingPathComponent("skill-effects.json")),let frames=try? JSONDecoder().decode([String:[String:SceneData.Frame]].self,from:data) { effectFrames=frames }
        backgroundColor = .black
        net.onPacket={ [weak self] in self?.packet($0) }
        net.onWalkAck={ [weak self] in self?.accepted() }
        net.onWalkRejected={ [weak self] in self?.rejectAction() }
        net.onAttackAck={ [weak self] in
            guard let self=self else { return };self.attackPending=false
            self.predictingSpell=false
            self.delayNotified=false
            self.attackReadyAt=ProcessInfo.processInfo.systemUptime+1.0
            self.nextAttack=max(self.nextAttack,self.clock+1.0)
            self.nextStep=max(self.nextStep,self.nextAttack)
        }
        net.onDisconnect={ [weak self] in self?.clear() }
    }
    required init?(coder:NSCoder) { fatalError("Use init(map:root:net:)") }
    override func didMove(to view:SKView) {
        guard !built else { return };built=true;view.preferredFramesPerSecond=60
        streamer=SceneStreamer(scene:self,map:map,root:root)
        addChild(effectsRoot);addChild(cameraNode);camera=cameraNode;cameraNode.position=point(map.spawn)
    }
    private func local(_ x:UInt16,_ y:UInt16)->Cell { Cell(x:Int(x)-map.originX,y:Int(y)-map.originY) }
    private func point(_ c:Cell)->CGPoint { CGPoint(x:CGFloat(c.x*48+24),y:CGFloat(-(c.y*32+16))) }
    private func contains(_ c:Cell)->Bool { c.x>=0 && c.y>=0 && c.x<map.width && c.y<map.height }
    private func clear() {
        lastSkillID=nil;lastAutoSkillID=nil;predictingSpell=false;transientEffects=[]
        for actor in actors.values { actor.node.removeFromParent() }
        actors.removeAll();playerID=nil;route=[];pending=nil;stopAutomation();dropNames=[:];pickupAttempts=[:];effectsRoot.removeAllChildren();events=[:];shields=[:];targetReport?("");targetHealthReport?(nil)
        for drop in drops.values { drop.node.removeFromParent() };drops.removeAll()
        selected=nil;selectedCorpse=nil;attackPending=false;gold=0;combatReport?("")
    }
    private func clearWorldKeepingPlayer() {
        let oldID=playerID, player=playerID.flatMap { actors[$0] }, balance=gold
        clear();gold=balance
        if let id=oldID,let player=player { player.node.removeAllActions();actors[id]=player;playerID=id;addChild(player.node) }
    }
    private func changeMap(_ p:MirWire.Packet) {
        let id=String(decoding:p.body,as:UTF8.self).trimmingCharacters(in:CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn:"\0")))
        do {
            let (next,_)=try SceneData.load(mapID:id)
            let destination=Cell(x:Int(p.x)-next.originX,y:Int(p.y)-next.originY)
            guard destination.x>=0,destination.y>=0,destination.x<next.width,destination.y<next.height else { throw SceneData.LoadError.invalid("入场坐标超出地图范围") }
            if p.id==634 { clearWorldKeepingPlayer() } else { clear() }
            streamer?.suspend();streamer=nil;cache.removeAllObjects()
            map=next;mapID=id;knownNPCs=[]
            let markerFile=id=="0" ? "classic-ui/bichon-npcs.json" : "maps/\(id)/npcs.json"
            if let data=try? Data(contentsOf:root.appendingPathComponent(markerFile)),let entries=try? JSONDecoder().decode([WorldNPC].self,from:data) { knownNPCs=entries }
            if built { streamer=SceneStreamer(scene:self,map:map,root:root) }
            if let ownID=playerID,let player=actors[ownID] { player.cell=destination;player.node.position=point(destination);player.action="stand";player.actionUntil=0 }
            cameraNode.position=point(destination);positionReport?(destination)
            nextStep=clock+0.65;movementReadyAt=ProcessInfo.processInfo.systemUptime+0.65;lastStream=0
            mapReport?(map.name,minimapImage);net.log("map loaded id=\(id) size=\(map.width)x\(map.height) destination=\(p.x),\(p.y)")
        } catch { net.disconnect();net.status="地图加载失败：\(error.localizedDescription)" }
    }
    private func animate(_ actor:Avatar,_ action:String,duration:Double) {
        actor.action=action;actor.actionAt=clock;actor.actionUntil=clock+duration
    }
    private func text(_ bytes:[UInt8])->String {
        let encoding=String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        return String(bytes:bytes,encoding:encoding) ?? "物品"
    }
    private func packet(_ p:MirWire.Packet) {
        if p.id==17 {
            if let a=actors[p.actor] {
                let target=local(p.x,p.y)
                a.direction=MirTouchInput.direction(x:Double(target.x-a.cell.x),y:Double(target.y-a.cell.y)) ?? a.direction
                animate(a,"spell",duration:0.6);readyEffect(Int(p.series),actor:a)
            }
            return
        }
        if p.id==637,let a=actors[p.actor] { a.direction=Int(p.series & 7);animate(a,"butcher",duration:0.6);return }
        if p.id==33,let a=actors[p.actor] {
            a.harvested=true;a.dead=true;a.action="skeleton";a.actionAt=clock
            if selectedCorpse==p.actor { selectedCorpse=nil;combatReport?("尸体已采集；所得物品以服务器背包更新为准") };return
        }
        if p.id==638 { magicFire(p);return }
        if p.id==639 {
            if p.actor==playerID { predictingSpell=false;if let id=lastSkillID { net.automaticSkills.remove(id) };combatReport?("施法未成功，请检查蓝量、护身符／毒粉、目标或冷却") }
            return
        }
        if p.id==804 {
            events.removeValue(forKey:p.actor)?.removeFromParent()
            let cell=local(p.y,p.series)
            if contains(cell),p.x==5 || p.x==4 {
                events[p.actor]=effect(base:p.x==5 ? 1630 : 1390,count:p.x==5 ? 6 : 10,at:point(cell),interval:p.x==5 ? 0.04 : 0.02,loop:true)
            }
            return
        }
        if p.id==805 { events.removeValue(forKey:p.actor)?.removeFromParent();return }
        if p.id==657 { updateShield(p.actor,state:UInt32(p.x) | UInt32(p.y)<<16);return }
        if p.id==8 || p.id==24 {
            if let a=actors[p.actor] { a.direction=Int(p.series & 7);animate(a,"attack",duration:0.6);meleeEffect(p.id,actor:a) }
            return
        }
        if p.id==41,let a=actors[p.actor],!a.monster,!a.npc { applyFeature(a,UInt32(p.x) | UInt32(p.y)<<16) }
        if (p.id==615 || p.id==619),let id=playerID,let a=actors[id] { applyFeature(a,UInt32(bitPattern:p.actor)) }
        if p.id==52 || p.id==653 { gold=p.actor;combatReport?("金币 \(gold)") }
        if p.id==200 { combatReport?("服务端确认获得物品 · 金币 \(gold)") }
        if p.id==610 {
            let cell=local(p.x,p.y);guard contains(cell) else { return }
            drops[p.actor]?.node.removeFromParent()
            let node=SKNode();node.position=point(cell);node.zPosition=1000+CGFloat(cell.y*4)
            let name=text(p.body);dropNames[p.actor]=name
            if let image=UIImage(contentsOfFile:root.appendingPathComponent("ground-items/\(p.series).png").path) {
                node.addChild(SKSpriteNode(texture:SKTexture(image:image)))
            } else {
                let coin=SKShapeNode(circleOfRadius:7);coin.fillColor = .yellow;coin.strokeColor = .orange;node.addChild(coin)
            }
            let label=SKLabelNode(text:name);label.fontSize=12;label.position.y = -18;node.addChild(label)
            addChild(node);drops[p.actor]=(cell,node);combatReport?("地面掉落：\(name) · 走到物品上点击拾取");return
        }
        if p.id==611 { if let cell=drops[p.actor]?.cell { pickupAttempts.removeValue(forKey:cell) };drops.removeValue(forKey:p.actor)?.node.removeFromParent();dropNames.removeValue(forKey:p.actor);return }
        if p.id==53,let a=actors[p.actor],p.actor != playerID {
            a.label.text="\(a.displayName) HP \(p.x)/\(p.series) MP \(p.y)"
            if selected==p.actor { targetHealthReport?(p.series>0 ? min(1,Double(p.x)/Double(p.series)) : nil) }
        }
        if p.id==31,let a=actors[p.actor] {
            if p.actor==playerID { route=[];pickupSweep=false }
            if !a.dead { animate(a,"struck",duration:0.25) }
            if p.actor != playerID { a.label.text = "\(a.displayName) HP \(p.x)/\(p.y)" }
            if selected==p.actor { targetReport?("\(a.displayName)  HP \(p.x)/\(p.y)");targetHealthReport?(p.y>0 ? min(1,Double(p.x)/Double(p.y)) : nil) }
            let number=SKLabelNode(text:"-\(p.series)");number.fontColor = .red;number.fontSize=18;number.position.y=55;a.node.addChild(number)
            number.run(.sequence([.moveBy(x:0,y:24,duration:0.6),.removeFromParent()]));return
        }
        if p.id==32 || p.id==34,let a=actors[p.actor] {
            shields.removeValue(forKey:p.actor)?.removeFromParent();a.dead=true;animate(a,"die",duration:1.2);a.node.removeAction(forKey:"walk")
            if selected==p.actor { stopAutomation();selected=nil;targetHealthReport?(nil);targetReport?("目标已击败") };if playerID==p.actor { stopAutomation();combatReport?("角色已死亡，请退出后重新登录") }
            return
        }
        if [UInt16(14),15,18,19].contains(p.id),let a=actors[p.actor] { a.direction=Int(p.series & 7);animate(a,"attack",duration:0.6);meleeEffect(p.id,actor:a);return }
        if p.id==51 || p.id==634 { changeMap(p);return }
        if p.id==633 { clearWorldKeepingPlayer();return }
        if p.id==30 { shields.removeValue(forKey:p.actor)?.removeFromParent();actors.removeValue(forKey:p.actor)?.node.removeFromParent();if selected==p.actor { stopAutomation();selected=nil;targetReport?("");targetHealthReport?(nil) };return }
        if p.id==28 {
            guard p.actor==playerID else { return }
            rejectAction()
            if let id=playerID,let a=actors[id] { a.cell=local(p.x,p.y);a.node.removeAllActions();a.node.position=point(a.cell) }
            report?("服务器拒绝移动，已校正位置");return
        }
        guard [UInt16(50),10,11,9,13,27,32,34,33].contains(p.id) else { return }
        let cell=local(p.x,p.y)
        if p.id==50 {
            guard contains(cell) else { net.disconnect();net.status="角色位于资源范围外，请在电脑运行测试角色复位脚本";return }
            playerID=p.actor;pending=nil;route=[]
        }
        guard contains(cell) else { actors.removeValue(forKey:p.actor)?.node.removeFromParent();return }
        let avatar:Avatar
        if let existing=actors[p.actor] { avatar=existing }
        else { avatar=Avatar(cell);actors[p.actor]=avatar;addChild(avatar.node);avatar.node.position=point(cell) }
        if p.body.count>=8 {
            // CharDesc starts with little-endian feature: race, weapon, appearance.
            let race=Int(p.body[0]),appearance=Int(p.body[2]) | (Int(p.body[3])<<8)
            avatar.appearanceKey="\(race)-\(appearance)"
            if race==0 { applyFeature(avatar,UInt32(bitPattern:MirEquipment.integer(p.body,0))) }
            avatar.npc=race==50
            avatar.monster=race>=10 && race<50
        }
        if p.id==27 || p.id==10 { avatar.dead=false;avatar.harvested=false;avatar.action="stand";avatar.actionUntil=0 }
        if p.id==10, p.bodyParts.count>1, !p.bodyParts[1].isEmpty {
            avatar.displayName=text(p.bodyParts[1]).components(separatedBy:"/").first ?? "角色"
        } else if avatar.monster {
            avatar.displayName=["11-160":"鸡","11-161":"鹿","18-27":"稻草人","17-25":"多钩猫","17-26":"钉耙猫","19-100":"半兽人"][avatar.appearanceKey] ?? "怪物"
        }
        if [UInt16(32),34,33].contains(p.id) { avatar.dead=true;avatar.harvested=p.id==33;animate(avatar,p.id==33 ? "skeleton" : "die",duration:1.2) }
        avatar.label.text = p.actor==playerID ? "我" : avatar.displayName
        avatar.label.fontColor = p.actor==playerID ? .yellow : .white
        avatar.direction=Int(p.series & 7);avatar.cell=cell
        if p.id==11 || p.id==9 || p.id==13 {
            avatar.running=p.id==9 || p.id==13;avatar.walkingUntil=clock+0.54
            avatar.node.run(.move(to:point(cell),duration:0.54),withKey:"walk")
        } else { avatar.node.removeAction(forKey:"walk");avatar.node.position=point(cell) }
        if p.body.count>=8 { updateShield(p.actor,state:UInt32(bitPattern:MirEquipment.integer(p.body,4))) }
        showPosition()
    }
    private func showPosition() {
        if let id=playerID,let a=actors[id] { positionReport?(a.cell);report?("\(map.name) (\(a.cell.x+map.originX),\(a.cell.y+map.originY)) · 可见角色 \(actors.count)") }
    }
    override func touchesEnded(_ touches:Set<UITouch>,with event:UIEvent?) {
        guard net.online,!net.npcOpen,!net.tradeBusy,!net.dealOpen,!interactionSuspended,let id=playerID,let a=actors[id],let touch=touches.first else { return }
        let p=touch.location(in:self),target=Cell(x:Int(floor(p.x/48)),y:Int(floor(-p.y/32)))
        if let skill=armedGroundSkill { performSkill(skill,ground:target);return }
        if let npc=actors.first(where:{$0.value.npc && $0.value.cell==target}) {
            stopAutomation()
            guard max(abs(target.x-a.cell.x),abs(target.y-a.cell.y))<=3 else { combatReport?("请走近 \(npc.value.displayName) 再交谈");return }
            net.talk(to:npc.key);return
        }
        if let other=actors.first(where: { $0.key != id && !$0.value.monster && !$0.value.npc && !$0.value.dead && ($0.value.cell==target || $0.value.node.calculateAccumulatedFrame().insetBy(dx:-8,dy:-8).contains(p)) }) {
            stopAutomation();selected=other.key;targetHealthReport?(nil);targetReport?(other.value.displayName);net.peerMessage="";net.inspectedName="";net.inspectedItems=[:];playerReport?(PlayerTarget(id:other.key,name:other.value.displayName));return
        }
        if let corpse=actors.first(where: { $0.value.dead && !$0.value.harvested && ["11-160","11-161"].contains($0.value.appearanceKey) && $0.value.cell==target }) {
            stopAutomation();selectedCorpse=corpse.key;combatReport?("已选中 \(corpse.value.displayName) 尸体；靠近后反复点击割肉");return
        }
        if let match=actors.first(where: { $0.value.monster && !$0.value.dead && $0.value.cell==target }) {
            stopAutomation();selected=match.key;targetHealthReport?(nil);route=[];targetReport?(match.value.label.text ?? match.value.displayName);combatReport?("已锁定 \(match.value.displayName)，点击攻击追打当前目标");return
        }
        navigate(to:target)
    }
    func attackSelected() {
        guard net.online,!net.npcOpen,!interactionSuspended,net.inventory.pending==nil,!net.tradeBusy,!net.dealOpen,!attackPending,pending==nil,clock>=nextAttack,ProcessInfo.processInfo.systemUptime>=attackReadyAt,let id=playerID,let a=actors[id],!a.dead else { return }
        let candidates=actors.filter { $0.value.monster && !$0.value.dead && max(abs($0.value.cell.x-a.cell.x),abs($0.value.cell.y-a.cell.y))<=12 }
        if !classicMode && (selected==nil || actors[selected!]?.dead != false) { targetHealthReport?(nil);selected=candidates.min { lhs,rhs in
            let l=max(abs(lhs.value.cell.x-a.cell.x),abs(lhs.value.cell.y-a.cell.y))
            let r=max(abs(rhs.value.cell.x-a.cell.x),abs(rhs.value.cell.y-a.cell.y))
            return l==r ? lhs.key<rhs.key : l<r
        }?.key }
        guard let selected=selected,let target=actors[selected],!target.dead else {
            // A normal swing uses the existing direction and authoritative attack command.
            lastSkillID=nil;attackPending=true;attackRequested=clock;nextAttack=clock+1;nextStep=nextAttack
            animate(a,"attack",duration:0.6)
            net.attack(x:a.cell.x+map.originX,y:a.cell.y+map.originY,direction:a.direction)
            return
        }
        targetReport?(target.label.text ?? target.displayName)
        let dx=target.cell.x-a.cell.x,dy=target.cell.y-a.cell.y
        let distance=max(abs(dx),abs(dy))
        let thrust=net.warrior.thrust && distance==2 && (dx==0 || dy==0 || abs(dx)==abs(dy))
        guard distance==1 || thrust else {
            guard autoAttack || !classicMode else { combatReport?("目标不在攻击距离，请靠近");return }
            guard max(abs(dx),abs(dy))<=12 else { stopAutomation();combatReport?("目标超出追击范围，已停止");return }
            guard route.isEmpty else { return }
            let goals=map.grid.neighbors(target.cell).sorted { max(abs($0.x-a.cell.x),abs($0.y-a.cell.y)) < max(abs($1.x-a.cell.x),abs($1.y-a.cell.y)) }
            if let goal=goals.first(where:{ cell in !actors.values.contains(where:{!$0.dead && $0.cell==cell}) }) { queuePath(to:goal,running:false) }
            return
        }
        let dirs=[Cell(x:0,y:-1),Cell(x:1,y:-1),Cell(x:1,y:0),Cell(x:1,y:1),Cell(x:0,y:1),Cell(x:-1,y:1),Cell(x:-1,y:0),Cell(x:-1,y:-1)]
        a.direction=dirs.firstIndex(of:Cell(x:dx.signum(),y:dy.signum())) ?? 4
        lastSkillID=nil;route=[];attackPending=true;attackRequested=clock;nextAttack=clock+1.0;nextStep=nextAttack
        animate(a,"attack",duration:0.6)
        let hit=net.warrior.hit(distance:distance,now:ProcessInfo.processInfo.systemUptime)
        meleeEffect(hit==3025 ? 8 : hit==3024 ? 24 : hit==3019 ? 19 : hit==3018 ? 18 : 14,actor:a)
        net.attack(x:a.cell.x+map.originX,y:a.cell.y+map.originY,direction:a.direction,distance:distance)
    }
    func butcherNearby() {
        guard net.online,!net.npcOpen,!interactionSuspended,pending==nil,!attackPending,let id=playerID,let a=actors[id],!a.dead else { return }
        stopAutomation()
        let candidates=actors.filter { $0.value.dead && !$0.value.harvested && ["11-160","11-161"].contains($0.value.appearanceKey) && max(abs($0.value.cell.x-a.cell.x),abs($0.value.cell.y-a.cell.y))<=2 }
        if selectedCorpse==nil || candidates[selectedCorpse!]==nil { selectedCorpse=candidates.keys.sorted().first }
        guard let corpseID=selectedCorpse,let corpse=candidates[corpseID] else { combatReport?("请靠近鸡或鹿的尸体再割肉");return }
        let direction=MirTouchInput.direction(x:Double(corpse.cell.x-a.cell.x),y:Double(corpse.cell.y-a.cell.y)) ?? a.direction
        if net.butcher(target:corpseID,x:corpse.cell.x+map.originX,y:corpse.cell.y+map.originY,direction:direction) {
            a.direction=direction;nextStep=clock+0.65;nextAttack=clock+0.65
            combatReport?("正在割肉；反复点击，直至服务器确认采集完成")
        }
    }
    func pickupHere() {
        guard net.online,!net.npcOpen,!interactionSuspended,net.inventory.pending==nil,!net.tradeBusy,!net.dealOpen,pending==nil,!attackPending,clock>=nextPickup,let id=playerID,let a=actors[id],!a.dead else { return }
        guard drops.values.contains(where:{$0.cell==a.cell}) else { combatReport?("请先走到掉落物所在格子");return }
        let attempts=pickupAttempts[a.cell,default:0]
        guard attempts<3 else { pickupSweep=false;autoPickup=false;combatReport?("连续拾取未获确认，已停止；请检查归属、背包和负重");return }
        pickupAttempts[a.cell]=attempts+1
        route=[];nextPickup=clock+0.8;net.pickup(x:a.cell.x+map.originX,y:a.cell.y+map.originY)
    }
    private func rejectAction() {
        if attackPending,let id=lastSkillID {
            net.skillReady.removeValue(forKey:id);net.automaticSkills.remove(id)
            combatReport?("服务器拒绝本次施法，已停止该技能自动释放")
        }
        lastSkillID=nil;predictingSpell=false
        pending=nil;route=[];attackPending=false;nextStep=clock+0.7;nextAttack=clock+1
        if let id=playerID,let a=actors[id] { a.node.removeAction(forKey:"walk");a.node.position=point(a.cell);a.walkingUntil=0;a.actionUntil=0 }
    }
    private func applyFeature(_ a:Avatar,_ feature:UInt32) {
        let dress=Int(feature>>24)
        a.sex=dress%2;a.appearanceKey="human-\(dress)";a.weaponVariant=Int((feature>>8)&255);a.hairVariant=Int((feature>>16)&255)
        a.lastFile=""
    }
    private func texture(_ file:String)->SKTexture? {
        if let tex=cache.object(forKey:file as NSString) { return tex }
        guard let img=UIImage(contentsOfFile:root.appendingPathComponent(file).path) else { return nil }
        let tex=SKTexture(image:img);tex.filteringMode = .nearest
        cache.setObject(tex,forKey:file as NSString,cost:Int(img.size.width*img.size.height)*4);return tex
    }
    private func drawOverlay(_ node:SKSpriteNode,key:String,action:String,direction:Int,phase:Int) {
        guard let frames=actorLibraries[key]?[action],frames.indices.contains(direction),!frames[direction].isEmpty else { node.isHidden=true;return }
        let f=frames[direction][min(phase,frames[direction].count-1)]
        guard let tex=texture(f.file) else { node.isHidden=true;return }
        node.isHidden=false;node.texture=tex;node.size=tex.size();node.position=CGPoint(x:CGFloat(f.offsetX-24),y:CGFloat(16-f.offsetY-f.height))
    }
    @discardableResult
    private func effect(base:Int,count:Int,at position:CGPoint,library:String="magic",interval:Double=0.08,loop:Bool=false,temporaryLoop:Bool=false,parent:SKNode?=nil)->SKNode {
        let temporary = !loop || temporaryLoop
        if temporary {
            transientEffects.removeAll { $0.scene==nil }
            let limit=(view?.preferredFramesPerSecond ?? 60)<=30 ? 48 : 96
            while transientEffects.count>=limit {
                let oldest=transientEffects.removeFirst();oldest.removeAllActions();oldest.removeFromParent()
            }
        }
        let container=SKNode(),sprite=SKSpriteNode()
        container.name=temporary ? "transient" : "persistent"
        if temporary { transientEffects.append(container) }
        sprite.anchorPoint = .zero;sprite.blendMode = .add
        container.addChild(sprite);container.position=position
        (parent ?? effectsRoot).addChild(container)
        container.zPosition=parent == nil ? 20000 : 4
        let duration=Double(count)*interval
        var previousIndex = -1
        let action=SKAction.customAction(withDuration:duration) { [weak self,weak sprite] _,elapsed in
            guard let self=self,let sprite=sprite else { return }
            let index=base+min(count-1,Int(Double(elapsed)/interval))
            guard index != previousIndex else { return };previousIndex=index
            guard let frame=self.effectFrames[library]?[String(index)],let tex=self.texture(frame.file) else { sprite.isHidden=true;return }
            sprite.isHidden=false;sprite.texture=tex;sprite.size=tex.size()
            sprite.position=CGPoint(x:CGFloat(frame.offsetX-24),y:CGFloat(16-frame.offsetY-frame.height))
        }
        container.run(loop ? .repeatForever(action) : .sequence([action,.removeFromParent()]))
        return container
    }
    private func readyEffect(_ number:Int,actor:Avatar) {
        guard let base=MirSkills.base(number) else { return }
        effect(base:base,count:10,at:.zero,library:number==9 || number==28 ? "magic2" : "magic",interval:0.06,parent:actor.node)
    }
    private func meleeEffect(_ message:UInt16,actor:Avatar) {
        let bases:[UInt16:Int]=[18:800,19:1410,24:1700,8:3480]
        if let base=bases[message] { effect(base:base+actor.direction*10,count:6,at:.zero,interval:0.1,parent:actor.node) }
    }
    private func updateShield(_ id:Int32,state:UInt32) {
        guard let a=actors[id] else { return }
        if state & 0x00100000 != 0 && !a.dead {
            if shields[id]==nil { shields[id]=effect(base:3890,count:3,at:.zero,interval:0.12,loop:true,parent:a.node) }
        } else { shields.removeValue(forKey:id)?.removeFromParent() }

    }
    private func magicFire(_ p:MirWire.Packet) {
        guard let a=actors[p.actor],let base=MirSkills.base(Int(p.series>>8)) else { return }
        let kind=Int(p.series & 255),number=Int(p.series>>8),cell=local(p.x,p.y)
        guard contains(cell) else { return }
        let destination=point(cell),start=a.node.position
        let direction=MirSkills.direction16(dx:Double(destination.x-start.x),dy:Double(start.y-destination.y))
        switch kind {
        case 0,1,8,9:
            let talisman=kind==8 || kind==9
            let flyBase=(talisman ? 1160 : base+10)+direction*10
            let impact=talisman ? (kind==9 ? (number==11 ? 1320 : 1340) : (number==17 ? 1540 : 1360)) : base+170
            let duration=max(0.12,min(0.9,Double(hypot(destination.x-start.x,destination.y-start.y))/500))
            let projectile=effect(base:flyBase,count:talisman ? 3 : 6,at:start,interval:0.05,loop:true,temporaryLoop:true)
            projectile.run(.sequence([.move(to:destination,duration:duration),.run { [weak self,weak projectile] in
                projectile?.removeFromParent();self?.effect(base:impact,count:kind==9 ? 16 : 10,at:destination)
            }]))
        case 2:
            let special:[Int:(Int,Int)]=[18:(1564,16),21:(1660,20),26:(3990,10),27:(1800,10),30:(3930,16),31:(3850,20)]
            let spec=special[number] ?? (base+170,10)
            effect(base:spec.0,count:spec.1,at:destination)
        case 7:effect(base:10,count:6,at:destination,library:"magic2",interval:0.1)
        case 6:effect(base:970+direction*10,count:6,at:start,interval:0.1)
        case 5:
            let delta=CGVector(dx:(destination.x-start.x)/5,dy:(destination.y-start.y)/5)
            for i in 1...5 { effect(base:930,count:6,at:CGPoint(x:start.x+delta.dx*CGFloat(i),y:start.y+delta.dy*CGFloat(i)),interval:0.1) }
        case 4,10:break // Ring is in the caster frames; prison/fire persist via 804/805.
        default:net.log("unimplemented magic visual type=\(kind) effect=\(number)")
        }
    }
    private func accepted() {
        guard let target=pending,let id=playerID,let a=actors[id] else { return }
        view?.preferredFramesPerSecond=clock-requestedAt>0.8 ? 30 : 60
        pending=nil;delayNotified=false;a.cell=target
        // Pace from the acknowledgement: network jitter must not compress two
        // server-side movements below the configured 600 ms interval.
        nextStep=clock+0.65
        movementReadyAt=ProcessInfo.processInfo.systemUptime+0.65
        net.log("move ack elapsed=\(clock-requestedAt) nextDelay=0.65")
        showPosition()
    }
    override func update(_ time:TimeInterval) {
        if let id=playerID,let me=actors[id],let v=net.vitals {
            me.label.text="我 HP \(v.hp)/\(v.maxHP) MP \(v.mp)/\(v.maxMP)"
        }
        guard built else { return };clock=time
        if pending != nil || attackPending {
            let elapsed=time-(pending != nil ? requestedAt : attackRequested)
            switch MirActionWait.decision(elapsed:elapsed) {
            case .waiting:break
            case .delayed:
                if !delayNotified {
                    delayNotified=true;stopAutomation()
                    net.log("action delayed move=\(pending != nil) attack=\(attackPending) age=\(elapsed); waiting without replay")
                    combatReport?("网络响应较慢，已暂停连续操作，等待服务器确认")
                }
            case .expired:
                net.log("action expired move=\(pending != nil) attack=\(attackPending) age=\(elapsed)")
                net.disconnect();net.status="动作超过20秒未确认，请重新登录同步位置；可导出日志排查"
                return
            }
        } else { delayNotified=false }
        transientEffects.removeAll { $0.scene==nil }
        if net.online && time>=nextPerformanceLog {
            nextPerformanceLog=time+10
            net.log("render transientEffects=\(transientEffects.count) groundEvents=\(events.count) shields=\(shields.count) fpsLimit=\(view?.preferredFramesPerSecond ?? 0)")
        }
        let locked = pending != nil || attackPending
        if net.actionLocked != locked { net.actionLocked=locked }
        if net.online,!interactionSuspended,!net.npcOpen,!net.tradeBusy,!net.dealOpen,net.inventory.pending==nil,pending==nil,!attackPending,clock>=nextAttack,ProcessInfo.processInfo.systemUptime>=attackReadyAt {
            if let skill=queuedSkill {
                let ground=queuedGround;queuedSkill=nil;queuedGround=nil
                if let ground=ground { performSkill(skill,ground:ground) } else { castSkill(skill) }
            }
            else if queuedAttack { queuedAttack=false;attackSelected() }
        }
        if net.online,!interactionSuspended,!net.npcOpen,pending==nil,!attackPending,net.inventory.pending==nil,!net.tradeBusy,!net.dealOpen,time>=nextStep,ProcessInfo.processInfo.systemUptime>=movementReadyAt,let id=playerID,let a=actors[id],!a.dead {
            if (autoAttack || attackHeld) && time>=nextAuto {
                nextAuto=time+0.3
                if let targetID=selected,let target=actors[targetID],!target.dead {
                    let distance=max(abs(target.cell.x-a.cell.x),abs(target.cell.y-a.cell.y))
                    let eligible=net.skills.filter { skill in
                        !classicMode && skill.castable && !MirSkills.warrior(skill.id) && net.automaticSkills.contains(skill.id)
                        && ProcessInfo.processInfo.systemUptime >= (net.skillReady[skill.id] ?? 0)
                        && (MirSkills.selfCast(skill.id) || distance<=10)
                        && !(skill.id==31 && shields[id] != nil)
                    }
                    if let nextID=MirSkills.nextAutomatic(eligible.map(\.id),after:lastAutoSkillID),let skill=eligible.first(where:{$0.id==nextID}) {
                        performSkill(skill,ground:MirSkills.ground(skill.id) ? target.cell : nil)
                        if attackPending { lastAutoSkillID=skill.id }
                    }
                }
                if !attackPending { attackSelected() }
            }
            if !attackPending,stickDirection==nil,route.isEmpty,!autoAttack,!attackHeld,(autoPickup || pickupSweep),time>=nextPickup {
                if net.inventory.bag.count>=46 { pickupSweep=false;autoPickup=false;combatReport?("背包已满，自动拾取已停止") }
                else if let drop=drops.filter({ pair in
                    max(abs(pair.value.cell.x-a.cell.x),abs(pair.value.cell.y-a.cell.y))<=3
                }).min(by:{ max(abs($0.value.cell.x-a.cell.x),abs($0.value.cell.y-a.cell.y)) < max(abs($1.value.cell.x-a.cell.x),abs($1.value.cell.y-a.cell.y)) }) {
                    if drop.value.cell==a.cell { pickupHere();nextPickup=time+1.5 }
                    else { queuePath(to:drop.value.cell,running:false) }
                } else { pickupSweep=false }
            }
            var next:Cell?,running=false,direction=a.direction
            if let d=stickDirection {
                direction=d;let delta=MirTouchInput.directions[d]
                let one=Cell(x:a.cell.x+delta.x,y:a.cell.y+delta.y)
                if map.grid.neighbors(a.cell).contains(one) {
                    next=one
                    let two=Cell(x:one.x+delta.x,y:one.y+delta.y)
                    if stickRunning && map.grid.neighbors(one).contains(two) && !actors.values.contains(where:{!$0.dead && ($0.cell==one || $0.cell==two)}) { next=two;running=true }
                }
            } else if !route.isEmpty {
                let one=route.removeFirst()
                if map.grid.neighbors(a.cell).contains(one) {
                    next=one;direction=MirTouchInput.directions.firstIndex(of:Cell(x:one.x-a.cell.x,y:one.y-a.cell.y)) ?? a.direction
                    if routeRunning,let two=route.first,two.x-one.x==one.x-a.cell.x,two.y-one.y==one.y-a.cell.y,map.grid.neighbors(one).contains(two),!actors.values.contains(where:{!$0.dead && ($0.cell==one || $0.cell==two)}) { next=two;route.removeFirst();running=true }
                } else { route=[] }
            }
            if !attackPending,let n=next,!actors.values.contains(where:{!$0.dead && $0.cell==n}),net.walk(x:n.x+map.originX,y:n.y+map.originY,direction:direction,running:running) {
                a.running=running;a.direction=direction;pending=n;requestedAt=time;pendingDuration=running ? 0.5 : 0.54
                a.walkingUntil=time+pendingDuration;a.node.run(.move(to:point(n),duration:pendingDuration),withKey:"walk")
            }
        }
        for a in actors.values {
            let walk=time<a.walkingUntil
            let active=a.dead || time<a.actionUntil
            let action=active ? a.action : walk ? (a.running ? "run" : "walk") : "stand"
            let library=actorLibraries[a.appearanceKey] ?? (a.monster ? map.monster : (actorLibraries["human-\(a.sex)"] ?? map.hero))
            guard let directions=library[action] ?? (a.dead ? library["die"] : library["stand"]),directions.indices.contains(a.direction) else { continue }
            let frames=directions[a.direction];guard !frames.isEmpty else { continue }
            let phase=active ? min(frames.count-1,max(0,Int((time-a.actionAt)/(action=="butcher" ? 0.3 : 0.1)))) : Int(time/(walk ? 0.09 : 0.2)) % frames.count
            let f=frames[phase]
            if a.lastFile != f.file {
                let tex=texture(f.file)
                if let tex=tex { a.image.texture=tex;a.image.size=tex.size();a.image.position=CGPoint(x:CGFloat(f.offsetX-24),y:CGFloat(16-f.offsetY-f.height));a.lastFile=f.file }
            }
            if !a.monster && !a.npc {
                drawOverlay(a.weapon,key:"weapon-\(a.weaponVariant)",action:action,direction:a.direction,phase:phase)
                drawOverlay(a.hair,key:"hair-\(a.hairVariant)",action:action,direction:a.direction,phase:phase)
                let index=f.index%600
                a.weapon.zPosition=(weaponOrder.indices.contains(a.sex) && weaponOrder[a.sex].indices.contains(index) && weaponOrder[a.sex][index]==0) ? -0.5 : 1
            }
            a.node.zPosition=1000+(-a.node.position.y/32-0.5)*4+2
        }
        if let id=playerID,let a=actors[id] { cameraNode.position=a.node.position }
        let scale=540/max(size.height,1);cameraNode.setScale(scale)
        if time-lastStream>=0.1 {
            lastStream=time;let w=size.width*scale,h=size.height*scale
            streamer.update(view:StreamRect(x:Double(cameraNode.position.x-w/2),y:Double(-cameraNode.position.y-h/2),width:Double(w),height:Double(h)))
        }
        streamer.animate(at:time)
    }
}
