# Security Policy

## Supported versions

Only the [latest release](https://github.com/raousama391/usami/releases/latest) receives security fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub: [**Report a vulnerability**](https://github.com/raousama391/usami/security/advisories/new). Include what you found, steps to reproduce, the affected version, and the impact you expect. You can expect an acknowledgement within a few days and a fix or mitigation plan as soon as it is understood.

## What Usami handles

Usami runs entirely on your Mac and has no server. Things worth knowing when assessing it:

- **Accessibility permission** — required to read the text you select and to write results back. It is granted by you in System Settings and can be revoked at any time.
- **Sign-in tokens** — the Claude and ChatGPT tokens obtained through browser sign-in are stored in the macOS Keychain (service `io.prodify.usami`). Claude tokens are passed to the local `claude` CLI through the `CLAUDE_CODE_OAUTH_TOKEN` environment variable of a child process.
- **Selected text** — sent only to the provider you selected, only when you request a rewrite. See [docs/privacy.md](docs/privacy.md).
- **Clipboard fallback** — for apps that reject direct Accessibility writes, Usami temporarily places the result on the clipboard to paste it, then restores the previous clipboard contents.
- **Logs** — `~/Library/Logs/Usami.log` records metadata only (app bundle ID, field role, selection length) and never the text itself.

## Distribution and signing

Release builds are **ad-hoc signed and not notarized**. The installer downloads over HTTPS with `curl` and verifies a SHA-256 checksum published with each release. If you prefer, build from source and inspect the code — it is small and has no third-party dependencies.

## Scope

In scope: the app, `install.sh`, and the release workflow. Out of scope: vulnerabilities in macOS, the Claude Code CLI, or the AI providers' services — please report those to their vendors.
