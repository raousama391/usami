import Foundation

enum ProviderKind: String, CaseIterable, Identifiable {
    case claude
    case codex

    var id: String { rawValue }
    var title: String { self == .claude ? "Claude" : "ChatGPT (Codex)" }
}

enum TriggerStyle: String, CaseIterable, Identifiable {
    case outline
    case solid

    var id: String { rawValue }
    var title: String { self == .outline ? "Blue outline" : "Solid" }
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
    @Published var provider: ProviderKind { didSet { defaults.set(provider.rawValue, forKey: "provider") } }
    @Published var claudeModel: String { didSet { defaults.set(claudeModel, forKey: "claudeModel") } }
    @Published var codexModel: String { didSet { defaults.set(codexModel, forKey: "codexModel") } }
    @Published var translateTo: String { didSet { defaults.set(translateTo, forKey: "translateTo") } }

    private init() {
        defaults.register(defaults: [
            "enabled": true,
            "showForReadOnly": false,
            "provider": ProviderKind.claude.rawValue,
            "triggerStyle": TriggerStyle.outline.rawValue,
            "claudeModel": "haiku",
            "codexModel": "gpt-6-luna",
            "translateTo": "English",
        ])
        enabled = defaults.bool(forKey: "enabled")
        showForReadOnly = defaults.bool(forKey: "showForReadOnly")
        triggerStyle = TriggerStyle(rawValue: defaults.string(forKey: "triggerStyle") ?? "") ?? .outline
        provider = ProviderKind(rawValue: defaults.string(forKey: "provider") ?? "") ?? .claude
        claudeModel = defaults.string(forKey: "claudeModel") ?? "haiku"
        codexModel = defaults.string(forKey: "codexModel") ?? "gpt-6-luna"
        translateTo = defaults.string(forKey: "translateTo") ?? "English"
    }
}
