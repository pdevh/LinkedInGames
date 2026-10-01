import AppKit

func runTelemetryJournalTests() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("test.sqlite")
    let serve = UUID()
    var journal: DifficultyJournal? = try DifficultyJournal(url: url)
    let first = try journal!.append(terminal: (serve,"patches",Data("snapshot".utf8))) { sequence,id in
        Data("{\"sequence\":\(sequence),\"id\":\"\(id)\"}".utf8)
    }
    let duplicate = try journal!.append(terminal: (serve,"patches",Data())) { _,_ in fatalError("Terminal encoded twice") }
    precondition(first == duplicate)
    journal = nil
    journal = try DifficultyJournal(url: url)
    let pending = try journal!.pending()
    precondition(pending.count == 1 && pending[0].sequence == 1)
    let snapshots = try journal!.terminalSnapshots(); precondition(snapshots.first!.data == Data("snapshot".utf8))
    do {
        try journal!.acknowledge([(first,"wrong")]); preconditionFailure("Accepted wrong hash")
    } catch DifficultyJournal.Failure.invalidReceipt { }
    let stillPending = try journal!.pending(); precondition(stillPending.count == 1)
    try journal!.acknowledge([(first,pending[0].sha256)])
    let afterReceipt = try journal!.pending(); precondition(afterReceipt.isEmpty)
    let retained = try journal!.terminalSnapshots(); precondition(retained.count == 1)
    do {
        try journal!.append { _,_ in throw NSError(domain:"fixture",code:1) }
    } catch { }
    try journal!.append { sequence,_ in precondition(sequence == 2); return Data("{}".utf8) }
    print("Telemetry journal: recovery, atomic sequence, terminal idempotency and receipt hashes passed")
}

func runTelemetryCrashWriter(url: URL) throws {
    let journal = try DifficultyJournal(url:url)
    for i in 0..<100_000 {
        try journal.append { sequence,_ in Data("{\"sequence\":\(sequence)}".utf8) }
        if i == 9 {
            FileHandle.standardOutput.write(Data("committed10\n".utf8))
        }
    }
}

func runTelemetryCrashTest() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let url = folder.appendingPathComponent("crash.sqlite")
    let child = Process(), pipe = Pipe()
    child.executableURL = URL(fileURLWithPath:CommandLine.arguments[0])
    child.arguments = ["--telemetry-crash-writer",url.path]; child.standardOutput = pipe
    try child.run()
    let signal = pipe.fileHandleForReading.availableData
    precondition(String(data:signal,encoding:.utf8)?.contains("committed10") == true)
    kill(child.processIdentifier,SIGKILL); child.waitUntilExit()
    let recovered = try DifficultyJournal(url:url)
    let pending = try recovered.pending()
    precondition(pending.count >= 10)
    for (index,row) in pending.enumerated() { precondition(row.sequence == Int64(index+1)) }
    print("Telemetry SIGKILL recovery: \(pending.count) committed transactions retained")
}

func runTelemetryOverflowTest() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let journal = try DifficultyJournal(url:folder.appendingPathComponent("overflow.sqlite"))
    for _ in 0..<20 { try journal.append { _,_ in Data(String(repeating:"x",count:1000).utf8) } }
    let lost = try journal.enforcePendingLimit(bytes:10_000,reserve:1000) { rows,sequence,id in
        precondition(!rows.isEmpty)
        return try JSONSerialization.data(withJSONObject:["kind":"loss","sequence":sequence,"lostIDs":rows.map(\.eventID)])
    }
    let pending = try journal.pending()
    precondition(lost == 11 && pending.count == 10)
    precondition(pending.last!.payload.contains("lostIDs"))
    print("Telemetry overflow: evictions and loss manifest reconciled")
}

