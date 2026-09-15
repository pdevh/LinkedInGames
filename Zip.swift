import AppKit

struct Cell: Hashable, Codable {
    let x: Int
    let y: Int
    func adjacent(to other: Cell) -> Bool { abs(x - other.x) + abs(y - other.y) == 1 }
}

struct Edge: Hashable, Codable {
    let a: Cell
    let b: Cell
    init(_ a: Cell, _ b: Cell) {
        if a.y < b.y || (a.y == b.y && a.x < b.x) { self.a = a; self.b = b }
        else { self.a = b; self.b = a }
    }
}

enum Difficulty: Int, CaseIterable {
    case easy, medium, hard
    var title: String { ["EASY", "MEDIUM", "HARD"][rawValue] }
    var size: Int { [5, 6, 7][rawValue] }
    var clueCount: Int { [5, 8, 11][rawValue] }
    var wallCount: Int { [0, 5, 13][rawValue] }
}

// Fast local generator for puzzle variation, seeded from system randomness once.
// Explicit seeds make generation tests reproducible; this is not used for security.
struct PuzzleRandom: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}

struct Puzzle: Codable {
    let size: Int
    let solution: [Cell]
    let clues: [Cell: Int]
    let walls: Set<Edge>

    func hintPrefix(for path: [Cell]) -> [Cell] {
        let correctCount = zip(path, solution).prefix { $0 == $1 }.count
        return Array(solution.prefix(max(1, correctCount)))
    }

    static func make(_ difficulty: Difficulty) -> Puzzle {
        var random = PuzzleRandom()
        return make(difficulty, using: &random)
    }
    static func make<R: RandomNumberGenerator>(_ difficulty: Difficulty, using random: inout R) -> Puzzle {
        let n = difficulty.size
        var path: [Cell] = []
        for y in 0..<n {
            let xs = y.isMultiple(of: 2) ? Array(0..<n) : Array((0..<n).reversed())
            for x in xs { path.append(Cell(x: x, y: y)) }
        }
        // Backbite moves preserve a full, non-repeating path while reshaping it.
        for _ in 0..<(n * n * 55) {
            let fromStart = Bool.random(using: &random)
            let end = fromStart ? path[0] : path[path.count - 1]
            let neighbors = [Cell(x: end.x - 1, y: end.y), Cell(x: end.x + 1, y: end.y),
                             Cell(x: end.x, y: end.y - 1), Cell(x: end.x, y: end.y + 1)]
                .filter { $0.x >= 0 && $0.x < n && $0.y >= 0 && $0.y < n }
            guard let neighbor = neighbors.randomElement(using: &random), let k = path.firstIndex(of: neighbor) else { continue }
            if fromStart && k > 1 { path[0..<k].reverse() }
            if !fromStart && k < path.count - 2 { path[(k + 1)..<path.count].reverse() }
        }
        let count = difficulty.clueCount
        var clues: [Cell: Int] = [:]
        for i in 0..<count {
            let index = i * (path.count - 1) / (count - 1)
            clues[path[index]] = i + 1
        }
        let solutionEdges = Set(zip(path, path.dropFirst()).map { Edge($0.0, $0.1) })
        var possibleWalls: [Edge] = []
        for y in 0..<n { for x in 0..<n {
            let c = Cell(x: x, y: y)
            if x + 1 < n { possibleWalls.append(Edge(c, Cell(x: x + 1, y: y))) }
            if y + 1 < n { possibleWalls.append(Edge(c, Cell(x: x, y: y + 1))) }
        }}
        possibleWalls.removeAll { solutionEdges.contains($0) }
        var walls = Set(possibleWalls.shuffled(using: &random).prefix(difficulty.wallCount))
        while true {
            let puzzle = Puzzle(size: n, solution: path, clues: clues, walls: walls)
            let check = puzzle.checkSolutions()
            if check.exhausted && check.count == 1 { return puzzle }
            // Remove an alternative route without ever blocking the intended solution.
            let alternativeEdges = zip(check.alternative, check.alternative.dropFirst()).map { Edge($0, $1) }
            let candidates = alternativeEdges.filter { !solutionEdges.contains($0) && !walls.contains($0) }
            let remaining = possibleWalls.filter { !walls.contains($0) }
            guard let wall = candidates.randomElement(using: &random) ?? remaining.randomElement(using: &random) else {
                preconditionFailure("A full path with every other edge blocked must be unique")
            }
            walls.insert(wall)
        }
    }

    // Count up to two solutions. A search budget is never treated as proof of uniqueness.
    func checkSolutions(budget: Int = 80_000) -> (count: Int, exhausted: Bool, alternative: [Cell]) {
        let cells = (0..<(size * size)).map { Cell(x: $0 % size, y: $0 / size) }
        // At most four neighbors per cell; bitsets avoid per-node flood-fill arrays.
        let neighbors: [UInt64] = cells.map { cell in
            var mask: UInt64 = 0
            for neighbor in [Cell(x: cell.x-1, y: cell.y), Cell(x: cell.x+1, y: cell.y),
                             Cell(x: cell.x, y: cell.y-1), Cell(x: cell.x, y: cell.y+1)] {
                if neighbor.x >= 0 && neighbor.x < size && neighbor.y >= 0 && neighbor.y < size
                    && !walls.contains(Edge(cell, neighbor)) {
                    mask |= UInt64(1) << (neighbor.y*size + neighbor.x)
                }
            }
            return mask
        }
        let numbers = cells.map { clues[$0] ?? 0 }
        let start = cells.firstIndex(of: solution[0])!
        let end = cells.firstIndex(of: solution.last!)!
        let all = (UInt64(1) << cells.count) - 1
        var route = [start], count = 0, nodes = 0, exhausted = true
        var alternative: [Cell] = []
        func search(_ head: Int, _ visited: UInt64, _ next: Int) {
            if count >= 2 || !exhausted { return }
            nodes += 1
            if nodes > budget { exhausted = false; return }
            if head == end {
                if visited == all {
                    count += 1
                    let result = route.map { cells[$0] }
                    if result != solution { alternative = result }
                }
                return
            }
            // Every unvisited square must remain connected to the current head.
            let remaining = all & ~visited
            var reached: UInt64 = 0
            var frontier = neighbors[head] & remaining
            while frontier != 0 {
                let at = frontier.trailingZeroBitCount
                frontier &= frontier - 1
                reached |= UInt64(1) << at
                frontier |= neighbors[at] & remaining & ~reached
            }
            if reached != remaining { return }
            var options = neighbors[head] & remaining
            while options != 0 {
                let neighbor = options.trailingZeroBitCount
                let bit = UInt64(1) << neighbor
                options &= options - 1
                if visited & bit != 0 { continue }
                let number = numbers[neighbor]
                if number != 0 && number != next { continue }
                if neighbor == end && visited | bit != all { continue }
                route.append(neighbor)
                search(neighbor, visited | bit, next + (number == 0 ? 0 : 1))
                route.removeLast()
            }
        }
        search(start, UInt64(1) << start, 2)
        return (count, exhausted, alternative)
    }
}

