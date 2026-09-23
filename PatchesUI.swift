import AppKit

private enum PatchArtwork {
    static func badge(for shape: PatchShape, in cell: NSRect) -> NSRect {
        let side = min(cell.width, cell.height)
        let width: CGFloat
        let height: CGFloat
        switch shape {
        case .square, .any: width = side * 0.53; height = side * 0.53
        case .tall: width = side * 0.39; height = side * 0.65
        case .wide: width = side * 0.65; height = side * 0.39
        }
        return NSRect(x: cell.midX-width/2, y: cell.midY-height/2,
                      width: width, height: height)
    }

    static func draw(_ badge: NSRect, shape: PatchShape, color: NSColor, numbered: Bool) {
        let path = NSBezierPath(roundedRect: badge, xRadius: min(8, badge.width * 0.16),
                                yRadius: min(8, badge.height * 0.16))
        color.withAlphaComponent(numbered ? 0.95 : 0.53).setFill()
        path.fill()
        if shape == .any {
            // Four edge tabs communicate freedom along both axes.
            color.withAlphaComponent(numbered ? 0.45 : 0.30).setFill()
            let depth = badge.width * 0.16, length = badge.width * 0.56
            for handle in [
                NSRect(x: badge.midX-length/2, y: badge.minY-depth, width: length, height: depth+2),
                NSRect(x: badge.midX-length/2, y: badge.maxY-2, width: length, height: depth+2),
                NSRect(x: badge.minX-depth, y: badge.midY-length/2, width: depth+2, height: length),
                NSRect(x: badge.maxX-2, y: badge.midY-length/2, width: depth+2, height: length)
            ] {
                NSBezierPath(roundedRect: handle, xRadius: 3, yRadius: 3).fill()
            }
        }
    }
}

