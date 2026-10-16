import AppKit
import SwiftUI

@MainActor
final class PopupModel: ObservableObject {
    enum Phase { case trigger, card }

    @Published var phase: Phase = .trigger
    @Published private(set) var selection: SelectionInfo?
    @Published private(set) var action: RewriteAction = .improve
    @Published private(set) var result = ""
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    /// Bumped every time the trigger is shown for a new selection, so its entrance animation replays.
    @Published private(set) var triggerEpoch = 0
    /// The Custom tab is open: the user describes the change in their own words.
    @Published private(set) var isCustomMode = false
    @Published var customInstruction = ""

    static let customSuggestions = ["More polite", "Bullet points", "Add a friendly greeting", "Sound more confident"]

    var onLayoutChange: (() -> Void)?
    var onExpand: (() -> Void)?
    var onDragBegan: (() -> Void)?
    var onDragEnded: (() -> Void)?
    var onClose: (() -> Void)?
    var onAccept: ((SelectionInfo, String) -> Void)?
    /// Asks the panel to accept (true) or give up (false) keyboard focus for the Custom field.
    var onKeyboardNeeded: ((Bool) -> Void)?

    private var task: Task<Void, Never>?

    var providerLabel: String {
        switch Settings.shared.provider {
        case .claude: "Claude · \(Settings.shared.claudeModel)"
        case .codex: "ChatGPT · \(Settings.shared.codexModel)"
        }
    }

    /// Puts the model in a fixed, finished state (used to render README screenshots).
    func configureForPreview(
        selection: SelectionInfo, result: String,
        action: RewriteAction = .improve, isLoading: Bool = false, customRequest: String? = nil
    ) {
        self.selection = selection
        self.result = result
        self.action = customRequest.map { .custom($0) } ?? action
        self.isCustomMode = customRequest != nil
        self.customInstruction = customRequest ?? ""
        self.error = nil
        self.isLoading = isLoading
        self.phase = .card
    }

    func reset(selection: SelectionInfo) {
        task?.cancel()
        self.selection = selection
        phase = .trigger
        result = ""
        error = nil
        isLoading = false
        action = .improve
        isCustomMode = false
        customInstruction = ""
        triggerEpoch += 1
    }

    func expand() {
        phase = .card
        run(.improve)
        onExpand?()
    }

    /// Opens the Custom tab: nothing runs until the user describes the change.
    func enterCustom() {
        task?.cancel()
        isCustomMode = true
        action = .custom(customInstruction)
        result = ""
        error = nil
        isLoading = false
        onKeyboardNeeded?(true)
        onLayoutChange?()
    }

    func submitCustom(_ suggestion: String? = nil) {
        if let suggestion { customInstruction = suggestion }
        let request = customInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { return }
        guard request.count <= 400 else {
            error = "Keep the request short: describe the change in a sentence or two."
            onLayoutChange?()
            return
        }
        run(.custom(request))
    }

    func run(_ newAction: RewriteAction) {
        guard let text = selection?.text else { return }
        if case .custom = newAction {} else if isCustomMode {
            isCustomMode = false
            onKeyboardNeeded?(false)
        }
        task?.cancel()
        action = newAction
        result = ""
        error = nil
        isLoading = true
        onLayoutChange?()

        task = Task { [weak self] in
            guard let self else { return }
            do {
                var output = ""
                let stream = ProviderFactory.current().stream(system: newAction.systemPrompt, user: text)
                for try await chunk in stream {
                    try Task.checkCancellation()
                    output += chunk
                    // Never flash the off-topic marker or a lead-in like "Here is…" while streaming.
                    self.result = OutputCleaner.isOffTopic(output) ? "" : OutputCleaner.clean(output, original: text)
                    self.onLayoutChange?()
                }
                if OutputCleaner.isOffTopic(output) {
                    self.result = ""
                    self.error = "Usami only edits the selected text. Describe a change to it, like \"make it friendlier\" or \"turn it into bullet points\"."
                } else {
                    self.result = OutputCleaner.clean(output, original: text)
                    if self.result.isEmpty { self.error = "The model returned an empty response." }
                }
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
            self.onLayoutChange?()
        }
    }

    func retry() { run(action) }

    func accept() {
        guard let selection, !result.isEmpty else { return }
        onAccept?(selection, result)
    }

    func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(result, forType: .string)
    }

    func close() {
        task?.cancel()
        onKeyboardNeeded?(false)
        onClose?()
    }
}
