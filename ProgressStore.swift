import Foundation

struct AppSnapshot: Codable {
    var patches: PatchesSnapshot? = nil
    var progress: [String: SavedProgress] = [:]
    var records: [PlayStatistics] = []
}

final class ProgressStore {
    let url: URL
    var snapshot: AppSnapshot
    var onError: ((Error) -> Void)?
    private(set) var telemetry: GameplayTelemetry?
    private let queue = DispatchQueue(label: "zip.atomic-save", qos: .utility)
    init(url: URL, startTelemetry: Bool = true) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            do { snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url)) }
            catch { snapshot = try JSONDecoder().decode(AppSnapshot.self, from: Data(contentsOf: url.appendingPathExtension("backup"))) }
        } else {
            snapshot = AppSnapshot()
            for d in Difficulty.allCases {
                let key = "zip.progress.v1.\(d.rawValue)"
                if let data = UserDefaults.standard.data(forKey: key) {
                    snapshot.progress[key] = try JSONDecoder().decode(SavedProgress.self, from: data)
                }
            }
            if let data = UserDefaults.standard.data(forKey: "zip.statistics.v1") {
                snapshot.records = try JSONDecoder().decode([PlayStatistics].self, from: data)
            }
        }
        // Telemetry failure must not prevent offline gameplay or legacy decoding.
        do {
            let journal = try DifficultyJournal(url: url.deletingLastPathComponent().appendingPathComponent("difficulty.sqlite"))
            for terminal in try journal.terminalSnapshots() {
                if terminal.game == "zip", var record = try? JSONDecoder().decode(PlayStatistics.self, from:terminal.data) {
                    if let saved = snapshot.records.first(where: { $0.id == record.id }), saved.outcome != "inProgress" {
                        record = saved // JSON may contain feedback saved after the immutable terminal.
                    } else { snapshot.records.removeAll { $0.id == record.id }; snapshot.records.append(record) }
                    for key in Array(snapshot.progress.keys) where snapshot.progress[key]?.statistics?.id == record.id {
                        snapshot.progress[key]?.statistics = record
                        if record.outcome == "solved" {
                            snapshot.progress[key]?.completed = true; snapshot.progress[key]?.path = record.puzzle.solution
                            if snapshot.progress[key]?.solved.contains(where: { CandidateDecision.content($0).0 == CandidateDecision.content(record.puzzle).0 }) == false { snapshot.progress[key]?.solved.append(record.puzzle) }
                        } else { snapshot.progress.removeValue(forKey:key) }
                    }
                } else if terminal.game == "patches", var record = try? JSONDecoder().decode(PatchesRecord.self, from:terminal.data) {
                    if snapshot.patches == nil { snapshot.patches = PatchesSnapshot() }
                    if let saved = snapshot.patches?.records.first(where: { $0.id == record.id }), saved.solved || saved.endedAt != nil {
                        record = saved
                    } else { snapshot.patches?.records.removeAll { $0.id == record.id }; snapshot.patches?.records.append(record) }
                    for key in Array(snapshot.patches!.sessions.keys) where snapshot.patches?.sessions[key]?.record.id == record.id {
                        snapshot.patches?.sessions[key]?.record = record
                        if record.solved { snapshot.patches?.sessions[key]?.placed = record.puzzle.solution }
                        else { snapshot.patches?.sessions.removeValue(forKey:key) }
                    }
                }
            }
            var recoveredFeedback = false
            for index in snapshot.records.indices where DifficultyFeedbackCoordinator.needsRecovery(snapshot.records[index].feedback) {
                let recovered = DifficultyFeedbackCoordinator.recovery(snapshot.records[index].feedback)
                snapshot.records[index].feedback = recovered
                recoveredFeedback = true
            }
            for key in Array(snapshot.progress.keys) where snapshot.progress[key]?.completed == true && DifficultyFeedbackCoordinator.needsRecovery(snapshot.progress[key]?.statistics?.feedback) {
                let recovered = DifficultyFeedbackCoordinator.recovery(snapshot.progress[key]?.statistics?.feedback)
                snapshot.progress[key]?.statistics?.feedback = recovered
                recoveredFeedback = true
            }
            if snapshot.patches != nil {
                for index in snapshot.patches!.records.indices where DifficultyFeedbackCoordinator.needsRecovery(snapshot.patches!.records[index].feedback) {
                    let recovered = DifficultyFeedbackCoordinator.recovery(snapshot.patches!.records[index].feedback)
                snapshot.patches!.records[index].feedback = recovered
                    recoveredFeedback = true
                }
                for key in Array(snapshot.patches!.sessions.keys) where snapshot.patches!.sessions[key]?.record.solved == true && DifficultyFeedbackCoordinator.needsRecovery(snapshot.patches!.sessions[key]?.record.feedback) {
                    let recovered = DifficultyFeedbackCoordinator.recovery(snapshot.patches!.sessions[key]?.record.feedback)
                snapshot.patches!.sessions[key]?.record.feedback = recovered
                    recoveredFeedback = true
                }
            }
            if recoveredFeedback { save() }
        } catch { NSLog("Difficulty recovery unavailable: %@", String(describing:error)) }
        if startTelemetry {
            do { telemetry = try GameplayTelemetry(url: url.deletingLastPathComponent().appendingPathComponent("difficulty.sqlite")) }
            catch { NSLog("Difficulty capture unavailable: %@", String(describing:error)) }
        }
    }
    func save() {
        let captured = snapshot
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(captured)
                if let old = try? Data(contentsOf: url), (try? JSONDecoder().decode(AppSnapshot.self, from: old)) != nil {
                    try old.write(to: url.appendingPathExtension("backup"), options: .atomic)
                }
                try data.write(to: url, options: .atomic)
            } catch { DispatchQueue.main.async { self.onError?(error) } }
        }
    }
    func flush() { queue.sync {} }
}