final class PatchesBoardView: NSView {
    var puzzle: PatchesPuzzle? { didSet { anchor = nil; cursor = Cell(x:0,y:0); needsDisplay = true } }
    var placed: [PatchRect] = [] { didSet { needsDisplay = true } }
    var locked = false
    var enabled = false { didSet { if !enabled { anchor = nil; preview = nil }; needsDisplay = true } }
    var onRectangle: ((PatchRect) -> Void)?
    var onRemove: ((Cell) -> Void)?
    var onInput: (() -> Void)?
    var onMessage: ((String) -> Void)?
    private var anchor: Cell?
    private var cursor = Cell(x:0,y:0)
    private var preview: PatchRect?
    private var dragged = false
    private var mouseOrigin = NSPoint.zero
    private var keyboard = false
    private var lastHaptic = Date.distantPast
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    private var grid: NSRect { bounds.insetBy(dx:8,dy:8) }
    private var unit: CGFloat { grid.width/CGFloat(puzzle?.size ?? 5) }
    override init(frame:NSRect) {
        super.init(frame:frame)
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("Patches board. Arrow keys move; Space selects two corners; Delete removes a patch; Escape cancels.")
    }
    required init?(coder:NSCoder) { fatalError() }
    func feedback(_ pattern:NSHapticFeedbackManager.FeedbackPattern) {
        guard Date().timeIntervalSince(lastHaptic) > 0.055 else { return }
        lastHaptic = Date(); NSHapticFeedbackManager.defaultPerformer.perform(pattern,performanceTime:.now)
    }
    private func cell(_ event:NSEvent) -> Cell? {
        let p = convert(event.locationInWindow,from:nil)
        guard grid.contains(p), let puzzle else { return nil }
        let c = Cell(x:Int((p.x-grid.minX)/unit), y:Int((p.y-grid.minY)/unit))
        return c.x < puzzle.size && c.y < puzzle.size ? c : nil
    }
    private func rect(_ r:PatchRect) -> NSRect {
        NSRect(x:grid.minX+CGFloat(r.x)*unit,y:grid.minY+CGFloat(r.y)*unit,width:CGFloat(r.width)*unit,height:CGFloat(r.height)*unit)
    }
    private func color(_ index:Int) -> NSColor {
        let rgb: [(CGFloat, CGFloat, CGFloat)] = [
            (0.00,0.46,0.50), (0.72,0.31,0.04), (0.49,0.25,0.70), (0.12,0.38,0.76),
            (0.73,0.16,0.40), (0.17,0.46,0.25), (0.37,0.31,0.66), (0.75,0.18,0.16),
            (0.51,0.35,0.27), (0.54,0.40,0.02)
        ]
        let palette = rgb.map { NSColor(calibratedRed:$0.0,green:$0.1,blue:$0.2,alpha:1) }
        return palette[index % palette.count]
    }
    override func draw(_ dirtyRect:NSRect) {
        NSColor.white.setFill(); NSBezierPath(roundedRect:grid,xRadius:12,yRadius:12).fill()
        guard let puzzle else { return }
        if !enabled {
            let label = NSAttributedString(string:"Your puzzle is waiting",attributes:[.font:NSFont.systemFont(ofSize:20,weight:.medium),.foregroundColor:NSColor.secondaryLabelColor])
            label.draw(at:NSPoint(x:bounds.midX-label.size().width/2,y:bounds.midY-12)); return
        }
        NSColor(calibratedWhite:0.82,alpha:1).setStroke()
        let lines = NSBezierPath(); lines.lineWidth = 0.7
        lines.setLineDash([3, 3], count: 2, phase: 0)
        for i in 0...puzzle.size {
            let offset = CGFloat(i)*unit
            lines.move(to:NSPoint(x:grid.minX+offset,y:grid.minY)); lines.line(to:NSPoint(x:grid.minX+offset,y:grid.maxY))
            lines.move(to:NSPoint(x:grid.minX,y:grid.minY+offset)); lines.line(to:NSPoint(x:grid.maxX,y:grid.minY+offset))
        }
        lines.stroke()
        for r in placed {
            let c = color(puzzle.clueIndex(r) ?? 0), path = NSBezierPath(roundedRect:rect(r).insetBy(dx:3,dy:3),xRadius:9,yRadius:9)
            c.withAlphaComponent(0.23).setFill(); path.fill(); c.setStroke(); path.lineWidth = 2.5; path.stroke()
        }
        if let anchor {
            let r = keyboard ? PatchRect.between(anchor,cursor) : (preview ?? PatchRect.between(anchor,cursor))
            let valid = (keyboard || preview != nil) && puzzle.valid(r) && !placed.contains { $0.mask(puzzle.size) & r.mask(puzzle.size) != 0 && puzzle.clueIndex($0) != puzzle.clueIndex(r) }
            let c = valid ? NSColor.systemTeal : NSColor.systemOrange
            let path = NSBezierPath(roundedRect:rect(r).insetBy(dx:3,dy:3),xRadius:9,yRadius:9)
            c.withAlphaComponent(0.16).setFill(); path.fill(); c.setStroke(); path.lineWidth = 3; path.stroke()
            onMessage?("\(r.width) × \(r.height) = \(r.area) cells" + (valid ? " · Release to place" : " · Match one clue’s size and shape"))
        }
        for (i,clue) in puzzle.clues.enumerated() {
            let box = rect(PatchRect(x:clue.cell.x,y:clue.cell.y,width:1,height:1))
            let badge = PatchArtwork.badge(for: clue.shape, in: box)
            PatchArtwork.draw(badge, shape: clue.shape, color: color(i), numbered: clue.area != nil)
            if let area = clue.area {
                let label = NSAttributedString(string:String(area),attributes:[
                    .font:NSFont.monospacedDigitSystemFont(ofSize:min(25, badge.height*0.52),weight:.bold),
                    .foregroundColor:NSColor.white
                ])
                label.draw(at:NSPoint(x:box.midX-label.size().width/2,y:box.midY-label.size().height/2))
            }
        }
        if keyboard && window?.firstResponder === self {
            NSColor.labelColor.setStroke(); let path = NSBezierPath(roundedRect:rect(PatchRect(x:cursor.x,y:cursor.y,width:1,height:1)).insetBy(dx:5,dy:5),xRadius:7,yRadius:7)
            path.lineWidth = 2; path.setLineDash([4,3],count:2,phase:0); path.stroke()
        }
    }
    private func updateSelection(_ event: NSEvent) -> PatchRect? {
        guard let anchor, let puzzle else { return nil }
        // AppKit keeps delivering the originating view's drag and mouse-up
        // events outside the window. Resolve them against the nearest playable
        // edge so a release after overshooting still chooses the edge cell.
        let playable = NSRect(x:grid.minX,y:grid.minY,
                              width:CGFloat(puzzle.size)*unit,height:CGFloat(puzzle.size)*unit)
        let point = BoardDrag.clamped(convert(event.locationInWindow, from:nil), to:playable)
        let x = Double((point.x-grid.minX)/unit), y = Double((point.y-grid.minY)/unit)
        let result = PatchSelection.resolve(anchor:anchor,x:x,y:y,puzzle:puzzle,placed:placed,previous:preview)
        if let c = PatchSelection.cell(x:x,y:y,size:puzzle.size) { cursor = c }
        if result != preview { feedback(.alignment) }
        preview = result; needsDisplay = true
        return result
    }
    override func mouseDown(with event:NSEvent) {
        guard enabled, !locked, let c = cell(event) else { return }
        window?.makeFirstResponder(self); keyboard = false; onInput?()
        anchor = c; cursor = c; preview = nil; dragged = false
        mouseOrigin = convert(event.locationInWindow,from:nil)
        _ = updateSelection(event)
    }
    override func mouseDragged(with event:NSEvent) {
        guard enabled, !locked, anchor != nil else { return }
        let p = convert(event.locationInWindow,from:nil)
        if hypot(p.x-mouseOrigin.x,p.y-mouseOrigin.y) > 5 { dragged = true }
        onInput?(); _ = updateSelection(event)
    }
    override func mouseUp(with event:NSEvent) {
        guard enabled, !locked, let start = anchor else { return }
        let chosen = updateSelection(event)
        let end = cell(event)
        anchor = nil; preview = nil; needsDisplay = true; onInput?()
        if !dragged, end == start, placed.contains(where: { $0.contains(start) }) { onRemove?(start) }
        else if let chosen { onRectangle?(chosen) }
        else { onMessage?("No matching rectangle here · Drag again, or Escape to cancel"); feedback(.generic) }
    }
    override func keyDown(with event:NSEvent) {
        guard enabled, !locked, let puzzle else { return }
        keyboard = true; onInput?()
        switch event.keyCode {
        case 123: cursor = Cell(x:max(0,cursor.x-1),y:cursor.y)
        case 124: cursor = Cell(x:min(puzzle.size-1,cursor.x+1),y:cursor.y)
        case 125: cursor = Cell(x:cursor.x,y:min(puzzle.size-1,cursor.y+1))
        case 126: cursor = Cell(x:cursor.x,y:max(0,cursor.y-1))
        case 49,36:
            if let start = anchor { anchor = nil; onRectangle?(PatchRect.between(start,cursor)) } else { anchor = cursor }
        case 51,117: anchor = nil; onRemove?(cursor)
        case 53: anchor = nil; onMessage?("Selection cancelled")
        default: super.keyDown(with:event); return
        }
        let clue = puzzle.clues.first { $0.cell == cursor }
        let description = "Row \(cursor.y+1), column \(cursor.x+1)" + (clue.map { ", \($0.shape.rawValue), \($0.area.map(String.init) ?? "any size")" } ?? ", empty")
        setAccessibilityValue(description)
        NSAccessibility.post(element:self,notification:.announcementRequested,userInfo:[.announcement:description,.priority:NSAccessibilityPriorityLevel.low.rawValue])
        needsDisplay = true
    }
}

