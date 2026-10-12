import SpriteKit
import ImageIO

final class SceneStreamer {
    private weak var scene: SKScene?
    private let root: URL
    let catalog: StreamCatalog
    private let queue = DispatchQueue(label: "mir.texture.decode", qos: .userInitiated)
    private var nodes: [String: SKSpriteNode] = [:]
    private var cache: [String: SKTexture] = [:]
    private var refs: [String: Int] = [:]
    private var sizes: [String: Int] = [:]
    // One set of subtextures per shared atlas, released with the last owner.
    private var animationFrames: [String: [SKTexture]] = [:]
    private var animationTime: Double = 0
    private var wanted = Set<String>(), keep = Set<String>(), failed = Set<String>()
    private var loading = false
    private var center = CGPoint.zero
    private var enabled = true
    private(set) var loads = 0, unloads = 0, failures = 0, budgetHits = 0
    private(set) var bytes = 0
    let budget = 48 * 1024 * 1024
    var nodeCount: Int { nodes.count }
    var textureCount: Int { cache.count }
    var pendingCount: Int { wanted.subtracting(Set(nodes.keys)).subtracting(failed).count }

    init(scene: SKScene, map: SceneData, root: URL) {
        self.scene = scene; self.root = root
        var entries = map.ground.enumerated().map { i, c in
            StreamItem(id: "g\(i)", file: c.file,
                       rect: StreamRect(x: Double(c.x), y: Double(c.y), width: Double(c.width), height: Double(c.height)), z: -100)
        }
        for (i, o) in map.objects.enumerated() {
            guard let t = map.textures[o.texture] else { continue }
            let frames = o.frameCount ?? 1
            let height = t.height / frames
            let x = o.x*48 + (o.blend == nil ? 0 : (o.offsetX ?? 0))
            let y = o.blend == nil ? (o.y+1)*32-height : o.y*32 + (o.offsetY ?? 0)
            entries.append(StreamItem(id: "o\(i)", file: t.file,
                rect: StreamRect(x: Double(x), y: Double(y), width: Double(t.width), height: Double(height)),
                z: 1000 + Double(o.y)*4 + Double(o.x)*0.001,
                frameCount: frames, frameDuration: o.frameDuration ?? 0.05))
        }
        catalog = StreamCatalog(entries)
    }
    func update(view: StreamRect) {
        guard enabled else { return }
        center = CGPoint(x: view.x + view.width/2, y: view.y + view.height/2)
        wanted = catalog.query(view.expanded(128))
        keep = catalog.query(view.expanded(384))
        for id in Array(nodes.keys) where !keep.contains(id) { remove(id) }
        pump()
    }
    private func remove(_ id: String) {
        guard let node = nodes.removeValue(forKey: id), let item = catalog.items[id] else { return }
        node.removeFromParent(); node.texture = nil; unloads += 1
        let count = (refs[item.file] ?? 1) - 1
        if count <= 0 {
            refs.removeValue(forKey: item.file); cache.removeValue(forKey: item.file)
            animationFrames.removeValue(forKey: item.file)
            bytes -= sizes.removeValue(forKey: item.file) ?? 0
        } else { refs[item.file] = count }
    }
    func suspend() {
        enabled = false; wanted = []; keep = []
        for id in Array(nodes.keys) { remove(id) }
        // The single in-flight decode is discarded by the wanted check.
    }
    func resume() { enabled = true }
    func trim() {
        for id in Array(nodes.keys) where !wanted.contains(id) { remove(id) }
    }
    private func attach(_ item: StreamItem, texture: SKTexture) {
        guard nodes[item.id] == nil, let scene = scene else { return }
        let node = SKSpriteNode(texture: texture)
        if item.frameCount > 1 {
            if animationFrames[item.file] == nil {
                animationFrames[item.file] = (0..<item.frameCount).map { frame in
                    // PNG rows are top-down; SpriteKit texture coordinates are bottom-up.
                    let rect = CGRect(x: 0, y: Double(item.frameCount-1-frame)/Double(item.frameCount),
                                      width: 1, height: 1/Double(item.frameCount))
                    let sub = SKTexture(rect: rect, in: texture)
                    sub.filteringMode = .nearest
                    return sub
                }
            }
            node.texture = animationFrames[item.file]?[item.frame(at: animationTime)]
            node.blendMode = .add
        }
        node.size = CGSize(width: item.rect.width, height: item.rect.height)
        node.anchorPoint = CGPoint(x: 0, y: 1)
        node.position = CGPoint(x: item.rect.x, y: -item.rect.y)
        node.zPosition = CGFloat(item.z)
        scene.addChild(node); nodes[item.id] = node
        refs[item.file, default: 0] += 1; loads += 1
    }
    func animate(at elapsed: Double) {
        guard enabled else { return }
        animationTime = elapsed
        for (id, node) in nodes {
            guard let item = catalog.items[id], item.frameCount > 1,
                  let frames = animationFrames[item.file] else { continue }
            let frame = frames[item.frame(at: elapsed)]
            if node.texture !== frame { node.texture = frame }
        }
    }
    private func pump() {
        guard enabled, !loading else { return }
        let pending = wanted.subtracting(Set(nodes.keys)).subtracting(failed).compactMap { catalog.items[$0] }.sorted {
            func distance(_ a: StreamItem) -> Double {
                let dx = a.rect.x+a.rect.width/2-Double(center.x), dy = a.rect.y+a.rect.height/2-Double(center.y)
                return dx*dx+dy*dy + (a.z < 0 ? 0 : 1e8)
            }
            return distance($0) < distance($1)
        }
        for item in pending {
            if let existing = cache[item.file] { attach(item, texture: existing); continue }
            if bytes + item.bytes > budget { trim() }
            guard bytes + item.bytes <= budget else { budgetHits += 1; continue }
            guard !item.file.contains(".."), !item.file.hasPrefix("/") else {
                failed.insert(item.id); failures += 1; continue
            }
            loading = true
            let url = root.appendingPathComponent(item.file)
            queue.async { [weak self] in
                let image: CGImage? = autoreleasepool {
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateImageAtIndex(source, 0,
                        [kCGImageSourceShouldCache: true, kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.loading = false
                    guard self.enabled, self.wanted.contains(item.id) else { self.pump(); return }
                    guard let image = image, image.width == Int(item.rect.width), image.height == item.textureHeight else {
                        self.failed.insert(item.id); self.failures += 1; self.pump(); return
                    }
                    // Budget checked again after asynchronous work; no stale view can reattach a node.
                    guard self.bytes + item.bytes <= self.budget else { self.budgetHits += 1; return }
                    let texture = SKTexture(cgImage: image); texture.filteringMode = .nearest
                    self.cache[item.file] = texture; self.sizes[item.file] = item.bytes; self.bytes += item.bytes
                    self.attach(item, texture: texture); self.pump()
                }
            }
            break // At most one decoded image waiting for the main thread.
        }
    }
}
