import AppKit
import CryptoKit
import Foundation

/// Browser sign-in with a Claude Pro/Max subscription (OAuth 2.0 + PKCE), the same flow byaan
/// ports from the Claude Code CLI. Tokens live in the Keychain and are handed to the `claude`
/// CLI through CLAUDE_CODE_OAUTH_TOKEN. With no stored tokens, the CLI's own login is used.
@MainActor
final class ClaudeAuth: ObservableObject {
    static let shared = ClaudeAuth()

    private static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let authURL = "https://claude.ai/oauth/authorize"
    private static let tokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let redirectURI = "https://console.anthropic.com/oauth/code/callback"
    private static let scopes = "org:create_api_key user:profile user:inference"
    private static let keychainAccount = "claude.tokens"

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
    }

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var awaitingCode = false
    @Published var lastError: String?
    @Published private(set) var isWorking = false

    private var pending: (verifier: String, state: String)?

    private init() {
        isSignedIn = Keychain.get(Self.keychainAccount) != nil
    }

    // MARK: Sign in

    func beginSignIn() {
        lastError = nil
        let verifier = Self.randomURLSafe(32)
        let state = Self.randomURLSafe(32)
        let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        pending = (verifier, state)

        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            .init(name: "code", value: "true"),
            .init(name: "client_id", value: Self.clientID),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "scope", value: Self.scopes),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        awaitingCode = true
        NSWorkspace.shared.open(components.url!)
    }

    func cancelSignIn() {
        pending = nil
        awaitingCode = false
    }

    /// `pasted` is the "code#state" string shown on the Anthropic callback page.
    func completeSignIn(pasted: String) async {
        guard let pending else {
            lastError = "Start the sign-in again."
            return
        }
        let parts = pasted.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "#", maxSplits: 1).map(String.init)
        guard let code = parts.first, !code.isEmpty else {
            lastError = "Paste the code shown after you approve access."
            return
        }
        let state = parts.count > 1 ? parts[1] : pending.state

        isWorking = true
        defer { isWorking = false }
        do {
            let response = try await post([
                "grant_type": "authorization_code",
                "code": code,
                "client_id": Self.clientID,
                "code_verifier": pending.verifier,
                "redirect_uri": Self.redirectURI,
                "state": state,
            ])
            try store(response)
            self.pending = nil
            awaitingCode = false
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() {
        Keychain.delete(Self.keychainAccount)
        isSignedIn = false
        awaitingCode = false
        pending = nil
    }

    // MARK: Token access

    /// Returns a valid access token, refreshing if needed. Nil means "use the CLI's own login".
    func activeAccessToken() async throws -> String? {
        guard let data = Keychain.get(Self.keychainAccount),
              var tokens = try? JSONDecoder().decode(Tokens.self, from: data) else { return nil }
        if tokens.expiresAt.timeIntervalSinceNow > 300 { return tokens.accessToken }

        let response = try await post([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": Self.clientID,
        ])
        tokens = try store(response)
        return tokens.accessToken
    }

    // MARK: Helpers

    @discardableResult
    private func store(_ response: [String: Any]) throws -> Tokens {
        guard let access = response["access_token"] as? String else {
            throw ProviderError.other("Claude did not return an access token.")
        }
        let expiresIn = (response["expires_in"] as? Double) ?? 3600
        let existingRefresh = Keychain.get(Self.keychainAccount)
            .flatMap { try? JSONDecoder().decode(Tokens.self, from: $0) }?.refreshToken
        let tokens = Tokens(
            accessToken: access,
            refreshToken: (response["refresh_token"] as? String) ?? existingRefresh ?? "",
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        Keychain.set(try JSONEncoder().encode(tokens), for: Self.keychainAccount)
        isSignedIn = true
        return tokens
    }

    private func post(_ body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ProviderError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var data = Data(count: bytes)
        _ = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return base64URL(data)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