final class BoardView: NSView {
    var puzzle = Puzzle(size: 1, solution: [Cell(x: 0, y: 0)], clues: [Cell(x: 0, y: 0): 1], walls: []) { didSet { choosePalette(); reset(); needsDisplay = true } }
    var path: [Cell] = [] { didSet { hintCell = nil; needsDisplay = true; onProgress?(path.count, puzzle.size * puzzle.size) } }
    var onProgress: ((Int, Int) -> Void)?
    var onWin: (() -> Void)?
    var onAction: ((String, Int) -> Void)?
    var onInput: (() -> Void)?
    private var hintCell: Cell?
    func revealHint() -> String {
        guard !isWon else { return "Puzzle complete." }
        let corrected = puzzle.hintPrefix(for: path)
        let removed = max(0, path.count - corrected.count)
        dragging = false; previousPoint = nil
        if removed > 0 { onAction?("hintRewindCells", removed) }
        if path != corrected { path = corrected }
        hintCell = puzzle.solution.count > path.count ? puzzle.solution[path.count] : nil
        haptics.perform(.levelChange, performanceTime: .now)
        needsDisplay = true
        return "Follow the arrow to the next square."
    }
    var isWon = false
    private var completionProgress: CGFloat = 0
    private var celebrationTimer: Timer?
    private var dragging = false
    private var previousPoint: NSPoint?
    private var lastErrorTime: TimeInterval = 0
    private let haptics = NSHapticFeedbackManager.defaultPerformer
    private let paper = NSColor(calibratedRed: 0.985, green: 0.989, blue: 1.0, alpha: 1)
    private let grid = NSColor(calibratedRed: 0.69, green: 0.71, blue: 0.72, alpha: 1)
    private var trail = NSColor(calibratedRed: 0.97, green: 0.26, blue: 0.19, alpha: 1)
    private var finish = NSColor(calibratedRed: 0.96, green: 0.25, blue: 0.63, alpha: 1)
    var accentColor: NSColor { trail }
    func restore(path savedPath: [Cell], completed: Bool) {
        path = savedPath; isWon = completed
        completionProgress = completed ? 1 : 0; needsDisplay = true
    }

    private func choosePalette() {
        let palettes: [(NSColor, NSColor)] = [
            (.init(calibratedRed: 0.98, green: 0.42, blue: 0.08, alpha: 1), .init(calibratedRed: 1.00, green: 0.76, blue: 0.05, alpha: 1)),
            (.init(calibratedRed: 0.05, green: 0.42, blue: 0.92, alpha: 1), .init(calibratedRed: 0.44, green: 0.24, blue: 0.84, alpha: 1)),
            (.init(calibratedRed: 0.96, green: 0.25, blue: 0.18, alpha: 1), .init(calibratedRed: 0.92, green: 0.20, blue: 0.58, alpha: 1)),
            (.init(calibratedRed: 0.08, green: 0.62, blue: 0.43, alpha: 1), .init(calibratedRed: 0.03, green: 0.62, blue: 0.72, alpha: 1))
        ]
        (trail, finish) = palettes.randomElement()!
    }
    private var cellGlow: NSColor { trail.blended(withFraction: 0.78, of: .white)! }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { undo() }
        else { super.keyDown(with: event) }
    }
    func reset() {
        celebrationTimer?.invalidate(); celebrationTimer = nil
        completionProgress = 0; dragging = false; previousPoint = nil; isWon = false; path = []
    }
    func undo() {
        guard !path.isEmpty && !isWon else { return }
        onAction?("undo", 1)
        path.removeLast()
        haptics.perform(.generic, performanceTime: .now)
    }
    private func boardRect() -> NSRect {
        let side = min(bounds.width - 12, bounds.height - 12)
        return NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
    }
    private func center(_ cell: Cell, in rect: NSRect, step: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + (CGFloat(cell.x) + 0.5) * step,
                y: rect.minY + (CGFloat(cell.y) + 0.5) * step)
    }
    private func cell(at point: NSPoint) -> Cell? {
        let r = boardRect(), step = r.width / CGFloat(puzzle.size)
        guard r.contains(point) else { return nil }
        return Cell(x: min(puzzle.size - 1, Int((point.x - r.minX) / step)),
                    y: min(puzzle.size - 1, Int((point.y - r.minY) / step)))
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let r = boardRect(), n = puzzle.size, step = r.width / CGFloat(n)
        let rounded = NSBezierPath(roundedRect: r, xRadius: step * 0.46, yRadius: step * 0.46)
        paper.setFill(); rounded.fill()
        NSGraphicsContext.current?.saveGraphicsState()
        rounded.addClip()
        if let start = puzzle.clues.first(where: { $0.value == 1 })?.key, path.isEmpty {
            cellGlow.withAlphaComponent(1 - completionProgress).setFill()
            NSRect(x: r.minX + CGFloat(start.x) * step, y: r.minY + CGFloat(start.y) * step,
                   width: step, height: step).fill()
        }
        for c in path {
            cellGlow.withAlphaComponent(1 - completionProgress).setFill()
            NSRect(x: r.minX + CGFloat(c.x) * step, y: r.minY + CGFloat(c.y) * step,
                   width: step, height: step).fill()
        }
        grid.withAlphaComponent(1 - completionProgress * 0.82).setStroke()
        for i in 1..<n {
            let p = NSBezierPath(); p.lineWidth = 1.3
            let at = CGFloat(i) * step
            p.move(to: NSPoint(x: r.minX + at, y: r.minY)); p.line(to: NSPoint(x: r.minX + at, y: r.maxY))
            p.move(to: NSPoint(x: r.minX, y: r.minY + at)); p.line(to: NSPoint(x: r.maxX, y: r.minY + at))
            p.stroke()
        }
        if !path.isEmpty {
            let pulse = sin(completionProgress * .pi) * 0.07
            let lineWidth = step * (0.50 + pulse)
            if isWon {
                for i in 1..<path.count {
                    let position = CGFloat(i - 1) / CGFloat(max(1, path.count - 2))
                    let target = trail.blended(withFraction: position, of: finish)!
                    let color = trail.blended(withFraction: completionProgress, of: target)!
                    let segment = NSBezierPath(); segment.lineCapStyle = .round
                    segment.lineWidth = lineWidth
                    segment.move(to: center(path[i - 1], in: r, step: step))
                    segment.line(to: center(path[i], in: r, step: step))
                    color.setStroke(); segment.stroke()
                }
            } else {
                let p = NSBezierPath(); p.lineCapStyle = .round; p.lineJoinStyle = .round
                p.lineWidth = lineWidth
                p.move(to: center(path[0], in: r, step: step))
                for c in path.dropFirst() { p.line(to: center(c, in: r, step: step)) }
                trail.setStroke(); p.stroke()
            }
        }
        NSColor.black.setStroke()
        for edge in puzzle.walls {
            let p = NSBezierPath(); p.lineWidth = max(8, step * 0.095)
            if edge.a.y == edge.b.y {
                let x = r.minX + CGFloat(max(edge.a.x, edge.b.x)) * step
                let y = r.minY + CGFloat(edge.a.y) * step
                p.move(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x, y: y + step))
            } else {
                let x = r.minX + CGFloat(edge.a.x) * step
                let y = r.minY + CGFloat(max(edge.a.y, edge.b.y)) * step
                p.move(to: NSPoint(x: x, y: y)); p.line(to: NSPoint(x: x + step, y: y))
            }
            p.stroke()
        }
        for (cell, number) in puzzle.clues {
            let c = center(cell, in: r, step: step)
            let diameter = step * 0.62
            NSColor(calibratedWhite: 0.065, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: c.x - diameter/2, y: c.y - diameter/2,
                                        width: diameter, height: diameter)).fill()
            let font = NSFont.systemFont(ofSize: step * (number >= 10 ? 0.24 : 0.30), weight: .bold)
            let s = NSAttributedString(string: "\(number)", attributes: [.font: font, .foregroundColor: NSColor.white])
            let size = s.size()
            s.draw(at: NSPoint(x: c.x - size.width/2, y: c.y - size.height/2))
        }
        if let hintCell, let last = path.last {
            let from = center(last, in: r, step: step)
            let to = center(hintCell, in: r, step: step)
            let dx = (to.x - from.x) / step, dy = (to.y - from.y) / step
            // Keep the arrow between cell centers, clear of numbered circles.
            let start = NSPoint(x: from.x + dx * step * 0.34, y: from.y + dy * step * 0.34)
            let tip = NSPoint(x: from.x + dx * step * 0.66, y: from.y + dy * step * 0.66)
            let arrow = NSBezierPath(); arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            arrow.move(to: start); arrow.line(to: tip)
            arrow.move(to: NSPoint(x: tip.x - dx * step * 0.11 - dy * step * 0.10,
                                  y: tip.y - dy * step * 0.11 + dx * step * 0.10))
            arrow.line(to: tip)
            arrow.line(to: NSPoint(x: tip.x - dx * step * 0.11 + dy * step * 0.10,
                                  y: tip.y - dy * step * 0.11 - dx * step * 0.10))
            NSColor.white.setStroke(); arrow.lineWidth = 8; arrow.stroke()
            NSColor(calibratedWhite: 0.12, alpha: 1).setStroke(); arrow.lineWidth = 4; arrow.stroke()
        }
        NSGraphicsContext.current?.restoreGraphicsState()
        grid.withAlphaComponent(1 - completionProgress * 0.82).setStroke()
        rounded.lineWidth = 1.5; rounded.stroke()
    }
    override func mouseDown(with event: NSEvent) {
        guard !isWon && !isHidden else { return }
        onInput?()
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        guard let c = cell(at: point) else { return }
        if path.isEmpty {
            guard puzzle.clues[c] == 1 else { errorHaptic(); return }
            path = [c]; haptics.perform(.alignment, performanceTime: .now)
        } else if let index = path.firstIndex(of: c) {
            if index < path.count - 1 { onAction?("backtrack", path.count - index - 1) }
            if index < path.count - 1 { path = Array(path.prefix(index + 1)) }
        } else { errorHaptic(); return }
        dragging = true; previousPoint = point
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragging && !isWon && !isHidden else { return }
        onInput?()
        let point = convert(event.locationInWindow, from: nil)
        let previous = previousPoint ?? point
        let distance = hypot(point.x - previous.x, point.y - previous.y)
        let step = boardRect().width / CGFloat(puzzle.size)
        let samples = max(1, Int(ceil(distance / (step * 0.18))))
        for i in 1...samples {
            let t = CGFloat(i) / CGFloat(samples)
            let sample = NSPoint(x: previous.x + (point.x - previous.x) * t,
                                 y: previous.y + (point.y - previous.y) * t)
            if let c = cell(at: sample) { advance(to: c) }
        }
        previousPoint = point
    }
    override func mouseUp(with event: NSEvent) { dragging = false; previousPoint = nil }
    private func advance(to c: Cell) {
        guard let last = path.last, c != last else { return }
        guard c.adjacent(to: last) else { return }
        if let index = path.firstIndex(of: c) {
            if index == path.count - 2 {
                onAction?("backtrack", 1)
                path.removeLast(); haptics.perform(.alignment, performanceTime: .now)
            }
            return
        }
        guard !puzzle.walls.contains(Edge(last, c)) else { errorHaptic(); return }
        if let clue = puzzle.clues[c] {
            let next = path.compactMap { puzzle.clues[$0] }.max().map { $0 + 1 } ?? 1
            guard clue == next else { errorHaptic(); return }
            guard clue != puzzle.clues.count || path.count == puzzle.size * puzzle.size - 1 else {
                errorHaptic(); return
            }
        }
        onAction?("move", 1)
        path.append(c)
        haptics.perform(puzzle.clues[c] == nil ? .alignment : .levelChange, performanceTime: .now)
        if path.count == puzzle.size * puzzle.size {
            isWon = true; dragging = false
            haptics.perform(.levelChange, performanceTime: .now)
            startCelebration()
            onWin?()
        }
    }
    private func startCelebration() {
        celebrationTimer?.invalidate()
        let began = ProcessInfo.processInfo.systemUptime
        celebrationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            completionProgress = min(1, CGFloat((ProcessInfo.processInfo.systemUptime - began) / 0.72))
            needsDisplay = true
            if completionProgress >= 1 { timer.invalidate(); celebrationTimer = nil }
        }
    }
    private func errorHaptic() {
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastErrorTime > 0.18 {
            onAction?("invalid", 1)
            haptics.perform(.generic, performanceTime: .now)
            lastErrorTime = now
        }
    }
}

