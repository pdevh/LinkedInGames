import AppKit

final class StatisticsScreen: NSView {
    var onClose: (() -> Void)?
    private let scroll = NSScrollView()
    private let document = NSView()
    private let close = NSButton(title: "‹ Back to game", target: nil, action: nil)
    private let period = NSSegmentedControl(labels: ["All time", "Last 30 days"], trackingMode: .selectOne, target: nil, action: nil)
    private var records: [PlayStatistics] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.965, alpha: 1).cgColor
        close.target = self; close.action = #selector(closeScreen)
        close.isBordered = false; close.font = .systemFont(ofSize: 14, weight: .semibold)
        close.contentTintColor = NSColor(calibratedRed: 0.12, green: 0.28, blue: 0.86, alpha: 1)
        period.selectedSegment = 0; period.target = self; period.action = #selector(changePeriod)
        period.font = .systemFont(ofSize: 13, weight: .semibold)
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = document
        addSubview(close); addSubview(period); addSubview(scroll)
        close.translatesAutoresizingMaskIntoConstraints = false; period.translatesAutoresizingMaskIntoConstraints = false; scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            close.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30), close.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            period.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30), period.centerYAnchor.constraint(equalTo: close.centerYAnchor),
            period.widthAnchor.constraint(equalToConstant: 205),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: close.bottomAnchor, constant: 13), scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func show(records: [PlayStatistics]) {
        self.records = records
        superview?.addSubview(self, positioned: .above, relativeTo: nil)
        layoutSubtreeIfNeeded()
        reload()
        isHidden = false
    }
    @objc private func closeScreen() { isHidden = true; onClose?() }
    @objc private func changePeriod() { reload() }

    private func label(_ text: String, font: NSFont, color: NSColor = .labelColor, lines: Int = 1) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = font; field.textColor = color; field.maximumNumberOfLines = lines
        return field
    }
    private func card() -> NSView {
        let view = NSView(); view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.white.cgColor; view.layer?.cornerRadius = 14
        view.layer?.borderColor = NSColor(calibratedWhite: 0.88, alpha: 1).cgColor; view.layer?.borderWidth = 1
        return view
    }
    private func verdictColor(_ difficulty: Difficulty) -> NSColor {
        switch difficulty { case .easy: return NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.32, alpha: 1)
        case .medium: return NSColor(calibratedRed: 0.78, green: 0.60, blue: 0.06, alpha: 1)
        case .hard: return NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.23, alpha: 1) }
    }
    private func reload() {
        document.subviews.forEach { $0.removeFromSuperview() }
        let summary = GameStatistics(records: records, period: period.selectedSegment == 0 ? .allTime : .last30Days)
        let width = max(600, bounds.width)
        document.frame = NSRect(x: 0, y: 0, width: width, height: 1050)
        let title = label("Your play", font: .systemFont(ofSize: 26, weight: .bold))
        let subtitle = label("Difficulty is measured from your completed games, not the button you chose.", font: .systemFont(ofSize: 14), color: .secondaryLabelColor)
        document.addSubview(title); document.addSubview(subtitle)
        title.frame = NSRect(x: 30, y: 982, width: width-60, height: 32)
        subtitle.frame = NSRect(x: 30, y: 958, width: width-60, height: 20)
        let rateText = summary.matchRate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        let cards = [(rateText, "matched intended difficulty", "Among \(summary.rated.count) rated solves"),
                     ("\(summary.games.count)", "puzzles solved", summary.skippedCount == 0 ? "No skipped games" : "\(summary.skippedCount) skipped game\(summary.skippedCount == 1 ? "" : "s")"),
                     (summary.medianActiveSeconds.map { Self.time($0) } ?? "—", "median active time", "Completed games with valid telemetry")]
        for (i, item) in cards.enumerated() {
            let c = card(); document.addSubview(c)
            let x = 30 + CGFloat(i)*(width-60)/3; c.frame = NSRect(x: x, y: 848, width: (width-72)/3, height: 92)
            let value = label(item.0, font: .systemFont(ofSize: 27, weight: .bold)); let name = label(item.1, font: .systemFont(ofSize: 13, weight: .semibold)); let detail = label(item.2, font: .systemFont(ofSize: 11), color: .secondaryLabelColor)
            [value,name,detail].forEach { c.addSubview($0) }
            value.frame = NSRect(x: 16,y: 49,width: c.bounds.width-32,height: 33); name.frame = NSRect(x: 16,y: 29,width:c.bounds.width-32,height:17); detail.frame = NSRect(x:16,y:12,width:c.bounds.width-32,height:14)
        }
        let matchCard = card(); document.addSubview(matchCard); matchCard.frame = NSRect(x: 30, y: 600, width: width-60, height: 220)
        let matchTitle = label("Intended vs. experienced difficulty", font: .systemFont(ofSize: 17, weight: .bold)); matchCard.addSubview(matchTitle); matchTitle.frame = NSRect(x: 20,y:181,width:420,height:23)
        let definition = label("A match means the difficulty you selected and the post-solve assessment agree. Unrated older games are excluded.", font: .systemFont(ofSize: 12), color: .secondaryLabelColor, lines: 2); matchCard.addSubview(definition); definition.frame = NSRect(x:20,y:150,width:width-100,height:30)
        let headers = ["Selected", "Easy", "Medium", "Hard"]
        for (i, header) in headers.enumerated() { let h = label(header, font: .systemFont(ofSize: 12, weight: .semibold), color: .secondaryLabelColor); matchCard.addSubview(h); h.alignment = .center; h.frame = NSRect(x: 20+CGFloat(i)*((width-100)/4), y: 119, width: (width-100)/4, height: 17) }
        for intended in Difficulty.allCases { for experienced in Difficulty.allCases {
            let value = summary.matrix[intended.rawValue][experienced.rawValue]
            let cell = label("\(value)", font: .monospacedDigitSystemFont(ofSize: 15, weight: .semibold), color: verdictColor(experienced)); cell.alignment = .center; matchCard.addSubview(cell)
            cell.frame = NSRect(x: 20+CGFloat(experienced.rawValue+1)*((width-100)/4), y: 84-CGFloat(intended.rawValue)*28, width: (width-100)/4, height: 19)
            if experienced == .easy { let row = label(intended.title.capitalized, font: .systemFont(ofSize: 13, weight: .semibold)); row.alignment = .center; matchCard.addSubview(row); row.frame = NSRect(x:20,y:84-CGFloat(intended.rawValue)*28,width:(width-100)/4,height:19) }
        }}
        let learning = card(); document.addSubview(learning); learning.frame = NSRect(x:30,y:314,width:width-60,height:260)
        let learningTitle = label("What the model is learning", font: .systemFont(ofSize: 17, weight: .bold)); learning.addSubview(learningTitle); learningTitle.frame = NSRect(x:20,y:224,width:400,height:24)
        let modelText: String
        if summary.model.sampleCount < 8 { modelText = "It needs \(8-summary.model.sampleCount) more valid solve\(8-summary.model.sampleCount == 1 ? "" : "s") before feature insights are shown." }
        else { modelText = "Based on your latest \(summary.model.sampleCount) valid solves. These are associations in the model, not proof that one feature causes difficulty." }
        let learningDetail = label(modelText, font: .systemFont(ofSize: 12), color: .secondaryLabelColor, lines: 2); learning.addSubview(learningDetail); learningDetail.frame = NSRect(x:20,y:188,width:width-100,height:30)
        if summary.features.isEmpty {
            let empty = label("Keep playing normally. Your completed games will fill this in automatically.", font: .systemFont(ofSize: 14, weight: .medium), color: .secondaryLabelColor); learning.addSubview(empty); empty.frame = NSRect(x:20,y:120,width:width-100,height:22)
        } else {
            for (index, insight) in summary.features.prefix(4).enumerated() {
                let direction = insight.effect >= 0 ? "tends harder" : "tends easier"
                let color = insight.effect >= 0 ? NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.23, alpha: 1) : NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.32, alpha: 1)
                let row = label("\(insight.name)  ·  \(direction)", font: .systemFont(ofSize: 14, weight: .semibold), color: color); learning.addSubview(row); row.frame = NSRect(x:20,y:151-CGFloat(index)*31,width:width-100,height:21)
            }
        }
        let recent = card(); document.addSubview(recent); recent.frame = NSRect(x:30,y:26,width:width-60,height:264)
        let recentTitle = label("Recent completed games", font: .systemFont(ofSize: 17, weight: .bold)); recent.addSubview(recentTitle); recentTitle.frame = NSRect(x:20,y:228,width:300,height:24)
        let formatter = DateFormatter(); formatter.dateStyle = .medium
        if summary.games.isEmpty { let empty = label("No completed games in this period.", font: .systemFont(ofSize: 14), color: .secondaryLabelColor); recent.addSubview(empty); empty.frame = NSRect(x:20,y:180,width:400,height:22) }
        else { for (i, game) in summary.recent(.all).enumerated() {
            let experienced = game.experienced?.title.capitalized ?? "Unrated"
            let result = game.matched ? "Matched" : (game.isRated ? "Different" : "No assessment")
            let row = label("\(formatter.string(from: game.date))     selected \(game.intended?.title.capitalized ?? "Unknown")     felt \(experienced)     \(result)", font: .monospacedSystemFont(ofSize: 12, weight: .regular), color: game.experienced.map(verdictColor) ?? .secondaryLabelColor)
            recent.addSubview(row); row.frame = NSRect(x:20,y:194-CGFloat(i)*20,width:width-100,height:18)
        }}
    }
    private static func time(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds)/60, Int(seconds)%60) }
}
