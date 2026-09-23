import AppKit

/// Shared chrome for every game. Boards and game-specific instructions stay independent.
enum GameUIStyle {
    static let background = NSColor(calibratedWhite: 0.965, alpha: 1)
    static let ink = NSColor(calibratedWhite: 0.10, alpha: 1)
    static let secondaryInk = NSColor(calibratedWhite: 0.36, alpha: 1)
    static let accent = NSColor(calibratedRed: 0.94, green: 0.23, blue: 0.17, alpha: 1)
    static let controlHeight: CGFloat = 34
    static let headerTitleX: CGFloat = 134
    static let headerHomeX: CGFloat = 88
    static let difficultyRightInset: CGFloat = 24

    static func button(_ button: NSButton, primary: Bool = false) {
        button.isBordered = false
        button.focusRingType = .none
        button.font = .systemFont(ofSize: 14, weight: .semibold)
        button.contentTintColor = primary ? .white : ink
        button.wantsLayer = true
        button.layer?.backgroundColor = (primary ? accent : .white).cgColor
        button.layer?.cornerRadius = 10
    }

    static func backButton(_ button: NSButton) {
        self.button(button)
        button.title = ""
        button.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back to Games")
        button.imagePosition = .imageOnly
        button.toolTip = "Back to Games"
        button.setAccessibilityLabel("Back to Games")
    }

    static func title(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 22, weight: .bold)
        label.textColor = ink
    }

    static func timer(_ label: NSTextField) {
        label.font = .monospacedDigitSystemFont(ofSize: 17, weight: .semibold)
        label.textColor = ink
    }

    static func status(_ label: NSTextField) {
        label.font = .systemFont(ofSize: 14)
        label.textColor = secondaryInk
    }
}
