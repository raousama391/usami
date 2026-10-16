import AppKit
import Foundation

/// Browser sign-in with a ChatGPT subscription through the Codex device-code flow
/// (same flow byaan uses). Tokens are kept in a private file in Application Support and refreshed on demand.
@MainActor
final class CodexAuth: ObservableObject {
    static let shared = CodexAuth()

    private static let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private static let base = "https://auth.openai.com"
    private static let tokenAccount = "codex.tokens"

    struct Tokens: Codable {
        var accessToken: String
        var refreshToken: String
        var expiresAt: Date
        var accountId: String?
    }

    enum Phase: Equatable {
        case idle
        case waiting(userCode: String, url: String)
    }

    @Published private(set) var isSignedIn: Bool
    @Published private(set) var phase: Phase = .idle
    @Published var lastError: String?

    private var signInTask: Task<Void, Never>?

    private init() {
        isSignedIn = TokenStore.get(Self.tokenAccount) != nil
    }

    // MARK: Sign in (device code)

    func beginSignIn() {
        signInTask?.cancel()
        lastError = nil
        signInTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.runDeviceFlow()
            } catch is CancellationError {
            } catch {
                self.lastError = error.localizedDescription
            }
            self.phase = .idle
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        phase = .idle
    }

    func signOut() {
        cancelSignIn()
        TokenStore.delete(Self.tokenAccount)
        isSignedIn = false
    }

    private func runDeviceFlow() async throws {
        let start = try await postJSON(
            "\(Self.base)/api/accounts/deviceauth/usercode", ["client_id": Self.clientID]
        )
        guard let deviceAuthId = start["device_auth_id"] as? String,
              let userCode = (start["user_code"] as? String) ?? (start["usercode"] as? String) else {
            throw ProviderError.other("Unexpected response from OpenAI while starting sign-in.")
        }
        let interval = Self.intValue(start["interval"]) ?? 5
        let verificationURL = "\(Self.base)/codex/device"

        phase = .waiting(userCode: userCode, url: verificationURL)
        NSWorkspace.shared.open(URL(string: verificationURL)!)

        let deadline = Date().addingTimeInterval(15 * 60)
        while Date() < deadline {
            try Task.checkCancellation()
            let (status, json) = try await rawPostJSON(
                "\(Self.base)/api/accounts/deviceauth/token",
                ["device_auth_id": deviceAuthId, "user_code": userCode]
            )
            if status == 200 {
                guard let code = json["authorization_code"] as? String,
                      let verifier = json["code_verifier"] as? String else {
                    throw ProviderError.other("OpenAI returned an incomplete authorization.")
                }
                let tokens = try await exchange(code: code, verifier: verifier)
                try save(tokens)
                return
            }
            if status == 403 || status == 404 {
                try await Task.sleep(nanoseconds: UInt64(max(interval, 2)) * 1_000_000_000)
                continue
            }
            throw ProviderError.http(status, "Device sign-in failed.")
        }
        throw ProviderError.other("Sign-in timed out after 15 minutes.")
    }

    private func exchange(code: String, verifier: String) async throws -> [String: Any] {
        try await postForm("\(Self.base)/oauth/token", [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": "\(Self.base)/deviceauth/callback",
            "client_id": Self.clientID,
            "code_verifier": verifier,
        ])
    }

    // MARK: Token access

    func validToken() async throws -> (token: String, accountId: String?) {
        guard let data = TokenStore.get(Self.tokenAccount),
              var tokens = try? JSONDecoder().decode(Tokens.self, from: data) else {
            throw ProviderError.notSignedIn("ChatGPT")
        }
        if tokens.expiresAt.timeIntervalSinceNow > 300 {
            return (tokens.accessToken, tokens.accountId)
        }
        guard !tokens.refreshToken.isEmpty else { throw ProviderError.notSignedIn("ChatGPT") }

        let refreshed = try await postForm("\(Self.base)/oauth/token", [
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": Self.clientID,
        ])
        tokens = try save(refreshed, fallback: tokens)
        return (tokens.accessToken, tokens.accountId)
    }

    @discardableResult
    private func save(_ response: [String: Any], fallback: Tokens? = nil) throws -> Tokens {
        guard let access = response["access_token"] as? String else {
            throw ProviderError.other("OpenAI did not return an access token.")
        }
        let expiresIn = (response["expires_in"] as? Double) ?? 3600
        var accountId: String?
        for key in ["id_token", "access_token"] {
            if let jwt = response[key] as? String, let id = Self.accountID(fromJWT: jwt) {
                accountId = id
                break
            }
        }
        let refresh = (response["refresh_token"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let tokens = Tokens(
            accessToken: access,
            refreshToken: refresh ?? fallback?.refreshToken ?? "",
            expiresAt: Date().addingTimeInterval(expiresIn),
            accountId: accountId ?? fallback?.accountId
        )
        TokenStore.set(try JSONEncoder().encode(tokens), for: Self.tokenAccount)
        isSignedIn = true
        return tokens
    }

    // MARK: Networking helpers

    private func rawPostJSON(_ url: String, _ body: [String: String]) async throws -> (Int, [String: Any]) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, json)
    }

    private func postJSON(_ url: String, _ body: [String: String]) async throws -> [String: Any] {
        let (status, json) = try await rawPostJSON(url, body)
        guard status == 200 else { throw ProviderError.http(status, "Could not start ChatGPT sign-in.") }
        return json
    }

    private func postForm(_ url: String, _ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").data(using: .utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw ProviderError.http(status, String(decoding: data.prefix(300), as: UTF8.self))
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let s = any as? String { return Int(s) }
        return nil
    }

    private static func accountID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let id = json["chatgpt_account_id"] as? String { return id }
        if let auth = json["https://api.openai.com/auth"] as? [String: Any],
           let id = auth["chatgpt_account_id"] as? String { return id }
        if let orgs = json["organizations"] as? [[String: Any]], let id = orgs.first?["id"] as? String { return id }
        return nil
    }
}
