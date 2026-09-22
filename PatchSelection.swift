import Foundation

/// Pointer coordinates are measured in cells. Only local clue rules are used;
/// snapping never consults the solution or repairs a distant selection.
struct PatchSelection {
    static let tolerance = 0.22
    static func cell(x: Double, y: Double, size: Int) -> Cell? {
        guard x >= -tolerance, y >= -tolerance,
              x <= Double(size)+tolerance, y <= Double(size)+tolerance else { return nil }
        return Cell(x:max(0,min(size-1,Int(floor(x)))), y:max(0,min(size-1,Int(floor(y)))))
    }
    static func resolve(anchor: Cell, x: Double, y: Double, puzzle: PatchesPuzzle,
                        placed: [PatchRect], previous: PatchRect?) -> PatchRect? {
        guard let end = cell(x:x,y:y,size:puzzle.size) else { return nil }
        func allowed(_ r: PatchRect) -> Bool {
            guard puzzle.valid(r), let clue = puzzle.clueIndex(r) else { return false }
            return !placed.contains { puzzle.clueIndex($0) != clue && $0.mask(puzzle.size) & r.mask(puzzle.size) != 0 }
        }
        func distance(_ r: PatchRect) -> Double {
            let ex = r.x == anchor.x ? r.x+r.width-1 : r.x
            let ey = r.y == anchor.y ? r.y+r.height-1 : r.y
            let dx = max(0,max(Double(ex)-x,x-Double(ex+1)))
            let dy = max(0,max(Double(ey)-y,y-Double(ey+1)))
            return hypot(dx,dy)
        }
        // Hysteresis keeps a preview stable across a small boundary wobble.
        if let previous, allowed(previous), distance(previous) <= tolerance { return previous }
        let direct = PatchRect.between(anchor,end)
        if allowed(direct) { return direct }
        var nearby: [(PatchRect,Double)] = []
        for row in max(0,end.y-1)...min(puzzle.size-1,end.y+1) {
            for col in max(0,end.x-1)...min(puzzle.size-1,end.x+1) {
                let r = PatchRect.between(anchor,Cell(x:col,y:row)), d = distance(r)
                if allowed(r) && d <= tolerance { nearby.append((r,d)) }
            }
        }
        nearby.sort { $0.1 < $1.1 }
        guard let first = nearby.first else { return nil }
        // Equally plausible alternatives remain under the player's control.
        if nearby.count > 1 && nearby[1].1-first.1 < 0.04 { return nil }
        return first.0
    }
}
