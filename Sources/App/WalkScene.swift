import SpriteKit
import UIKit

final class WalkScene: SKScene {
    let map: SceneData
    let root: URL
    var onStatus: ((String, Cell) -> Void)?
    private let cameraNode = SKCameraNode()
    private let hero = SKNode(), body = SKSpriteNode(), collision = SKNode()
    private let marker = SKShapeNode(ellipseOf: CGSize(width: 34, height: 18))
    private var textures: [String: SKTexture] = [:]
    private var streamer: SceneStreamer!
    private let telemetry = WalkTelemetry()
    var onMetrics: ((String, Bool, URL?) -> Void)?
    private var testing = false, tourIndex = 0, steps = 0
    private var metricTime = 0.0, streamTime = 0.0
    private var observers: [NSObjectProtocol] = []
    private var lastCollisionCell: Cell?
    private var active = true
    private var cell: Cell
    private var route: [Cell] = []
    private var destination: Cell?
    private var direction = 4, lastFrame = ""
    private var elapsed: TimeInterval = 0, lastTime: TimeInterval = 0, stepElapsed: TimeInterval = 0
    private let stepDuration: TimeInterval = 0.54
    private var built = false
    private var zoom: CGFloat = 1
    var onCombat: ((String) -> Void)?
    private var combat = Combat()
    private let monster = SKNode()
    private let monsterLabel = SKLabelNode(fontNamed: "Helvetica-Bold")
    private var monsterCell = Cell(x: 0, y: 0)
    private var monsterMove = 0.0
    private var attackTime = 1.0
    private var encounter = false
    private let monsterBody = SKSpriteNode()
    private let lootNode = SKNode()
    private var lootAvailable = false
    private var monsterDirection = 4
    private var monsterAction = "stand", monsterActionTime = 0.0
    private var inventory = (UserDefaults.standard.data(forKey: "mir.loot.v1").flatMap {
        try? JSONDecoder().decode(LootInventory.self, from: $0)
    }) ?? LootInventory()

    init(map: SceneData, root: URL) {
        self.map = map; self.root = root; self.cell = map.spawn
        super.init(size: CGSize(width: 960, height: 540))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.09, green: 0.11, blue: 0.10, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError("Use init(map:root:)") }

