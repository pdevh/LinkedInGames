import Foundation

/// ProgressStore owns the compatible save; this object owns the independent journal.
/// Absent supplied consent remains unknown and does not enable capture.
final class GameplayTelemetry {
    let journal: DifficultyJournal
    private let identity: TelemetryIdentity
    private let bootID = UUID()
    private var sessionID = UUID()
    private var lastForeground = Date()
    var lastError: Error?
    init(url: URL) throws {
        journal = try DifficultyJournal(url:url)
        identity = try TelemetryIdentity.load()
    }
    func foreground() {
        let now = Date()
        if now.timeIntervalSince(lastForeground) > 1800 {
            record(game:"system",serveID:nil,kind:"sessionEnd",payload:["inferred":true])
            sessionID = UUID()
        }
        lastForeground = now
    }
    func record<T: Encodable>(game: String, serveID: UUID?, kind: String, payload: T,
                              terminal: Data? = nil) {
        guard let consent = TelemetryConsent.supplied, consent.status == "active" else { return }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]
            let object = try JSONSerialization.jsonObject(with: encoder.encode(payload))
            let versions: [String:Any] = ["app":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development",
                "build":Bundle.main.object(forInfoDictionaryKey:"CFBundleVersion") as? String ?? "development",
                "os":ProcessInfo.processInfo.operatingSystemVersionString,"architecture":Self.architecture,
                "feature":1,"model":3,"generator":4,"timing":1,"calibration":"legacy",
                "experiment":"baseline","configHash":"builtin-v1"]
            let now = ISO8601DateFormatter().string(from:Date())
            let effective: Any = consent.effectiveAt.map { ISO8601DateFormatter().string(from:$0) } ?? (NSNull() as Any)
            let terminalValue = terminal.flatMap { data in serveID.map { ($0,game,data) } }
            try journal.append(terminal:terminalValue) { sequence,id in
                let event: [String:Any] = ["schemaVersion":1,"eventID":id.uuidString,"installationID":identity.installationID.uuidString,
                    "sequence":sequence,"bootID":bootID.uuidString,"sessionID":sessionID.uuidString,
                    "serveID":serveID.map { $0.uuidString } ?? (NSNull() as Any),"game":game,"kind":kind,
                    "createdAt":now,"monotonicSeconds":ProcessInfo.processInfo.systemUptime,
                    "consent":["status":consent.status,"version":consent.version,"effectiveAt":effective],
                    "versions":versions,"payload":object]
                return try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys])
            }
        } catch { lastError = error; NSLog("Difficulty journal write failed: %@", String(describing:error)) }
    }
    private static var architecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "x86_64"
        #endif
    }
}
