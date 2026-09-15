import Foundation

struct AppSnapshot: Codable {
    var progress: [String: SavedProgress] = [:]
    var records: [PlayStatistics] = []
}

final class ProgressStore {
    let url: URL
    var snapshot: AppSnapshot
    var onError: ((Error) -> Void)?
    private let queue = DispatchQueue(label: "zip.atomic-save", qos: .utility)
    init(url: URL) throws {
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