func runDifficultyFeedbackTests() {
    let suite = "feedback-tests-" + UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let coordinator = DifficultyFeedbackCoordinator(defaults:defaults)
    let serveID = UUID(uuidString:"00000000-0000-0000-0000-000000000001")!
    let first = coordinator.assign(serveID:serveID)
    let repeatDraw = coordinator.assign(serveID:serveID)
    precondition(first.draw == repeatDraw.draw)
    precondition(first.eligibleProbability == 0.25)
    defaults.set(true,forKey:"difficulty.feedback.stopped")
    let stopped = coordinator.assign(serveID:UUID())
    precondition(stopped.state == "notInvited" && stopped.suppressionReason == "disabled")
    let pending = DifficultyFeedback(draw:0,eligibleProbability:0.25,suppressionReason:nil,state:"pending")
    let recovered = DifficultyFeedbackCoordinator.recovery(pending)
    precondition(recovered?.state == "skipped" && recovered?.resolution == "recovery" && recovered?.contractSatisfied == true)
    precondition(DifficultyFeedbackCoordinator.canDisclose(pending) == false)
    precondition(DifficultyFeedbackCoordinator.canDisclose(recovered) == true)
    print("Difficulty feedback: deterministic assignment, disable, recovery and disclosure gate passed")
}

func runTelemetryRetryTests() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let journal = try DifficultyJournal(url:folder.appendingPathComponent("retry.sqlite"))
    try journal.append { _,_ in Data("{}".utf8) }
    let sent = try journal.pending(), id = sent[0].eventID, hash = sent[0].sha256
    func receipt(_ accepted: [[String:Any]], _ rejected: [[String:Any]] = []) throws -> Data {
        try JSONSerialization.data(withJSONObject:["batchID":"batch","accepted":accepted,"rejected":rejected])
    }
    for data in [try receipt([]), try receipt([["eventID":id,"sha256":"wrong"]]),
                 try receipt([["eventID":id,"sha256":hash],["eventID":id,"sha256":hash]]),
                 try receipt([["eventID":id,"sha256":hash]],[["eventID":id,"reason":"conflict","retryable":false]])] {
        do { _ = try TelemetryUploader.validatedReceipt(data,batchID:"batch",sent:sent); preconditionFailure("Invalid receipt accepted") }
        catch DifficultyJournal.Failure.invalidReceipt { }
    }
    let valid = try TelemetryUploader.validatedReceipt(try receipt([["eventID":id,"sha256":hash]]),batchID:"batch",sent:sent)
    let retryAt = Date().addingTimeInterval(3600)
    try journal.retry([id],after:retryAt)
    let before = try journal.pending(); precondition(before.isEmpty)
    let after = try journal.pending(now:retryAt.addingTimeInterval(1)); precondition(after.map(\.eventID) == [id])
    try journal.acknowledge(valid.accepted.map { ($0.eventID,$0.sha256) })
    try journal.acknowledge(valid.accepted.map { ($0.eventID,$0.sha256) }) // Lost ACK retry.
    let remaining = try journal.pending(now:retryAt); precondition(remaining.isEmpty)
    for code in [429,503] {
        let response = HTTPURLResponse(url:URL(string:"https://localhost")!,statusCode:code,httpVersion:nil,headerFields:["Retry-After":"3600"])!
        precondition(TelemetryUploader.retryDelay(failures:1,response:response) >= 3600)
    }
    print("Telemetry retry: complete receipts, duplicate ACK, persisted delay, 429/503 Retry-After passed")
}

func runLegacyImportIdentityTests() throws {
    let recordID = UUID()
    let zipID = GameplayTelemetry.legacyEventID(game:"zip",recordID:recordID)
    precondition(zipID == GameplayTelemetry.legacyEventID(game:"zip",recordID:recordID))
    precondition(zipID != GameplayTelemetry.legacyEventID(game:"patches",recordID:recordID))
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let journal = try DifficultyJournal(url:folder.appendingPathComponent("legacy.sqlite"))
    try journal.append(eventID:zipID) { _,_ in Data("{}".utf8) }
    let beforeAcknowledgment = try journal.contains(eventID:zipID)
    precondition(beforeAcknowledgment)
    let pending = try journal.pending()
    try journal.acknowledge([(zipID.uuidString,pending[0].sha256)])
    let afterAcknowledgment = try journal.contains(eventID:zipID)
    precondition(afterAcknowledgment)
    print("Legacy import: stable per-game identity and durable deduplication passed")
}