final class PatchesStatisticsScreen: NSView {
    var onClose: (() -> Void)?
    private let close = NSButton(title: "‹ Back to game", target: nil, action: nil)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = GameUIStyle.background.cgColor
        autoresizingMask = [.width, .height]
        GameUIStyle.button(close)
        close.frame = NSRect(x:30,y:frameRect.height-56,width:130,height:34)
        close.target = self; close.action = #selector(closeScreen)
        addSubview(close)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func label(_ value: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                       size: CGFloat = 14, bold: Bool = false, secondary: Bool = false) {
        let field = NSTextField(wrappingLabelWithString:value)
        field.font = .systemFont(ofSize:size, weight:bold ? .semibold : .regular)
        field.textColor = secondary ? .secondaryLabelColor : GameUIStyle.ink
        field.frame = NSRect(x:x,y:y,width:width,height:height)
        addSubview(field)
    }
    private func card(value: String, title: String, detail: String, x: CGFloat, y: CGFloat) {
        let width:CGFloat = 190
        let surface = NSView(frame:NSRect(x:x,y:y,width:width,height:110))
        surface.wantsLayer = true
        surface.layer?.backgroundColor = NSColor.white.cgColor
        surface.layer?.cornerRadius = 14
        surface.layer?.borderColor = NSColor(calibratedWhite:0.88,alpha:1).cgColor
        surface.layer?.borderWidth = 1
        addSubview(surface)
        label(value,x:x+14,y:y+65,width:width-28,height:36,size:28,bold:true)
        label(title,x:x+14,y:y+39,width:width-28,height:20,size:13,bold:true)
        label(detail,x:x+14,y:y+14,width:width-28,height:18,size:11,secondary:true)
    }
    func show(records: [PatchesRecord]) {
        subviews.filter { $0 !== close }.forEach { $0.removeFromSuperview() }
        let solved = records.filter(\.solved)
        let measured = solved.filter { $0.effort != nil }
        let rated = solved.filter { $0.verdict != nil }
        let matched = rated.filter { $0.verdict == Difficulty(rawValue:$0.requested)?.title.lowercased() }.count
        let times = measured.map(\.activeSeconds).sorted()
        let median:Double? = times.isEmpty ? nil : times.count % 2 == 1 ? times[times.count/2] : (times[times.count/2-1]+times[times.count/2])/2
        let timeText = median.map { String(format:"%d:%02d",Int($0)/60,Int($0)%60) } ?? "—"
        label("Your Patches statistics",x:30,y:660,width:600,height:40,size:26,bold:true)
        label("All difficulties combined",x:30,y:632,width:600,height:22,secondary:true)
        card(value:"\(solved.count)",title:"Solved",detail:"Patches only",x:30,y:495)
        card(value:timeText,title:"Typical solve time",detail:"Based on \(measured.count) measured",x:235,y:495)
        card(value:rated.isEmpty ? "—" : "\(Int((Double(matched)/Double(rated.count)*100).rounded()))%",
             title:"Difficulty match",detail:"Based on \(rated.count) rated",x:440,y:495)
        label("How puzzle picks adapt",x:30,y:433,width:600,height:26,size:18,bold:true)
        label("Patches uses active time, corrections, hesitation, hints, and resets from measured solves. " +
              "Predictions gain full weight after eight; difficulty targets keep adapting as you play.",
              x:30,y:357,width:600,height:66,size:14,secondary:true)
        label("\(solved.filter { $0.hints == 0 }.count) solved without hints",x:30,y:309,width:600,height:24,size:14)
        label("Forecasts are estimates. Patches history stays separate from Zip.",
              x:30,y:278,width:600,height:44,size:13,secondary:true)
        superview?.addSubview(self, positioned:.above, relativeTo:nil)
        isHidden = false
    }
    @objc private func closeScreen() { isHidden = true; onClose?() }
}

