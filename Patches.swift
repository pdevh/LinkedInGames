import Foundation

struct PatchRect: Codable, Hashable {
    let x: Int, y: Int, width: Int, height: Int
    var area: Int { width * height }
    func contains(_ c: Cell) -> Bool { c.x >= x && c.x < x+width && c.y >= y && c.y < y+height }
    func mask(_ size: Int) -> UInt64 {
        var result: UInt64 = 0
        for row in y..<y+height { for col in x..<x+width { result |= 1 << (row*size+col) } }
        return result
    }
    static func between(_ a: Cell, _ b: Cell) -> PatchRect {
        PatchRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x)+1, height: abs(a.y-b.y)+1)
    }
}
enum PatchShape: String, Codable, CaseIterable {
    case square, tall, wide, any
    var symbol: String { switch self { case .square: return "□"; case .tall: return "▯"; case .wide: return "▭"; case .any: return "◇" } }
    func accepts(_ r: PatchRect) -> Bool {
        switch self { case .square: return r.width == r.height; case .tall: return r.height > r.width
        case .wide: return r.width > r.height; case .any: return true }
    }
}
struct PatchClue: Codable, Equatable {
    var cell: Cell
    var area: Int?
    var shape: PatchShape
}
struct PatchesPuzzle: Codable, Equatable {
    let size: Int
    var clues: [PatchClue]
    let solution: [PatchRect]
    func clueIndex(_ r: PatchRect) -> Int? {
        let matches = clues.indices.filter { r.contains(clues[$0].cell) }
        return matches.count == 1 ? matches[0] : nil
    }
    func valid(_ r: PatchRect) -> Bool {
        guard r.width > 0, r.height > 0, r.x >= 0, r.y >= 0, r.x+r.width <= size, r.y+r.height <= size,
              let i = clueIndex(r) else { return false }
        return (clues[i].area == nil || clues[i].area == r.area) && clues[i].shape.accepts(r)
    }
    func legal(_ rectangles: [PatchRect]) -> Bool {
        var occupied: UInt64 = 0
        for r in rectangles {
            guard valid(r) else { return false }
            let mask = r.mask(size)
            guard occupied & mask == 0 else { return false }
            occupied |= mask
        }
        return true
    }
    func complete(_ rectangles: [PatchRect]) -> Bool { legal(rectangles) && rectangles.reduce(0) { $0+$1.area } == size*size }
    func candidates() -> [[PatchRect]] {
        var result = [[PatchRect]](repeating: [], count: clues.count)
        for y in 0..<size { for x in 0..<size { for h in 1...size-y { for w in 1...size-x {
            let r = PatchRect(x: x,y: y,width: w,height: h)
            if valid(r), let i = clueIndex(r) { result[i].append(r) }
        } } } }
        return result
    }
    // Exact cover with minimum-remaining-values branching. Budget exhaustion never proves uniqueness.
    func solve(budget: Int = 30_000) -> (count: Int, exhausted: Bool, nodes: Int) {
        let options = candidates().map { $0.map { $0.mask(size) } }
        var count = 0, nodes = 0, exhausted = false
        let full = (UInt64(1) << (size*size))-1
        func visit(_ used: UInt64, _ remaining: [Int]) {
            guard count < 2, !exhausted else { return }
            nodes += 1
            if nodes > budget { exhausted = true; return }
            if remaining.isEmpty { if used == full { count += 1 }; return }
            var selected = remaining[0], choices: [UInt64] = [], best = Int.max
            var union = used
            for i in remaining {
                let available = options[i].filter { $0 & used == 0 }
                if available.isEmpty { return }
                for mask in available { union |= mask }
                if available.count < best { selected = i; choices = available; best = available.count }
            }
            if union != full { return }
            let rest = remaining.filter { $0 != selected }
            for mask in choices { visit(used | mask, rest) }
        }
        visit(0, Array(clues.indices))
        return (count, exhausted, nodes)
    }
    var features: [Double] {
        let options = candidates().map { Double($0.count) }, n = Double(clues.count)
        let ambiguity = options.reduce(0) { $0+log1p($1-1) }/max(1,n)
        let free = Double(clues.filter { $0.area == nil || $0.shape == .any }.count)/max(1,n)
        return [1, Double(size*size)/49, n/Double(size*size), ambiguity/3, free,
                Double(solution.map(\.area).max() ?? 1)/Double(size*size), ambiguity*free/3]
    }
    static func make(_ difficulty: Difficulty, using rng: inout PuzzleRandom) -> PatchesPuzzle {
        let size = difficulty.size
        var regions = [PatchRect(x: 0,y: 0,width: size,height: size)]
        func split(_ index: Int) {
            let r = regions.remove(at: index)
            let vertical = r.width > 1 && (r.height == 1 || Bool.random(using: &rng))
            if vertical {
                let cut = Int.random(in: 1..<r.width, using: &rng)
                regions += [PatchRect(x:r.x,y:r.y,width:cut,height:r.height), PatchRect(x:r.x+cut,y:r.y,width:r.width-cut,height:r.height)]
            } else {
                let cut = Int.random(in: 1..<r.height, using: &rng)
                regions += [PatchRect(x:r.x,y:r.y,width:r.width,height:cut), PatchRect(x:r.x,y:r.y+cut,width:r.width,height:r.height-cut)]
            }
        }
        for _ in 1..<[7,9,11][difficulty.rawValue] {
            let eligible = regions.indices.filter { regions[$0].area > 2 }
            if let i = eligible.max(by: { regions[$0].area < regions[$1].area }) { split(i) }
        }
        var puzzle: PatchesPuzzle
        while true {
            let clues = regions.map { r in PatchClue(cell: Cell(x: Int.random(in:r.x..<r.x+r.width,using:&rng), y:Int.random(in:r.y..<r.y+r.height,using:&rng)), area:r.area,
                shape: r.width == r.height ? .square : r.width > r.height ? .wide : .tall) }
            puzzle = PatchesPuzzle(size:size, clues:clues, solution:regions)
            let check = puzzle.solve()
            if check.count == 1 && !check.exhausted { break }
            // Refinement terminates at singleton cells, so no unverified fallback board is needed.
            if let i = regions.indices.filter({ regions[$0].area > 1 }).randomElement(using:&rng) { split(i) }
        }
        let attempts = [0,3,8][difficulty.rawValue]
        for i in puzzle.clues.indices.shuffled(using:&rng).prefix(attempts) {
            let original = puzzle.clues[i]
            if Bool.random(using:&rng) { puzzle.clues[i].area = nil } else { puzzle.clues[i].shape = .any }
            let check = puzzle.solve()
            if check.count != 1 || check.exhausted { puzzle.clues[i] = original }
        }
        return puzzle
    }
}

