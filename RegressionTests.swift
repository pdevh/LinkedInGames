import Foundation

// Original array-based search retained only as a correctness oracle.
extension Puzzle {
    func referenceSolutions(budget: Int = 80_000) -> (count: Int, exhausted: Bool, alternative: [Cell]) {
        let cells = (0..<(size * size)).map { Cell(x: $0 % size, y: $0 / size) }
        let neighbors = cells.map { a in
            cells.indices.filter { a.adjacent(to: cells[$0]) && !walls.contains(Edge(a, cells[$0])) }
        }
        let numbers = cells.map { clues[$0] ?? 0 }
        let start = cells.firstIndex(of: solution[0])!
        let end = cells.firstIndex(of: solution.last!)!
        let all = (UInt64(1) << cells.count) - 1
        var route = [start], count = 0, nodes = 0, exhausted = true
        var alternative: [Cell] = []
        func search(_ head: Int, _ visited: UInt64, _ next: Int) {
            if count >= 2 || !exhausted { return }
            nodes += 1
            if nodes > budget { exhausted = false; return }
            if head == end {
                if visited == all {
                    count += 1
                    let result = route.map { cells[$0] }
                    if result != solution { alternative = result }
                }
                return
            }
            // Every unvisited square must remain connected to the current head.
            let remaining = all & ~visited
            var reached: UInt64 = 0, frontier = [head]
            while let at = frontier.popLast() {
                for neighbor in neighbors[at] {
                    let bit = UInt64(1) << neighbor
                    if remaining & bit != 0 && reached & bit == 0 {
                        reached |= bit; frontier.append(neighbor)
                    }
                }
            }
            if reached != remaining { return }
            for neighbor in neighbors[head] {
                let bit = UInt64(1) << neighbor
                if visited & bit != 0 { continue }
                let number = numbers[neighbor]
                if number != 0 && number != next { continue }
                if neighbor == end && visited | bit != all { continue }
                route.append(neighbor)
                search(neighbor, visited | bit, next + (number == 0 ? 0 : 1))
                route.removeLast()
            }
        }
        search(start, UInt64(1) << start, 2)
        return (count, exhausted, alternative)
    }
}

