import Foundation

func runPatchesTests() {
    let snapPuzzle = PatchesPuzzle(size: 4, clues: [
        PatchClue(cell:Cell(x:0,y:0),area:4,shape:.square),
        PatchClue(cell:Cell(x:2,y:0),area:4,shape:.square),
        PatchClue(cell:Cell(x:0,y:2),area:4,shape:.square),
        PatchClue(cell:Cell(x:2,y:2),area:4,shape:.square)
    ], solution: [])
    let topLeft = PatchRect(x:0,y:0,width:2,height:2)
    let bottomRight = PatchRect(x:2,y:2,width:2,height:2)
    func snap(_ a:Cell, _ x:Double, _ y:Double, _ previous:PatchRect? = nil) -> PatchRect? {
        PatchSelection.resolve(anchor:a,x:x,y:y,puzzle:snapPuzzle,placed:[],previous:previous)
    }
    precondition(snap(Cell(x:0,y:0),1.8,1.8) == topLeft)
    precondition(snap(Cell(x:0,y:0),2.12,1.8) == topLeft, "Small overshoot must snap")
    precondition(snap(Cell(x:0,y:0),2.1,2.1,topLeft) == topLeft, "Diagonal wobble must retain preview")
    precondition(snap(Cell(x:0,y:0),2.5,1.8,topLeft) == nil, "Distant movements must not stick")
    precondition(snap(Cell(x:1,y:1),-0.12,0.3) == topLeft, "Reverse drags at board edge must work")
    precondition(snap(Cell(x:2,y:2),4.12,3.8) == bottomRight, "Slight release outside board must place")
    precondition(snap(Cell(x:2,y:2),4.5,3.8,bottomRight) == nil)
    let obstruction = PatchRect(x:1,y:0,width:2,height:2)
    precondition(PatchSelection.resolve(anchor:Cell(x:0,y:0),x:2.1,y:1.8,puzzle:snapPuzzle,placed:[obstruction],previous:topLeft) == nil)
    let wildcard = PatchesPuzzle(size:3,clues:[PatchClue(cell:Cell(x:0,y:0),area:nil,shape:.any)],solution:[])
    let strip = PatchRect(x:0,y:0,width:2,height:1)
    precondition(PatchSelection.resolve(anchor:Cell(x:0,y:0),x:2.1,y:0.5,puzzle:wildcard,placed:[],previous:strip) == strip)
    precondition(PatchSelection.resolve(anchor:Cell(x:0,y:0),x:2.4,y:0.5,puzzle:wildcard,placed:[],previous:strip)?.width == 3)

    // Independent cell-first tiling oracle: no masks, no production candidate builder.
    func oracle(_ p:PatchesPuzzle) -> Int {
        var occupied = Set<Cell>(), count = 0
        func search() {
            if count >= 2 { return }
            guard let first = (0..<p.size*p.size).map({ Cell(x:$0 % p.size,y:$0 / p.size) }).first(where: { !occupied.contains($0) }) else { count += 1; return }
            for h in 1...p.size-first.y { for w in 1...p.size-first.x {
                let cells = (first.y..<first.y+h).flatMap { y in (first.x..<first.x+w).map { Cell(x:$0,y:y) } }
                if cells.contains(where: { occupied.contains($0) }) { continue }
                let clues = p.clues.filter { cells.contains($0.cell) }
                guard clues.count == 1 else { continue }
                let clue = clues[0]
                if let area = clue.area, area != w*h { continue }
                switch clue.shape { case .square: if w != h { continue }; case .tall: if h <= w { continue }
                case .wide: if w <= h { continue }; case .any: break }
                occupied.formUnion(cells); search(); occupied.subtract(cells)
            } }
        }
        search(); return count
    }
    for d in Difficulty.allCases { for seed in 0..<40 {
        var rng = PuzzleRandom(seed:UInt64(seed)), replay = rng
        let p = PatchesPuzzle.make(d,using:&rng)
        precondition(p == PatchesPuzzle.make(d,using:&replay))
        precondition(p.complete(p.solution))
        let solved = p.solve(); precondition(solved.count == 1 && !solved.exhausted)
        precondition(oracle(p) == 1,"Independent tiling oracle found ambiguity")
        precondition(p.solve(budget:0).exhausted)
        precondition(!p.legal(p.solution+[p.solution[0]]))
        precondition(!p.valid(PatchRect(x:-1,y:0,width:1,height:1)))
        precondition(p.features.allSatisfy(\.isFinite))
        let restored = try! JSONDecoder().decode(PatchesPuzzle.self,from:JSONEncoder().encode(p))
        precondition(restored == p)
    } }
    let ambiguous = PatchesPuzzle(size:2,clues:[PatchClue(cell:Cell(x:0,y:0),area:2,shape:.any),PatchClue(cell:Cell(x:1,y:1),area:2,shape:.any)],solution:[])
    precondition(ambiguous.solve().count == 2 && oracle(ambiguous) == 2)
    let impossible = PatchesPuzzle(size:2,clues:[PatchClue(cell:Cell(x:0,y:0),area:3,shape:.square)],solution:[])
    precondition(impossible.solve().count == 0 && oracle(impossible) == 0)
    var rng = PuzzleRandom(seed:90)
    let puzzle = PatchesPuzzle.make(.medium,using:&rng)
    func record(hard:Bool) -> PatchesRecord {
        var r = PatchesRecord(puzzle:puzzle,requested:hard ? 0 : 2)
        r.solved = true; r.activeSeconds = hard ? 180 : 8
        r.corrections = hard ? 70 : 0; r.intervals = hard ? [6,8,10,8] : [0.4,0.5]
        return r
    }
    let easy = (0..<40).map { _ in record(hard:false) }, hard = (0..<40).map { _ in record(hard:true) }
    let a = PatchesModel(easy), b = PatchesModel(hard)
    precondition(a.predict(puzzle) < b.predict(puzzle))
    precondition(PatchesModel([easy[0]]).predict(puzzle) < PatchesModel([]).predict(puzzle))
    precondition(PatchesModel(Array(repeating:easy[0],count:50)).count == 1)
    var invalid = easy[0]; invalid.activeSeconds = .infinity
    var skipped = hard[0]; skipped.solved = false
    precondition(PatchesModel([invalid,skipped]).count == 0)
    var hinted = easy[0]; hinted.hints = 1
    precondition(hinted.effort! > easy[0].effort!)
    precondition(PatchesModel(hard+easy).predict(puzzle) < PatchesModel(easy+hard).predict(puzzle))
    precondition(PatchesModel.verdict(easy[0]) == "easy" && PatchesModel.verdict(hard[0]) == "hard")
    for model in [a,b,PatchesModel([]),PatchesModel(easy+hard)] {
        let f = model.forecast(puzzle)
        precondition(f.probabilities.allSatisfy { $0 >= 0 && $0 <= 1 && $0.isFinite })
        precondition(abs(f.probabilities.reduce(0,+)-1) < 1e-10)
    }
    precondition(!PatchesModel([]).forecast(puzzle).qualifies(.easy))
    let restoredRecords = try! JSONDecoder().decode([PatchesRecord].self,from:JSONEncoder().encode(easy))
    precondition(PatchesModel(restoredRecords).weights == a.weights)
    let oldSnapshot = Data("{\"progress\":{},\"records\":[]}".utf8)
    precondition(try! JSONDecoder().decode(AppSnapshot.self,from:oldSnapshot).patches == nil)
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("patches-test-"+UUID().uuidString)
    let url = folder.appendingPathComponent("progress.json")
    let store = try! ProgressStore(url:url)
    let session = PatchesSession(record:easy[0],placed:[puzzle.solution[0]],undo:[[]])
    store.snapshot.patches = PatchesSnapshot(sessions:["0":session],records:easy,selected:0)
    store.save(); store.flush()
    let reopened = try! ProgressStore(url:url)
    precondition(reopened.snapshot.patches?.sessions["0"]?.placed == session.placed)
    precondition(reopened.snapshot.patches?.sessions["0"]?.undo == [[]])
    precondition(reopened.snapshot.patches?.records.count == 40)
    try! FileManager.default.removeItem(at:folder)
    let start = Date()
    for d in Difficulty.allCases {
        let selected = a.select(d,excluding:[puzzle],using:&rng)
        precondition(selected != puzzle && selected.complete(selected.solution))
        precondition(oracle(selected) == 1)
    }
    print("Patches: 120 seeded unique boards checked by independent oracle; rules, ambiguity, budgets, learning, forecasts, compatibility and persistence passed. Selection: \(Date().timeIntervalSince(start))s")
}