struct PatchesRecord: Codable {
    var id = UUID()
    let puzzle: PatchesPuzzle
    let requested: Int
    var activeSeconds = 0.0
    var corrections = 0, hints = 0, resets = 0
    var intervals: [Double] = []
    var solved = false
    var targets: [Double] = [0.25,0.65,1.15]
    var forecast: [Double] = []
    var verdict: String?
    var nextHintAt = 30.0
    var effort: Double? {
        guard solved, activeSeconds.isFinite, activeSeconds > 0, corrections >= 0, hints >= 0, resets >= 0,
              intervals.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let cells = Double(puzzle.size*puzzle.size)
        let pauses = intervals.filter { $0 >= 2 }
        return min(4, 0.45*log1p(4*Double(corrections)/cells) + 0.10*log1p(activeSeconds/cells)
                   + 0.25*Double(hints) + 0.10*log1p(Double(resets))
                   + 0.25*log1p(4*Double(pauses.count)/cells) + 0.15*log1p(pauses.reduce(0,+)/cells))
    }
}
struct PatchesSession: Codable {
    var record: PatchesRecord
    var placed: [PatchRect] = []
    var undo: [[PatchRect]] = []
}
struct PatchesSnapshot: Codable {
    var sessions: [String: PatchesSession] = [:]
    var records: [PatchesRecord] = []
    var selected = 0
}

