import Foundation

// Offline demo rules; independent of SpriteKit and frame rate.
public struct Combat {
    public private(set) var heroHP = 100
    public private(set) var monsterHP = 25
    public private(set) var heroCooldown = 0.0
    public private(set) var monsterCooldown = 2.5
    public private(set) var monsterSwings = 0
    private var monsterHit: Double?
    private var pendingHit: Double?
    public init() {}
    public var finished: Bool { heroHP == 0 || monsterHP == 0 }
    public mutating func attack() -> Bool {
        guard !finished, heroCooldown <= 0 else { return false }
        heroCooldown = 0.60; pendingHit = 0.255
        return true
    }
    public mutating func tick(_ dt: Double, adjacent: Bool, heroDamage: Int = Int.random(in: 2...5), monsterDamage: Int = Int.random(in: 1...2)) {
        guard !finished, dt.isFinite, dt >= 0 else { return }
        heroCooldown = max(0, heroCooldown-dt)
        monsterCooldown = max(0, monsterCooldown-dt)
        if let hit = pendingHit {
            pendingHit = hit-dt
            if hit <= dt {
                pendingHit = nil
                if adjacent { monsterHP = max(0, monsterHP-min(5,max(2,heroDamage))) }
            }
        }
        if let hit = monsterHit {
            monsterHit = hit-dt
            if hit <= dt {
                monsterHit = nil
                if !finished && adjacent { heroHP = max(0, heroHP-min(2,max(1,monsterDamage))) }
            }
        }
        if !finished && adjacent && monsterCooldown <= 0 {
            monsterCooldown = 2.5; monsterHit = 0.3; monsterSwings += 1
        }
    }
}
