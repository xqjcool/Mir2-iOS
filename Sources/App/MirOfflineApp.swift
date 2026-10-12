import SwiftUI
import SpriteKit

final class OnlineModel:ObservableObject {
    let net=MirConnection()
    let scene:OnlineScene?
    @Published var coordinates=""
    @Published var combat="点击稻草人选中，再点攻击"
    @Published var target=""
    @Published var targetHealth:Double?
    @Published var position=Cell(x:0,y:0)
    let minimap:UIImage?
    let error:String?
    init() {
        do {
            let (map,root)=try SceneData.load()
            scene=OnlineScene(map:map,root:root,net:net);error=nil;minimap=scene?.minimapImage
            scene?.report={ [weak self] in self?.coordinates=$0 }
            scene?.combatReport={ [weak self] in self?.combat=$0 }
            scene?.targetReport={ [weak self] in self?.target=$0 }
            scene?.targetHealthReport={ [weak self] in self?.targetHealth=$0 }
            scene?.positionReport={ [weak self] in self?.position=$0 }
        } catch { scene=nil;minimap=nil;self.error=error.localizedDescription }
    }
}
@main struct MirOnlineApp:App {
    var body:some Scene { WindowGroup { OnlineRoot() } }
}
struct OnlineRoot:View {
    @StateObject private var model=OnlineModel()
    var body:some View { OnlineView(model:model,net:model.net) }
}
struct OnlineView:View {
    @ObservedObject var model:OnlineModel
    @ObservedObject var net:MirConnection
    @Environment(\.scenePhase) private var phase
    @State private var showEquipment=false
    @State private var showMap=false
    @State private var showSkills=false

    init(model: OnlineModel, net: MirConnection) {
        _model = ObservedObject(wrappedValue: model)
        _net = ObservedObject(wrappedValue: net)
    }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if net.online,let scene=model.scene { SpriteView(scene:scene).ignoresSafeArea() }
            VStack {
                HStack {
                    VStack(alignment:.leading) {
                        Text("传奇 · 比奇联网测试").font(.headline)
                        Text(net.status).font(.caption)
                        if let mana=net.mana { Text("MP \(mana)").font(.caption).foregroundColor(.cyan) }
                        Text(model.coordinates).font(.caption.monospacedDigit())
                    }.padding(8).background(.black.opacity(0.75))
                    Spacer()
                    if let url=net.logURL { ShareLink("导出日志",item:url).buttonStyle(.borderedProminent) }
                    if net.online || net.busy { Button("退出登录"){net.disconnect();net.status="已退出，可重新登录"}.buttonStyle(.borderedProminent) }
                }
                if net.online { Text(model.target).font(.headline).foregroundColor(.yellow);if let health=model.targetHealth { ProgressView(value:health).tint(.red).frame(width:220) } }
                Spacer()
                if net.online {
                    HStack(alignment:.bottom) {
                        VirtualJoystick { x,y in model.scene?.joystick(x:x,y:y) }
                        VStack(spacing:6) {
                            Text(model.combat).font(.caption).lineLimit(2).padding(6).background(.black.opacity(0.75))
                            HStack {
                                Button("装备") { model.scene?.stopAutomation();showEquipment=true }
                                Button("地图") { model.scene?.stopAutomation();showMap=true }
                                Button("技能") { model.scene?.stopAutomation();showSkills=true }
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                        }.frame(maxWidth:.infinity)
                        CombatButtons(net:net,scene:model.scene)
                    }
                }
            }.padding().foregroundColor(.white)
            if !net.online { ClassicLobby(net:net).disabled(model.scene==nil) }
            if let error=model.error { Text(error).foregroundColor(.red).padding().background(Color.black) }
            if net.online && !net.npcText.isEmpty {
                VStack(alignment:.leading,spacing:16) {
                    ScrollView { Text(net.npcText).foregroundColor(Color(red:0.88,green:0.77,blue:0.48)).frame(maxWidth:.infinity,alignment:.leading) }
                    Button("关闭") { net.closeNPC() }.buttonStyle(.borderedProminent)
                }.padding(24).frame(maxWidth:460,maxHeight:300).background(Color.black.opacity(0.95)).overlay(Rectangle().stroke(Color.brown,lineWidth:3))
            }
        }.sheet(isPresented:$showEquipment) { EquipmentPanel(net:net).onAppear { model.scene?.stopAutomation() } }
        .sheet(isPresented:$showMap) { NavigationPanel(model:model) }
        .sheet(isPresented:$showSkills) { SkillPanel(net:net,scene:model.scene) }
        .onChange(of:showEquipment) { _ in model.scene?.suspendControls(showEquipment || showMap || showSkills) }
        .onChange(of:showMap) { _ in model.scene?.suspendControls(showEquipment || showMap || showSkills) }
        .onChange(of:showSkills) { _ in model.scene?.suspendControls(showEquipment || showMap || showSkills) }
        .onChange(of:phase) { value in
            if value == .background { net.disconnect();net.status="已进入后台，返回后请重新登录" }
        }.persistentSystemOverlays(.hidden)
    }
}

