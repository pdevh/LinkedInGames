import AppKit

/// A lightweight notification with a distinct color for each difficulty verdict.
final class DifficultyToast: NSView {
    private var message = ""
    private var accent = NSColor.systemBlue
    private var dismissal: DispatchWorkItem?
    private var presentation = UUID()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        isHidden = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(verdict: String?, accent: NSColor) {
        dismiss()
        switch verdict {
        case "easy": self.accent = NSColor(calibratedRed: 0.16, green: 0.58, blue: 0.32, alpha: 1)
        case "medium": self.accent = NSColor(calibratedRed: 0.78, green: 0.60, blue: 0.06, alpha: 1)
        case "hard": self.accent = NSColor(calibratedRed: 0.85, green: 0.25, blue: 0.23, alpha: 1)
        default: self.accent = accent
        }
        message = verdict.map { "This puzzle was \($0) for you" } ?? "Still learning what feels difficult for you"
        setAccessibilityLabel(message)
        isHidden = false
        alphaValue = 0
        needsDisplay = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.22
            animator().alphaValue = 1
        }
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [
            .announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        let current = presentation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.presentation == current else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.25
                self.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self, self.presentation == current else { return }
                self.isHidden = true
            })
        }
        dismissal = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }
    func dismiss() {
        presentation = UUID()
        dismissal?.cancel(); dismissal = nil
        layer?.removeAllAnimations()
        isHidden = true; alphaValue = 1
    }
    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 8, dy: 8)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 7; shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.set()
        NSColor(calibratedRed: 0.995, green: 0.995, blue: 0.985, alpha: 1).setFill()
        NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16).fill()
        NSGraphicsContext.restoreGraphicsState()
        accent.withAlphaComponent(0.16).setStroke()
        let border = NSBezierPath(roundedRect: card.insetBy(dx: 0.5, dy: 0.5), xRadius: 16, yRadius: 16)
        border.lineWidth = 1; border.stroke()
        let icon = NSRect(x: card.minX+16, y: card.midY-15, width: 30, height: 30)
        accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(ovalIn: icon).fill()
        accent.setStroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: icon.minX+8, y: icon.midY))
        check.line(to: NSPoint(x: icon.minX+13, y: icon.midY-5))
        check.line(to: NSPoint(x: icon.minX+22, y: icon.midY+6))
        check.lineWidth = 2; check.lineCapStyle = .round; check.lineJoinStyle = .round; check.stroke()
        let label = NSAttributedString(string: message, attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.16, alpha: 1)
        ])
        label.draw(at: NSPoint(x: icon.maxX+12, y: card.midY-label.size().height/2))
    }
}
