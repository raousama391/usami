import Foundation

enum ProviderError: LocalizedError {
    case claudeCLINotFound
    case notSignedIn(String)
    case cli(String)
    case http(Int, String)
    case other(String)

    var errorDescription: String? {
        switch self {
        case .claudeCLINotFound:
            "Claude Code CLI not found. Install it (npm i -g @anthropic-ai/claude-code) or sign in from Settings."
        case .notSignedIn(let name):
            "Not signed in to \(name). Open Usami → Settings to sign in."
        case .cli(let message):
            message.isEmpty ? "The Claude CLI exited with an error." : message
        case .http(let status, let body):
            "Request failed (\(status)). \(body)"
        case .other(let message):
            message
        }
    }
}

protocol LLMProvider {
    func stream(system: String, user: String) -> AsyncThrowingStream<String, Error>
}

enum ProviderFactory {
    static func current() -> LLMProvider {
        switch Settings.shared.provider {
        case .claude: ClaudeProvider(model: Settings.shared.claudeModel)
        case .codex: CodexProvider(model: Settings.shared.codexModel)
        }
    }
}

// MARK: - Claude (through the Claude Code CLI, same approach byaan uses)

/// Resolves the login-shell PATH and CLI locations once, since GUI apps get a minimal environment.
actor ShellEnvironment {
    static let shared = ShellEnvironment()
    private var cached: (path: String, claude: String?)?

    func resolve() async -> (path: String, claude: String?) {
        if let cached { return cached }
        let value = await Task.detached { Self.probe() }.value
        cached = value
        return value
    }

    func invalidate() { cached = nil }

    private static func probe() -> (path: String, claude: String?) {
        let home = NSHomeDirectory()
        var path = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local", "/usr/bin", "/bin"]
        var claude: String?

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-ilc", "echo \"__USAMI_PATH__$PATH\"; echo \"__USAMI_CLAUDE__$(command -v claude)\""]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice
        if (try? process.run()) != nil {
            let watchdog = DispatchWorkItem { if process.isRunning { process.terminate() } }
            DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: watchdog)
            let data = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            watchdog.cancel()
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
                if let range = line.range(of: "__USAMI_PATH__") {
                    path = line[range.upperBound...].split(separator: ":").map(String.init) + path
                } else if let range = line.range(of: "__USAMI_CLAUDE__") {
                    let found = String(line[range.upperBound...])
                    if !found.isEmpty, FileManager.default.isExecutableFile(atPath: found) { claude = found }
                }
            }
        }

        if claude == nil {
            claude = path.map { "\($0)/claude" }.first { FileManager.default.isExecutableFile(atPath: $0) }
        }
        var seen = Set<String>()
        let joined = path.filter { seen.insert($0).inserted }.joined(separator: ":")
        return (joined, claude)
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
    var value: Data { lock.lock(); defer { lock.unlock() }; return data }
}

struct ClaudeProvider: LLMProvider {
    let model: String

    func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let processBox = ProcessBox()
            let task = Task {
                do {
                    let shell = await ShellEnvironment.shared.resolve()
                    guard let cli = shell.claude else { throw ProviderError.claudeCLINotFound }

                    var environment = ProcessInfo.processInfo.environment
                    environment["PATH"] = shell.path
                    environment.removeValue(forKey: "ANTHROPIC_API_KEY")
                    if let token = try await ClaudeAuth.shared.activeAccessToken() {
                        environment["CLAUDE_CODE_OAUTH_TOKEN"] = token
                    }

                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: cli)
                    process.arguments = [
                        "-p", "--model", model,
                        "--system-prompt", system,
                        "--tools", "",
                        "--no-session-persistence",
                        "--output-format", "text",
                        "--setting-sources", "local",
                        "--strict-mcp-config",
                    ]
                    process.environment = environment
                    process.currentDirectoryURL = FileManager.default.temporaryDirectory

                    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
                    process.standardInput = stdin
                    process.standardOutput = stdout
                    process.standardError = stderr
                    processBox.process = process

                    let outBox = DataBox(), errBox = DataBox()
                    stdout.fileHandleForReading.readabilityHandler = { h in
                        let d = h.availableData
                        if !d.isEmpty { outBox.append(d) }
                    }
                    stderr.fileHandleForReading.readabilityHandler = { h in
                        let d = h.availableData
                        if !d.isEmpty { errBox.append(d) }
                    }

                    let exited: Int32 = try await withCheckedThrowingContinuation { cont in
                        process.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
                        do {
                            try process.run()
                            stdin.fileHandleForWriting.write(Data(user.utf8))
                            try? stdin.fileHandleForWriting.close()
                        } catch {
                            cont.resume(throwing: error)
                        }
                    }

                    stdout.fileHandleForReading.readabilityHandler = nil
                    stderr.fileHandleForReading.readabilityHandler = nil
                    outBox.append((try? stdout.fileHandleForReading.readToEnd()) ?? Data())
                    errBox.append((try? stderr.fileHandleForReading.readToEnd()) ?? Data())

                    let output = String(decoding: outBox.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if exited != 0 {
                        let err = String(decoding: errBox.value, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        throw ProviderError.cli(String((output.isEmpty ? err : output).prefix(400)))
                    }
                    continuation.yield(output)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
                if let p = processBox.process, p.isRunning { p.terminate() }
            }
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    var process: Process?
}

// MARK: - ChatGPT / Codex (Responses API on chatgpt.com, same endpoint byaan uses)

struct CodexProvider: LLMProvider {
    let model: String

    func stream(system: String, user: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (token, accountId) = try await CodexAuth.shared.validToken()

                    var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/codex/responses")!)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 90
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
                    request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
                    if let accountId { request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id") }

                    let body: [String: Any] = [
                        "model": model,
                        "instructions": system,
                        "input": [["role": "user", "content": user]],
                        "store": false,
                        "stream": true,
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ProviderError.other("No response") }
                    guard http.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte); if data.count > 600 { break } }
                        throw ProviderError.http(http.statusCode, String(decoding: data, as: UTF8.self))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard payload != "[DONE]",
                              let json = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
                              let type = json["type"] as? String else { continue }
                        switch type {
                        case "response.output_text.delta":
                            if let delta = json["delta"] as? String { continuation.yield(delta) }
                        case "response.failed", "error":
                            let message = (json["message"] as? String)
                                ?? ((json["response"] as? [String: Any])?["error"] as? [String: Any])?["message"] as? String
                                ?? "The model returned an error."
                            throw ProviderError.other(message)
                        case "response.completed":
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