private struct ClassicLobby:View {
    private static let images=NSCache<NSString,UIImage>()
    @ObservedObject var net:MirConnection
    @AppStorage("mir.online.host") private var host="192.168.1.81"
    @State private var account="probealpha"
    @State private var password=""
    @State private var creating=false
    @State private var newName=""
    @State private var job=0
    @State private var sex=0
    private let jobs=["战士","法师","道士"]
    private let gold=Color(red:0.88,green:0.77,blue:0.48)
    private func asset(_ name:String)->UIImage? {
        if let cached=Self.images.object(forKey:name as NSString) { return cached }
        guard let root=Bundle.main.resourceURL else { return nil }
        guard let image=UIImage(contentsOfFile:root.appendingPathComponent("GameData/classic-ui/\(name).png").path) else { return nil }
        Self.images.totalCostLimit=48*1024*1024
        Self.images.setObject(image,forKey:name as NSString,cost:Int(image.size.width*image.size.height)*4)
        return image
    }
    private func action(_ title:String,_ run:@escaping ()->Void)->some View {
        Button(action:run) { Text(title).font(.system(size:20,weight:.bold,design:.serif)).foregroundColor(gold).frame(minWidth:110,minHeight:42).background(Color.black.opacity(0.7)).overlay(Rectangle().stroke(gold.opacity(0.5))) }.buttonStyle(.plain).disabled(net.busy)
    }
    var body:some View {
        GeometryReader { geometry in
            let scale=min(geometry.size.width/800,geometry.size.height/600)
            ZStack {
                Color.black
                ZStack {
                    if let image=asset(net.screen=="characters" ? "characters" : "login") {
                        Image(uiImage:image).resizable().frame(width:800,height:600)
                    }
                    if net.screen=="login" {
                        VStack(spacing:16) {
                            Text("热 血 传 奇").font(.system(size:38,weight:.bold,design:.serif)).foregroundColor(gold)
                            Text("经典 1.76").foregroundColor(gold)
                            HStack { Text("账号");TextField("账号",text:$account) }
                            HStack { Text("密码");SecureField("密码",text:$password) }
                            DisclosureGroup("服务器地址") { TextField("服务器地址",text:$host) }
                            action("登 录") { net.login(host:host.trimmingCharacters(in:.whitespacesAndNewlines),account:account,password:password);password="" }
                        }.textFieldStyle(.roundedBorder).padding(24).frame(width:350).background(Color.black.opacity(0.84)).overlay(Rectangle().stroke(gold.opacity(0.7))).position(x:400,y:320)
                    } else if net.screen=="servers" {
                        VStack(spacing:24) {
                            Text("选择服务器").font(.title).foregroundColor(gold)
                            action("比奇 · 经典服") { net.chooseServer() }
                            action("返回登录") { net.disconnect() }
                        }.padding(32).background(Color.black.opacity(0.85)).position(x:400,y:320)
                    } else if net.screen=="characters" {
                        ForEach(0..<2,id:\.self) { slot in
                            if net.characters.indices.contains(slot) {
                                let chr=net.characters[slot]
                                let center=CGFloat(slot==0 ? 230 : 570)
                                Button { net.selectedName=chr.name } label: {
                                    TimelineView(.animation(minimumInterval:0.3,paused:net.selectedName != chr.name)) { context in
                                        let phase=Int(context.date.timeIntervalSinceReferenceDate/0.3)%16
                                        let filename=net.selectedName==chr.name ? "portrait-\(chr.job)-\(chr.sex)-\(phase)" : "stone-\(chr.job)-\(chr.sex)"
                                        if let image=asset(filename) {
                                            Image(uiImage:image).resizable().scaledToFit()
                                        } else { Text(jobs.indices.contains(chr.job) ? jobs[chr.job] : "人物") }
                                    }.frame(width:300,height:360)
                                }.buttonStyle(.plain).position(x:center,y:245)
                                VStack(alignment:.leading,spacing:10) {
                                    Text(chr.name);Text("\(chr.level)");Text(jobs.indices.contains(chr.job) ? jobs[chr.job] : "未知")
                                }.font(.system(size:16)).foregroundColor(gold).frame(width:112,alignment:.leading).position(x:CGFloat(slot==0 ? 165 : 705),y:529)
                                action("选择") { net.selectedName=chr.name }.position(x:CGFloat(slot==0 ? 170 : 728),y:469)
                            } else {
                                Text("空位").font(.title).foregroundColor(gold.opacity(0.7)).position(x:CGFloat(slot==0 ? 230 : 570),y:240)
                            }
                        }
                        VStack(spacing:6) {
                            action("开始游戏") { net.enterSelectedCharacter() }.disabled(net.selectedName.isEmpty)
                            action("创建人物") { creating=true }.disabled(net.characters.count>=2)
                            action("返回登录") { net.disconnect() }
                        }.position(x:403,y:519)
                    }
                    if creating && net.screen=="characters" {
                        Color.black.opacity(0.75)
                        VStack(spacing:18) {
                            Text("创建人物").font(.title).foregroundColor(gold)
                            TextField("人物名字",text:$newName).textFieldStyle(.roundedBorder)
                            Picker("职业",selection:$job) { ForEach(0..<3,id:\.self) { Text(jobs[$0]).tag($0) } }.pickerStyle(.segmented)
                            Picker("性别",selection:$sex) { Text("男").tag(0);Text("女").tag(1) }.pickerStyle(.segmented)
                            HStack {
                                action("创建") { net.createCharacter(name:newName,job:job,sex:sex);if net.busy { creating=false } }
                                action("取消") { creating=false }
                            }
                        }.padding(28).frame(width:440).background(Color.black).overlay(Rectangle().stroke(gold)).position(x:400,y:300)
                    }
                    VStack { Text(net.status).foregroundColor(gold);if net.busy { ProgressView().tint(gold) } }
                        .padding(8).background(Color.black.opacity(0.85)).position(x:400,y:25)
                }.foregroundColor(.white).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .frame(width:800,height:600).scaleEffect(scale).frame(width:geometry.size.width,height:geometry.size.height)
            }
        }.ignoresSafeArea()
    }
}


