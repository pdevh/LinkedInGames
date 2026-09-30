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
    private var uploader: TelemetryUploader?
    private var uploadTimer: Timer?
    private var captureCount = 0
    init(url: URL) throws {
        journal = try DifficultyJournal(url:url)
        identity = try TelemetryIdentity.load()
        uploader = try TelemetryUploader(journal:journal,directory:url.deletingLastPathComponent().appendingPathComponent("telemetry-upload"))
        if try journal.metadata("captureOpen") == "true" {
            record(game:"system",serveID:nil,kind:"recovery",payload:["interruptedCaptureInterval":true,"lostCountUnknown":true])
        }
        try journal.setMetadata("captureOpen",value:"true")
        uploader?.wake()
        uploadTimer = Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in self?.uploader?.wake() }
    }
    deinit { uploadTimer?.invalidate() }
    func close() {
        record(game:"system",serveID:nil,kind:"sessionEnd",payload:["inferred":false])
        do { try journal.setMetadata("captureOpen",value:"false") } catch { lastError = error }
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
            func envelope(sequence: Int64, id: UUID, eventKind: String, eventGame: String, eventServe: UUID?, body: Any) throws -> Data {
                let event: [String:Any] = ["schemaVersion":1,"eventID":id.uuidString,"installationID":identity.installationID.uuidString,
                    "sequence":sequence,"bootID":bootID.uuidString,"sessionID":sessionID.uuidString,
                    "serveID":eventServe.map { $0.uuidString } ?? (NSNull() as Any),"game":eventGame,"kind":eventKind,
                    "createdAt":now,"monotonicSeconds":ProcessInfo.processInfo.systemUptime,
                    "consent":["status":consent.status,"version":consent.version,"effectiveAt":effective],
                    "versions":versions,"payload":body]
                return try JSONSerialization.data(withJSONObject:event,options:[.sortedKeys])
            }
            try journal.append(terminal:terminalValue) { sequence,id in
                try envelope(sequence:sequence,id:id,eventKind:kind,eventGame:game,eventServe:serveID,body:object)
            }
            captureCount += 1
            if captureCount % 100 == 0 {
                _ = try journal.enforcePendingLimit { losses,sequence,id in
                    let rows = try JSONSerialization.jsonObject(with:encoder.encode(losses))
                    return try envelope(sequence:sequence,id:id,eventKind:"loss",eventGame:"system",eventServe:nil,
                                        body:["reason":"offlineCapacity","events":rows,"completeTrace":false])
                }
            }
            if terminal != nil { uploader?.wake() }
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