final class DifficultyPicker: NSView {
    var selected = 0 { didSet { needsDisplay = true } }
    var onChange: ((Int) -> Void)?
    private let labels = ["Easy", "Medium", "Hard"]
    override var intrinsicContentSize: NSSize { NSSize(width: 226, height: 38) }
    override func draw(_ dirtyRect: NSRect) {
        let outer = bounds.insetBy(dx: 1, dy: 1)
        NSColor(calibratedWhite: 0.90, alpha: 1).setFill()
        NSBezierPath(roundedRect: outer, xRadius: 11, yRadius: 11).fill()
        let width = outer.width / 3
        let selectedRect = NSRect(x: outer.minX + CGFloat(selected) * width + 3,
                                  y: outer.minY + 3, width: width - 6, height: outer.height - 6)
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 4; shadow.shadowOffset = NSSize(width: 0, height: -1)
        NSGraphicsContext.saveGraphicsState(); shadow.set()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: selectedRect, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
        for (index, label) in labels.enumerated() {
            let font = NSFont.systemFont(ofSize: 13, weight: index == selected ? .semibold : .medium)
            let color = index == selected ? NSColor(calibratedWhite: 0.08, alpha: 1) : NSColor(calibratedWhite: 0.42, alpha: 1)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            let size = text.size()
            text.draw(at: NSPoint(x: outer.minX + CGFloat(index) * width + (width - size.width) / 2,
                                  y: outer.midY - size.height / 2))
        }
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let choice = min(2, max(0, Int(point.x / (bounds.width / 3))))
        guard choice != selected else { return }
        selected = choice
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        onChange?(choice)
    }
}

final class WindowDragView: NSView {
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}

final class WelcomeMark: NSView {
    var paused = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        NSColor.white.setFill()
        let tile = NSBezierPath(roundedRect: r, xRadius: 26, yRadius: 26); tile.fill()
        NSColor(calibratedWhite: 0.84, alpha: 1).setStroke(); tile.lineWidth = 1; tile.stroke()
        let step = r.width / 3
        NSGraphicsContext.saveGraphicsState(); tile.addClip()
        NSColor(calibratedWhite: 0.91, alpha: 1).setStroke()
        for i in 1...2 {
            let line = NSBezierPath(); line.lineWidth = 1
            line.move(to: NSPoint(x: r.minX + CGFloat(i)*step, y: r.minY))
            line.line(to: NSPoint(x: r.minX + CGFloat(i)*step, y: r.maxY))
            line.move(to: NSPoint(x: r.minX, y: r.minY + CGFloat(i)*step))
            line.line(to: NSPoint(x: r.maxX, y: r.minY + CGFloat(i)*step)); line.stroke()
        }
        let points = [(0,0),(1,0),(1,1),(0,1),(0,2),(1,2),(2,2),(2,1),(2,0)].map {
            NSPoint(x: r.minX + (CGFloat($0.0)+0.5)*step, y: r.minY + (CGFloat($0.1)+0.5)*step)
        }
        let path = NSBezierPath(); path.lineWidth = step*0.40; path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }
        NSColor(calibratedRed: 0.94, green: 0.23, blue: 0.17, alpha: 1).setStroke(); path.stroke()
        for (i, at) in [points.first!, points.last!].enumerated() {
            let d = step*0.66
            NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: at.x-d/2, y: at.y-d/2, width: d, height: d)).fill()
            let text = NSAttributedString(string: paused ? "Ⅱ" : "\(i+1)", attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .bold), .foregroundColor: NSColor.white])
            text.draw(at: NSPoint(x: at.x-text.size().width/2, y: at.y-text.size().height/2))
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

