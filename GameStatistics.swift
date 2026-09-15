import Foundation

enum StatisticsPeriod: Int { case allTime, last30Days }
enum StatisticsResultFilter: Int { case all, matched, missed, unrated }

struct GameStatistics {
    struct Game {
        let record: PlayStatistics
        let intended: Difficulty?
        let experienced: Difficulty?
        var isRated: Bool { intended != nil && experienced != nil }
        var matched: Bool { isRated && intended == experienced }
        var hasValidTelemetry: Bool { AdaptiveDifficulty.effort(record) != nil }
        var date: Date { record.endedAt ?? record.startedAt ?? record.createdAt }
    }
    struct FeatureInsight {
        let name: String
        // Expected effort change over one observed standard deviation, with
        // interactions included in the local model sensitivity. Not a causal effect.
        let effect: Double
    }
    let games: [Game]
    let skippedCount: Int
    let model: AdaptiveDifficulty
    let training: [PlayStatistics]
    let features: [FeatureInsight]
    let period: StatisticsPeriod

    static func difficulty(_ name: String?) -> Difficulty? {
        Difficulty.allCases.first { $0.title.lowercased() == name?.lowercased() }
    }
    init(records: [PlayStatistics], period: StatisticsPeriod = .allTime, now: Date = Date()) {
        self.period = period
        var seen = Set<UUID>()
        let unique = records.reversed().filter { seen.insert($0.id).inserted }.reversed()
        let cutoff = now.addingTimeInterval(-30*24*60*60)
        let scoped = unique.filter {
            let date = $0.endedAt ?? $0.startedAt ?? $0.createdAt
            return period == .allTime || (date >= cutoff && date <= now)
        }
        games = scoped.filter { $0.outcome == "solved" }.map {
            Game(record: $0, intended: Self.difficulty($0.difficulty), experienced: Self.difficulty($0.experiencedDifficulty))
        }.sorted { $0.date == $1.date ? $0.record.id.uuidString < $1.record.id.uuidString : $0.date < $1.date }
        skippedCount = scoped.filter { $0.outcome == "skipped" }.count
        model = AdaptiveDifficulty(records: Array(unique))
        training = Array(unique.filter { AdaptiveDifficulty.effort($0) != nil }.suffix(200))
        features = Self.featureInsights(model: model, records: training)
    }
    var rated: [Game] { games.filter { $0.isRated } }
    var matchedCount: Int { rated.filter { $0.matched }.count }
    var unratedCount: Int { games.count-rated.count }
    var matchRate: Double? { rated.isEmpty ? nil : Double(matchedCount)/Double(rated.count) }
    var medianActiveSeconds: Double? { Self.median(games.filter { $0.hasValidTelemetry }.map { $0.record.activeSeconds }) }
    var matrix: [[Int]] {
        var counts = [[Int]](repeating: [Int](repeating: 0, count: 3), count: 3)
        for game in rated { counts[game.intended!.rawValue][game.experienced!.rawValue] += 1 }
        return counts
    }
    func recent(_ filter: StatisticsResultFilter) -> [Game] {
        Array(games.reversed().filter {
            switch filter {
            case .all: return true
            case .matched: return $0.matched
            case .missed: return $0.isRated && !$0.matched
            case .unrated: return !$0.isRated
            }
        }.prefix(10))
    }
    static func median(_ values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite }.sorted()
        guard !sorted.isEmpty else { return nil }
        let i = sorted.count/2
        return sorted.count.isMultiple(of: 2) ? (sorted[i-1]+sorted[i])/2 : sorted[i]
    }
    private static func featureInsights(model: AdaptiveDifficulty, records: [PlayStatistics]) -> [FeatureInsight] {
        guard model.sampleCount >= 8 else { return [] }
        let vectors = records.map { AdaptiveDifficulty.vector($0.puzzle) }
        let labels = ["Larger boards", "More walls", "More checkpoints", "More turns", "Longer checkpoint gaps",
                      "More junctions", "Longer checkpoint detours", "Less even checkpoint spacing", "More forced cells"]
        let blend = min(1, Double(model.sampleCount)/8)
        let priorSlopes = [0.0, 0, 0, 0, 0.45, 0.45, 0.6, 0.5, 0, -0.5]
        var insights: [FeatureInsight] = []
        for j in 1...9 {
            let mean = vectors.reduce(0) { $0+$1[j] }/Double(vectors.count)
            let deviation = sqrt(vectors.reduce(0) { $0+pow($1[j]-mean, 2) }/Double(vectors.count))
            guard deviation > 1e-8 else { continue }
            var sensitivity = 0.0
            for x in vectors {
                let prediction = AdaptiveDifficulty.prior(x) + blend*zip(model.weights, x).reduce(0) { $0+$1.0*$1.1 }
                guard prediction > 0 && prediction < 4 else { continue }
                let prior = 0.15 + 0.45*x[4] + 0.45*x[5] + 0.6*x[6] + 0.5*x[7] - 0.5*x[9]
                var slope = (prior > 0.05 ? priorSlopes[j] : 0) + blend*model.weights[j]
                for (coefficient, a, b) in [(10,4,6), (11,5,7), (12,2,3)] {
                    if j == a { slope += blend*model.weights[coefficient]*x[b] }
                    if j == b { slope += blend*model.weights[coefficient]*x[a] }
                }
                sensitivity += slope
            }
            let effect = sensitivity/Double(vectors.count)*deviation
            if effect.isFinite && abs(effect) >= 0.001 { insights.append(FeatureInsight(name: labels[j-1], effect: effect)) }
        }
        return insights.sorted { abs($0.effect) > abs($1.effect) }
    }
}
