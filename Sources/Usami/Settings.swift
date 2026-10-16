import Foundation

enum ProviderKind: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "ChatGPT (Codex)" }
}

enum UpdateMode: String, CaseIterable, Identifiable {
    case notify
    case automatic
    case off

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notify: "Notify me"
        case .automatic: "Install automatically"
        case .off: "Never check"
        }
    }
}

enum TriggerStyle: String, CaseIterable, Identifiable {
    case outline
    case solid

    var id: String { rawValue }
    var title: String { self == .outline ? "Light" : "App icon" }
}

final class Settings: ObservableObject {
    static let shared = Settings()

    static let claudeModels = ["haiku", "sonnet", "opus"]
    static let codexModels = ["gpt-6-luna", "gpt-6-astra", "gpt-6.1-sol"]
    static let languages = [
        "English", "Spanish", "French", "German", "Italian", "Portuguese", "Arabic",
        "Urdu", "Hindi", "Chinese", "Japanese", "Korean", "Russian", "Turkish",
    ]

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool { didSet { defaults.set(enabled, forKey: "enabled") } }
    @Published var showForReadOnly: Bool { didSet { defaults.set(showForReadOnly, forKey: "showForReadOnly") } }
    @Published var triggerStyle: TriggerStyle { didSet { defaults.set(triggerStyle.rawValue, forKey: "triggerStyle") } }
    @Published var updateMode: UpdateMode { didSet { defaults.set(updateMode.rawValue, forKey: "updateMode") } }
    @Published var provider: ProviderKind { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "claudeModel") } }
    @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    @Published var translateTo: String { didSet { defaults.set(translateTo, forKey: "translateTo") } }
    /// Set once the setup guide has been finished (or skipped).
    @Published var onboarded: Bool { didSet { defaults.set(onboarded, forKey: "onboarded") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "showForReadOnly": false,
            "provider": ProviderKind.claude.rawValue,
            "triggerStyle": TriggerStyle.solid.rawValue,
            "updateMode": UpdateMode.notify.rawValue,
            "claudeModel": "haiku",
            "codexModel": "gpt-6-luna",
            "translateTo": "English",
            "onboarded": false,
        ])
        enabled = defaults.bool(forKey: "enabled")
        showForReadOnly = defaults.bool(forKey: "showForReadOnly")
        triggerStyle = TriggerStyle(rawValue: defaults.string(forKey: "triggerStyle") ?? "") ?? .solid
        updateMode = UpdateMode(rawValue: defaults.string(forKey: "updateMode") ?? "") ?? .notify
        provider = ProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .claude
        claudeModel = defaults.string(forKey: "claudeModel") ?? "haiku"
        codexModel = defaults.string(forKey: "codexModel") ?? "gpt-6-luna"
        translateTo = defaults.string(forKey: "translateTo") ?? "English"
        onboarded = defaults.bool(forKey: "onboarded")
    }
}