func runProgressRecoveryTests() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at:folder) }
    let journal = try DifficultyJournal(url:folder.appendingPathComponent("difficulty.sqlite"))
    let puzzle = Puzzle.make(.easy)
    var zipRecord = PlayStatistics(puzzle:puzzle,difficulty:.easy)
    zipRecord.outcome = "solved"
    zipRecord.feedback = DifficultyFeedback(draw:0,eligibleProbability:0.25,suppressionReason:nil,state:"assigned")
    var patches = PatchesRecord(puzzle:PatchesPuzzle(size:1,clues:[],solution:[]),requested:0)
    patches.solved = true; patches.feedback = zipRecord.feedback
    try journal.append(terminal:(zipRecord.id,"zip",JSONEncoder().encode(zipRecord))) { _,_ in Data("{}".utf8) }
    try journal.append(terminal:(patches.id,"patches",JSONEncoder().encode(patches))) { _,_ in Data("{}".utf8) }
    // JSON saved after the terminal contains the response; recovery must not erase it.
    zipRecord.feedback?.state = "shown"; zipRecord.feedback?.response = 4
    patches.feedback?.state = "shown"; patches.feedback?.response = 2
    let url = folder.appendingPathComponent("progress.json")
    var snapshot = AppSnapshot()
    snapshot.records = [zipRecord]; snapshot.patches = PatchesSnapshot(records:[patches])
    try JSONEncoder().encode(snapshot).write(to:url)
    let saved = try ProgressStore(url:url,startTelemetry:false)
    precondition(saved.snapshot.records[0].feedback?.response == 4)
    precondition(saved.snapshot.patches?.records[0].feedback?.response == 2)
    // Crash before JSON save: both terminal records come back, invitation is explicitly skipped.
    try JSONEncoder().encode(AppSnapshot()).write(to:url)
    let recovered = try ProgressStore(url:url,startTelemetry:false)
    recovered.flush()
    precondition(recovered.snapshot.records.count == 1 && recovered.snapshot.patches?.records.count == 1)
    precondition(recovered.snapshot.records[0].feedback?.resolution == "recovery")
    precondition(recovered.snapshot.patches?.records[0].feedback?.resolution == "recovery")
    let again = try ProgressStore(url:url,startTelemetry:false)
    precondition(again.snapshot.records.count == 1)
    print("Progress recovery: post-terminal responses preserved; both games recovered without Keychain")
}

func runFeedbackPresentationTests() {
    _ = NSApplication.shared
    let suite = "feedback-ui-" + UUID().uuidString
    let defaults = UserDefaults(suiteName:suite)!
    defer { defaults.removePersistentDomain(forName:suite) }
    let window = NSWindow(contentRect:NSRect(x:0,y:0,width:700,height:500),styleMask:[.titled],backing:.buffered,defer:false)
    window.makeKeyAndOrderFront(nil)
    for choice in [0,5,6,-1] {
        defaults.removePersistentDomain(forName:suite)
        let coordinator = DifficultyFeedbackCoordinator(defaults:defaults)
        let assigned = DifficultyFeedback(draw:0,eligibleProbability:0.25,suppressionReason:nil,state:"assigned")
        var states: [DifficultyFeedback] = [], revealed = false
        coordinator.present(assigned,window:window,save: { states.append($0) },reveal: {
            precondition(states.last?.state == "shown")
            revealed = true
        })
        precondition(states.last?.state == "pending" && !revealed)
        precondition(!DifficultyFeedbackCoordinator.canDisclose(states.last))
        guard let sheet = window.attachedSheet else { preconditionFailure("No feedback sheet") }
        if choice == -1 { coordinator.resolvePending(reason:"close") }
        else { window.endSheet(sheet,returnCode:NSApplication.ModalResponse(rawValue:1000+choice)) }
        let deadline = Date().addingTimeInterval(2)
        while window.attachedSheet != nil && Date() < deadline {
            RunLoop.current.run(until:Date().addingTimeInterval(0.02))
        }
        if choice == -1 {
            precondition(states.last?.resolution == "close" && !revealed)
        } else {
            precondition(revealed && states.map(\.state) == ["pending",choice == 0 ? "submitted" : "skipped","shown"])
            precondition(states.last?.response == (choice == 0 ? 1 : nil))
            if choice == 6 { precondition(defaults.bool(forKey:"difficulty.feedback.stopped")) }
        }
    }
    window.orderOut(nil)
    print("Feedback AppKit: neutral pending gate, answer, skip, stop asking and close ordering passed")
}
