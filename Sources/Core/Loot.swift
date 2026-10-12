import Foundation

public struct LootInventory: Codable {
    public private(set) var gold = 0
    public private(set) var swords = 0
    public private(set) var equipped = false
    public init() {}
    public mutating func collect() { gold += 3000; swords += 1 }
    public mutating func equip() { if swords > 0 { equipped = true } }
}
