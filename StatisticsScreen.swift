import AppKit

final class StatisticsScreen: NSView {
    var onClose: (() -> Void)?
    private let scroll = NSScrollView()
    private let document = NSView()
    private let close = NSButton(title: "‹ Back to game", target: nil, action: nil)
    private let period = NSSegmentedControl(labels: ["All time", "Last 30 days"], trackingMode: .selectOne, target: nil, action: nil)
    private var showsDetails = false
    private var records: [PlayStatistics] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = GameUIStyle.background.cgColor
        close.target = self; close.action = #selector(closeScreen)
        GameUIStyle.button(close)
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
    @objc private func toggleDetails() { showsDetails.toggle(); reload() }
    private func reload() {
        document.subviews.forEach { $0.removeFromSuperview() }
        let summary = GameStatistics(records: records, period: period.selectedSegment == 0 ? .allTime : .last30Days)
        let width = max(600, bounds.width)
        let height: CGFloat = showsDetails ? 1060 : 610
        document.frame = NSRect(x: 0, y: 0, width: width, height: height)
        func text(_ value: String, x: CGFloat = 30, top: CGFloat, w: CGFloat? = nil,
                  h: CGFloat = 24, size: CGFloat = 14, bold: Bool = false, secondary: Bool = false) {
            let field = label(value, font: .systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                              color: secondary ? .secondaryLabelColor : .labelColor, lines: 0)
            document.addSubview(field)
            field.frame = NSRect(x: x, y: height-top-h, width: w ?? width-60, height: h)
        }
        text("Your statistics", top: 20, h: 36, size: 26, bold: true)
        text("All difficulties combined", top: 61, secondary: true)
        let cards = [("\(summary.games.count)", "Solved", "\(summary.skippedCount) skipped"),
                     (summary.medianActiveSeconds.map { Self.time($0) } ?? "—", "Typical solve time", "Based on \(summary.timedCount) solves"),
                     (summary.matchRate.map { "\(Int(($0*100).rounded()))%" } ?? "—", "Difficulty match", "Based on \(summary.rated.count) solves")]
        let cardWidth = (width-80)/3
        for (i, item) in cards.enumerated() {
            let x = 30 + CGFloat(i)*(cardWidth+10)
            let c = card(); document.addSubview(c)
            c.frame = NSRect(x: x, y: height-207, width: cardWidth, height: 105)
            text(item.0, x: x+14, top: 113, w: cardWidth-28, h: 35, size: 28, bold: true)
            text(item.1, x: x+14, top: 153, w: cardWidth-28, h: 19, size: 13, bold: true)
            text(item.2, x: x+14, top: 180, w: cardWidth-28, h: 17, size: 11, secondary: true)
        }
        text("Every solved game is counted", top: 228, bold: true)
        text("\(summary.rated.count) have difficulty assessments, including \(summary.backfilledCount) estimated from older measurements. \(summary.unratedCount) lack complete measurements and count toward your total only.", top: 258, h: 54, size: 13, secondary: true)
        text("Difficulty match compares your selected level with the assessment from your play.", top: 318, h: 38, size: 13, secondary: true)
        text("Recent games", top: 372, bold: true)
        let formatter = DateFormatter(); formatter.dateStyle = .medium
        if summary.games.isEmpty {
            text("No solved games in this period.", top: 409, secondary: true)
        }
        for (i, game) in summary.recent(.all).prefix(5).enumerated() {
            let selected = game.intended?.title.capitalized ?? "Unknown"
            let assessment = game.experienced.map { $0.title.capitalized + (game.isBackfilled ? " (estimated)" : "") } ?? "Unavailable"
            text(formatter.string(from: game.date), top: 410+CGFloat(i)*28, w: 140, size: 12, secondary: true)
            text("\(selected) selected · \(assessment)", x: 185, top: 410+CGFloat(i)*28, w: width-215, size: 13)
        }
        let details = NSButton(title: showsDetails ? "Hide details ▴" : "Details ▾", target: self, action: #selector(toggleDetails))
        details.bezelStyle = .rounded; document.addSubview(details)
        details.frame = NSRect(x: 30, y: height-586, width: 125, height: 28)
        if showsDetails {
            text("Difficulty breakdown", top: 614, size: 18, bold: true)
            text("Rows: selected level. Columns: assessed level, including estimates.", top: 647, h: 32, size: 12, secondary: true)
            let columnWidth = (width-60)/4
            for (i, name) in ["Selected", "Easy", "Medium", "Hard"].enumerated() {
                text(name, x: 30+CGFloat(i)*columnWidth, top: 689, w: columnWidth, size: 13, bold: true)
            }
            for difficulty in Difficulty.allCases {
                let top = 721+CGFloat(difficulty.rawValue)*28
                text(difficulty.title.capitalized, top: top, w: columnWidth, size: 13)
                for experienced in Difficulty.allCases {
                    text("\(summary.matrix[difficulty.rawValue][experienced.rawValue])", x: 30+CGFloat(experienced.rawValue+1)*columnWidth,
                         top: top, w: columnWidth, size: 13)
                }
            }
            text("How difficulty adapts", top: 821, size: 18, bold: true)
            text("Uses the latest \(summary.model.sampleCount) measured solves across all time. These patterns are associations, not causes.", top: 854, h: 38, size: 12, secondary: true)
            if summary.features.isEmpty {
                text("More measured games are needed to show patterns.", top: 906, secondary: true)
            }
            for (i, insight) in summary.features.prefix(4).enumerated() {
                text("\(insight.name) · \(insight.effect >= 0 ? "tends harder" : "tends easier")", top: 906+CGFloat(i)*29, size: 13)
            }
        }
        let top = max(0, document.bounds.height-scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: top))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    private static func time(_ seconds: Double) -> String { String(format: "%d:%02d", Int(seconds)/60, Int(seconds)%60) }
}