// Separate feature space and training history: Zip path geometry cannot describe rectangles.
struct PatchesModel {
    var weights = [Double](repeating:0,count:7)
    var targets = [0.25,0.65,1.15]
    var count = 0
    var evidence: [(x:[Double], residual:Double, weight:Double)] = []
    static func prior(_ x:[Double]) -> Double { max(0.08, 0.1+0.25*x[1]+0.8*x[3]+0.35*x[4]-0.3*x[2]) }
    init(_ records:[PatchesRecord]) {
        var seen = Set<UUID>()
        let valid = records.reversed().filter { seen.insert($0.id).inserted && $0.effort != nil }.prefix(200)
        count = valid.count
        guard count > 0 else { return }
        let rows = valid.enumerated().map { age,r in (r.puzzle.features,r.effort!,pow(0.5,Double(age)/60)*(r.hints > 0 ? 0.65 : 1)) }
        let total = rows.reduce(0) { $0+$1.2 }
        let ordered = rows.sorted { $0.1 < $1.1 }
        for (i,q) in [0.15,0.5,0.85].enumerated() {
            var cumulative = 0.0
            for row in ordered { cumulative += row.2; if cumulative >= total*q {
                let blend = min(1,Double(count)/20); targets[i] = (1-blend)*targets[i]+blend*row.1; break
            } }
        }
        targets[1] = max(targets[1],targets[0]+0.05); targets[2] = max(targets[2],targets[1]+0.05)
        let n = weights.count
        var a = Array(repeating:Array(repeating:0.0,count:n),count:n), b = Array(repeating:0.0,count:n)
        for (x,y,w) in rows { for j in 0..<n {
            b[j] += w/total*x[j]*(y-Self.prior(x))
            for k in 0..<n { a[j][k] += w/total*x[j]*x[k] }
        } }
        for j in 0..<n { a[j][j] += j == 0 ? 0.001 : max(0.002,0.04/sqrt(Double(count))) }
        for j in 0..<n { for k in 0...j {
            var value = a[j][k]
            for l in 0..<k { value -= a[j][l]*a[k][l] }
            a[j][k] = j == k ? sqrt(max(value,1e-12)) : value/a[k][k]
        } }
        for j in 0..<n { var v = b[j]; for k in 0..<j { v -= a[j][k]*weights[k] }; weights[j] = v/a[j][j] }
        for j in (0..<n).reversed() { var v = weights[j]; for k in j+1..<n { v -= a[k][j]*weights[k] }; weights[j] = v/a[j][j] }
        evidence = rows.map { x,y,w in
            var z = Array(repeating:0.0,count:n)
            for j in 0..<n { var v = x[j]; for k in 0..<j { v -= a[j][k]*z[k] }; z[j] = v/a[j][j] }
            let leverage = min(0.95,w/total*z.reduce(0) { $0+$1*$1 })
            let fitted = Self.prior(x)+zip(x,weights).reduce(0) { $0+$1.0*$1.1 }
            return (x,(y-fitted)/(1-leverage),w)
        }
    }
    func predict(_ p:PatchesPuzzle) -> Double {
        let x = p.features
        return max(0,min(4,Self.prior(x)+min(1,Double(count)/8)*zip(x,weights).reduce(0) { $0+$1.0*$1.1 }))
    }
    func forecast(_ p:PatchesPuzzle) -> AdaptiveDifficulty.Forecast {
        let x = p.features, mean = predict(p)
        let low = (targets[0]+targets[1])/2, high = (targets[1]+targets[2])/2
        let scale = max(0.04,(targets[2]-targets[0])*0.15)
        var probs = [0.5,0.5,0.5], total = 1.5
        for row in evidence {
            let distance = zip(x,row.x).reduce(0) { $0+pow($1.0-$1.1,2) }
            let w = row.weight*exp(-4*distance), value = mean+row.residual
            let easy = 1/(1+exp(max(-50,min(50,(value-low)/scale))))
            let belowHard = 1/(1+exp(max(-50,min(50,(value-high)/scale))))
            probs[0] += w*easy; probs[1] += w*(belowHard-easy); probs[2] += w*(1-belowHard); total += w
        }
        return AdaptiveDifficulty.Forecast(probabilities:probs.map { $0/total },effort:mean,support:total-1.5)
    }
    func select(_ d:Difficulty, excluding:[PatchesPuzzle], using rng:inout PuzzleRandom) -> PatchesPuzzle {
        var pool:[PatchesPuzzle] = []
        for _ in 0..<6 { for preset in Difficulty.allCases {
            let p = PatchesPuzzle.make(preset,using:&rng)
            if !excluding.contains(p) { pool.append(p) }
        } }
        if pool.isEmpty { pool.append(PatchesPuzzle.make(d,using:&rng)) }
        return pool.max { a,b in
            let fa = forecast(a), fb = forecast(b)
            if fa.qualifies(d) != fb.qualifies(d) { return !fa.qualifies(d) }
            // Until data arrives, rank by distance from a structural target.
            if count == 0 { return abs(fa.effort-targets[d.rawValue]) > abs(fb.effort-targets[d.rawValue]) }
            return fa.utility(d,targets:targets) < fb.utility(d,targets:targets)
        }!
    }
    static func verdict(_ r:PatchesRecord) -> String? {
        guard let e = r.effort, let t = AdaptiveDifficulty.validTargets(r.targets) else { return nil }
        return e < (t[0]+t[1])/2 ? "easy" : e < (t[1]+t[2])/2 ? "medium" : "hard"
    }
}
