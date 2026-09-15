import Foundation

// Personalized ridge regression of observed effort, never of the requested label.
struct AdaptiveDifficulty {
    static let version = 2
    static let names = ["cells", "walls", "clues", "solutionTurns", "maxCheckpointGap", "junctionCells", "checkpointDetour", "checkpointGapSpread", "forcedCells"]
    // Original ten coefficients plus three interactions between puzzle features.
    var weights = [Double](repeating: 0, count: 13)
    var sampleCount = 0
    var targets = [0.25, 0.65, 1.15]

    static func vector(_ p: Puzzle, features: [String: Int]? = nil) -> [Double] {
        let f = features ?? PlayStatistics.extractFeatures(p)
        let cells = Double(p.size*p.size)
        let scales = [49, Double(2*p.size*(p.size-1)), cells, cells, cells, cells, cells, cells*cells, cells]
        let x = [1.0] + zip(names, scales).map { min(2, Double(f[$0.0] ?? 0) / $0.1) }
        return x + [x[4]*x[6], x[5]*x[7], x[2]*x[3]]
    }
    static func prior(_ x: [Double]) -> Double {
        max(0.05, 0.15 + 0.45*x[4] + 0.45*x[5] + 0.6*x[6] + 0.5*x[7] - 0.5*x[9])
    }
    static func effort(_ r: PlayStatistics) -> Double? {
        guard r.outcome == "solved", var m = r.measurements, m.collectedFromStart,
              r.activeSeconds.isFinite, r.activeSeconds > 0,
              r.actions.values.allSatisfy({ $0 >= 0 }),
              m.moveIntervals.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        // Derive labels from raw telemetry so stale saved summaries cannot train the model.
        var record = r
        record.updateMeasurements()
        m = record.measurements!
        let values = [m.activeSecondsPerCell, m.backtrackedCellsPerCell, m.pausesPerCell, m.pauseSecondsPerCell]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        return min(4, 0.45*log1p(4*m.backtrackedCellsPerCell)
            + 0.25*log1p(4*m.pausesPerCell) + 0.15*log1p(m.pauseSecondsPerCell)
            + 0.10*log1p(m.activeSecondsPerCell)
            + 0.25*Double(r.actions["hint"] ?? 0) + 0.10*log1p(Double(r.actions["reset"] ?? 0)))
    }
    init(records: [PlayStatistics]) {
        // Skips and incomplete telemetry must not displace valid training examples.
        var recent: [(PlayStatistics, Double)] = []
        var seen = Set<UUID>()
        for record in records.reversed() {
            guard seen.insert(record.id).inserted, let y = Self.effort(record) else { continue }
            recent.append((record, y))
            if recent.count == 200 { break }
        }
        sampleCount = recent.count
        guard sampleCount > 0 else { return }
        let rows = recent.enumerated().map { age, item -> ([Double], Double, Double) in
            let (record, y) = item
            let reusable = (2...3).contains(record.generatorVersion) && Self.names.allSatisfy { record.features[$0] != nil }
            let x = Self.vector(record.puzzle, features: reusable ? record.features : nil)
            // Recent games track improving skill. Hints remain evidence of difficulty,
            // with reduced confidence because assistance changes subsequent play.
            let confidence = (record.actions["hint"] ?? 0) > 0 ? 0.65 : 1.0
            return (x, y, confidence * pow(0.5, Double(age)/60))
        }
        let total = rows.reduce(0) { $0 + $1.2 }
        let sorted = rows.sorted { $0.1 < $1.1 }
        func quantile(_ fraction: Double) -> Double {
            var cumulative = 0.0
            for row in sorted {
                cumulative += row.2
                if cumulative >= total*fraction { return row.1 }
            }
            return sorted.last!.1
        }
        let confidence = min(1, Double(sampleCount)/20)
        for (i, q) in [0.15, 0.5, 0.85].enumerated() {
            targets[i] = (1-confidence)*targets[i] + confidence*quantile(q)
        }
        targets[1] = max(targets[1], targets[0] + 0.05)
        targets[2] = max(targets[2], targets[1] + 0.05)

        // Solve the small positive-definite ridge system directly. No 250-pass scan.
        let n = weights.count
        var matrix = [Double](repeating: 0, count: n*n)
        var rhs = [Double](repeating: 0, count: n)
        for (x, y, weight) in rows {
            let w = weight/total, residual = y-Self.prior(x)
            for j in 0..<n {
                rhs[j] += w*x[j]*residual
                for k in 0...j { matrix[j*n+k] += w*x[j]*x[k] }
            }
        }
        let penalty = max(0.002, 0.04/sqrt(Double(sampleCount)))
        for j in 0..<n { matrix[j*n+j] += j == 0 ? 0.001 : penalty }
        // Cholesky factorization, then forward/back substitution.
        for j in 0..<n {
            for k in 0...j {
                var value = matrix[j*n+k]
                for l in 0..<k { value -= matrix[j*n+l]*matrix[k*n+l] }
                matrix[j*n+k] = j == k ? sqrt(max(value, 1e-12)) : value/matrix[k*n+k]
            }
        }
        for j in 0..<n {
            var value = rhs[j]
            for k in 0..<j { value -= matrix[j*n+k]*weights[k] }
            weights[j] = value/matrix[j*n+j]
        }
        for j in (0..<n).reversed() {
            var value = weights[j]
            for k in (j+1)..<n { value -= matrix[k*n+j]*weights[k] }
            weights[j] = value/matrix[j*n+j]
        }
    }
    func predict(_ puzzle: Puzzle) -> Double {
        let x = Self.vector(puzzle)
        let blend = min(1, Double(sampleCount)/8)
        return max(0, min(4, Self.prior(x) + blend*zip(weights,x).reduce(0) { $0 + $1.0*$1.1 }))
    }
    // Judge the completed play, not the board's original prediction or button label.
    // Use the pre-solve targets so the result cannot move its own boundaries.
    func experiencedDifficulty(for record: PlayStatistics) -> Difficulty? {
        guard let observed = Self.effort(record) else { return nil }
        if observed < (targets[0]+targets[1])/2 { return .easy }
        if observed < (targets[1]+targets[2])/2 { return .medium }
        return .hard
    }
    func choose(_ difficulty: Difficulty, from candidates: [Puzzle]) -> Puzzle {
        precondition(!candidates.isEmpty)
        var ranked: [(index: Int, puzzle: Puzzle, score: Double)] = []
        for (index, puzzle) in candidates.enumerated() { ranked.append((index, puzzle, predict(puzzle))) }
        ranked.sort { a, b in a.score == b.score ? a.index < b.index : a.score < b.score }
        // Disjoint bands prevent all buttons chasing the same candidate when the
        // available batch cannot reach a historical target. No claim of certainty.
        let lower = difficulty.rawValue*ranked.count/3
        let upper = max(lower+1, (difficulty.rawValue+1)*ranked.count/3)
        return ranked[lower..<upper].min { abs($0.2-targets[difficulty.rawValue]) < abs($1.2-targets[difficulty.rawValue]) }!.1
    }
    func select(_ difficulty: Difficulty, excluding previous: [[Cell]]) -> Puzzle {
        let excluded = Set(previous)
        // Three bounded workers, six candidates each. No quality-reducing early exit.
        let lock = NSLock()
        var batches = [[Puzzle]](repeating: [], count: 3)
        DispatchQueue.concurrentPerform(iterations: 3) { worker in
            let candidates = (0..<6).map { _ in Puzzle.make(Difficulty.allCases[worker]) }
            lock.lock(); batches[worker] = candidates; lock.unlock()
        }
        let candidates = batches.flatMap { $0 }.filter { !excluded.contains($0.solution) }
        if !candidates.isEmpty { return choose(difficulty, from: candidates) }
        var fresh = Puzzle.make(difficulty)
        while excluded.contains(fresh.solution) { fresh = Puzzle.make(difficulty) }
        return fresh
    }
}