struct DifficultyMeasurements: Codable {
    var collectedFromStart = true
    // Gaps of at least two seconds are pause candidates, not proven thinking time.
    var moveIntervals: [Double] = []
    var pauseThresholdSeconds: Double = 2
    var activeSecondsPerCell: Double = 0
    var activeSecondsPerMove: Double?
    var backtrackedCellsPerCell: Double = 0
    var pauseCount: Int = 0
    var pauseSeconds: Double = 0
    var pausesPerCell: Double = 0
    var pauseSecondsPerCell: Double = 0
    var assisted = false
}

struct PlayStatistics: Codable {
    var experiencedDifficulty: String?
    var predictedEffort: Double?
    var classificationModelVersion: Int?
    var classificationSamples: Int?
    var measurements: DifficultyMeasurements?
    var id = UUID()
    var createdAt = Date()
    var startedAt: Date?
    var endedAt: Date?
    var outcome = "inProgress"
    var nextHintAt: Double?
    var activeSeconds: Double = 0
    var elapsedSeconds: Double = 0
    var actions: [String: Int] = [:]
    let difficulty: String
    let puzzle: Puzzle
    let features: [String: Int]
    let generatorVersion: Int

    init(puzzle: Puzzle, difficulty: Difficulty) {
        measurements = DifficultyMeasurements()
        generatorVersion = 3
        self.puzzle = puzzle; self.difficulty = difficulty.title
        features = Self.extractFeatures(puzzle)
    }
    static func extractFeatures(_ puzzle: Puzzle) -> [String: Int] {
        let path = puzzle.solution
        let indices = path.indices.filter { puzzle.clues[path[$0]] != nil }
        let gaps = zip(indices, indices.dropFirst()).map { $1 - $0 }
        let turns = (1..<(path.count - 1)).filter {
            path[$0].x - path[$0 - 1].x != path[$0 + 1].x - path[$0].x ||
            path[$0].y - path[$0 - 1].y != path[$0 + 1].y - path[$0].y
        }.count
        let junctions = path.reduce(0) { total, cell in
            let degree = [Cell(x: cell.x-1, y: cell.y), Cell(x: cell.x+1, y: cell.y),
                          Cell(x: cell.x, y: cell.y-1), Cell(x: cell.x, y: cell.y+1)].reduce(0) { degree, neighbor in
                degree + (neighbor.x >= 0 && neighbor.x < puzzle.size && neighbor.y >= 0
                    && neighbor.y < puzzle.size && !puzzle.walls.contains(Edge(cell, neighbor)) ? 1 : 0)
            }
            return total + (degree >= 3 ? 1 : 0)
        }
        let checkpointDetour = zip(indices, indices.dropFirst()).reduce(0) { total, pair in
            let a = path[pair.0], b = path[pair.1]
            return total + pair.1 - pair.0 - abs(a.x-b.x) - abs(a.y-b.y)
        }
        let meanGap = Double(gaps.reduce(0,+)) / Double(max(1,gaps.count))
        let spread = gaps.reduce(0.0) { $0 + pow(Double($1)-meanGap, 2) } / Double(max(1,gaps.count))
        let forced = path.count - junctions
        return ["checkpointDetour": checkpointDetour, "checkpointGapSpread": Int(spread), "forcedCells": forced, "cells": path.count, "gridSize": puzzle.size, "clues": puzzle.clues.count,
                    "walls": puzzle.walls.count, "solutionTurns": turns,
                    "maxCheckpointGap": gaps.max() ?? 0, "junctionCells": junctions]
    }
    mutating func updateMeasurements() {
        guard var measured = measurements else { return }
        let cells = Double(puzzle.size * puzzle.size)
        let backtracked = (actions["backtrack"] ?? 0) + (actions["undo"] ?? 0)
        let moves = (actions["move"] ?? 0) + backtracked
        measured.activeSecondsPerCell = activeSeconds / cells
        measured.activeSecondsPerMove = moves > 0 ? activeSeconds / Double(moves) : nil
        measured.backtrackedCellsPerCell = Double(backtracked) / cells
        let pauses = measured.moveIntervals.filter { $0 >= measured.pauseThresholdSeconds }
        measured.pauseCount = pauses.count
        measured.pauseSeconds = pauses.reduce(0, +)
        measured.pausesPerCell = Double(pauses.count) / cells
        measured.pauseSecondsPerCell = measured.pauseSeconds / cells
        measured.assisted = (actions["hint"] ?? 0) > 0
        measurements = measured
    }
}

enum HintPolicy {
    static let limit = 3
    static let delay: Double = 30
    static func wait(active: Double, next: Double?) -> Int {
        max(0, Int(ceil((next ?? delay) - active)))
    }
}

struct SavedProgress: Codable {
    var statistics: PlayStatistics? = nil
    var solved: [Puzzle] = []
    var current: Puzzle?
    var path: [Cell] = []
    var elapsed: TimeInterval = 0
    var completed = false
}

