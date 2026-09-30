import Foundation

/// One in-flight persisted batch; at-least-once delivery, exact-hash receipts.
final class TelemetryUploader {
    private let queue = DispatchQueue(label:"difficulty.upload",qos:.utility)
    private let journal: DifficultyJournal
    private let directory: URL
    private var identity: TelemetryIdentity
    private var busy = false
    private var failures = 0
    private var limit = 100
    private(set) var lastStatus = "Offline"
    init(journal: DifficultyJournal, directory: URL) throws {
        self.journal = journal; self.directory = directory; identity = try TelemetryIdentity.load()
        if identity.enrollmentKey == nil { identity.enrollmentKey = UUID().uuidString + UUID().uuidString; try identity.save() }
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
    }
    func wake() { queue.async { self.start() } }
    private func start() {
        guard !busy, TelemetryConsent.supplied?.status == "active",
              UserDefaults.standard.bool(forKey:"difficulty.telemetry.uploadEnabled"),
              let configured = UserDefaults.standard.string(forKey:"difficulty.telemetry.endpoint"),
              let endpoint = URL(string:configured), endpoint.scheme == "https", endpoint.user == nil,
              endpoint.password == nil else { return }
        busy = true
        do {
            let records = try journal.pending(limit:limit)
            guard !records.isEmpty else { busy = false; lastStatus = "No pending events"; return }
            if identity.credential == nil { enroll(endpoint); return }
            let file = directory.appendingPathComponent("batch.json")
            let batchID = UUID().uuidString
            var entries = records
            var data = Data()
            while !entries.isEmpty {
                let object: [String:Any] = ["batchID":batchID,"installationID":identity.installationID.uuidString,
                    "schemaVersion":1,"checksum":DifficultyJournal.hash(Data(entries.map(\.sha256).joined().utf8)),
                    "events":entries.map { ["eventID":$0.eventID,"sequence":$0.sequence,"payload":$0.payload,"sha256":$0.sha256] as [String:Any] }]
                data = try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys])
                if data.count <= 512*1024 { break }
                if entries.count == 1 {
                    try journal.retry(entries.map(\.eventID),after:Date(),quarantine:"oversizedEventRequiresChunking")
                    busy = false; lastStatus = "Oversized event quarantined"; return
                }
                entries.removeLast()
            }
            try data.write(to:file,options:.atomic)
            var request = URLRequest(url:endpoint.appendingPathComponent("v1/events/batch"))
            request.httpMethod = "POST"; request.timeoutInterval = 30
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.setValue("Bearer \(identity.credential!)",forHTTPHeaderField:"Authorization")
            let sent = entries
            URLSession.shared.uploadTask(with:request,fromFile:file) { data,response,error in
                self.queue.async { self.complete(sent:sent,batchID:batchID,data:data,response:response,error:error,file:file) }
            }.resume()
        } catch { busy = false; lastStatus = "Queue error: \(error)" }
    }
    private func enroll(_ endpoint: URL) {
        var request = URLRequest(url:endpoint.appendingPathComponent("v1/installations"))
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject:["installationID":identity.installationID.uuidString,"enrollmentKey":identity.enrollmentKey!])
        URLSession.shared.dataTask(with:request) { data,response,error in
            self.queue.async {
                defer { self.busy = false }
                guard error == nil, (response as? HTTPURLResponse)?.statusCode == 200, let data,
                      let body = try? JSONSerialization.jsonObject(with:data) as? [String:Any],
                      let credential = body["credential"] as? String else {
                    self.lastStatus = "Enrollment unavailable; queue retained"; return
                }
                do { self.identity.credential = credential; try self.identity.save(); self.queue.async { self.start() } }
                catch { self.lastStatus = "Credential persistence failed" }
            }
        }.resume()
    }
    private func complete(sent:[DifficultyJournal.Pending],batchID:String,data:Data?,response:URLResponse?,error:Error?,file:URL) {
        defer { busy = false }
        let http = response as? HTTPURLResponse
        do {
            if error == nil, http?.statusCode == 200, let data,
               let receipt = try JSONSerialization.jsonObject(with:data) as? [String:Any],
               receipt["batchID"] as? String == batchID,
               let accepted = receipt["accepted"] as? [[String:Any]], let rejected = receipt["rejected"] as? [[String:Any]] {
                let expected = Dictionary(uniqueKeysWithValues:sent.map { ($0.eventID,$0.sha256) })
                var acknowledgments: [(String,String)] = []
                for item in accepted {
                    guard let id = item["eventID"] as? String, let hash = item["sha256"] as? String,
                          expected[id] == hash else { throw DifficultyJournal.Failure.invalidReceipt }
                    acknowledgments.append((id,hash))
                }
                try journal.acknowledge(acknowledgments)
                for item in rejected {
                    if let id = item["eventID"] as? String, expected[id] != nil, item["retryable"] as? Bool == false {
                        try journal.retry([id],after:Date(),quarantine:item["reason"] as? String ?? "rejected")
                    }
                }
                failures = 0; lastStatus = "Acknowledged \(acknowledgments.count) events"
                try? FileManager.default.removeItem(at:file)
                return
            }
            failures += 1
            if http?.statusCode == 413 { limit = max(1,limit/2) }
            // Never re-enroll as a new installation or discard immutable old IDs on 401.
            if http?.statusCode == 401 {
                identity.credential = nil; try identity.save()
                lastStatus = "Credential recovery queued; event identity retained"
            }
            else { lastStatus = "Retry queued (\(http?.statusCode ?? 0))" }
            let ceiling = min(3600,5*pow(2,Double(min(failures-1,10))))
            var delay = Double.random(in:0...ceiling)
            if let header = http?.value(forHTTPHeaderField:"Retry-After") {
                if let seconds = Double(header) { delay = max(delay,seconds) }
                else {
                    let formatter = DateFormatter(); formatter.locale = Locale(identifier:"en_US_POSIX")
                    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                    if let date = formatter.date(from:header) { delay = max(delay,date.timeIntervalSinceNow) }
                }
            }
            try journal.retry(sent.map(\.eventID),after:Date().addingTimeInterval(delay))
        } catch { lastStatus = "Receipt/queue error; data retained: \(error)" }
    }
}