func runAdaptiveRegressionTests() {
    func fixture(_ size: Int) -> Puzzle {
        let path = (0..<size).flatMap { y in
            (0..<size).map { x in Cell(x: y.isMultiple(of: 2) ? x : size-1-x, y: y) }
        }
        let edges = Set(zip(path, path.dropFirst()).map { Edge($0, $1) })
        var walls = Set<Edge>()
        for c in path {
            for neighbor in [Cell(x: c.x+1, y: c.y), Cell(x: c.x, y: c.y+1)] {
                if neighbor.x < size && neighbor.y < size && !edges.contains(Edge(c, neighbor)) {
                    walls.insert(Edge(c, neighbor))
                }
            }
        }
        return Puzzle(size: size, solution: path, clues: [path.first!: 1, path.last!: 2], walls: walls)
    }
    // Exhaustively compare all 512 wall subsets of a fixed 4x4 path.
    let small = fixture(4)
    let walls = small.walls.sorted {
        let a = [$0.a.y, $0.a.x, $0.b.y, $0.b.x], b = [$1.a.y, $1.a.x, $1.b.y, $1.b.x]
        return a.lexicographicallyPrecedes(b)
    }
    for bits in 0..<(1 << walls.count) {
        let p = Puzzle(size: 4, solution: small.solution, clues: small.clues,
                       walls: Set(walls.enumerated().filter { bits & (1 << $0.offset) != 0 }.map { $0.element }))
        for budget in [1, 80_000] {
            let a = p.checkSolutions(budget: budget), b = p.referenceSolutions(budget: budget)
            precondition(a.count == b.count && a.exhausted == b.exhausted && a.alternative == b.alternative,
                         "Bitset solver changed uniqueness or budget semantics")
        }
        let f = PlayStatistics.extractFeatures(p)
        let degrees = p.solution.map { a in p.solution.filter { a.adjacent(to: $0) && !p.walls.contains(Edge(a, $0)) }.count }
        precondition(f["junctionCells"] == degrees.filter { $0 >= 3 }.count)
        precondition(f["forcedCells"] == degrees.filter { $0 <= 2 }.count)
    }
    for difficulty in Difficulty.allCases {
        for seed in 0..<10 {
            var random = PuzzleRandom(seed: UInt64(seed)), replay = PuzzleRandom(seed: UInt64(seed))
            let p = Puzzle.make(difficulty, using: &random)
            let repeated = Puzzle.make(difficulty, using: &replay)
            precondition(p.solution == repeated.solution && p.walls == repeated.walls && p.clues == repeated.clues)
            let oracle = p.referenceSolutions()
            precondition(oracle.exhausted && oracle.count == 1, "Generated puzzle must remain unique under the original solver")
            let statistics = PlayStatistics(puzzle: p, difficulty: difficulty)
            precondition(AdaptiveDifficulty.vector(p, features: statistics.features) == AdaptiveDifficulty.vector(p))
        }
    }
    func record(_ puzzle: Puzzle, difficult: Bool, label: Difficulty = .hard) -> PlayStatistics {
        var r = PlayStatistics(puzzle: puzzle, difficulty: label)
        let cells = puzzle.size*puzzle.size
        r.outcome = "solved"; r.activeSeconds = Double(cells)*(difficult ? 3 : 0.25)
        r.actions["move"] = cells
        if difficult {
            r.actions["backtrack"] = cells*2
            r.actions["hint"] = 2
            r.measurements?.moveIntervals = [Double](repeating: 4, count: cells/2)
        }
        r.updateMeasurements()
        return r
    }
    let a = fixture(5), b = fixture(7)
    var training: [PlayStatistics] = []
    for _ in 0..<60 { training.append(record(a, difficult: false)); training.append(record(b, difficult: true, label: .easy)) }
    let model = AdaptiveDifficulty(records: training)
    precondition(model.sampleCount == 120)
    precondition(model.predict(a) < 0.3 && model.predict(b) > 1.2,
                 "Observed effort must override the requested difficulty")
    let inverted = AdaptiveDifficulty(records: (0..<60).flatMap { _ in
        [record(a, difficult: true), record(b, difficult: false)]
    })
    precondition(inverted.predict(a) > 1.2 && inverted.predict(b) < 0.3,
                 "Feature coefficients must learn either direction")
    let judge = AdaptiveDifficulty(records: [])
    precondition(judge.experiencedDifficulty(for: record(a, difficult: false, label: .hard)) == .easy)
    precondition(judge.experiencedDifficulty(for: record(a, difficult: true, label: .easy)) == .hard)
    var moderate = record(a, difficult: false)
    moderate.actions["backtrack"] = a.solution.count/2
    precondition(judge.experiencedDifficulty(for: moderate) == .medium)
    var unrated = moderate; unrated.measurements?.collectedFromStart = false
    precondition(judge.experiencedDifficulty(for: unrated) == nil)
    moderate.experiencedDifficulty = "medium"
    let restoredVerdict = try! JSONDecoder().decode(PlayStatistics.self, from: JSONEncoder().encode(moderate))
    precondition(restoredVerdict.experiencedDifficulty == "medium")
    let initial = AdaptiveDifficulty(records: [])
    let first = AdaptiveDifficulty(records: [record(a, difficult: false)])
    precondition(first.predict(a) < initial.predict(a), "Learning must begin on the first solve")
    precondition(AdaptiveDifficulty(records: Array(repeating: training[0], count: 200)).sampleCount == 1)
    var skipped = record(a, difficult: true); skipped.outcome = "skipped"
    precondition(AdaptiveDifficulty(records: training + Array(repeating: skipped, count: 250)).sampleCount == 120)
    var incomplete = training[0]; incomplete.measurements?.collectedFromStart = false
    var invalid = training[0]; invalid.activeSeconds = .infinity
    var invalidPause = training[0]; invalidPause.measurements?.moveIntervals = [.nan]
    precondition(AdaptiveDifficulty(records: [incomplete, invalid, invalidPause]).sampleCount == 0)
    var stale = training[0]; stale.measurements?.activeSecondsPerCell = 999
    precondition(AdaptiveDifficulty.effort(stale) == AdaptiveDifficulty.effort(training[0]))
    var hinted = training[0]; hinted.actions["hint"] = 1
    precondition(AdaptiveDifficulty.effort(hinted)! > AdaptiveDifficulty.effort(training[0])!)
    let recovering = (0..<100).map { _ in record(a, difficult: true) }
        + (0..<100).map { _ in record(a, difficult: false) }
    let recentModel = AdaptiveDifficulty(records: recovering)
    let reversedModel = AdaptiveDifficulty(records: Array(recovering.reversed()))
    precondition(recentModel.predict(a) < reversedModel.predict(a), "Recent skill must outweigh old effort")
    let reopened = try! JSONDecoder().decode([PlayStatistics].self, from: JSONEncoder().encode(training))
    precondition(AdaptiveDifficulty(records: reopened).weights == model.weights, "Learning must survive restart")
    precondition(model.weights.allSatisfy { $0.isFinite })
    precondition(model.targets[0] < model.targets[1] && model.targets[1] < model.targets[2])
    let pool = (3...7).map { fixture($0) }
    let easy = model.predict(model.choose(.easy, from: pool))
    let medium = model.predict(model.choose(.medium, from: pool))
    let hard = model.predict(model.choose(.hard, from: pool))
    precondition(easy < medium && medium < hard, "Candidate bands must separate available difficulty")
    // Independent gradient check: the fitted coefficients must minimize the stated ridge objective.
    let n = model.weights.count, penalty = max(0.002, 0.04/sqrt(Double(training.count)))
    var gradient = model.weights.enumerated().map { $0.element*($0.offset == 0 ? 0.001 : penalty) }
    var total = 0.0
    var dataGradient = [Double](repeating: 0, count: n)
    for (age, r) in training.reversed().enumerated() {
        let x = AdaptiveDifficulty.vector(r.puzzle, features: r.features)
        let weight = ((r.actions["hint"] ?? 0) > 0 ? 0.65 : 1)*pow(0.5, Double(age)/60)
        let residual = AdaptiveDifficulty.prior(x) + zip(x, model.weights).reduce(0) { $0 + $1.0*$1.1 } - AdaptiveDifficulty.effort(r)!
        total += weight
        for j in 0..<n { dataGradient[j] += weight*residual*x[j] }
    }
    for j in 0..<n { gradient[j] += dataGradient[j]/total }
    precondition(gradient.allSatisfy { abs($0) < 1e-8 }, "Direct solve failed ridge optimality")
    print("512 solver equivalence cases, 30 seeded generation/replay cases, feature equivalence, telemetry learning/reversal, recency, filtering, restart, ranking, and ridge optimality passed")
}
