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

    var onLayoutChange: (() -> Void)?
    var onExpand: (() -> Void)?
    var onClose: (() -> Void)?
    var onAccept: ((SelectionInfo, String) -> Void)?

    private var task: Task<Void, Never>?

    var providerLabel: String {
        switch Settings.shared.provider {
        case .claude: "Claude · \(Settings.shared.claudeModel)"
        case .codex: "ChatGPT · \(Settings.shared.codexModel)"
        }
    }

    /// Puts the model in a fixed, finished state (used to render README screenshots).
    func configureForPreview(selection: SelectionInfo, result: String) {
        self.selection = selection
        self.result = result
        self.action = .improve
        self.error = nil
        self.isLoading = false
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
    }

    func expand() {
        phase = .card
        run(.improve)
        onExpand?()
    }

    func run(_ newAction: RewriteAction) {
        guard let text = selection?.text else { return }
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
                    self.result = output
                    self.onLayoutChange?()
                }
                self.result = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.result.isEmpty { self.error = "The model returned an empty response." }
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
        onClose?()
    }
}
