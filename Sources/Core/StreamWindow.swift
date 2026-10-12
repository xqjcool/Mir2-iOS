import Foundation

public struct StreamRect {
    public let x, y, width, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public func intersects(_ b: StreamRect) -> Bool {
        x < b.x + b.width && x + width > b.x && y < b.y + b.height && y + height > b.y
    }
    public func expanded(_ margin: Double) -> StreamRect {
        StreamRect(x: x-margin, y: y-margin, width: width+2*margin, height: height+2*margin)
    }
}

public struct StreamItem {
    public let id: String
    public let file: String
    public let rect: StreamRect
    public let z: Double
    public let frameCount: Int
    public let frameDuration: Double
    public init(id: String, file: String, rect: StreamRect, z: Double, frameCount: Int = 1, frameDuration: Double = 0.05) {
        self.id = id; self.file = file; self.rect = rect; self.z = z
        self.frameCount = max(1, frameCount); self.frameDuration = max(0.05, frameDuration)
    }
    public var textureHeight: Int { Int(rect.height) * frameCount }
    public var bytes: Int { Int(rect.width) * textureHeight * 4 }
    public func frame(at elapsed: Double) -> Int {
        Int(floor(max(0, elapsed) / frameDuration).truncatingRemainder(dividingBy: Double(frameCount)))
    }
}

// Index by actual image bounds: a tree can extend into a visible block even
// when its map-cell anchor is several rows outside the view.
public struct StreamCatalog {
    public let items: [String: StreamItem]
    private var buckets: [Cell: Set<String>] = [:]
    public init(_ entries: [StreamItem]) {
        items = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for item in entries {
            for bucket in Self.keys(item.rect) { buckets[bucket, default: []].insert(item.id) }
        }
    }
    private static func keys(_ r: StreamRect) -> [Cell] {
        guard r.width > 0, r.height > 0 else { return [] }
        let left = Int(floor(r.x/512)), right = Int(ceil((r.x+r.width)/512))-1
        let top = Int(floor(r.y/512)), bottom = Int(ceil((r.y+r.height)/512))-1
        return (top...bottom).flatMap { y in (left...right).map { Cell(x: $0, y: y) } }
    }
    public func query(_ rect: StreamRect) -> Set<String> {
        var ids = Set<String>()
        for key in Self.keys(rect) { ids.formUnion(buckets[key] ?? []) }
        return Set(ids.filter { items[$0]?.rect.intersects(rect) == true })
    }
}
