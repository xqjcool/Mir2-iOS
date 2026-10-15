import SwiftUI
import SpriteKit

final class OnlineModel:ObservableObject {
    let net=MirConnection()
    let scene:OnlineScene?
    @Published var playerTarget:OnlineScene.PlayerTarget?
    @Published var coordinates=""
    @Published var combat="点击攻击：自动追打最近怪物；再次点击停止"
    @Published var target=""
    @Published var targetHealth:Double?
    @Published var position=Cell(x:0,y:0)
    @Published var minimap:UIImage?
    @Published var mapName="比奇省"
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
            scene?.playerReport={ [weak self] in self?.playerTarget=$0 }
            scene?.mapReport={ [weak self] name,image in self?.mapName=name;self?.minimap=image }
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
private enum HUDPanel:String,Identifiable {
    case bag,character,skills,map,settings,chat,nearby
    var id:String { rawValue }
}
private enum ClassicTheme {
    static let gold=Color(red:0.61,green:0.45,blue:0.26)
    static let text=Color(red:0.91,green:0.83,blue:0.67)
    static let panel=Color(red:0.13,green:0.106,blue:0.09)
}
struct OnlineView:View {
    @ObservedObject var model:OnlineModel
    @ObservedObject var net:MirConnection
    @Environment(\.scenePhase) private var phase
    @State private var panel:HUDPanel?
    @AppStorage("hud.menuExpanded") private var menuExpanded=false
    @AppStorage("hud.chatMinimized") private var chatMinimized=false
    @AppStorage("hud.classic") private var classic=true
    @AppStorage("hud.opacity") private var opacity=0.9
    @AppStorage("hud.scale") private var scale=1.0
    @AppStorage("hud.leftInset") private var leftInset=0.0
    @AppStorage("hud.rightInset") private var rightInset=0.0
    @AppStorage("hud.bottomInset") private var bottomInset=0.0
    init(model:OnlineModel,net:MirConnection) {
        _model=ObservedObject(wrappedValue:model);_net=ObservedObject(wrappedValue:net)
    }
    private func controlScale(_ size:CGSize)->CGFloat {
        let inset=min(bottomInset,max(0,Double(size.height)-350))
        return CGFloat(min(1.1,max(0.9,min(scale,min((Double(size.width)-20)/406,(Double(size.height)-92-inset)/254)))))
    }
    private func open(_ value:HUDPanel) { menuExpanded=false;model.scene?.suspendControls(true);panel=value }
    private func shortcut(_ title:String,_ icon:String,_ value:HUDPanel)->some View {
        Button { open(value) } label: {
            VStack(spacing:2) { Image(systemName:icon);Text(title).font(.caption2) }.frame(width:44,height:44)
        }.background(ClassicTheme.panel).overlay(Circle().stroke(ClassicTheme.gold)).clipShape(Circle())
    }
    private var statusCard:some View {
        HStack(spacing:4) {
            Button { open(.character) } label: {
                HStack(spacing:6) {
                    Image(systemName:"person.crop.circle").font(.system(size:30)).frame(width:44,height:44)
                    VStack(alignment:.leading,spacing:3) {
                        Text(net.selectedName+"  Lv.\(net.vitals?.level.description ?? "—")").font(.caption.bold()).lineLimit(1)
                        meter("HP",net.vitals?.hp,net.vitals?.maxHP,.red)
                        meter("MP",net.vitals?.mp,net.vitals?.maxMP,.blue)
                        ProgressView(value:Double(min(max(0,net.vitals?.experience ?? 0),max(1,net.vitals?.maxExperience ?? 1))),total:Double(max(1,net.vitals?.maxExperience ?? 1)))
                            .tint(ClassicTheme.gold).frame(height:3).accessibilityLabel("经验 \(net.vitals?.experience ?? 0)/\(net.vitals?.maxExperience ?? 0)")
                    }
                }.frame(width:178)
            }.accessibilityLabel("角色属性")
            Button { net.cycleAttackMode() } label: {
                VStack(spacing:2) { Image(systemName:"shield.lefthalf.filled");Text(net.attackModeName).font(.caption2);Text("PK模式").font(.system(size:9)) }.frame(width:48,height:56)
            }.disabled(net.attackMode==nil || net.tradeBusy || net.dealOpen).accessibilityLabel("当前\(net.attackModeName)攻击模式，点击切换")
        }.padding(6).background(ClassicTheme.panel.opacity(opacity))
            .overlay(RoundedRectangle(cornerRadius:4).stroke(ClassicTheme.gold)).buttonStyle(.plain)
    }
    private var quickMenu:some View {
        VStack(alignment:.trailing,spacing:4) {
            Button { withAnimation(.easeInOut(duration:0.15)) { menuExpanded.toggle() } } label: {
                HStack(spacing:4) { Image(systemName:menuExpanded ? "chevron.up" : "square.grid.2x2");Text(menuExpanded ? "收起" : "菜单").font(.caption) }.frame(width:72,height:44)
            }.background(ClassicTheme.panel.opacity(opacity)).overlay(Capsule().stroke(ClassicTheme.gold)).clipShape(Capsule())
            if menuExpanded {
                VStack(spacing:4) {
                    HStack(spacing:4) { shortcut("背包","bag",.bag);shortcut("角色","person",.character);shortcut("技能","sparkles",.skills) }
                    HStack(spacing:4) { shortcut("附近","person.2",.nearby);shortcut("聊天","bubble.left",.chat);shortcut("设置","gearshape",.settings) }
                }.padding(4).background(ClassicTheme.panel.opacity(opacity))
            }
        }.buttonStyle(.plain)
    }
    private func meter(_ title:String,_ value:Int?,_ maximum:Int?,_ color:Color)->some View {
        ZStack {
            ProgressView(value:Double(value ?? 0),total:Double(max(1,maximum ?? 1))).tint(color)
            Text("\(title) \(value?.description ?? "—")/\(maximum?.description ?? "—")").font(.system(size:10)).foregroundColor(.white)
        }.frame(height:14)
    }
    private var miniMap:some View {
        Button { open(.map) } label: {
            VStack(spacing:2) {
                Text(model.mapName).font(.caption.bold())
                if let image=model.minimap,let scene=model.scene {
                    ZStack(alignment:.topLeading) {
                        Image(uiImage:image).resizable().interpolation(.none)
                        Circle().fill(Color.yellow).frame(width:5,height:5)
                            .position(x:CGFloat(model.position.x)/CGFloat(scene.mapWidth)*88,y:CGFloat(model.position.y)/CGFloat(scene.mapHeight)*34)
                    }.frame(width:88,height:34).clipped()
                }
                Text("\(model.position.x),\(model.position.y)").font(.caption2.monospacedDigit())
            }.padding(4).background(ClassicTheme.panel.opacity(opacity)).overlay(Rectangle().stroke(ClassicTheme.gold))
        }.buttonStyle(.plain).accessibilityLabel("打开地图")
    }
    var body:some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if net.online,let scene=model.scene { SpriteView(scene:scene).ignoresSafeArea() }
            if net.online {
                GeometryReader { geo in
                    VStack(spacing:0) {
                        HStack(alignment:.top,spacing:6) {
                            statusCard
                            Spacer(minLength:0)
                            Color.clear.frame(width:72,height:44).overlay(alignment:.topTrailing) { quickMenu }
                            miniMap
                        }.zIndex(10)
                        Spacer(minLength:0)
                        HStack(alignment:.bottom,spacing:4) {
                            VirtualJoystick { x,y in model.scene?.input(.move(x,y)) }
                                .scaleEffect(controlScale(geo.size),anchor:.bottomLeading)
                                .frame(width:148*controlScale(geo.size),height:148*controlScale(geo.size))
                                .padding(.leading,CGFloat(min(leftInset,max(0,(Double(geo.size.width)-20-406*Double(controlScale(geo.size)))/2))))
                                .opacity(opacity)
                            Spacer(minLength:0)
                            CombatButtons(net:net,scene:model.scene)
                                .scaleEffect(controlScale(geo.size),anchor:.bottomTrailing)
                                .frame(width:258*controlScale(geo.size),height:254*controlScale(geo.size))
                                .padding(.trailing,CGFloat(min(rightInset,max(0,(Double(geo.size.width)-20-406*Double(controlScale(geo.size)))/2))))
                                .opacity(opacity)
                        }.padding(.bottom,CGFloat(min(bottomInset,max(0,Double(geo.size.height)-350))))
                    }.padding(8)
                    VStack(spacing:3) {
                        if !model.target.isEmpty {
                            Text(model.target).font(.caption).foregroundColor(.yellow)
                            if let health=model.targetHealth { ProgressView(value:health).tint(.red).frame(width:160) }
                        }
                    }.frame(maxWidth:.infinity).padding(.top,geo.size.height<360 ? 70 : 78).allowsHitTesting(false)
                    VStack(alignment:.leading,spacing:0) {
                        HStack(spacing:0) {
                            Button { open(.chat) } label: { Text(net.chatChannel+"聊天").font(.caption).frame(minWidth:80,minHeight:44) }
                            Button { chatMinimized.toggle() } label: { Image(systemName:chatMinimized ? "plus" : "minus").frame(width:44,height:44) }.accessibilityLabel(chatMinimized ? "恢复聊天窗口" : "最小化聊天窗口")
                        }
                        if !chatMinimized {
                            Button { open(.chat) } label: {
                                VStack(alignment:.leading,spacing:2) {
                                    if net.displayedChat().isEmpty { Text("暂无"+net.chatChannel+"消息 · 点击切换频道") }
                                    ForEach(Array(net.displayedChat().suffix(2).enumerated()),id:\.offset) { _,text in Text(text).lineLimit(1) }
                                }.font(.caption2).frame(width:180,height:36,alignment:.leading)
                            }.frame(minHeight:44)
                        }
                    }.padding(.horizontal,4).background(ClassicTheme.panel.opacity(0.8)).buttonStyle(.plain)
                        .padding(.leading,8).padding(.top,76)
                }.foregroundColor(ClassicTheme.text)
            } else {
                ClassicLobby(net:net).disabled(model.scene==nil)
                VStack { HStack { Spacer();if let url=net.logURL { ShareLink("导出日志",item:url) } };Spacer() }.padding()
            }
            if let error=model.error { Text(error).foregroundColor(.red).padding().background(Color.black) }
            if net.online && net.npcOpen {
                Color.black.opacity(0.35).ignoresSafeArea().onTapGesture {}
                NPCShopPanel(net:net)
            }
            if net.online && net.dealOpen {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture {}
                PeerTradePanel(net:net)
            } else if net.online,let target=model.playerTarget {
                Color.black.opacity(0.5).ignoresSafeArea().onTapGesture {}
                PeerPlayerPanel(net:net,scene:model.scene,target:target) { model.playerTarget=nil }
            }
        }
        .sheet(item:$panel,onDismiss:{ model.scene?.suspendControls(net.dealOpen || model.playerTarget != nil) }) { selected in
            Group {
                switch selected {
                case .bag:EquipmentPanel(net:net,characterOnly:false)
                case .character:EquipmentPanel(net:net,characterOnly:true)
                case .skills:SkillPanel(net:net,scene:model.scene)
                case .map:NavigationPanel(model:model)
                case .settings:HUDSettings(net:net)
                case .chat:ChatPanel(net:net)
                case .nearby:NearbyPanel(scene:model.scene) { target in
                    panel=nil;model.scene?.chooseNearby(target)
                }
                }
            }.onAppear { model.scene?.suspendControls(true) }
        }
        .onAppear { model.scene?.classicMode=classic }
        .onChange(of:classic) { value in
            model.scene?.input(.stop);model.scene?.classicMode=value
            if value { net.automaticSkills=[] }
        }
        .onChange(of:net.npcOpen) { open in if open { model.scene?.input(.stop) } }
        .onChange(of:net.online) { online in if !online { panel=nil;model.playerTarget=nil } }
        .onChange(of:model.playerTarget) { target in model.scene?.suspendControls(target != nil || panel != nil || net.dealOpen) }
        .onChange(of:net.dealOpen) { open in if open { panel=nil;model.playerTarget=nil };model.scene?.suspendControls(open || panel != nil || model.playerTarget != nil) }
        .onChange(of:phase) { value in
            if value != .active { model.scene?.input(.stop) }
            if value == .background { net.log("app entered background; closing connection intentionally");net.disconnect();net.status="已进入后台，返回后请重新登录" }
        }.persistentSystemOverlays(.hidden)
    }
}
private struct HUDSettings:View {
    @ObservedObject var net:MirConnection
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hud.classic") private var classic=true
    @AppStorage("hud.floating") private var floating=false
    @AppStorage("hud.opacity") private var opacity=0.9
    @AppStorage("hud.scale") private var scale=1.0
    @AppStorage("hud.leftInset") private var leftInset=0.0
    @AppStorage("hud.rightInset") private var rightInset=0.0
    @AppStorage("hud.bottomInset") private var bottomInset=0.0
    var body:some View {
        NavigationStack { Form {
            Toggle("经典模式（原版规则与地图操作）",isOn:$classic)
            Text("触屏增强模式可在技能面板主动开启辅助功能；服务端战斗规则保持不变。").font(.caption)
            Section("触屏布局 · 自动限制在安全区域") {
                Toggle("浮动摇杆（在左下操作区内）",isOn:$floating)
                Text("操作区缩放");Slider(value:$scale,in:0.9...1.1)
                Text("HUD 透明度");Slider(value:$opacity,in:0.45...1)
                Text("摇杆向内移动");Slider(value:$leftInset,in:0...60)
                Text("技能区向内移动");Slider(value:$rightInset,in:0...60)
                Text("操作区向上移动");Slider(value:$bottomInset,in:0...40)
                Button("恢复默认布局") { opacity=0.9;scale=1;leftInset=0;rightInset=0;bottomInset=0 }
            }
            Section("诊断") {
                Text(net.status)
                if let url=net.logURL { ShareLink("导出联网日志",item:url) }
                Button("退出登录",role:.destructive) { net.disconnect();net.status="已退出，可重新登录";dismiss() }
            }
        }.navigationTitle("设置").toolbar { Button("关闭") { dismiss() } } }
    }
}
private struct ChatPanel:View {
    @ObservedObject var net:MirConnection
    @Environment(\.dismiss) private var dismiss
    @State private var draft=""
    var body:some View {
        NavigationStack {
            VStack {
                Picker("频道",selection:$net.chatChannel) { ForEach(["当前","行会","系统","综合"],id:\.self) { Text($0).tag($0) } }.pickerStyle(.segmented).padding(.horizontal)
                List(Array(net.displayedChat().enumerated()),id:\.offset) { _,message in Text(message) }
                Text(net.chatChannel=="行会" && net.guildName.isEmpty ? "尚未加入行会，可切换普通聊天" : net.chatFeedback).font(.caption)
                HStack { TextField(net.chatChannel=="行会" ? "行会聊天" : "当前聊天",text:$draft).textFieldStyle(.roundedBorder).onSubmit { send() };Button("发送") { send() }.frame(minWidth:44,minHeight:44) }.padding().disabled(net.chatChannel=="系统")
                if net.chatChannel=="系统" { Text("系统频道仅供查看").font(.caption) }
            }.navigationTitle("聊天与系统消息").toolbar { Button("关闭") { dismiss() } }
        }
    }
    private func send() { guard net.chatChannel != "系统" else { return };if net.sendChat(draft,guild:net.chatChannel=="行会") { draft="" } }
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
    @AppStorage("hud.floating") private var floating=false
    @GestureState private var tracking=false
    @State private var offset=CGSize.zero
    @State private var origin=CGPoint(x:74,y:74)
    var body:some View {
        ZStack {
            Circle().fill(ClassicTheme.panel.opacity(0.6)).overlay(Circle().stroke(ClassicTheme.gold,lineWidth:2))
                .frame(width:floating ? 104:148,height:floating ? 104:148).offset(x:origin.x-74,y:origin.y-74)
            Text("轻推走 · 满推跑").font(.caption2).offset(y:59)
            Circle().fill(ClassicTheme.gold.opacity(0.8)).frame(width:52,height:52).offset(x:origin.x-74+offset.width,y:origin.y-74+offset.height)
        }.frame(width:148,height:148).contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:0).updating($tracking) { _,state,_ in state=true }.onChanged { value in
            origin=floating ? CGPoint(x:min(96,max(52,value.startLocation.x)),y:min(96,max(52,value.startLocation.y))) : CGPoint(x:74,y:74)
            let dx=Double(value.location.x-origin.x),dy=Double(value.location.y-origin.y),distance=hypot(dx,dy)
            let factor=distance>48 ? 48/distance : 1
            offset=CGSize(width:dx*factor,height:dy*factor);changed(dx*factor/48,dy*factor/48)
        }.onEnded { _ in reset() })
        .onChange(of:tracking) { active in if !active { reset() } }
        .onDisappear { reset() }
        .accessibilityLabel("移动摇杆，轻推行走，满推奔跑")
    }
    private func reset() { offset = .zero;origin=CGPoint(x:74,y:74);changed(0,0) }
}
private struct CombatButtons:View {
    @ObservedObject var net:MirConnection
    let scene:OnlineScene?
    @State private var bindingSlot=0
    @State private var chooseSkill=false
    @State private var choosePotion=false
    @State private var chooseScroll=false
    @AppStorage("hud.randomScroll") private var scrollName=""
    private var scrolls:[MirEquipment.Item] { net.inventory.bag.values.filter { [0,1,2,3,31].contains($0.mode) && net.itemName($0).contains("随机") }.sorted { $0.id<$1.id } }
    private var scrollCount:Int { guard let item=scroll else { return 0 };return scrolls.filter { net.itemName($0)==net.itemName(item) }.count }
    private var scroll:MirEquipment.Item? { scrollName.isEmpty ? scrolls.first : scrolls.first { net.itemName($0)==scrollName } }
    @GestureState private var aiming=false
    @AppStorage("hud.potion") private var potionName=""
    private var potions:[MirEquipment.Item] { net.inventory.bag.values.filter { (0...3).contains($0.mode) && !net.itemName($0).contains("随机") }.sorted{$0.id<$1.id} }
    private var potion:MirEquipment.Item? { potions.first { net.itemName($0)==potionName } ?? (potionName.isEmpty ? potions.first : nil) }
    private var potionCount:Int { guard let item=potion else { return 0 };return potions.filter{net.itemName($0)==net.itemName(item)}.count }
    private func skillPosition(_ index:Int)->CGPoint {
        let angle=Double(180+index*30) * .pi / 180
        return CGPoint(x:206+122*cos(angle),y:158+122*sin(angle))
    }
    var body:some View {
        ZStack {
            HoldAttackButton(scene:scene).position(x:206,y:158)
            ForEach(0..<4,id:\.self) { index in
                if let skill=net.quickSkillSlots[index] {
                    TimelineView(.periodic(from:.now,by:0.2)) { _ in
                        let remaining=max(0,(net.skillReady[skill.id] ?? 0)-ProcessInfo.processInfo.systemUptime)
                        VStack(spacing:2) {
                            Text(net.skillName(skill)).font(.caption.bold()).lineLimit(2)
                            if remaining>0 { Text(String(format:"%.1fs",remaining)).font(.caption2.monospacedDigit()) }
                        }.frame(width:56,height:56).background(ClassicTheme.panel.opacity(remaining>0 ? 0.6:1))
                            .clipShape(Circle()).overlay(Circle().stroke(ClassicTheme.gold,lineWidth:2))
                            .contentShape(Rectangle())
                            .gesture(LongPressGesture(minimumDuration:0.5).onEnded { _ in bindingSlot=index;scene?.suspendControls(true);chooseSkill=true }
                                .exclusively(before:TapGesture().onEnded { scene?.input(.skill(skill)) }))
                            .simultaneousGesture(DragGesture(minimumDistance:14).updating($aiming) { _,state,_ in state=true }
                                .onChanged { value in scene?.aimSkill(skill,dx:Double(value.translation.width),dy:Double(value.translation.height)) }
                                .onEnded { value in scene?.aimSkill(skill,dx:Double(value.translation.width),dy:Double(value.translation.height),release:true) })
                            .accessibilityLabel(net.skillName(skill)+"，长按替换")
                            .accessibilityAddTraits(.isButton)
                    }.position(skillPosition(index))
                } else {
                    Button { bindingSlot=index;scene?.suspendControls(true);chooseSkill=true } label: { Text("技能\(index+1)").font(.caption2).frame(width:56,height:56) }
                        .background(ClassicTheme.panel).clipShape(Circle()).overlay(Circle().stroke(ClassicTheme.gold)).position(skillPosition(index))
                }
            }
            VStack(spacing:0) {
                if let item=potion { ClassicAsset(path:"item-icons/\(item.looks)").frame(width:30,height:30) }
                Text(potion == nil ? "药水" : "×\(potionCount)").font(.caption2)
            }.frame(width:50,height:50).background(ClassicTheme.panel).clipShape(Circle()).overlay(Circle().stroke(ClassicTheme.gold))
                .opacity(potion == nil || net.usePending != nil ? 0.5:1).contentShape(Rectangle())
                .gesture(LongPressGesture(minimumDuration:0.5).onEnded { _ in scene?.suspendControls(true);choosePotion=true }
                    .exclusively(before:TapGesture().onEnded { if let item=potion { net.useItem(item) } else { scene?.suspendControls(true);choosePotion=true } }))
                .position(x:137,y:139).accessibilityLabel("药水，长按更换")
            VStack(spacing:0) {
                if let item=scroll { ClassicAsset(path:"item-icons/\(item.looks)").frame(width:28,height:28) }
                Text(scroll == nil ? "随机卷" : "×\(scrollCount)").font(.caption2)
            }.frame(width:50,height:50).background(ClassicTheme.panel).clipShape(Circle()).overlay(Circle().stroke(ClassicTheme.gold))
                .opacity(scroll == nil || net.usePending != nil ? 0.5 : 1).contentShape(Circle())
                .gesture(LongPressGesture(minimumDuration:0.5).onEnded { _ in scene?.suspendControls(true);chooseScroll=true }
                    .exclusively(before:TapGesture().onEnded { if let item=scroll { net.useItem(item) } else { scene?.suspendControls(true);chooseScroll=true } }))
                .position(x:190,y:90).accessibilityLabel("随机传送卷，长按绑定")
            HStack {
                Button("割肉") { scene?.butcherNearby() }.frame(minWidth:70,minHeight:50)
                Button("拾取") { scene?.input(.pickup) }.frame(minWidth:70,minHeight:50)
            }.background(ClassicTheme.panel).overlay(Capsule().stroke(ClassicTheme.gold)).clipShape(Capsule()).position(x:132,y:228)
        }.frame(width:258,height:254).foregroundColor(ClassicTheme.text).buttonStyle(.plain)
        .confirmationDialog("替换快捷技能",isPresented:$chooseSkill,titleVisibility:.visible) {
            ForEach(net.skills.filter(\.castable)) { skill in Button(net.skillName(skill)) { net.setQuickSkill(skill.id,slot:bindingSlot) } }
            Button("取消",role:.cancel) {}
        }
        .confirmationDialog("选择快捷药水",isPresented:$choosePotion,titleVisibility:.visible) {
            ForEach(Array(Set(potions.map{net.itemName($0)})).sorted(),id:\.self) { name in Button(name) { potionName=name } }
            Button("取消",role:.cancel) {}
        }
        .confirmationDialog("绑定随机传送卷",isPresented:$chooseScroll,titleVisibility:.visible) {
            ForEach(Array(Set(scrolls.map { net.itemName($0) })).sorted(),id:\.self) { name in Button(name) { scrollName=name } }
            Button("取消",role:.cancel) {}
        }
        .onChange(of:chooseScroll) { _ in scene?.suspendControls(chooseSkill || choosePotion || chooseScroll) }
        .onChange(of:aiming) { active in if !active { scene?.cancelAim() } }
        .onChange(of:chooseSkill) { _ in scene?.suspendControls(chooseSkill || choosePotion || chooseScroll) }
        .onChange(of:choosePotion) { _ in scene?.suspendControls(chooseSkill || choosePotion || chooseScroll) }
    }
}
private struct HoldAttackButton:View {
    let scene:OnlineScene?
    var body:some View {
        Button { scene?.input(.attack) } label: {
            VStack(spacing:2) { Text("攻击").font(.title3.bold());Text("再点停止").font(.caption2) }
                .frame(width:86,height:86).background(ClassicTheme.panel).clipShape(Circle())
                .overlay(Circle().stroke(ClassicTheme.gold,lineWidth:3))
        }.buttonStyle(.plain).accessibilityLabel("自动攻击最近怪物，再次点击停止")
    }
}
private struct ClassicAsset:View {
    let path:String
    var body:some View {
        if let root=Bundle.main.resourceURL,let image=UIImage(contentsOfFile:root.appendingPathComponent("GameData/"+path+".png").path) {
            Image(uiImage:image).resizable().interpolation(.none).scaledToFit()
        } else { Color.clear }
    }
}
private struct EquipmentPanel:View {
    @ObservedObject var net:MirConnection
    let characterOnly:Bool
    @State private var category="全部"
    @Environment(\.dismiss) private var dismiss
    @State private var selected:Int32?
    @State private var selectedSlot:Int?
    @State private var page=0
    @State private var confirmDrop=false
    private static let paperdoll:[String:SceneData.Frame] = {
        guard let url=Bundle.main.resourceURL?.appendingPathComponent("GameData/paperdoll.json"),let data=try? Data(contentsOf:url) else { return [:] }
        return (try? JSONDecoder().decode([String:SceneData.Frame].self,from:data)) ?? [:]
    }()
    @State private var characterTab="属性"
    private var scale:CGFloat { characterOnly ? 1.0 : 1.4 }
    private let points:[CGPoint]=[.init(x:122,y:178),.init(x:70,y:113),.init(x:185,y:142),.init(x:185,y:103),.init(x:124,y:94),.init(x:185,y:192),.init(x:59,y:192),.init(x:185,y:232),.init(x:59,y:232)]
    private var bag:[MirEquipment.Item] {
        net.inventory.bag.values.filter { item in
            switch category {
            case "装备":return !item.slots.isEmpty
            case "药品":return (0...3).contains(item.mode)
            case "其他":return item.slots.isEmpty && !(0...3).contains(item.mode)
            default:return true
            }
        }.sorted{$0.id<$1.id}
    }
    private var item:MirEquipment.Item? {
        if let slot=selectedSlot { return net.inventory.equipped[slot] }
        return selected.flatMap { net.inventory.bag[$0] }
    }
    private var locked:Bool { net.dealOpen || net.tradeBusy || net.inventory.pending != nil || net.usePending != nil || net.actionLocked }
    private func icon(_ item:MirEquipment.Item)->some View { ClassicAsset(path:"item-icons/\(item.looks)").frame(width:38,height:38) }
    private func paperLayer(_ key:String)->some View {
        Group {
            if let frame=Self.paperdoll[key] {
                ClassicAsset(path:String(frame.file.dropLast(4)))
                    .frame(width:CGFloat(frame.width)*scale,height:CGFloat(frame.height)*scale)
                    .offset(x:CGFloat(31+frame.offsetX)*scale,y:CGFloat(96+frame.offsetY)*scale)
            }
        }.allowsHitTesting(false)
    }
    private var character:some View {
        ZStack(alignment:.topLeading) {
            ClassicAsset(path:"classic-ui/equipment").frame(width:232*scale,height:325*scale)
            ClassicAsset(path:net.playerSex==1 ? "classic-ui/body-female" : "classic-ui/body-male")
                .frame(width:168*scale,height:199*scale).offset(x:38*scale,y:52*scale)
            paperLayer("hair-\(440+net.playerHair/2+net.playerSex)")
            ForEach([0,1,4],id:\.self) { slot in
                if let value=net.inventory.equipped[slot] { paperLayer(String(value.looks)) }
            }
            ForEach(0..<9,id:\.self) { slot in
                Button { selectedSlot=slot;selected=nil } label: {
                    ZStack {
                        if let value=net.inventory.equipped[slot] {
                            if ![0,1,4].contains(slot) || Self.paperdoll[String(value.looks)]==nil { icon(value) }
                        }
                        else { Text(MirEquipment.slotNames[slot]).font(.caption2).foregroundColor(.white.opacity(0.65)) }
                    }.frame(width:slot==0 ? 74 : slot==1 ? 66 : 44,height:slot==0 ? 157 : slot==1 ? 122 : 44).contentShape(Rectangle()).background(selectedSlot==slot ? Color.yellow.opacity(0.3) : Color.clear)
                }.position(x:points[slot].x*scale,y:points[slot].y*scale)
            }
            Text("人物装备").font(.headline).position(x:116*scale,y:24*scale)
        }.frame(width:232*scale,height:325*scale)
    }
    private var characterDetails:some View {
        VStack(alignment:.leading,spacing:10) {
            Picker("人物信息",selection:$characterTab) { Text("属性").tag("属性");Text("装备").tag("装备") }.pickerStyle(.segmented)
            if characterTab=="属性" {
                Text(net.selectedName).font(.headline)
                if let v=net.vitals {
                    Text("等级：\(v.level)")
                    Text("生命：\(v.hp)/\(v.maxHP)").foregroundColor(.red)
                    Text("魔法：\(v.mp)/\(v.maxMP)").foregroundColor(.blue)
                    Text("经验：\(v.experience)/\(v.maxExperience)")
                }
                Text(net.abilityText).font(.callout)
                Text("金币：\(net.goldBalance)")
                Text("攻击模式：\(net.attackModeName)")
            } else {
                ForEach(0..<MirEquipment.slotNames.count,id:\.self) { slot in
                    Button { selectedSlot=slot;selected=nil } label: {
                        HStack { Text(MirEquipment.slotNames[slot]);Spacer();if let value=net.inventory.equipped[slot] { icon(value);Text(net.itemName(value)) } else { Text("空") } }.frame(minHeight:44)
                    }
                }
            }
        }.padding(10).frame(width:240,alignment:.topLeading).background(ClassicTheme.panel).overlay(Rectangle().stroke(ClassicTheme.gold))
    }
    private var backpack:some View {
        ZStack(alignment:.topLeading) {
            ClassicAsset(path:"classic-ui/bag").frame(width:336*scale,height:270*scale)
            ForEach(0..<40,id:\.self) { index in
                let offset=page*40+index
                Button {
                    selected=offset<bag.count ? bag[offset].id : nil;selectedSlot=nil
                } label: {
                    ZStack {
                        if offset<bag.count { icon(bag[offset]) }
                    }.frame(width:49,height:44).contentShape(Rectangle())
                        .background(offset<bag.count && selected==bag[offset].id && selectedSlot==nil ? Color.yellow.opacity(0.3) : Color.clear)
                }.position(x:(38+CGFloat(index%8)*36)*scale,y:(29+CGFloat(index/8)*32)*scale)
            }
            Text("\(net.goldBalance)").font(.caption.monospacedDigit()).position(x:126*scale,y:185*scale)
            Text(item.map{net.itemName($0)} ?? "请选择物品").font(.caption).position(x:166*scale,y:228*scale)
        }.frame(width:336*scale,height:270*scale)
    }
    var body:some View {
        NavigationStack {
            ScrollView([.horizontal,.vertical]) {
                VStack(alignment:.leading,spacing:8) {
                    HStack(alignment:.top,spacing:8) {
                        if characterOnly { character;characterDetails } else {
                        VStack {
                            Picker("分类",selection:$category) { ForEach(["全部","装备","药品","其他"],id:\.self) { Text($0) } }.pickerStyle(.segmented)
                            backpack
                            HStack {
                                Text("背包 \(net.inventory.bag.count)/46")
                                Button(page==0 ? "后 6 格 →" : "← 前 40 格") { page=1-page }.frame(minHeight:44)
                            }
                        }
                    }
                    }
                    if !characterOnly { Text(net.abilityText).font(.caption) }
                    if let value=item {
                        Text("\(net.itemName(value)) · 耐久 \(value.durability)/\(value.maxDurability)")
                        Text("攻击 \(MirEquipment.range(value.dc)) · 魔法 \(MirEquipment.range(value.mc)) · 道术 \(MirEquipment.range(value.sc)) · 防御 \(MirEquipment.range(value.ac)) · 魔防 \(MirEquipment.range(value.mac))").font(.caption)
                    }
                    Text(net.tradeMessage.isEmpty ? net.equipmentMessage : net.tradeMessage).font(.caption)
                }.padding().disabled(locked)
            }.background(Color.black).foregroundColor(Color(red:0.88,green:0.77,blue:0.48))
            .safeAreaInset(edge:.bottom) {
                VStack(spacing:4) {
                    if let value=item {
                        Text(net.itemName(value)).font(.caption.bold())
                        HStack {
                            if let slot=selectedSlot {
                                Button("卸下") { net.changeEquipment(value,slot:slot,takingOff:true) }.frame(minHeight:44)
                            } else {
                                ForEach(value.slots,id:\.self) { slot in
                                    Button("穿戴·"+MirEquipment.slotNames[slot]) { net.changeEquipment(value,slot:slot,takingOff:false) }.frame(minHeight:44)
                                }
                                if [0,1,2,3,4,31].contains(value.mode) { Button("使用") { net.useItem(value) }.frame(minWidth:44,minHeight:44) }
                                Button("丢弃",role:.destructive) { confirmDrop=true }.frame(minWidth:70,minHeight:50)
                            }
                        }.buttonStyle(.bordered).disabled(locked)
                    } else { Text("点选背包物品，可穿戴或丢弃；已穿戴物品请先卸下").font(.caption) }
                }.padding(8).frame(maxWidth:.infinity).background(Color.black.opacity(0.96)).foregroundColor(Color(red:0.88,green:0.77,blue:0.48))
            }
            .onChange(of:category) { _ in page=0;selected=nil }
            .navigationTitle(characterOnly ? "人物装备与属性" : "背包").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44).disabled(net.tradeBusy) }
            .confirmationDialog("丢到地面后，其他玩家可能捡走",isPresented:$confirmDrop,titleVisibility:.visible) {
                if let value=item,selectedSlot==nil { Button("丢弃 \(net.itemName(value))",role:.destructive) { net.drop(value) } }
            }
            .interactiveDismissDisabled(net.tradeBusy)
        }
    }
}
private struct NPCShopPanel:View {
    @ObservedObject var net:MirConnection
    @State private var purchaseName=""
    @State private var purchaseIndex:Int32=0
    @State private var purchasePrice=0
    @State private var confirmBuy=false
    private var dialogue:String {
        net.npcText.replacingOccurrences(of:"<([^<>/]+)/(@[^<>]+)>",with:"$1",options:.regularExpression)
    }
    private func offer(_ name:String,index:Int32=0,price:Int) {
        purchaseName=name;purchaseIndex=index;purchasePrice=price;confirmBuy=true
    }
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            HStack { Text("金币 \(net.goldBalance)").bold();Spacer();Button("关闭") { net.closeNPC() }.frame(minWidth:44,minHeight:44).disabled(net.tradeBusy) }
            ScrollView {
                VStack(alignment:.leading,spacing:8) {
                    Text(dialogue).font(.callout)
                    HStack {
                        ForEach(net.npcLinks) { link in Button(link.label) { net.selectNPC(link.command) }.frame(minWidth:44,minHeight:44) }
                    }
                    if net.shopMode=="buy" {
                        if !net.shopDetails.isEmpty {
                            ForEach(net.shopDetails) { item in
                                Button { offer(net.itemName(item),index:item.id,price:Int(item.maxDurability)) } label: {
                                    HStack { ClassicAsset(path:"item-icons/\(item.looks)").frame(width:38,height:38);Text("\(net.itemName(item)) · 耐久 \(item.durability) · \(item.maxDurability) 金币");Spacer();Text("购买") }.frame(minHeight:44)
                                }
                            }
                        } else {
                            ForEach(net.shopGoods) { good in
                                Button {
                                    if good.submenu>0 { net.browse(good) } else { offer(good.name,price:good.price) }
                                } label: {
                                    HStack { Text(good.name);Spacer();Text("\(good.price) 金币 · 库存 \(good.stock)");Text(good.submenu>0 ? "挑选" : "购买") }.frame(minHeight:44)
                                }
                            }
                        }
                    }
                    if net.shopMode=="sell" {
                        Text("选择背包物品，由商店报价后确认出售")
                        ForEach(net.inventory.bag.values.sorted{$0.id<$1.id}) { item in
                            Button { net.quote(item) } label: {
                                HStack { ClassicAsset(path:"item-icons/\(item.looks)").frame(width:38,height:38);Text(net.itemName(item));Spacer();Text("询价") }.frame(minHeight:44)
                            }
                        }
                        if let id=net.saleItem,let item=net.inventory.bag[id],let price=net.salePrice,price>0 {
                            Button("确认出售 \(net.itemName(item))：\(price) 金币") { net.sellQuoted() }.frame(minHeight:44).buttonStyle(.borderedProminent)
                        }
                    }
                }.disabled(net.tradeBusy)
            }
            Text(net.tradeMessage).font(.caption)
        }.padding(16).frame(maxWidth:620,maxHeight:360).background(Color.black.opacity(0.97))
            .foregroundColor(Color(red:0.88,green:0.77,blue:0.48)).overlay(Rectangle().stroke(Color.brown,lineWidth:3))
            .confirmationDialog("购买 \(purchaseName)，价格 \(purchasePrice) 金币？",isPresented:$confirmBuy,titleVisibility:.visible) {
                Button("购买") { net.buy(name:purchaseName,index:purchaseIndex) }
            }
    }
}
private struct NavigationPanel:View {
    @ObservedObject var model:OnlineModel
    @Environment(\.dismiss) private var dismiss
    @State private var tapToWalk=true
    @State private var zoom:CGFloat=1
    @GestureState private var pinch:CGFloat=1
    @State private var marker:Cell?
    var body:some View {
        NavigationStack {
            VStack {
                HStack {
                    Button { zoom=max(1,zoom-0.5) } label: { Image(systemName:"minus.magnifyingglass").frame(minWidth:44,minHeight:44) }
                    Text("地图放大 \(Int(zoom*100))%").font(.caption).monospacedDigit()
                    Button { zoom=min(4,zoom+0.5) } label: { Image(systemName:"plus.magnifyingglass").frame(minWidth:44,minHeight:44) }
                    Toggle("点击寻路",isOn:$tapToWalk).fixedSize()
                }
                Text("双指缩放、拖动浏览；开启点击寻路后，点地图即可前往，推摇杆可中断").font(.caption)
                if let image=model.minimap,let scene=model.scene {
                    GeometryReader { geo in
                        let edge=min(geo.size.width,geo.size.height)*min(4,max(1,zoom*pinch))
                        let mapHeight=edge * image.size.height / image.size.width
                        ScrollView([.horizontal,.vertical]) {
                            ZStack(alignment:.topLeading) {
                                Image(uiImage:image).resizable().interpolation(.none)
                                ForEach(Array(scene.npcMarkers.enumerated()),id:\.offset) { _,cell in
                                    Circle().fill(Color.green).frame(width:5,height:5).position(x:CGFloat(cell.x)/CGFloat(scene.mapWidth)*edge,y:CGFloat(cell.y)/CGFloat(scene.mapHeight)*mapHeight)
                                }
                                Circle().fill(Color.yellow).frame(width:9,height:9).position(x:CGFloat(model.position.x)/CGFloat(scene.mapWidth)*edge,y:CGFloat(model.position.y)/CGFloat(scene.mapHeight)*mapHeight)
                                if let cell=marker { Image(systemName:"plus").foregroundColor(.white).position(x:CGFloat(cell.x)/CGFloat(scene.mapWidth)*edge,y:CGFloat(cell.y)/CGFloat(scene.mapHeight)*mapHeight) }
                            }.frame(width:edge,height:mapHeight).contentShape(Rectangle())
                                .simultaneousGesture(MagnificationGesture().updating($pinch) { value,state,_ in state=value }.onEnded { zoom=min(4,max(1,zoom * $0)) })
                                .simultaneousGesture(SpatialTapGesture().onEnded { value in
                                    marker=Cell(x:min(scene.mapWidth-1,max(0,Int(value.location.x/edge*CGFloat(scene.mapWidth)))),y:min(scene.mapHeight-1,max(0,Int(value.location.y/mapHeight*CGFloat(scene.mapHeight)))))
                                    if tapToWalk,let cell=marker { scene.suspendControls(false);scene.navigate(to:cell);dismiss() }
                                })
                        }
                    }
                    Text("黄点：本人 · 绿点：当前地图商人及已观察 NPC").font(.caption)
                    if let cell=marker {
                        HStack {
                            Text("选中坐标 \(cell.x),\(cell.y)")
                            if let name=scene.npcName(near:cell) { Text(name).foregroundColor(.green) }
                            if !tapToWalk { Button("前往此处") { scene.suspendControls(false);scene.navigate(to:cell);dismiss() }.frame(minHeight:44) }
                        }
                    }
                }
            }.padding().navigationTitle("当前地图").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44) }
        }
    }
}
private struct SkillPanel:View {
    @ObservedObject var net:MirConnection
    let scene:OnlineScene?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hud.classic") private var classic=true
    @State private var autoPickup=true
    var body:some View {
        NavigationStack {
            List {
                Toggle("自动拾取附近物品和金币",isOn:$autoPickup).onChange(of:autoPickup) { scene?.autoPickup=$0 }
                if net.skills.isEmpty { Text("当前角色尚未学习技能；学习后会显示服务器下发的技能。") }
                ForEach(net.skills) { skill in
                    HStack {
                        Text("\(net.skillName(skill)) · \(skill.level)级 · 熟练度 \(skill.training)")
                        Spacer()
                        if skill.castable {
                            Button("释放") { scene?.suspendControls(false);scene?.input(.skill(skill));dismiss() }.frame(minHeight:44)
                            if !classic && !MirSkills.warrior(skill.id) { Button(net.automaticSkills.contains(skill.id) ? "关闭自动" : "自动") { scene?.toggleAutoSkill(skill.id) }.frame(minHeight:44) }
                            Menu("快捷键") {
                                ForEach(0..<4,id:\.self) { slot in Button("位置 \(slot+1)") { net.setQuickSkill(skill.id,slot:slot) } }
                            }.frame(minHeight:44)
                        } else { Text("被动技能或尚未接入的技能").font(.caption) }
                    }.buttonStyle(.bordered)
                }
                Text("技能由服务端判断等级、蓝量、冷却和材料。火墙等范围技能先点技能，再点地图；自动释放时以当前怪物所在格为目标。刺杀／半月点击切换，烈火点击蓄力；长按快捷技能可替换绑定。经典模式不启用自动技能。")
            }.onAppear { autoPickup=scene?.autoPickup ?? true }.navigationTitle("技能与拾取").navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44) }
        }
    }
}

