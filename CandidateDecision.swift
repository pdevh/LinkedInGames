import Foundation

struct CandidateObservation: Codable {
    let candidateID: String
    let puzzleJSON: String
    let rawFeatures: [String:Double]
    let scaledFeatures: [Double]
    let structuralPrediction: Double
    let unblendedPrediction: Double
    let blendedEffort: Double
    let probabilities: [Double]
    let support: Double
    var eligible: Bool
    var exclusionReason: String?
    let generationSeconds: Double
    let evaluationSeconds: Double
    let preset: Int
}
struct CandidateDecision: Codable {
    var schemaVersion = 1
    let decisionID: UUID
    let generationStartedAt: Date
    var generationEndedAt: Date
    let requested: Int
    var candidates: [CandidateObservation]
    var selectedID: String?
    var qualified: Bool?
    var fallback: Bool?
    var selectionReason: String?
    let weights: [Double]
    let targets: [Double]
    var trainingIDs: [UUID] = []
    var intent = "normal"
    var expectedCandidateCount: Int { candidates.count }
    static func content<T: Encodable>(_ puzzle: T) -> (String,String) {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        // All puzzle types contain finite integers and enums; failure is a programmer error.
        let data = try! encoder.encode(puzzle)
        return (DifficultyJournal.hash(data),String(data:data,encoding:.utf8)!)
    }
}
