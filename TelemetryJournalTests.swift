import Foundation

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