private struct VirtualJoystick:View {
    let changed:(Double,Double)->Void
    @State private var offset=CGSize.zero
    var body:some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.45)).overlay(Circle().stroke(Color.white.opacity(0.4),lineWidth:2))
            Text("轻推走 · 满推跑").font(.caption2).offset(y:59)
            Circle().fill(Color.white.opacity(0.5)).frame(width:52,height:52).offset(offset)
        }.frame(width:148,height:148).contentShape(Circle())
        .gesture(DragGesture(minimumDistance:0).onChanged { value in
            let dx=Double(value.location.x-74),dy=Double(value.location.y-74),distance=hypot(dx,dy)
            let factor=distance>48 ? 48/distance : 1
            offset=CGSize(width:dx*factor,height:dy*factor);changed(dx*factor/48,dy*factor/48)
        }.onEnded { _ in offset = .zero;changed(0,0) })
        .onDisappear { changed(0,0) }
        .accessibilityLabel("移动摇杆，轻推行走，满推奔跑")
    }
}
private struct CombatButtons:View {
    @ObservedObject var net:MirConnection
    let scene:OnlineScene?
    private let positions=[CGPoint(x:48,y:52),CGPoint(x:128,y:32),CGPoint(x:205,y:61),CGPoint(x:43,y:135)]
    var body:some View {
        ZStack {
            Button { scene?.toggleAttack() } label: { Text("攻击").font(.title3.bold()).frame(width:86,height:86).background(Color.red.opacity(0.85)).clipShape(Circle()) }.position(x:137,y:127)
            ForEach(Array(net.quickSkills.enumerated()),id:\.element.id) { index,skill in
                TimelineView(.periodic(from:.now,by:0.2)) { _ in
                    let remaining=max(0,(net.skillReady[skill.id] ?? 0)-ProcessInfo.processInfo.systemUptime)
                    Button { scene?.castSkill(skill) } label: {
                        VStack(spacing:2) {
                            Text(net.skillName(skill)).font(.caption.bold())
                            if remaining>0 { Text(String(format:"%.1fs",remaining)).font(.caption2.monospacedDigit()) }
                            else if net.automaticSkills.contains(skill.id) { Text("自动").font(.caption2).foregroundColor(.yellow) }
                            else if (skill.id==12 && net.warrior.thrust) || (skill.id==25 && net.warrior.halfMoon) { Text("已开启").font(.caption2).foregroundColor(.yellow) }
                            else if skill.id==26 && net.warrior.fireUntil>ProcessInfo.processInfo.systemUptime { Text("已蓄力").font(.caption2).foregroundColor(.orange) }
                        }.frame(width:64,height:56).background(Color.brown.opacity(remaining>0 ? 0.5 : 0.9)).clipShape(Capsule())
                    }.disabled(remaining>0)
                    .highPriorityGesture(LongPressGesture(minimumDuration:0.65).onEnded { _ in scene?.toggleAutoSkill(skill.id) })
                }
                    .position(positions[index])
            }
            Button("拾取周围") { scene?.collectNearby() }.frame(minWidth:96,minHeight:44).background(Color.blue.opacity(0.8)).clipShape(Capsule()).position(x:130,y:198)
        }.frame(width:240,height:225).foregroundColor(.white).buttonStyle(.plain)
    }
}
private struct EquipmentPanel:View {
    @ObservedObject var net:MirConnection
    @Environment(\.dismiss) private var dismiss
    @State private var selected:Int32?
    private func icon(_ item:MirEquipment.Item)->some View {
        Group {
            if let path=Bundle.main.resourceURL?.appendingPathComponent("GameData/item-icons/\(item.looks).png").path,let image=UIImage(contentsOfFile:path) { Image(uiImage:image).resizable().scaledToFit() }
            else { Image(systemName:"shippingbox").resizable().scaledToFit().padding(8) }
        }.frame(width:38,height:38)
    }
    var body:some View {
        NavigationStack {
            VStack(alignment:.leading,spacing:8) {
                Text(net.abilityText).font(.caption)
                Text("金币 \(net.goldBalance) · 背包 \(net.inventory.bag.count)/46").font(.headline)
                Text(net.equipmentMessage).font(.caption).foregroundColor(.secondary)
                HStack(alignment:.top) {
                    ScrollView {
                        ForEach(0..<MirEquipment.slotNames.count,id:\.self) { slot in
                            Button {
                                if let item=net.inventory.equipped[slot] { net.changeEquipment(item,slot:slot,takingOff:true) }
                            } label: {
                                HStack {
                                    Text(MirEquipment.slotNames[slot]).frame(width:55,alignment:.leading)
                                    if let item=net.inventory.equipped[slot] { icon(item);Text(net.itemName(item));Spacer();Text("卸下") }
                                    else { Text("空").foregroundColor(.secondary);Spacer() }
                                }.frame(minHeight:44).padding(.horizontal,6)
                            }.disabled(net.inventory.equipped[slot]==nil)
                        }
                    }.frame(maxWidth:330)
                    VStack {
                        ScrollView {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:90))]) {
                                ForEach(net.inventory.bag.values.sorted{$0.id<$1.id}) { item in
                                    Button { selected=item.id } label: {
                                        VStack { icon(item);Text(net.itemName(item)).font(.caption).lineLimit(1) }.frame(maxWidth:.infinity,minHeight:70).background(selected==item.id ? Color.brown.opacity(0.4) : Color.gray.opacity(0.12)).cornerRadius(6)
                                    }
                                }
                            }
                        }
                        if let id=selected,let item=net.inventory.bag[id] {
                            VStack(alignment:.leading,spacing:4) {
                                Text("\(net.itemName(item))  耐久 \(item.durability/1000)/\(item.maxDurability/1000)").bold()
                                Text("攻击 \(MirEquipment.range(item.dc))  魔法 \(MirEquipment.range(item.mc))  道术 \(MirEquipment.range(item.sc))").font(.caption)
                                Text("防御 \(MirEquipment.range(item.ac))  魔防 \(MirEquipment.range(item.mac))  需求值 \(item.needLevel)（以服务端判定为准）").font(.caption)
                                HStack {
                                    ForEach(item.slots,id:\.self) { slot in Button("穿戴·"+MirEquipment.slotNames[slot]) { net.changeEquipment(item,slot:slot,takingOff:false) }.frame(minHeight:44).buttonStyle(.borderedProminent) }
                                    if item.slots.isEmpty { Text("此物品不能穿戴").foregroundColor(.secondary) }
                                }
                            }
                        }
                    }
                }.disabled(net.inventory.pending != nil || net.actionLocked)
            }.padding().navigationTitle("人物装备与背包").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement:.confirmationAction) { Button("关闭") { dismiss() }.frame(minHeight:44) } }
        }
    }
}
private struct NavigationPanel:View {
    @ObservedObject var model:OnlineModel
    @Environment(\.dismiss) private var dismiss
    var body:some View {
        NavigationStack {
            VStack {
                Text("点击地图目的地自动跑图；推摇杆可取消")
                if let image=model.minimap,let scene=model.scene {
                    GeometryReader { geo in
                        ZStack(alignment:.topLeading) {
                            Image(uiImage:image).resizable().interpolation(.none)
                            Circle().fill(Color.yellow).frame(width:9,height:9).position(x:CGFloat(model.position.x)/CGFloat(scene.mapWidth)*geo.size.width,y:CGFloat(model.position.y)/CGFloat(scene.mapHeight)*geo.size.height)
                        }.contentShape(Rectangle()).gesture(DragGesture(minimumDistance:0).onEnded { value in
                            let x=min(scene.mapWidth-1,max(0,Int(value.location.x/geo.size.width*CGFloat(scene.mapWidth))))
                            let y=min(scene.mapHeight-1,max(0,Int(value.location.y/geo.size.height*CGFloat(scene.mapHeight))))
                            scene.navigate(to:Cell(x:x,y:y));dismiss()
                        })
                    }.aspectRatio(1,contentMode:.fit)
                }
            }.padding().navigationTitle("比奇通行地图").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44) }
        }
    }
}
private struct SkillPanel:View {
    @ObservedObject var net:MirConnection
    let scene:OnlineScene?
    @Environment(\.dismiss) private var dismiss
    @State private var autoGold=true
    var body:some View {
        NavigationStack {
            List {
                Toggle("自动拾取附近金币",isOn:$autoGold).onChange(of:autoGold) { scene?.autoGold=$0 }
                if net.skills.isEmpty { Text("当前角色尚未学习技能；学习后会显示服务器下发的技能。") }
                ForEach(net.skills) { skill in
                    HStack {
                        Text("\(net.skillName(skill)) · \(skill.level)级")
                        Spacer()
                        if skill.castable {
                            Button("释放") { scene?.castSkill(skill);dismiss() }.frame(minHeight:44)
                            if !MirSkills.warrior(skill.id) { Button(net.automaticSkills.contains(skill.id) ? "关闭自动" : "自动") { scene?.toggleAutoSkill(skill.id) }.frame(minHeight:44) }
                            Menu("快捷键") {
                                ForEach(0..<net.quickSkills.count,id:\.self) { slot in Button("位置 \(slot+1)") { net.setQuickSkill(skill.id,slot:slot) } }
                            }.frame(minHeight:44)
                        } else { Text("被动技能或尚未接入的技能").font(.caption) }
                    }.buttonStyle(.bordered)
                }
                Text("技能由服务端判断等级、蓝量、冷却和材料。火墙等范围技能先点技能，再点地图；自动释放时以当前怪物所在格为目标。刺杀／半月点击切换，烈火点击蓄力；其余技能长按快捷键可切换自动。")
            }.onAppear { autoGold=scene?.autoGold ?? true }.navigationTitle("技能与拾取").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44) }
        }
    }
}