final class GameController: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let board = BoardView()
    private let title = NSTextField(labelWithString: "Zip")
    private let subtitle = NSTextField(labelWithString: "Drag from 1 · visit every square in order")
    private let timerLabel = NSTextField(labelWithString: "00:00")
    private let progressLabel = NSTextField(labelWithString: "0 / 25")
    private let difficultyControl = DifficultyPicker()
    private let statisticsButton = NSButton(title: "Statistics", target: nil, action: nil)
    private let statisticsScreen = StatisticsScreen()
    private let successPanel = NSView()
    private let difficultyToast = DifficultyToast()
    private var playControls: [NSView] = []
    private let hintButton = NSButton(title: "Hint · 30s", target: nil, action: nil)
    private let successButton = NSButton(title: "New puzzle  →", target: nil, action: nil)
    private let successTitle = NSTextField(labelWithString: "Puzzle complete")
    private let successTime = NSTextField(labelWithString: "")
    private var difficulty: Difficulty = .easy
    private var progress = SavedProgress()
    private var lastStatisticsTick = Date()
    private var activeGap: Double = 0
    private var store: ProgressStore!
    private var paused = false
    private var startScreen = true
    private var lastInput = Date()
    private var lastCheckpoint = Date()
    private var cachedModel: AdaptiveDifficulty?
    private var recordsRevision = 0
    private var cachedRevision = -1
    private let cover = NSView()
    private let coverMark = WelcomeMark()
    private let coverTitle = NSTextField(labelWithString: "Ready for a little Zip?")
    private let coverDetail = NSTextField(labelWithString: "One path. Every square.")
    private let coverButton = NSButton(title: "Play", target: nil, action: nil)
    private var loading = false
    private var restoring = false
    private var generationID = UUID()
    private let loadingLabel = NSTextField(labelWithString: "Creating your puzzle…")
    private let spinner = NSProgressIndicator()

    private func installApplicationMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Zip", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Zip", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = .command
        appMenu.addItem(quitItem)
        appMenuItem.submenu = appMenu

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        let closeItem = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = .command
        windowMenu.addItem(closeItem)
        windowMenuItem.submenu = windowMenu

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    private var storageKey: String { "zip.progress.v1.\(difficulty.rawValue)" }
    private func saveProgress() {
        guard !loading && !restoring && !startScreen && progress.current != nil else { return }
        progress.path = board.path
        progress.elapsed = startedAt.map { Date().timeIntervalSince($0) } ?? elapsed
        progress.statistics?.elapsedSeconds = progress.elapsed
        progress.statistics?.updateMeasurements()
        store.snapshot.progress[storageKey] = progress
        store.save()
    }
    private func archiveStatistics(outcome: String) {
        guard var record = progress.statistics, record.startedAt != nil else { return }
        record.outcome = outcome; record.endedAt = Date()
        record.elapsedSeconds = progress.elapsed
        record.updateMeasurements()
        if outcome == "solved" {
            let model = cachedRevision == recordsRevision ? cachedModel : nil
            let assessment = model ?? AdaptiveDifficulty(records: store.snapshot.records.filter { $0.id != record.id })
            record.experiencedDifficulty = assessment.experiencedDifficulty(for: record)?.title.lowercased()
        }
        progress.statistics = record
        var records = store.snapshot.records
        records.removeAll { $0.id == record.id }; records.append(record)
        store.snapshot.records = records
        recordsRevision += 1
        prepareModel()
    }
    private func updateLevel() {
        let level = progress.solved.count + (progress.completed ? 0 : 1)
        subtitle.stringValue = "Level \(max(1, level))  ·  \(progress.solved.count) solved"
    }
    private func loadProgress() {
        activeGap = 0
        restoring = true
        progress = store.snapshot.progress[storageKey] ?? SavedProgress()
        restoring = false
        guard let puzzle = progress.current else { newGame(); return }
        if progress.statistics == nil && !progress.completed {
            progress.statistics = PlayStatistics(puzzle: puzzle, difficulty: difficulty)
            progress.statistics?.measurements?.collectedFromStart = progress.path.isEmpty && progress.elapsed == 0
        } else if progress.statistics?.measurements == nil && !progress.completed {
            progress.statistics?.measurements = DifficultyMeasurements()
            progress.statistics?.measurements?.collectedFromStart = false
        }
        restoring = true
        board.puzzle = puzzle
        board.restore(path: progress.path, completed: progress.completed)
        elapsed = progress.elapsed
        startedAt = !progress.completed && elapsed > 0 ? Date().addingTimeInterval(-elapsed) : nil
        restoring = false
        tick(); updateLevel(); hideSuccessPanel()
        if progress.completed {
            successTime.stringValue = "Solved in \(timerLabel.stringValue)"
            showSuccessPanel()
        }
    }
    func applicationWillTerminate(_ notification: Notification) { saveProgress(); store?.flush() }
    func applicationDidResignActive(_ notification: Notification) {
        if !startScreen && !loading && !progress.completed && startedAt != nil { pauseGame() }
        activeGap = 0; lastStatisticsTick = Date(); saveProgress()
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        activeGap = 0; lastStatisticsTick = Date()
    }
    private var startedAt: Date?
    private var elapsed: TimeInterval = 0
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installApplicationMenu()
        do {
            let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            store = try ProgressStore(url: folder.appendingPathComponent("Zip/progress.json"))
        } catch {
            let alert = NSAlert(); alert.messageText = "Saved progress could not be read"
            alert.informativeText = "Your files have been left untouched. \(error.localizedDescription)"
            alert.runModal(); NSApp.terminate(nil); return
        }
        store.onError = { error in
            let alert = NSAlert(); alert.messageText = "Progress could not be saved"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) { NSApp.applicationIconImage = icon }
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 660, height: 820))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1).cgColor
        let windowDragArea = WindowDragView()
        window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1)
        window.center(); window.contentView = content
        window.isReleasedWhenClosed = false

        title.font = .systemFont(ofSize: 22, weight: .bold)
        title.textColor = NSColor(calibratedWhite: 0.10, alpha: 1)
        subtitle.font = .systemFont(ofSize: 14)
        subtitle.textColor = NSColor(calibratedWhite: 0.34, alpha: 1)
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        timerLabel.textColor = NSColor(calibratedWhite: 0.20, alpha: 1)
        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        progressLabel.textColor = NSColor(calibratedWhite: 0.36, alpha: 1)
        progressLabel.alignment = .right
        difficultyControl.onChange = { [weak self] selected in self?.changeDifficulty(selected) }

        let reset = NSButton(title: "Reset", target: self, action: #selector(resetGame))
        let new = NSButton(title: "New game", target: self, action: #selector(newGame))
        let undo = NSButton(title: "Undo", target: self, action: #selector(undoMove))
        successButton.target = self; successButton.action = #selector(newGame)
        hintButton.target = self; hintButton.action = #selector(useHint)
        statisticsButton.target = self; statisticsButton.action = #selector(showStatistics)
        hintButton.toolTip = "Up to 3 hints per puzzle. Unlocks after 30 seconds of active play, with 30 seconds between hints."
        playControls = [timerLabel, progressLabel, reset, undo, new, hintButton]
        for button in [reset, new, undo, hintButton, statisticsButton] {
            button.isBordered = false; button.font = .systemFont(ofSize: 14, weight: .semibold)
            button.contentTintColor = NSColor(calibratedWhite: 0.18, alpha: 1)
            button.wantsLayer = true; button.layer?.backgroundColor = NSColor.white.cgColor
            button.layer?.cornerRadius = 10
        }
        new.contentTintColor = .white
        new.layer?.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.23, blue: 0.17, alpha: 1).cgColor
        statisticsButton.layer?.backgroundColor = NSColor.white.cgColor
        successPanel.wantsLayer = true
        successPanel.isHidden = true
        successTitle.font = .systemFont(ofSize: 20, weight: .semibold); successTitle.alignment = .left
        successTime.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        successTime.textColor = NSColor(calibratedWhite: 0.42, alpha: 1); successTime.alignment = .left
        successButton.isBordered = false; successButton.font = .systemFont(ofSize: 15, weight: .bold)
        successButton.contentTintColor = .white; successButton.wantsLayer = true
        successButton.layer?.backgroundColor = NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.86, alpha: 1).cgColor
        successButton.layer?.cornerRadius = 11
        for v in [successTitle, successTime, successButton] {
            successPanel.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false
        }
        new.keyEquivalent = "n"; new.keyEquivalentModifierMask = .command
        undo.keyEquivalent = "z"; undo.keyEquivalentModifierMask = .command
        loadingLabel.font = .systemFont(ofSize: 15, weight: .medium)
        loadingLabel.textColor = .secondaryLabelColor
        loadingLabel.isHidden = true
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isHidden = true
        board.onInput = { [weak self] in self?.lastInput = Date() }
        board.onAction = { [weak self] action, amount in
            guard let self, !self.loading, !self.restoring, !self.progress.completed else { return }
            self.tick(); self.lastInput = Date()
            if ["move", "backtrack", "undo"].contains(action) {
                self.progress.statistics?.measurements?.moveIntervals.append(self.activeGap)
                self.activeGap = 0
            }
            self.progress.statistics?.actions[action, default: 0] += amount
        }
        board.onProgress = { [weak self] count, total in
            self?.progressLabel.stringValue = "\(count) / \(total)"
            if count == 1 && self?.startedAt == nil && self?.restoring == false { self?.startedAt = Date() }
            if count > 0 && self?.progress.statistics?.startedAt == nil && self?.restoring == false {
                self?.progress.statistics?.startedAt = Date()
            }
            if self?.restoring == false { self?.lastInput = Date() }
            self?.saveProgress()
        }
        board.onWin = { [weak self] in
            guard let self else { return }
            self.tick()
            self.startedAt = nil
            if !self.progress.completed { self.progress.solved.append(self.board.puzzle) }
            self.progress.completed = true
            self.progress.elapsed = self.elapsed
            self.archiveStatistics(outcome: "solved"); self.saveProgress(); self.updateLevel()
            self.successTime.stringValue = "Solved in \(self.timerLabel.stringValue)"
            self.showSuccessPanel()
            self.difficultyToast.show(verdict: self.progress.statistics?.experiencedDifficulty, accent: self.board.accentColor)
        }
        for v in [windowDragArea, title, subtitle, timerLabel, progressLabel, difficultyControl, statisticsButton, board, reset, new, undo, hintButton, loadingLabel, spinner] {
            content.addSubview(v)
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        content.addSubview(successPanel); successPanel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(difficultyToast); difficultyToast.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(statisticsScreen); statisticsScreen.translatesAutoresizingMaskIntoConstraints = false
        statisticsScreen.isHidden = true
        statisticsScreen.onClose = { [weak self] in self?.window.makeFirstResponder(self?.board) }
        NSLayoutConstraint.activate([
            statisticsScreen.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            statisticsScreen.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            statisticsScreen.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            statisticsScreen.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            difficultyToast.centerXAnchor.constraint(equalTo: board.centerXAnchor),
            difficultyToast.bottomAnchor.constraint(equalTo: board.bottomAnchor, constant: -16),
            difficultyToast.widthAnchor.constraint(equalToConstant: 426),
            difficultyToast.heightAnchor.constraint(equalToConstant: 76),
            loadingLabel.centerXAnchor.constraint(equalTo: board.centerXAnchor),
            loadingLabel.centerYAnchor.constraint(equalTo: board.centerYAnchor),
            spinner.centerXAnchor.constraint(equalTo: board.centerXAnchor),
            spinner.bottomAnchor.constraint(equalTo: loadingLabel.topAnchor, constant: -12),
            windowDragArea.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            windowDragArea.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            windowDragArea.topAnchor.constraint(equalTo: content.topAnchor),
            windowDragArea.heightAnchor.constraint(equalToConstant: 56),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 88),
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 15),
            subtitle.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 36),
            subtitle.topAnchor.constraint(equalTo: content.topAnchor, constant: 68),
            difficultyControl.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            difficultyControl.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            difficultyControl.widthAnchor.constraint(equalToConstant: 226),
            difficultyControl.heightAnchor.constraint(equalToConstant: 38),
            statisticsButton.trailingAnchor.constraint(equalTo: difficultyControl.leadingAnchor, constant: -12),
            statisticsButton.centerYAnchor.constraint(equalTo: title.centerYAnchor),
            statisticsButton.widthAnchor.constraint(equalToConstant: 96),
            statisticsButton.heightAnchor.constraint(equalToConstant: 30),
            board.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            board.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            board.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 14),
            board.heightAnchor.constraint(equalTo: board.widthAnchor),
            timerLabel.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 6),
            timerLabel.topAnchor.constraint(equalTo: board.bottomAnchor, constant: 18),
            progressLabel.trailingAnchor.constraint(equalTo: board.trailingAnchor, constant: -6),
            progressLabel.centerYAnchor.constraint(equalTo: timerLabel.centerYAnchor),
            reset.leadingAnchor.constraint(equalTo: board.leadingAnchor, constant: 6),
            reset.topAnchor.constraint(equalTo: timerLabel.bottomAnchor, constant: 17),
            reset.widthAnchor.constraint(equalToConstant: 76), reset.heightAnchor.constraint(equalToConstant: 34),
            undo.leadingAnchor.constraint(equalTo: reset.trailingAnchor, constant: 8),
            undo.centerYAnchor.constraint(equalTo: reset.centerYAnchor),
            undo.widthAnchor.constraint(equalToConstant: 76), undo.heightAnchor.constraint(equalToConstant: 34),
            hintButton.trailingAnchor.constraint(equalTo: board.trailingAnchor, constant: -6),
            hintButton.centerYAnchor.constraint(equalTo: reset.centerYAnchor),
            hintButton.widthAnchor.constraint(equalToConstant: 114),
            hintButton.heightAnchor.constraint(equalToConstant: 34),
            new.centerXAnchor.constraint(equalTo: board.centerXAnchor),
            new.centerYAnchor.constraint(equalTo: reset.centerYAnchor),
            new.widthAnchor.constraint(equalToConstant: 106), new.heightAnchor.constraint(equalToConstant: 34),
            successPanel.centerXAnchor.constraint(equalTo: board.centerXAnchor),
            successPanel.topAnchor.constraint(equalTo: board.bottomAnchor, constant: 16),
            successPanel.widthAnchor.constraint(equalTo: board.widthAnchor, constant: -12),
            successPanel.heightAnchor.constraint(equalToConstant: 72),
            successTitle.topAnchor.constraint(equalTo: successPanel.topAnchor, constant: 8),
            successTitle.leadingAnchor.constraint(equalTo: successPanel.leadingAnchor),
            successTime.topAnchor.constraint(equalTo: successTitle.bottomAnchor, constant: 5),
            successTime.leadingAnchor.constraint(equalTo: successTitle.leadingAnchor),
            successTime.trailingAnchor.constraint(equalTo: successTitle.trailingAnchor),
            successButton.centerYAnchor.constraint(equalTo: successPanel.centerYAnchor),
            successButton.trailingAnchor.constraint(equalTo: successPanel.trailingAnchor),
            successButton.widthAnchor.constraint(equalToConstant: 150),
            successButton.heightAnchor.constraint(equalToConstant: 38)
        ])
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.tick() }
        cover.wantsLayer = true; cover.layer?.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1).cgColor
        content.addSubview(cover); cover.translatesAutoresizingMaskIntoConstraints = false
        coverTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        coverDetail.font = .systemFont(ofSize: 15); coverDetail.textColor = .secondaryLabelColor
        coverButton.target = self; coverButton.action = #selector(beginOrResume)
        coverButton.isBordered = false; coverButton.focusRingType = .none
        coverButton.font = .systemFont(ofSize: 15, weight: .semibold)
        coverButton.contentTintColor = .white; coverButton.wantsLayer = true
        coverButton.layer?.backgroundColor = NSColor(calibratedRed: 0.94, green: 0.23, blue: 0.17, alpha: 1).cgColor
        coverButton.layer?.cornerRadius = 11
        for v in [coverMark, coverTitle, coverDetail, coverButton] { cover.addSubview(v); v.translatesAutoresizingMaskIntoConstraints = false }
        NSLayoutConstraint.activate([
            cover.leadingAnchor.constraint(equalTo: content.leadingAnchor), cover.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            cover.topAnchor.constraint(equalTo: content.topAnchor, constant: 58), cover.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            coverMark.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            coverMark.bottomAnchor.constraint(equalTo: coverTitle.topAnchor, constant: -26),
            coverMark.widthAnchor.constraint(equalToConstant: 144), coverMark.heightAnchor.constraint(equalToConstant: 144),
            coverTitle.centerXAnchor.constraint(equalTo: cover.centerXAnchor), coverTitle.centerYAnchor.constraint(equalTo: cover.centerYAnchor, constant: 15),
            coverDetail.centerXAnchor.constraint(equalTo: cover.centerXAnchor), coverDetail.topAnchor.constraint(equalTo: coverTitle.bottomAnchor, constant: 12),
            coverButton.centerXAnchor.constraint(equalTo: cover.centerXAnchor), coverButton.topAnchor.constraint(equalTo: coverDetail.bottomAnchor, constant: 28),
            coverButton.widthAnchor.constraint(equalToConstant: 160), coverButton.heightAnchor.constraint(equalToConstant: 42)
        ])
        showStartScreen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    @objc private func showStatistics() {
        guard !loading else { return }
        if !startScreen && !paused && !progress.completed && startedAt != nil { pauseGame() }
        difficultyToast.dismiss()
        statisticsScreen.show(records: store.snapshot.records)
        window.makeFirstResponder(statisticsScreen)
    }
    private func changeDifficulty(_ selected: Int) {
        difficultyToast.dismiss()
        saveProgress()
        generationID = UUID()
        setLoading(false)
        difficulty = Difficulty(rawValue: selected) ?? .easy
        if startScreen { showStartScreen() } else { paused = false; cover.isHidden = true; loadProgress() }
    }
    private func setLoading(_ value: Bool) {
        loading = value; board.isHidden = value
        loadingLabel.isHidden = !value; spinner.isHidden = !value
        if value { spinner.startAnimation(nil) } else { spinner.stopAnimation(nil) }
        playControls.compactMap { $0 as? NSButton }.forEach { $0.isEnabled = !value }
        successButton.isEnabled = !value
    }
    @objc private func newGame() {
        guard !loading && !paused else { return }
        if startScreen { beginOrResume(); return }
        saveProgress()
        if !progress.completed { archiveStatistics(outcome: "skipped"); saveProgress() }
        hideSuccessPanel(); setLoading(true)
        startedAt = nil
        let id = UUID(); generationID = id
        let selected = difficulty
        let records = store.snapshot.records
        let revision = recordsRevision
        let preparedModel = cachedRevision == revision ? cachedModel : nil
        let previous = records.filter { $0.outcome == "solved" }.map { $0.puzzle.solution }
            + progress.solved.map { $0.solution } + [progress.current?.solution ?? []]
        subtitle.stringValue = "Level \(progress.solved.count + 1)  ·  \(progress.solved.count) solved"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let model = preparedModel ?? AdaptiveDifficulty(records: records)
            let generated = model.select(selected, excluding: previous)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generationID == id else { return }
                if self.recordsRevision == revision { self.cachedModel = model; self.cachedRevision = revision }
                self.lastInput = Date()
                self.restoring = true
                self.progress.current = generated; self.progress.completed = false
                self.activeGap = 0
                self.progress.statistics = PlayStatistics(puzzle: generated, difficulty: selected)
                self.progress.statistics?.predictedEffort = model.predict(generated)
                self.progress.statistics?.classificationModelVersion = AdaptiveDifficulty.version
                self.progress.statistics?.classificationSamples = model.sampleCount
                self.progress.path = []; self.progress.elapsed = 0
                self.board.puzzle = generated
                self.elapsed = 0; self.startedAt = nil
                self.restoring = false
                self.setLoading(false); self.tick(); self.updateLevel(); self.saveProgress()
            }
        }
    }
    @objc private func resetGame() {
        guard !loading && !paused && !startScreen && !progress.completed else { return }
        tick(); finishThinkingInterval()
        hideSuccessPanel()
        if startedAt == nil && elapsed > 0 { startedAt = Date().addingTimeInterval(-elapsed) }
        progress.statistics?.actions["reset", default: 0] += 1
        board.reset(); tick()
        updateLevel(); saveProgress()
    }
    private func refreshHint() {
        let used = progress.statistics?.actions["hint"] ?? 0
        let wait = HintPolicy.wait(active: progress.statistics?.activeSeconds ?? 0, next: progress.statistics?.nextHintAt)
        hintButton.isEnabled = !loading && !paused && !startScreen && !progress.completed && used < HintPolicy.limit && wait == 0
        hintButton.title = used >= HintPolicy.limit ? "No hints left" : wait > 0 ? "Hint · \(wait)s" : "Hint · \(HintPolicy.limit - used) left"
    }
    @objc private func useHint() {
        refreshHint()
        guard hintButton.isEnabled, progress.statistics != nil else { return }
        lastInput = Date()
        tick(); finishThinkingInterval()
        progress.statistics?.actions["hint", default: 0] += 1
        let nextUnlock = (progress.statistics?.activeSeconds ?? 0) + HintPolicy.delay
        progress.statistics?.nextHintAt = nextUnlock
        subtitle.stringValue = board.revealHint()
        saveProgress(); refreshHint()
    }
    @objc private func undoMove() { if !paused && !startScreen && !loading { board.undo() } }
    private func showSuccessPanel() {
        playControls.forEach { $0.isHidden = true }
        successButton.layer?.backgroundColor = board.accentColor.cgColor
        successTitle.stringValue = "Level \(progress.solved.count) complete"
        successPanel.isHidden = false; successPanel.alphaValue = 0
        successPanel.layer?.removeAllAnimations()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28; context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            successPanel.animator().alphaValue = 1
        }
    }
    private func hideSuccessPanel() {
        difficultyToast.dismiss()
        playControls.forEach { $0.isHidden = false }
        successPanel.layer?.removeAllAnimations(); successPanel.alphaValue = 1; successPanel.isHidden = true
    }
    private func showStartScreen() {
        startScreen = true; startedAt = nil; board.isHidden = true
        progress = store.snapshot.progress[storageKey] ?? SavedProgress()
        coverMark.paused = false
        let continuing = progress.current != nil && !progress.completed
        cover.isHidden = false; coverTitle.stringValue = "Level \(max(1, progress.solved.count + 1))"
        coverDetail.stringValue = "\(progress.solved.count) solved · \(difficulty.title.capitalized)"
        coverButton.title = continuing ? "Continue puzzle  →" : "Play puzzle  →"
        window.makeFirstResponder(coverButton)
        prepareModel()
    }
    private func prepareModel() {
        let records = store.snapshot.records
        let revision = recordsRevision
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let model = AdaptiveDifficulty(records: records)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.recordsRevision == revision else { return }
                self.cachedModel = model; self.cachedRevision = revision
            }
        }
    }
    // Preserve measured thinking before hints, resets, or pauses break the interval.
    private func finishThinkingInterval() {
        if activeGap > 0 { progress.statistics?.measurements?.moveIntervals.append(activeGap) }
        activeGap = 0
    }
    @objc private func beginOrResume() {
        lastInput = Date(); lastStatisticsTick = Date(); activeGap = 0
        if paused {
            paused = false; cover.isHidden = true; board.isHidden = false
            startedAt = Date().addingTimeInterval(-elapsed)
        } else {
            startScreen = false; cover.isHidden = true; board.isHidden = false
            if progress.current != nil && !progress.completed { loadProgress() } else { newGame() }
        }
        window.makeFirstResponder(board)
    }
    private func pauseGame() {
        guard !paused && !startScreen && !loading && !progress.completed else { return }
        if let startedAt { elapsed = min(Date(), lastInput.addingTimeInterval(10)).timeIntervalSince(startedAt) }
        finishThinkingInterval()
        startedAt = nil; paused = true
        saveProgress(); board.isHidden = true
        coverMark.paused = true
        cover.isHidden = false; coverTitle.stringValue = "Paused"
        coverDetail.stringValue = "Level \(progress.solved.count + 1) · \(timerLabel.stringValue) · Progress saved"
        coverButton.title = "Resume puzzle  →"; window.makeFirstResponder(coverButton)
    }
    private func tick() {
        let now = Date()
        if !paused && !startScreen && !loading && startedAt != nil && now.timeIntervalSince(lastInput) >= 10 { pauseGame() }
        let delta = now.timeIntervalSince(lastStatisticsTick)
        lastStatisticsTick = now
        if NSApp.isActive && !loading && !restoring && startedAt != nil && delta >= 0 && delta < 1 {
            progress.statistics?.activeSeconds += delta
            activeGap += delta
        } else {
            // Never bridge app inactivity, sleep, generation, or puzzle switches.
            activeGap = 0
        }
        if let startedAt { elapsed = Date().timeIntervalSince(startedAt) }
        if now.timeIntervalSince(lastCheckpoint) >= 2 {
            lastCheckpoint = now
            if startedAt != nil { saveProgress() }
        }
        refreshHint()
        timerLabel.stringValue = String(format: "%02d:%02d", Int(elapsed) / 60, Int(elapsed) % 60)
    }
}

