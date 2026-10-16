import Foundation

struct SceneData: Decodable {
    struct Texture: Decodable { let file: String; let width, height: Int }
    struct Ground: Decodable { let file: String; let x, y, width, height: Int }
    struct Object: Decodable {
        let texture: String
        let x, y: Int
        let blend: String?
        let frameCount: Int?
        let frameDuration: Double?
        let offsetX, offsetY: Int?
    }
    struct Frame: Decodable { let file: String; let offsetX, offsetY, width, height, index: Int }
    let version: Int
    let name, sourceMap, sourceSHA256: String
    let originX, originY, width, height: Int
    let walkable: [Bool]
    let spawn: Cell
    let ground: [Ground]
    let textures: [String: Texture]
    let objects: [Object]
    let hero: [String: [[Frame]]]
    let monster: [String: [[Frame]]]
    let autoRoute: [Cell]
    var grid: NavigationGrid { NavigationGrid(width: width, height: height, mask: walkable) }

    static func load(mapID:String = "0") throws -> (SceneData, URL) {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("GameData") else {
            throw LoadError.invalid("找不到随应用打包的地图资源")
        }
        guard ["0", "0103", "0105", "0106", "2", "4", "11", "D001", "D002", "D003"].contains(mapID) else { throw LoadError.invalid("尚未安装地图资源：\(mapID)") }
        let sceneFile = mapID == "0" ? "scene.json" : "maps/\(mapID)/scene.json"
        let data = try JSONDecoder().decode(SceneData.self, from: Data(contentsOf: root.appendingPathComponent(sceneFile)))
        guard data.version == 1, (1...1024).contains(data.width), (1...1024).contains(data.height),
              data.walkable.count == data.width * data.height, data.grid.canWalk(data.spawn) else {
            throw LoadError.invalid("地图尺寸或出生点无效")
        }
        for (action, count) in [("stand", 4), ("walk", 6), ("attack", 6)] {
            guard let directions = data.hero[action], directions.count == 8,
                  directions.allSatisfy({ $0.count == count }) else {
                throw LoadError.invalid("人物动画帧不完整")
            }
        }
        var last = data.spawn
        for (action,count) in [("stand",4),("walk",6),("attack",6),("struck",2),("die",10)] {
            guard let directions = data.monster[action], directions.count == 8,
                  directions.allSatisfy({ $0.count == count }) else {
                throw LoadError.invalid("稻草人动画不完整")
            }
        }
        for object in data.objects {
            guard let texture = data.textures[object.texture], texture.width > 0, texture.height > 0 else {
                throw LoadError.invalid("物体纹理尺寸无效")
            }
            if let blend = object.blend {
                guard blend == "add", let frames = object.frameCount, (2...64).contains(frames),
                      texture.height % frames == 0,
                      let duration = object.frameDuration, duration.isFinite, duration >= 0.05,
                      object.offsetX != nil, object.offsetY != nil else {
                    throw LoadError.invalid("光效动画数据无效")
                }
            } else if object.frameCount != nil {
                throw LoadError.invalid("动画缺少混合方式")
            }
        }
        guard !data.autoRoute.isEmpty else { throw LoadError.invalid("自动行走路线为空") }
        for next in data.autoRoute {
            guard data.grid.neighbors(last).contains(next) else { throw LoadError.invalid("自动行走路线穿过障碍") }
            last = next
        }
        guard last == data.spawn else { throw LoadError.invalid("自动行走路线未闭合") }
        return (data, root)
    }
    enum LoadError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
    }
}