    private func texture(_ file: String) -> SKTexture? {
        if let cached = textures[file] { return cached }
        guard !file.contains(".."), !file.hasPrefix("/"),
              let image = UIImage(contentsOfFile: root.appendingPathComponent(file).path) else { return nil }
        let tex = SKTexture(image: image); tex.filteringMode = .nearest
        textures[file] = tex
        return tex
    }
    private func point(_ cell: Cell) -> CGPoint {
        CGPoint(x: CGFloat(cell.x * 48 + 24), y: -CGFloat(cell.y * 32 + 16))
    }
    override func didMove(to view: SKView) {
        guard !built else { return }; built = true
        view.preferredFramesPerSecond = 60
        streamer = SceneStreamer(scene: self, map: map, root: root)
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            self?.streamer.trim(); self?.textures.removeAll(); self?.telemetry.memoryWarning()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = false; self?.streamer.suspend(); self?.lastTime = 0
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.active = true; self?.streamer.resume(); self?.streamTime = 0; self?.lastTime = 0
        })
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 28, height: 12))
        shadow.fillColor = .black; shadow.strokeColor = .clear; shadow.alpha = 0.3; shadow.zPosition = -1
        hero.addChild(shadow); body.anchorPoint = .zero; hero.addChild(body); addChild(hero)
        hero.position = point(cell)
        marker.strokeColor = .cyan; marker.lineWidth = 2; marker.zPosition = 900
        marker.isHidden = true; addChild(marker)
        collision.zPosition = 9000; collision.isHidden = true; addChild(collision)
        addChild(cameraNode); camera = cameraNode
        updateBody(walking: false); updateCamera()
        monsterBody.anchorPoint = .zero; monster.addChild(monsterBody)
        addChild(lootNode)
        monsterLabel.fontSize = 12; monsterLabel.position.y = 38
        monster.addChild(monsterLabel); addChild(monster)
        resetEncounter()
        onStatus?("点击行走；30 分钟测试可自动跨分块往返", cell)
    }

    override func didChangeSize(_ oldSize: CGSize) { if built { updateCamera() } }

    func resetPlayer() {
        if testing { stopTest(reason: "reset") }
        route = []; destination = nil; stepElapsed = 0; cell = map.spawn
        hero.position = point(cell); marker.isHidden = true
        updateBody(walking: false); updateCamera(); onStatus?("已回到起点", cell)
        resetEncounter()
    }
    func toggleZoom() { zoom = zoom == 1 ? 1.4 : 1; updateCamera() }
    func toggleCollision() {
        collision.isHidden.toggle(); lastCollisionCell = nil
        refreshCollision()
    }
    private func refreshCollision() {
        guard !collision.isHidden, cell != lastCollisionCell else { return }
        lastCollisionCell = cell; collision.removeAllChildren()
        let path = CGMutablePath()
        for y in max(0,cell.y-22)..<min(map.height,cell.y+23) {
            for x in max(0,cell.x-40)..<min(map.width,cell.x+41) where !map.grid.canWalk(Cell(x: x,y: y)) {
                path.addRect(CGRect(x: CGFloat(x*48), y: -CGFloat((y+1)*32), width: 48, height: 32))
            }
        }
        let node = SKShapeNode(path: path)
        node.fillColor = SKColor.red.withAlphaComponent(0.25); node.strokeColor = SKColor.red.withAlphaComponent(0.5)
        node.lineWidth = 0.5; collision.addChild(node)
    }
    func toggleTest() {
        if testing { stopTest(reason: "user"); return }
        resetPlayer(); testing = true; tourIndex = 0; steps = 0
        encounter = false; monster.isHidden = true
        onCombat?("行走测试中 · 点击“重新挑战”返回战斗")
        telemetry.start(); beginStep()
        UIApplication.shared.isIdleTimerDisabled = true
        onMetrics?("自动行走测试开始", true, nil)
        onStatus?("自动行走测试开始：30 分钟前台运行，可随时停止", cell)
    }
    private func stopTest(reason: String) {
        testing = false; route = []
        _ = telemetry.sample(stream: streamer, steps: steps, cell: cell, force: true)
        telemetry.stop(reason: reason)
        UIApplication.shared.isIdleTimerDisabled = false
        onMetrics?("测试已结束 · 可分享 CSV", false, telemetry.url)
        onStatus?("测试结束：\(steps) 步", cell)
    }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard combat.heroHP > 0, attackTime >= 0.51 else { return }
        guard let touch = touches.first else { return }
        if testing { stopTest(reason: "manual_touch") }
        let p = touch.location(in: self)
        let target = Cell(x: Int(floor(p.x / 48)), y: Int(floor(-p.y / 32)))
        // Replan from the next grid centre, finishing the current step first.
        let start = destination ?? cell
        guard let path = map.grid.path(from: start, to: target) else {
            onStatus?("此处不可到达，请点击空地", cell); return
        }
        route = path; marker.position = point(target); marker.isHidden = false
        if destination == nil { beginStep() }
        onStatus?("前往 (\(target.x + map.originX), \(target.y + map.originY))", cell)
    }

    private func beginStep() {
        guard combat.heroHP > 0, attackTime >= 0.51 else { return }
        let next: Cell
        if testing {
            next = map.autoRoute[tourIndex]; tourIndex = (tourIndex + 1) % map.autoRoute.count
        } else {
            guard !route.isEmpty else { destination = nil; marker.isHidden = true; return }
            next = route.removeFirst()
        }
        guard map.grid.neighbors(cell).contains(next) else {
            route = []; destination = nil
            if testing { stopTest(reason: "invalid_route") }
            onStatus?("路线校验失败，已停止行走", cell)
            return
        }
        if encounter && combat.monsterHP > 0 && next == monsterCell {
            route = []; destination = nil; return
        }
        let dx = next.x - cell.x, dy = next.y - cell.y
        let directions = [Cell(x: 0,y: -1), Cell(x: 1,y: -1), Cell(x: 1,y: 0), Cell(x: 1,y: 1),
                          Cell(x: 0,y: 1), Cell(x: -1,y: 1), Cell(x: -1,y: 0), Cell(x: -1,y: -1)]
        direction = directions.firstIndex(of: Cell(x: dx,y: dy)) ?? direction
        destination = next; stepElapsed = 0
    }

    override func update(_ currentTime: TimeInterval) {
        guard built, active else { return }
        let rawDelta = lastTime == 0 ? 0 : max(currentTime - lastTime, 0)
        let dt = min(rawDelta, 0.05)
        telemetry.tick(delta: rawDelta)
        if testing && telemetry.elapsed >= 1800 { stopTest(reason: "completed") }
        lastTime = currentTime; elapsed += dt
        streamer.animate(at: elapsed)
        attackTime += dt
        updateCombat(dt)
        if let target = destination {
            stepElapsed += dt
            let t = CGFloat(min(stepElapsed / stepDuration, 1))
            let a = point(cell), b = point(target)
            hero.position = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            if t >= 1 {
                cell = target; steps += 1; destination = nil; beginStep()
                onStatus?(destination == nil ? "已到达 · 点击继续行走" : "行走中", cell)
            }
        }
        updateBody(walking: destination != nil); updateCamera(); refreshCollision()
        if currentTime - metricTime >= 1 {
            metricTime = currentTime
            let memory = telemetry.sample(stream: streamer, steps: steps, cell: cell)
            let memoryText = memory.map { String(format: "%.0f", $0) } ?? "?"
            let text = "内存 \(memoryText) MB · 峰值 \(Int(telemetry.peak)) MB · \(Int(telemetry.fps)) FPS\n纹理 \(streamer.bytes/1048576)/48 MB · 节点 \(streamer.nodeCount) · 待载 \(streamer.pendingCount) · 失败 \(streamer.failures)\n\(testing ? "测试中" : "手动") \(Int(telemetry.elapsed)) 秒 · \(steps) 步\(telemetry.logFailed ? " · 日志写入失败" : "")"
            onMetrics?(text, testing, testing ? nil : telemetry.url)
        }
    }
    private func updateBody(walking: Bool) {
        let action = attackTime < 0.51 ? "attack" : (walking ? "walk" : "stand")
        guard let directions = map.hero[action], directions.indices.contains(direction) else { body.isHidden = true; return }
        let frames = directions[direction]
        let phase = action == "attack" ? min(Int(attackTime / 0.085),5) : (walking ? min(Int(stepElapsed / 0.09), 5) : Int(elapsed / 0.2) % 4)
        guard frames.indices.contains(phase) else { body.isHidden = true; return }
        let frame = frames[phase]
        if frame.file != lastFrame {
            guard let tex = texture(frame.file) else { body.isHidden = true; return }
            body.texture = tex; body.size = tex.size(); body.isHidden = false
            body.position = CGPoint(x: CGFloat(frame.offsetX - 24), y: CGFloat(16 - frame.offsetY - frame.height))
            lastFrame = frame.file
        }
        hero.zPosition = 1000 + (-hero.position.y / 32 - 0.5) * 4 + 2
    }
    private func updateCamera() {
        guard size.height > 0 else { return }
        // Keep about 17 map rows visible regardless of device pixel density.
        let scale = 540 / size.height * zoom
        cameraNode.setScale(scale)
        let halfW = size.width * scale / 2, halfH = size.height * scale / 2
        func clamp(_ value: CGFloat, _ half: CGFloat, _ total: CGFloat) -> CGFloat {
            total <= half * 2 ? total / 2 : min(max(value, half), total - half)
        }
        cameraNode.position = CGPoint(x: clamp(hero.position.x, halfW, CGFloat(map.width * 48)),
                                      y: -clamp(-hero.position.y, halfH, CGFloat(map.height * 32)))
        if elapsed - streamTime >= 0.1 || streamTime == 0 {
            streamTime = elapsed
            streamer.update(view: StreamRect(x: Double(cameraNode.position.x-halfW),
                y: Double(-cameraNode.position.y-halfH), width: Double(halfW*2), height: Double(halfH*2)))
        }
    }

    func attackMonster() {
        guard !testing, encounter, destination == nil, combat.attack() else { return }
        route = []; attackTime = 0
        let dx = (monsterCell.x-cell.x).signum(), dy = (monsterCell.y-cell.y).signum()
        let dirs = [Cell(x:0,y:-1),Cell(x:1,y:-1),Cell(x:1,y:0),Cell(x:1,y:1),
                    Cell(x:0,y:1),Cell(x:-1,y:1),Cell(x:-1,y:0),Cell(x:-1,y:-1)]
        direction = dirs.firstIndex(of: Cell(x:dx,y:dy)) ?? direction
        onStatus?("挥击！靠近怪物才能命中", cell)
    }

    private func resetEncounter() {
        lootAvailable = false; lootNode.removeAllChildren(); setMonsterAction("stand")
        combat = Combat(); attackTime = 1; monsterMove = 0; encounter = true
        hero.removeAllActions(); hero.alpha = 1; monster.alpha = 1; monster.isHidden = false
        monster.removeAllActions()
        // Select a nearby reachable position, never spawn inside scenery.
        var frontier = [cell], seen: Set<Cell> = [cell]
        for _ in 0..<4 {
            var next: [Cell] = []
            for p in frontier { for n in map.grid.neighbors(p) where !seen.contains(n) {
                seen.insert(n); next.append(n)
            }}
            if next.isEmpty { break }; frontier = next
        }
        guard let spawn = frontier.first(where: { $0 != cell }) else {
            encounter = false; monster.isHidden = true; onCombat?("附近无可用怪物出生点"); return
        }
        monsterCell = spawn; monster.position = point(spawn)
        publishCombat()
    }

    private func publishCombat() {
        monsterLabel.text = "稻草人 \(combat.monsterHP)/25"
        onCombat?("生命 \(combat.heroHP)/100 · 稻草人 \(combat.monsterHP)/25\n金币 \(inventory.gold) · 木剑 ×\(inventory.swords)\(inventory.equipped ? "（已装备）" : "")" +
                  (combat.monsterHP == 0 ? " · 击杀成功！" : combat.heroHP == 0 ? " · 你已倒下" : ""))
    }

    private func updateCombat(_ dt: Double) {
        guard encounter, !testing else { return }
        monsterActionTime += dt
        renderMonster()
        let adjacent = destination == nil && monster.action(forKey: "move") == nil && map.grid.neighbors(cell).contains(monsterCell)
        let oldHero = combat.heroHP, oldMonster = combat.monsterHP
        let swings = combat.monsterSwings
        combat.tick(dt, adjacent: adjacent, heroDamage: inventory.equipped ? Int.random(in: 2...5) : 2)
        if combat.monsterSwings != swings {
            let delta = Cell(x:(cell.x-monsterCell.x).signum(),y:(cell.y-monsterCell.y).signum())
            let dirs = [Cell(x:0,y:-1),Cell(x:1,y:-1),Cell(x:1,y:0),Cell(x:1,y:1),Cell(x:0,y:1),Cell(x:-1,y:1),Cell(x:-1,y:0),Cell(x:-1,y:-1)]
            monsterDirection = dirs.firstIndex(of:delta) ?? monsterDirection
            setMonsterAction("attack")
        }
        if combat.monsterHP != oldMonster {
            if monsterAction != "attack" { setMonsterAction("struck") }
            if combat.monsterHP == 0 {
                monster.removeAllActions(); setMonsterAction("die"); dropLoot()
                onStatus?("击杀成功！点击重新挑战可再打一只", cell)
            }
        }
        if combat.heroHP != oldHero {
            hero.run(.sequence([.fadeAlpha(to: 0.4, duration: 0.08),.fadeAlpha(to: 1, duration: 0.12)]))
            if combat.heroHP == 0 {
                route = []; destination = nil; hero.removeAllActions(); hero.alpha = 0.3
                onStatus?("你已倒下，点击重新挑战恢复生命", cell)
            }
        }
        if oldHero != combat.heroHP || oldMonster != combat.monsterHP { publishCombat() }
        guard !combat.finished else { return }
        monsterMove -= dt
        if monsterMove <= 0 {
            monsterMove = 1.5
            let distance = max(abs(monsterCell.x-cell.x),abs(monsterCell.y-cell.y))
            if !adjacent, monsterAction != "attack", distance <= 10,
               let path = map.grid.path(from: monsterCell, to: cell), let next = path.first,
               next != cell, next != destination {
                let delta = Cell(x: (next.x-monsterCell.x).signum(), y: (next.y-monsterCell.y).signum())
                let dirs = [Cell(x:0,y:-1),Cell(x:1,y:-1),Cell(x:1,y:0),Cell(x:1,y:1),Cell(x:0,y:1),Cell(x:-1,y:1),Cell(x:-1,y:0),Cell(x:-1,y:-1)]
                monsterDirection = dirs.firstIndex(of: delta) ?? monsterDirection
                monsterCell = next; setMonsterAction("walk")
                monster.run(.move(to: point(next), duration: 0.96), withKey: "move")
            }
        }
        monster.zPosition = 1000 + (-monster.position.y / 32 - 0.5) * 4 + 2
    }

    private func setMonsterAction(_ action: String) {
        monsterAction = action; monsterActionTime = 0
    }
    private func renderMonster() {
        let interval = ["stand":0.2,"walk":0.16,"attack":0.1,"struck":0.1,"die":0.12][monsterAction] ?? 0.2
        guard let frames = map.monster[monsterAction]?[monsterDirection] else { return }
        var phase = Int(monsterActionTime/interval)
        if monsterAction == "die" { phase = min(phase,frames.count-1) }
        else if monsterAction == "stand" { phase %= frames.count }
        else if phase >= frames.count { setMonsterAction("stand"); renderMonster(); return }
        let f = frames[phase]
        guard let tex = texture(f.file) else { return }
        monsterBody.texture = tex; monsterBody.size = tex.size()
        monsterBody.position = CGPoint(x: CGFloat(f.offsetX-24),y: CGFloat(16-f.offsetY-f.height))
    }
    private func dropLoot() {
        lootAvailable = true; lootNode.removeAllChildren(); lootNode.position = point(monsterCell)
        lootNode.zPosition = 999 + Double(monsterCell.y)*4
        let sword = SKSpriteNode(texture: texture("wooden-sword-ground.png"))
        sword.position.x = 18; lootNode.addChild(sword)
        let label = SKLabelNode(fontNamed: "Helvetica-Bold")
        label.text = "金币3000 · 木剑"; label.fontSize = 13; label.fontColor = .yellow
        label.position.y = -20; lootNode.addChild(label)
    }
    func pickUpLoot() {
        guard lootAvailable, combat.heroHP > 0, !testing, destination == nil,
              cell == monsterCell || map.grid.neighbors(cell).contains(monsterCell) else {
            onStatus?("走到掉落物旁边，再点拾取",cell); return
        }
        lootAvailable = false; lootNode.removeAllChildren(); inventory.collect(); saveInventory(); publishCombat()
        onStatus?("拾取金币3000和木剑，已保存到本机",cell)
    }
    func equipSword() {
        inventory.equip(); saveInventory(); publishCombat()
        onStatus?(inventory.equipped ? "已装备木剑：攻击2–5（本版暂不显示持剑外观）" : "先击杀稻草人并拾取木剑",cell)
    }
    private func saveInventory() {
        if let data = try? JSONEncoder().encode(inventory) { UserDefaults.standard.set(data,forKey:"mir.loot.v1") }
    }
}
