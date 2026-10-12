import Foundation

public struct Cell: Codable, Hashable {
    public let x: Int
    public let y: Int
    public init(x: Int, y: Int) { self.x = x; self.y = y }
}

public struct NavigationGrid {
    public let width: Int
    public let height: Int
    public let mask: [Bool]
    public init(width: Int, height: Int, mask: [Bool]) {
        self.width = width; self.height = height; self.mask = mask
    }
    public func canWalk(_ cell: Cell) -> Bool {
        guard width > 0, height > 0, cell.x >= 0, cell.y >= 0,
              cell.x < width, cell.y < height, mask.count == width * height else { return false }
        return mask[cell.y * width + cell.x]
    }
    public func neighbors(_ cell: Cell) -> [Cell] {
        var result: [Cell] = []
        for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
            let next = Cell(x: cell.x + dx, y: cell.y + dy)
            guard canWalk(next) else { continue }
            // Never cut diagonally through the corner of a wall.
            if dx != 0 && dy != 0 {
                guard canWalk(Cell(x: cell.x + dx, y: cell.y)),
                      canWalk(Cell(x: cell.x, y: cell.y + dy)) else { continue }
            }
            result.append(next)
        }}
        return result
    }
    // A* uses flat grid arrays so a full 700x700 map does not allocate a dictionary per tile.
    public func path(from start: Cell, to goal: Cell) -> [Cell]? {
        guard canWalk(start),canWalk(goal) else { return nil }
        if start==goal { return [] }
        let count=width*height,source=start.y*width+start.x,target=goal.y*width+goal.x
        var parent=[Int32](repeating:-1,count:count),distance=[Int32](repeating:Int32.max,count:count)
        var closed=[Bool](repeating:false,count:count)
        struct Entry { let index:Int;let g:Int32;let f:Int32 }
        var heap:[Entry]=[]
        func heuristic(_ index:Int)->Int32 { Int32(max(abs(index%width-goal.x),abs(index/width-goal.y))) }
        func before(_ a:Entry,_ b:Entry)->Bool { a.f==b.f ? a.g>b.g : a.f<b.f }
        func push(_ entry:Entry) {
            heap.append(entry);var child=heap.count-1
            while child>0 { let p=(child-1)/2;guard before(heap[child],heap[p]) else { break };heap.swapAt(child,p);child=p }
        }
        func pop()->Entry {
            let result=heap[0],last=heap.removeLast()
            if !heap.isEmpty {
                heap[0]=last;var p=0
                while p*2+1<heap.count {
                    var child=p*2+1
                    if child+1<heap.count && before(heap[child+1],heap[child]) { child+=1 }
                    guard before(heap[child],heap[p]) else { break };heap.swapAt(child,p);p=child
                }
            }
            return result
        }
        distance[source]=0;push(Entry(index:source,g:0,f:heuristic(source)))
        while !heap.isEmpty {
            let entry=pop(),current=entry.index
            if closed[current] || entry.g != distance[current] { continue }
            if current==target {
                var path:[Cell]=[],cursor=target
                while cursor != source { path.append(Cell(x:cursor%width,y:cursor/width));cursor=Int(parent[cursor]);if cursor<0 { return nil } }
                return Array(path.reversed())
            }
            closed[current]=true
            for next in neighbors(Cell(x:current%width,y:current/width)) {
                let index=next.y*width+next.x,g=entry.g+1
                if !closed[index] && g<distance[index] {
                    distance[index]=g;parent[index]=Int32(current);push(Entry(index:index,g:g,f:g+heuristic(index)))
                }
            }
        }
        return nil
    }
}