final class PatchesController: NSObject, NSWindowDelegate {
    private let store: ProgressStore
    private var snapshot: PatchesSnapshot
    private var session: PatchesSession?
    private var difficulty: Difficulty
    private var window: NSWindow!
    private let board = PatchesBoardView(frame:.zero)
    private let status = NSTextField(labelWithString:"Draw a rectangle around each clue")
    private let timerLabel = NSTextField(labelWithString:"00:00")
    private let hint = NSButton(title:"Hint · 30s",target:nil,action:nil)
    private let undo = NSButton(title:"Undo",target:nil,action:nil)
    private let reset = NSButton(title:"Reset",target:nil,action:nil)
    private let play = NSButton(title:"Play",target:nil,action:nil)
    private let picker = DifficultyPicker()
    private let statisticsScreen = PatchesStatisticsScreen(frame:NSRect(x:0,y:0,width:660,height:790))
    private let toast = DifficultyToast()
    private let welcome = NSView()
    private let welcomeTitle = NSTextField(labelWithString:"Everything in its place.")
    private let welcomeDetail = NSTextField(labelWithString:"One clue. One rectangle. A perfect fit.")
    private let welcomePlay = GameActionButton(title:"Play Patches  →",target:nil,action:nil)
    private var newButton: NSButton!