if CommandLine.arguments.contains("--self-test") {
    runAdaptiveRegressionTests()
    precondition(HintPolicy.wait(active: 0, next: nil) == 30)
    precondition(HintPolicy.wait(active: 29.5, next: nil) == 1)
    precondition(HintPolicy.wait(active: 30, next: nil) == 0)
    precondition(HintPolicy.wait(active: 40, next: 60) == 20)
    for difficulty in Difficulty.allCases {
        for _ in 0..<100 {
            let p = Puzzle.make(difficulty)
            precondition(p.solution.count == p.size * p.size)
            precondition(Set(p.solution).count == p.solution.count)
            precondition(zip(p.solution, p.solution.dropFirst()).allSatisfy { $0.adjacent(to: $1) && !p.walls.contains(Edge($0, $1)) })
            precondition(p.hintPrefix(for: []) == [p.solution[0]])
            let correct = Array(p.solution.prefix(3))
            precondition(p.hintPrefix(for: correct) == correct)
            precondition(p.hintPrefix(for: correct + [p.solution[5]]) == correct)
            precondition(p.hintPrefix(for: p.solution) == p.solution)
            let check = p.checkSolutions()
            precondition(check.exhausted && check.count == 1)
            precondition(p.clues.count == difficulty.clueCount)
            precondition(p.clues[p.solution.first!] == 1)
            precondition(p.clues[p.solution.last!] == difficulty.clueCount)
            var saved = SavedProgress(solved: [p], current: p, path: Array(p.solution.prefix(3)), elapsed: 42, completed: false)
            saved.statistics = PlayStatistics(puzzle: p, difficulty: difficulty)
            saved.statistics?.actions["reset"] = 2
            saved.statistics?.actions["hint"] = 1
            saved.statistics?.nextHintAt = 65
            saved.statistics?.activeSeconds = 50
            saved.statistics?.actions["move"] = 20
            saved.statistics?.actions["backtrack"] = 3
            saved.statistics?.actions["undo"] = 2
            saved.statistics?.actions["hintRewindCells"] = 10
            saved.statistics?.measurements?.moveIntervals = [0.5, 2, 5]
            saved.statistics?.updateMeasurements()
            precondition(saved.statistics?.measurements?.pauseCount == 2)
            precondition(saved.statistics?.measurements?.pauseSeconds == 7)
            precondition(saved.statistics?.measurements?.activeSecondsPerMove == 2)
            precondition(saved.statistics?.measurements?.backtrackedCellsPerCell == 5 / Double(p.size * p.size))
            let data = try! JSONEncoder().encode(saved)
            let restored = try! JSONDecoder().decode(SavedProgress.self, from: data)
            precondition(restored.solved[0].solution == p.solution)
            precondition(restored.current?.clues == p.clues && restored.current?.walls == p.walls)
            precondition(restored.path == saved.path && restored.elapsed == 42 && !restored.completed)
            precondition(restored.statistics?.actions["reset"] == 2)
            precondition(restored.statistics?.actions["hint"] == 1 && restored.statistics?.nextHintAt == 65)
            precondition(restored.statistics?.features["cells"] == p.size * p.size)
            precondition(restored.statistics?.generatorVersion == 3)
            precondition(restored.statistics?.measurements?.assisted == true)
            precondition(restored.statistics?.measurements?.pauseSeconds == 7)
        }
    }
    let calibrationPuzzle = Puzzle.make(.medium)
    var easyRecord = PlayStatistics(puzzle: calibrationPuzzle, difficulty: .medium)
    easyRecord.outcome = "solved"; easyRecord.activeSeconds = 20
    easyRecord.actions["move"] = 35; easyRecord.updateMeasurements()
    var hardRecord = easyRecord
    hardRecord.activeSeconds = 90; hardRecord.actions["backtrack"] = 40
    hardRecord.measurements?.moveIntervals = [8, 9, 10, 6, 12]
    hardRecord.updateMeasurements()
    func independentRecords(_ record: PlayStatistics, count: Int) -> [PlayStatistics] {
        (0..<count).map { _ in var copy = record; copy.id = UUID(); return copy }
    }
    let lowModel = AdaptiveDifficulty(records: independentRecords(easyRecord, count: 40))
    let highModel = AdaptiveDifficulty(records: independentRecords(hardRecord, count: 40))
    precondition(highModel.predict(calibrationPuzzle) > lowModel.predict(calibrationPuzzle))
    var incomplete = hardRecord; incomplete.measurements?.collectedFromStart = false
    precondition(AdaptiveDifficulty(records: [incomplete]).sampleCount == 0)
    var skipped = hardRecord; skipped.outcome = "skipped"
    precondition(AdaptiveDifficulty(records: [skipped]).sampleCount == 0)
    let testFolder = FileManager.default.temporaryDirectory.appendingPathComponent("zip-save-test-" + UUID().uuidString)
    let testURL = testFolder.appendingPathComponent("progress.json")
    let testStore = try! ProgressStore(url: testURL)
    testStore.snapshot = AppSnapshot(progress: ["test": SavedProgress(solved: [calibrationPuzzle], current: calibrationPuzzle, completed: true)], records: [easyRecord])
    testStore.save(); testStore.flush()
    let reopened = try! ProgressStore(url: testURL)
    precondition(reopened.snapshot.progress["test"]?.completed == true && reopened.snapshot.records.count == 1)
    testStore.save(); testStore.flush()
    try! Data("broken".utf8).write(to: testURL)
    let recovered = try! ProgressStore(url: testURL)
    precondition(recovered.snapshot.records.count == 1)
    try! FileManager.default.removeItem(at: testFolder)
    print("Atomic snapshot, reopen, and backup recovery checks passed")
    let fitStart = Date()
    let fullModel = AdaptiveDifficulty(records: independentRecords(hardRecord, count: 200))
    let fitMilliseconds = Date().timeIntervalSince(fitStart) * 1000
    precondition(fullModel.predict(calibrationPuzzle).isFinite)
    print("Maximum-history model fit: \(fitMilliseconds) ms (200 samples, 13 coefficients)")
    let start = Date()
    for d in Difficulty.allCases {
        let candidate = highModel.select(d, excluding: [calibrationPuzzle.solution])
        precondition(candidate.solution != calibrationPuzzle.solution)
        let check = candidate.checkSolutions()
        precondition(check.exhausted && check.count == 1)
    }
    print("300 puzzle/persistence checks and adaptive-model checks passed. Three adaptive selections: \(Date().timeIntervalSince(start))s")
} else {
    let app = NSApplication.shared
    let controller = GameController()
    app.delegate = controller
    app.run()
}
