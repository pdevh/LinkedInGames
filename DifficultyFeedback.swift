import AppKit

struct DifficultyFeedback: Codable {
    var policyVersion = 1
    var scaleVersion = 1
    let draw: Double
    let eligibleProbability: Double
    let suppressionReason: String?
    var state: String // notInvited, assigned, pending, submitted, skipped, shown
    var invitedAt: Date?
    var submittedAt: Date?
    var skippedAt: Date?
    var verdictShownAt: Date?
    var response: Int?
    var resolution: String?
    var contractSatisfied: Bool?
}

/// Shared across games; answers are never supplied to either effort model.
final class DifficultyFeedbackCoordinator {
    static let shared = DifficultyFeedbackCoordinator()
    private var displayedThisSession = 0
    private var lastActivity = Date()
    private var pending: ((String) -> Void)?
    private var pendingAlert: NSAlert?
    private var pendingWindow: NSWindow?
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["difficulty.feedback.enabled": true])
    }

    func assign(serveID: UUID, now: Date = Date()) -> DifficultyFeedback {
        if now.timeIntervalSince(lastActivity) > 1800 { displayedThisSession = 0 }
        lastActivity = now
        let hash = DifficultyJournal.hash(Data(("feedback-v1:"+serveID.uuidString).utf8))
        let draw = Double(UInt64(hash.prefix(12),radix:16)!)/Double(0x1000000000000 as UInt64)
        let enabled = defaults.bool(forKey:"difficulty.feedback.enabled") && !defaults.bool(forKey:"difficulty.feedback.stopped")
        let suppressed = enabled ? nil : "disabled"
        return DifficultyFeedback(draw:draw,eligibleProbability:enabled ? 0.25 : 0,
                                  suppressionReason:suppressed,state:enabled && draw < 0.25 ? "assigned" : "notInvited")
    }
    /// Writes pending before showing the neutral prompt. save owns record/event persistence.
    func present(_ initial: DifficultyFeedback?, window: NSWindow, save: @escaping (DifficultyFeedback) -> Void,
                 reveal: @escaping () -> Void) {
        resolvePending(reason:"nextPresentation")
        guard var state = initial, state.state == "assigned" else { reveal(); return }
        guard defaults.bool(forKey:"difficulty.feedback.enabled"), !defaults.bool(forKey:"difficulty.feedback.stopped") else {
            state.state = "skipped"; state.skippedAt = Date(); state.resolution = "disabled"
            save(state); reveal(); return
        }
        let now = Date(), day = Calendar.current.startOfDay(for:Date()).timeIntervalSince1970
        if defaults.double(forKey:"difficulty.feedback.day") != day {
            defaults.set(day,forKey:"difficulty.feedback.day"); defaults.set(0,forKey:"difficulty.feedback.dayCount")
        }
        let dayCount = defaults.integer(forKey:"difficulty.feedback.dayCount")
        guard displayedThisSession < 3 && dayCount < 6 else {
            state.state = "skipped"; state.skippedAt = now; state.resolution = "displayCap"
            state.contractSatisfied = true; save(state); reveal(); return
        }
        displayedThisSession += 1; defaults.set(dayCount+1,forKey:"difficulty.feedback.dayCount")
        state.state = "pending"; state.invitedAt = now; save(state)
        let alert = NSAlert(); alert.messageText = "How difficult did this puzzle feel?"
        alert.informativeText = "Optional. Your answer does not change the measured effort."
        for title in ["Very easy","Easy","Moderate","Hard","Very hard","Skip","Stop asking"] {
            let button = alert.addButton(withTitle:title); button.keyEquivalent = ""
        }
        alert.buttons[5].keyEquivalent = "\u{1b}"
        var resolved = false
        func finish(_ ordinal: Int?, reason: String, show: Bool) {
            guard !resolved else { return }; resolved = true
            state.response = ordinal; state.resolution = reason; state.contractSatisfied = true
            if ordinal != nil { state.state = "submitted"; state.submittedAt = Date() }
            else { state.state = "skipped"; state.skippedAt = Date() }
            save(state)
            self.pending = nil; self.pendingAlert = nil; self.pendingWindow = nil
            if show {
                state.state = "shown"; state.verdictShownAt = Date(); save(state); reveal()
            }
        }
        pending = { reason in finish(nil,reason:reason,show:false) }
        pendingAlert = alert; pendingWindow = window
        alert.beginSheetModal(for:window) { response in
            let index = response.rawValue-NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            if index == 6 { self.defaults.set(true,forKey:"difficulty.feedback.stopped") }
            finish((0..<5).contains(index) ? index+1 : nil,reason:index == 6 ? "stopAsking" : "button",show:true)
        }
    }
    func resolvePending(reason: String) {
        // Resolving locally is independent of connectivity. Navigation will render saved verdict.
        let window = pendingWindow, alert = pendingAlert
        pending?(reason)
        if let window, let alert { window.endSheet(alert.window,returnCode:.abort) }
    }
    static func canDisclose(_ feedback: DifficultyFeedback?) -> Bool { feedback?.state != "pending" && feedback?.state != "assigned" }
    static func needsRecovery(_ feedback: DifficultyFeedback?) -> Bool {
        feedback.map { ["pending", "assigned"].contains($0.state) } ?? false
    }
    static func recovery(_ feedback: DifficultyFeedback?) -> DifficultyFeedback? {
        guard var value = feedback, ["pending", "assigned"].contains(value.state) else { return feedback }
        value.state = "skipped"; value.skippedAt = Date(); value.resolution = "recovery"; value.contractSatisfied = true
        return value
    }
}