    private var isPresented = true
    private var paused = true, loading = false
    private var generation = UUID()
    private var lastTick = Date(), lastInput = Date(), lastSave = Date()
    private var interval = 0.0
    private var ticker: Timer?
    init(store:ProgressStore) {
        self.store = store; snapshot = store.snapshot.patches ?? PatchesSnapshot()
        difficulty = Difficulty(rawValue:snapshot.selected) ?? .easy
        super.init(); makeWindow()
        session = snapshot.sessions[String(difficulty.rawValue)]; restore()
        ticker = Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.tick() }
    }
    var onHome: (() -> Void)?
    var gameContent: NSView { window.contentView! }
    func attach(to host: NSWindow) { window = host; host.delegate = self; isPresented = true }
    func leave() {
        if !paused { tick() }
        pause(); statisticsScreen.isHidden = true; picker.isHidden = false
        isPresented = false
    }
    @objc private func goHome() { leave(); onHome?() }
    func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true) }
    func smokePlay(completion: @escaping (Bool) -> Void) {
        newPuzzle()
        var attempts = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            attempts += 1
            guard let self else { timer.invalidate(); completion(false); return }
            if attempts > 100 { timer.invalidate(); completion(false); return }
            guard !self.loading, let puzzle = self.session?.record.puzzle else { return }
            timer.invalidate()
            if self.paused { self.togglePlay() }
            guard !self.paused else { completion(false); return }
            self.place(puzzle.solution[0])
            guard self.session?.placed.count == 1 else { completion(false); return }
            self.undoMove()
            guard self.session?.placed.isEmpty == true else { completion(false); return }
            for rectangle in puzzle.solution { self.place(rectangle) }
            completion(self.session?.record.solved == true && self.session?.placed.count == puzzle.solution.count)
        }
    }
    // Offscreen visual QA uses the real view hierarchy and isolated save storage.
    func renderPreview(to url: URL, welcomeOnly: Bool = false) throws {
        var rng = PuzzleRandom(seed: 19)
        let puzzle = PatchesPuzzle.make(.hard, using: &rng)
        session = PatchesSession(record: PatchesRecord(puzzle: puzzle, requested: 2), placed: Array(puzzle.solution.prefix(4)))
        board.puzzle = puzzle; board.placed = session!.placed; board.enabled = true; paused = false
        picker.selected = 2
        status.stringValue = "\(session!.placed.reduce(0) { $0+$1.area }) / \(puzzle.size*puzzle.size) cells filled"
        if welcomeOnly { session = nil; paused = true; board.enabled = false }
        refresh()
        let content = window.contentView!
        content.layoutSubtreeIfNeeded()
        let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds)!
        content.cacheDisplay(in: content.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }

    private func makeWindow() {
        let root = NSView(frame:NSRect(x:0,y:0,width:660,height:820))
        root.wantsLayer = true; root.layer?.backgroundColor = GameUIStyle.background.cgColor
        window = NSWindow(contentRect:root.bounds,styleMask:[.titled,.closable,.miniaturizable,.fullSizeContentView],backing:.buffered,defer:false)
        window.title = "Patches"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
        window.backgroundColor = GameUIStyle.background
        window.contentView = root; window.isReleasedWhenClosed = false; window.delegate = self; window.center()
        let title = NSTextField(labelWithString:"Patches")
        GameUIStyle.title(title)
        title.frame = NSRect(x:GameUIStyle.headerTitleX,y:778,width:120,height:34)
        let home = NSButton(title:"‹ Games",target:self,action:#selector(goHome))
        GameUIStyle.backButton(home); home.frame = NSRect(x:GameUIStyle.headerHomeX,y:778,width:34,height:34)
        root.addSubview(home)
        picker.frame = NSRect(x:410,y:776,width:226,height:38)
        picker.selected = difficulty.rawValue
        picker.onChange = { [weak self] d in self?.changeDifficulty(Difficulty(rawValue:d) ?? .easy) }
        board.frame = NSRect(x:30,y:130,width:600,height:600)
        timerLabel.frame = NSRect(x:36,y:96,width:82,height:24); GameUIStyle.timer(timerLabel)
        status.frame = NSRect(x:132,y:98,width:492,height:22); GameUIStyle.status(status)
        status.alignment = .right
        let new = NSButton(title:"New puzzle",target:self,action:#selector(newPuzzle))
        newButton = new
        let stats = NSButton(title:"Statistics",target:self,action:#selector(showStatistics))
        // Stable groups, aligned to both edges of the board.
        let buttons: [(NSButton, CGFloat, CGFloat)] = [
            (play,36,34), (reset,78,68), (undo,154,68), (hint,230,110),
            (stats,408,98), (new,514,110)
        ]
        for (button,x,width) in buttons {
            button.frame = NSRect(x:x,y:40,width:width,height:GameUIStyle.controlHeight)
            GameUIStyle.button(button, primary: button === new)
            root.addSubview(button)
        }
        play.imagePosition = .imageOnly
        undo.target = self; undo.action = #selector(undoMove); undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = .command
        reset.target = self; reset.action = #selector(resetBoard)
        play.target = self; play.action = #selector(togglePlay)
        hint.target = self; hint.action = #selector(useHint)
        new.keyEquivalent = "n"; new.keyEquivalentModifierMask = .command
        hint.toolTip = "Three hints maximum; each unlocks after 30 seconds of active play."
        for v in [title,picker,board,status,timerLabel,toast] { root.addSubview(v) }
        toast.frame = NSRect(x:117,y:137,width:426,height:76)
        welcome.frame = board.frame
        welcome.wantsLayer = true
        welcome.layer?.backgroundColor = NSColor(calibratedWhite:0.965,alpha:1).cgColor
        let art = GameArtwork(frame:NSRect(x:206,y:314,width:188,height:188))
        welcome.addSubview(art)
        welcomeTitle.frame = NSRect(x:30,y:253,width:540,height:42)
        welcomeTitle.font = .systemFont(ofSize:28,weight:.bold); welcomeTitle.alignment = .center
        welcomeDetail.frame = NSRect(x:30,y:215,width:540,height:28)
        welcomeDetail.font = .systemFont(ofSize:16); welcomeDetail.textColor = .secondaryLabelColor; welcomeDetail.alignment = .center
        welcomePlay.frame = NSRect(x:195,y:142,width:210,height:48)
        welcomePlay.isBordered = false; welcomePlay.wantsLayer = true; welcomePlay.layer?.cornerRadius = 14
        welcomePlay.layer?.backgroundColor = NSColor.systemTeal.cgColor; welcomePlay.contentTintColor = .white
        welcomePlay.font = .systemFont(ofSize:16,weight:.semibold); welcomePlay.target = self; welcomePlay.action = #selector(togglePlay)
        for view in [welcomeTitle,welcomeDetail,welcomePlay] { welcome.addSubview(view) }
        root.addSubview(welcome)
        statisticsScreen.isHidden = true
        root.addSubview(statisticsScreen)
        statisticsScreen.onClose = { [weak self] in
            self?.picker.isHidden = false
            self?.window.makeFirstResponder(self?.board)
        }

        board.onInput = { [weak self] in self?.lastInput = Date() }
        board.onMessage = { [weak self] message in self?.status.stringValue = message }
        board.onRectangle = { [weak self] r in self?.place(r) }
        board.onRemove = { [weak self] c in self?.remove(c) }
    }
    private func save() {
        if let session { snapshot.sessions[String(difficulty.rawValue)] = session }
        snapshot.selected = difficulty.rawValue
        store.snapshot.patches = snapshot; store.save()
    }
    private func restore() {
        board.puzzle = session?.record.puzzle; board.placed = session?.placed ?? []
        paused = true; board.enabled = session?.record.solved == true; toast.dismiss(); refresh()
    }
    private func refresh() {
        let seconds = Int(session?.record.activeSeconds ?? 0)
        timerLabel.stringValue = String(format:"%02d:%02d",seconds/60,seconds%60)
        let solved = session?.record.solved == true
        board.locked = solved
        let showWelcome = (paused || loading) && !solved
        welcome.isHidden = !showWelcome
        welcomeTitle.stringValue = loading ? "Finding your next puzzle…" : session == nil ? "Everything in its place." : "A little pause. Then, a perfect fit."
        welcomeDetail.stringValue = session == nil ? "One clue. One rectangle. Fill every square." : "Your progress is saved. Continue at your own pace."
        welcomePlay.title = session == nil ? "Play Patches  →" : "Continue puzzle  →"
        welcomePlay.isEnabled = !loading
        for button in [undo,reset,hint,play,newButton!] { button.isHidden = showWelcome }
        timerLabel.isHidden = showWelcome; status.isHidden = showWelcome

        let playLabel = paused ? "Resume" : "Pause"
        play.title = ""
        play.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: playLabel)
        play.imagePosition = .imageOnly
        play.toolTip = playLabel; play.setAccessibilityLabel(playLabel)
        play.isEnabled = !loading && !solved
        undo.isEnabled = !paused && !solved && !(session?.undo.isEmpty ?? true)
        reset.isEnabled = !paused && !solved && !(session?.placed.isEmpty ?? true)
        let wait = Int(ceil(max(0,(session?.record.nextHintAt ?? 30)-(session?.record.activeSeconds ?? 0))))
        let hints = session?.record.hints ?? 0
        hint.title = hints >= 3 ? "Hints used" : wait > 0 ? "Hint · \(wait)s" : "Hint"
        hint.isEnabled = !paused && !solved && !loading && hints < 3 && wait == 0
        if loading { status.stringValue = "Creating your puzzle…" }
        else if solved { status.stringValue = "Puzzle complete · \(session?.record.verdict ?? "") for you" }
        else if paused { status.stringValue = session == nil ? "Ready when you are · Press Play" : "Paused · Progress saved" }

    }
    @objc private func togglePlay() {
        guard !loading else { return }
        if session == nil { newPuzzle(); return }
        if paused { paused = false; board.enabled = true; lastTick = Date(); lastInput = Date(); status.stringValue = "\(session!.placed.reduce(0) { $0+$1.area }) / \(session!.record.puzzle.size*session!.record.puzzle.size) cells filled"; window.makeFirstResponder(board) }
        else { pause() }
        refresh()
    }
    private func pause() {
        finishInterval(); paused = true; board.enabled = session?.record.solved == true; save(); refresh()
    }
    func windowDidResignKey(_ notification:Notification) { if !paused { tick(); pause() } }
    func windowWillClose(_ notification:Notification) { pause() }
    func flush() { if !paused { tick() }; finishInterval(); save() }
    private func tick() {
        let now = Date(), delta = now.timeIntervalSince(lastTick); lastTick = now
        guard !paused, !loading, session?.record.solved == false else { return }
        guard window.isKeyWindow, NSApp.isActive, delta >= 0, delta < 1 else { pause(); return }
        if now.timeIntervalSince(lastInput) >= 30 { pause(); return }
        session?.record.activeSeconds += delta; interval += delta
        if now.timeIntervalSince(lastSave) >= 2 { lastSave = now; save() }
        refresh()
    }
    private func finishInterval() {
        if interval > 0 { session?.record.intervals.append(interval) }; interval = 0
    }
    private func changeDifficulty(_ d:Difficulty) {
        if !paused { tick() }; pause(); generation = UUID(); loading = false
        difficulty = d; session = snapshot.sessions[String(d.rawValue)]; restore(); save()
    }
    @objc private func newPuzzle() {
        if !paused { tick() }; pause(); loading = true; board.enabled = false; toast.dismiss(); refresh()
        let token = UUID(); generation = token
        let d = difficulty, records = snapshot.records
        let excluded = records.map(\.puzzle) + snapshot.sessions.values.map { $0.record.puzzle }
        DispatchQueue.global(qos:.userInitiated).async { [weak self] in
            var rng = PuzzleRandom(); let model = PatchesModel(records)
            let puzzle = model.select(d,excluding:excluded,using:&rng)
            var record = PatchesRecord(puzzle:puzzle,requested:d.rawValue)
            record.targets = model.targets; record.forecast = model.forecast(puzzle).probabilities
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.session = PatchesSession(record:record); self.loading = false; self.restore(); self.save()
                if self.isPresented && self.window.isKeyWindow && NSApp.isActive { self.togglePlay() }
            }
        }
    }
    private func error(_ message:String) { board.feedback(.generic); status.stringValue = message }
    private func place(_ r:PatchRect) {
        guard !paused, let s = session, !s.record.solved else { return }
        guard s.record.puzzle.valid(r), let clue = s.record.puzzle.clueIndex(r) else { error("Use exactly one clue; match its area and shape"); return }
        let kept = s.placed.filter { s.record.puzzle.clueIndex($0) != clue }
        guard s.record.puzzle.legal(kept+[r]) else { error("Patches cannot overlap · Remove the neighboring patch first"); return }
        guard !s.placed.contains(r) else { return }
        commit(kept+[r],corrections:s.placed.filter { !kept.contains($0) }.reduce(0) { $0+$1.area })
    }
    private func remove(_ c:Cell) {
        guard !paused, let s = session, !s.record.solved, let r = s.placed.first(where: { $0.contains(c) }) else { return }
        commit(s.placed.filter { $0 != r },corrections:r.area)
    }
    private func commit(_ placed:[PatchRect],corrections:Int = 0, pushUndo:Bool = true) {
        tick(); finishInterval()
        guard !paused, var s = session, !s.record.solved else { return }
        if pushUndo { s.undo.append(s.placed); if s.undo.count > 100 { s.undo.removeFirst() } }
        s.record.corrections += corrections; s.placed = placed
        s.record.solved = s.record.puzzle.complete(placed)
        if s.record.solved {
            s.record.verdict = PatchesModel.verdict(s.record)
            snapshot.records.removeAll { $0.id == s.record.id }; snapshot.records.append(s.record)
        }
        session = s; board.placed = placed; board.feedback(s.record.solved ? .levelChange : .alignment)
        status.stringValue = "\(placed.reduce(0) { $0+$1.area }) / \(s.record.puzzle.size*s.record.puzzle.size) cells filled"
        if s.record.solved { paused = true; toast.show(verdict:s.record.verdict,accent:.systemTeal) }
        save(); refresh()
    }
    @objc private func undoMove() {
        guard !paused, session?.record.solved == false, let previous = session?.undo.popLast() else { return }
        let removed = session!.placed.filter { !previous.contains($0) }.reduce(0) { $0+$1.area }
        commit(previous,corrections:removed,pushUndo:false)
    }
    @objc private func resetBoard() {
        guard !paused, session?.record.solved == false else { return }
        session?.record.resets += 1
        commit([],corrections:session!.placed.reduce(0) { $0+$1.area })
    }
    @objc private func useHint() {
        guard !paused, let s = session, !s.record.solved, s.record.hints < 3, s.record.activeSeconds >= s.record.nextHintAt else { return }
        let p = s.record.puzzle
        if let wrong = s.placed.first(where: { !p.solution.contains($0) }) {
            session?.record.hints += 1; session?.record.nextHintAt = s.record.activeSeconds+30
            commit(s.placed.filter { $0 != wrong },corrections:wrong.area)
            status.stringValue = "Hint: removed a patch that blocks the solution"
        } else if let next = p.solution.first(where: { !s.placed.contains($0) }) {
            session?.record.hints += 1; session?.record.nextHintAt = s.record.activeSeconds+30
            commit(s.placed+[next]); if session?.record.solved != true { status.stringValue = "Hint: placed one rectangle · Undo to try it yourself" }
        }
    }
    @objc private func showStatistics() {
        if !paused { tick(); pause() }
        picker.isHidden = true
        statisticsScreen.show(records:snapshot.records)
        window.makeFirstResponder(statisticsScreen)
    }
}
