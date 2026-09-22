import Foundation

// Personalized ridge regression of observed effort, never of the requested label.
struct AdaptiveDifficulty {
    static let version = 3
    static let names = ["cells", "walls", "clues", "solutionTurns", "maxCheckpointGap", "junctionCells", "checkpointDetour", "checkpointGapSpread", "forcedCells"]
    // Original ten coefficients plus three interactions between puzzle features.
    var weights = [Double](repeating: 0, count: 13)
    var sampleCount = 0
    var targets = [0.25, 0.65, 1.15]
    private var evidence: [(x: [Double], residual: Double, weight: Double)] = []
    private var featureScales = [Double](repeating: 0.1, count: 13)

    struct Forecast {
        let probabilities: [Double] // Easy, Medium, Hard; estimates, not guarantees.
        let effort: Double
        let support: Double
        func qualifies(_ difficulty: Difficulty) -> Bool {
            if difficulty == .easy { return probabilities[0] >= 0.85 && probabilities[2] <= 0.05 }
            return probabilities[difficulty.rawValue] >= 0.70
        }
        func utility(_ difficulty: Difficulty, targets: [Double]) -> Double {
            // A hard surprise costs more than a medium miss on Easy.
            switch difficulty {
            case .easy: return probabilities[0] - 3*probabilities[2] - 0.03*effort
            case .medium: return probabilities[1] - 0.25*probabilities[2] - 0.2*abs(effort-targets[1])
            case .hard: return probabilities[2] + 0.01*effort - 0.03*abs(effort-targets[2])
            }
        }
    }

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
            let reusable = (2...4).contains(record.generatorVersion) && Self.names.allSatisfy { record.features[$0] != nil }
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
        for j in 1..<n {
            let mean = rows.reduce(0) { $0 + $1.2*$1.0[j] }/total
            featureScales[j] = max(0.08, sqrt(rows.reduce(0) { $0 + $1.2*pow($1.0[j]-mean, 2) }/total))
        }
        evidence = rows.map { x, y, weight in
            // Leave-one-out ridge residuals avoid treating a fitted example as an
            // independent success. Solve L z = x to obtain its leverage.
            var z = [Double](repeating: 0, count: n)
            for j in 0..<n {
                var value = x[j]
                for k in 0..<j { value -= matrix[j*n+k]*z[k] }
                z[j] = value/matrix[j*n+j]
            }
            let leverage = min(0.95, weight/total*z.reduce(0) { $0+$1*$1 })
            let fitted = Self.prior(x) + zip(weights, x).reduce(0) { $0+$1.0*$1.1 }
            return (x, (y-fitted)/(1-leverage), weight)
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
        let boundaries = Self.validTargets(record.difficultyTargets) ?? targets
        if observed < (boundaries[0]+boundaries[1])/2 { return .easy }
        if observed < (boundaries[1]+boundaries[2])/2 { return .medium }
        return .hard
    }
    static func validTargets(_ values: [Double]?) -> [Double]? {
        guard let values, values.count == 3, values.allSatisfy({ $0.isFinite && $0 >= 0 }),
              values[0] < values[1], values[1] < values[2] else { return nil }
        return values
    }
    func forecast(_ puzzle: Puzzle) -> Forecast {
        let x = Self.vector(puzzle), mean = predict(puzzle)
        let low = (targets[0]+targets[1])/2, high = (targets[1]+targets[2])/2
        let smoothing = max(0.005, min(0.08, 0.25*min(targets[1]-targets[0], targets[2]-targets[1])))
        func distribution(_ center: Double, _ width: Double) -> [Double] {
            func cdf(_ boundary: Double) -> Double { 0.5*(1+erf((boundary-center)/(width*sqrt(2)))) }
            let a = cdf(low), b = cdf(high)
            return [a, max(0, b-a), 1-b]
        }
        var mass = [Double](repeating: 0, count: 3), total = 0.0, nearest = 0.0
        for row in evidence {
            // Structural similarity localizes risk: unpredictable boards must not
            // borrow certainty from reliably easy boards elsewhere in the history.
            let distance = (1...9).reduce(0.0) { $0 + pow((x[$1]-row.x[$1])/featureScales[$1], 2) }/9
            // A broad kernel would let dissimilar boards dominate a forecast.
            // This narrower kernel keeps feedback local to comparable structures.
            let similarity = exp(-3*distance)
            nearest = max(nearest, similarity)
            let weight = row.weight*similarity
            let probabilities = distribution(mean+row.residual, smoothing)
            for i in 0..<3 { mass[i] += weight*probabilities[i] }
            total += weight
        }
        // Sparse/novel candidates retain broad uncertainty instead of fabricated
        // confidence. Recent outcomes progressively replace this weak prior.
        let priorWeight = 3 + 9*(1-nearest)
        let prior = distribution(mean, 0.4)
        for i in 0..<3 { mass[i] = (mass[i]+priorWeight*prior[i])/(total+priorWeight) }
        return Forecast(probabilities: mass, effort: mean, support: total/(total+priorWeight))
    }
    func choose(_ difficulty: Difficulty, from candidates: [Puzzle]) -> Puzzle {
        precondition(!candidates.isEmpty)
        var best = candidates[0], bestForecast = forecast(best)
        for candidate in candidates.dropFirst() {
            let next = forecast(candidate)
            let qualifies = next.qualifies(difficulty), bestQualifies = bestForecast.qualifies(difficulty)
            if (qualifies && !bestQualifies) || (qualifies == bestQualifies && next.utility(difficulty, targets: targets) > bestForecast.utility(difficulty, targets: targets)) {
                best = candidate; bestForecast = next
            }
        }
        return best
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
        var candidates = batches.flatMap { $0 }.filter { !excluded.contains($0.solution) }
        // Search beyond the first batch when it does not meet the requested level.
        // Easy gets progressively more guidance, not merely more random boards.
        for round in 0..<3 {
            if !candidates.isEmpty && forecast(choose(difficulty, from: candidates)).qualifies(difficulty) { break }
            for _ in 0..<6 {
                var candidate = Puzzle.make(difficulty)
                if difficulty == .easy { candidate = candidate.guided(maxGap: [4, 3, 2][round], blockedFraction: [0.25, 0.5, 0.75][round]) }
                if !excluded.contains(candidate.solution) { candidates.append(candidate) }
            }
        }
        if !candidates.isEmpty { return choose(difficulty, from: candidates) }
        var fresh = Puzzle.make(difficulty)
        while excluded.contains(fresh.solution) { fresh = Puzzle.make(difficulty) }
        return fresh
    }
}