private struct PeerPlayerPanel:View {
    @ObservedObject var net:MirConnection
    let scene:OnlineScene?
    let target:OnlineScene.PlayerTarget
    let close:()->Void
    var body:some View {
        ScrollView { VStack(spacing:8) {
            HStack { Text(target.name).font(.headline);Spacer();Button("关闭",action:close).frame(minWidth:44,minHeight:44) }
            HStack {
                Button("查看装备") { scene?.inspect(target) }
                Button("面向对方") { scene?.face(target) }
                Button("发起交易") { scene?.face(target,trade:true) }
            }.buttonStyle(.bordered).frame(minHeight:44).disabled(net.tradeBusy)
            HStack {
                Button("锁定施法") { scene?.lockPlayer(target);close() }
                Button("攻击此人") { scene?.lockPlayer(target,attack:true);close() }
                Button("模式："+net.attackModeName) { net.cycleAttackMode() }
            }.buttonStyle(.bordered).frame(minHeight:44).disabled(net.tradeBusy)
            Text("锁定后用右侧技能施法；点击模式切换。安全区及和平模式等限制由服务端判定。").font(.caption)
            Text("交易需双方相邻、面对面；请双方分别点“面向对方”。").font(.caption)
            Text(net.peerMessage).font(.caption).foregroundColor(.yellow)
            if !net.inspectedName.isEmpty {
                Text("\(net.inspectedName) 的装备 · \(net.inspectedGuild)").font(.headline)
                ScrollView { VStack(alignment:.leading,spacing:6) {
                    ForEach(0..<MirEquipment.slotNames.count,id:\.self) { slot in
                        HStack {
                            Text(MirEquipment.slotNames[slot]).frame(width:65,alignment:.leading)
                            if let item=net.inspectedItems[slot] {
                                ClassicAsset(path:"item-icons/\(item.looks)").frame(width:32,height:32)
                                VStack(alignment:.leading) { Text(net.itemName(item));Text("攻击 \(MirEquipment.range(item.dc)) 魔法 \(MirEquipment.range(item.mc)) 道术 \(MirEquipment.range(item.sc)) 防御 \(MirEquipment.range(item.ac)) 魔御 \(MirEquipment.range(item.mac)) · 持久 \(item.durability)/\(item.maxDurability)").font(.caption2) }
                            } else { Text("空").foregroundColor(.gray) }
                        }.frame(minHeight:44)
                    }
                } }.frame(height:160)
            }
        }.padding() }.frame(maxWidth:570,maxHeight:340).background(ClassicTheme.panel).foregroundColor(ClassicTheme.text).overlay(Rectangle().stroke(ClassicTheme.gold))
    }
}
private struct PeerTradePanel:View {
    @ObservedObject var net:MirConnection
    @State private var choosingItem=false
    @State private var selectedItem:Int32?
    @State private var gold="0"
    @State private var confirming=false
    @State private var revision=0
    private var locked:Bool { net.tradeBusy || net.dealConfirmed }
    private var summary:String {
        "我方金币：\(net.dealOwnGold)，物品：" + net.dealOwn.values.sorted{$0.id<$1.id}.map{net.itemName($0)}.joined(separator:"、") +
        "\n对方金币：\(net.dealRemoteGold)，物品：" + net.dealRemote.values.sorted{$0.id<$1.id}.map{net.itemName($0)}.joined(separator:"、")
    }
    var body:some View {
        ScrollView { VStack(spacing:6) {
            HStack { Text("与 \(net.dealPartner) 交易").font(.headline);Spacer();Button("取消交易") { net.cancelPeerTrade() }.frame(minHeight:44).disabled(net.tradeBusy) }
            HStack(alignment:.top) {
                VStack(alignment:.leading) {
                    Text("我方 · 金币 \(net.dealOwnGold)").bold()
                    Text("点背包物品放入；禁止取回时可取消整笔交易").font(.caption2)
                    ScrollView { ForEach(net.dealOwn.values.sorted{$0.id<$1.id}) { item in
                        Button("取回："+net.itemName(item)) { net.offerPeerItem(item,remove:true) }.frame(minHeight:44).disabled(locked)
                    } }.frame(height:75)
                    HStack { TextField("金币",text:$gold).keyboardType(.numberPad).textFieldStyle(.roundedBorder);Button("放入") { net.offerPeerGold(gold) }.frame(minHeight:44) }.disabled(locked)
                }.frame(maxWidth:.infinity)
                VStack(alignment:.leading) {
                    Text("对方 · 金币 \(net.dealRemoteGold)").bold()
                    ScrollView { ForEach(net.dealRemote.values.sorted{$0.id<$1.id}) { item in
                        VStack(alignment:.leading) { Text(net.itemName(item));Text("攻击 \(MirEquipment.range(item.dc)) 魔法 \(MirEquipment.range(item.mc)) 道术 \(MirEquipment.range(item.sc)) 防御 \(MirEquipment.range(item.ac)) 魔御 \(MirEquipment.range(item.mac)) · 持久 \(item.durability)/\(item.maxDurability)").font(.caption2) }.frame(minHeight:44)
                    } }.frame(height:125)
                }.frame(maxWidth:.infinity)
            }
            Button { selectedItem=nil;choosingItem=true } label: {
                Label("选择背包物品（\(net.inventory.bag.count)）",systemImage:"bag").frame(maxWidth:.infinity,minHeight:48)
            }.buttonStyle(.borderedProminent).disabled(locked)
            Text("已穿戴装备需先取消交易，卸下到背包后再交易。确认报价后不能继续添加物品。").font(.caption2)
            HStack {
                Text(net.peerMessage).font(.caption).frame(maxWidth:.infinity,alignment:.leading)
                Button(net.dealConfirmed ? "等待对方确认" : "核对并确认") { revision=net.dealRevision;confirming=true }.frame(minHeight:44).disabled(locked)
            }
        }.padding(12) }.frame(maxWidth:640,maxHeight:340).background(ClassicTheme.panel).foregroundColor(ClassicTheme.text).overlay(Rectangle().stroke(ClassicTheme.gold))
        .sheet(isPresented:$choosingItem) {
            NavigationStack {
                VStack(spacing:8) {
                    List(net.inventory.bag.values.sorted{$0.id<$1.id}) { item in
                        Button { selectedItem=item.id } label: {
                            HStack {
                                ClassicAsset(path:"item-icons/\(item.looks)").frame(width:40,height:40)
                                VStack(alignment:.leading) { Text(net.itemName(item));Text("持久 \(item.durability)/\(item.maxDurability)").font(.caption) }
                                Spacer();if selectedItem==item.id { Image(systemName:"checkmark.circle.fill") }
                            }.frame(minHeight:52).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    if net.inventory.bag.isEmpty { Text("背包没有可放入的物品；已穿戴装备请先卸下") }
                    if let id=selectedItem,let item=net.inventory.bag[id] {
                        Text("攻击 \(MirEquipment.range(item.dc)) · 魔法 \(MirEquipment.range(item.mc)) · 道术 \(MirEquipment.range(item.sc))").font(.caption)
                        Button("放入交易："+net.itemName(item)) { net.offerPeerItem(item);choosingItem=false }.frame(minHeight:48).buttonStyle(.borderedProminent).disabled(locked)
                    }
                    Text(net.peerMessage).font(.caption)
                }.padding(.bottom).navigationTitle("选择交易物品").navigationBarTitleDisplayMode(.inline)
                    .toolbar { Button("返回交易") { choosingItem=false }.frame(minHeight:44) }
            }
        }
        .onChange(of:net.dealOpen) { open in if !open { choosingItem=false } }
        .alert("确认双方交易内容",isPresented:$confirming) {
            Button("确认交易") { net.confirmPeerTrade(revision:revision) }
            Button("返回核对",role:.cancel) {}
        } message: { Text(summary) }
    }
}

private struct NearbyPanel:View {
    let scene:OnlineScene?
    let select:(OnlineScene.NearbyTarget)->Void
    @Environment(\.dismiss) private var dismiss
    @State private var playersOnly=false
    var body:some View {
        NavigationStack {
            VStack {
                Picker("目标类型",selection:$playersOnly) { Text("全部目标").tag(false);Text("玩家").tag(true) }.pickerStyle(.segmented).padding(.horizontal)
                TimelineView(.periodic(from:.now,by:0.5)) { _ in
                    let targets=(scene?.nearbyTargets ?? []).filter { !playersOnly || !$0.monster }
                    List {
                        if targets.isEmpty { Text("视野内没有符合条件的目标") }
                        ForEach(targets) { target in
                            Button { select(target) } label: {
                                HStack {
                                    Image(systemName:target.monster ? "flame" : "person")
                                    Text(target.name);Spacer();Text("\(target.distance)格").font(.caption)
                                    Text(target.monster ? "锁定" : "交互").font(.caption)
                                }.frame(minHeight:44)
                            }
                        }
                    }
                }
                Text("点击怪物锁定；点击玩家可查看装备、交易或选择攻击。列表仅显示服务端已同步到视野的目标。").font(.caption).padding(.horizontal)
            }.navigationTitle("附近目标").navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("关闭") { dismiss() }.frame(minHeight:44) }
        }
    }
}
