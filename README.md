<p align="center">
  <img src="docs/images/icon.png" width="96" alt="Usami app icon">
</p>

<h1 align="center">Usami</h1>

<p align="center">
  <strong>An open-source Grammarly alternative for macOS.</strong><br>
  Select text in any app, then improve, rephrase or translate it with AI —<br>
  powered by your own Claude or ChatGPT subscription.
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/raousama391/usami"></a>
  <a href="https://github.com/raousama391/usami/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/raousama391/usami?include_prereleases"></a>
  <a href="https://github.com/raousama391/usami/actions/workflows/ci.yml"><img alt="Build status" src="https://img.shields.io/github/actions/workflow/status/raousama391/usami/ci.yml?branch=main&label=build"></a>
  <img alt="macOS 14+" src="https://img.shields.io/badge/macOS-14%2B-lightgrey">
  <img alt="Swift 5.9" src="https://img.shields.io/badge/Swift-5.9-orange">
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/screenshot-dark.png">
    <img src="docs/images/screenshot-light.png" width="640" alt="Usami grammar and rewrite suggestion card next to selected text on macOS">
  </picture>
</p>

## What is Usami?

Usami is a small native macOS menu-bar app: a **system-wide AI writing assistant** that works like a grammar checker and rewriting tool in *every* app — Mail, Slack, Notes, browsers, editors, chat apps. Select some text, click the **⌄** icon that appears beside it, and pick **Improve**, **Rephrase**, **Translate** or one of the **More** options. Accept the result and it replaces your text in place.

It is built in Swift and SwiftUI, has **no server and no analytics**, and uses the Claude or ChatGPT subscription you already pay for instead of another monthly plan.

## Features

- **Works everywhere** — any app that exposes text through macOS Accessibility, not just browsers.
- **Improve** grammar, spelling, clarity and flow while keeping your voice.
- **Rephrase**, **translate** into 14 languages, or make text **shorter, longer, more formal, more casual**, or **summarize** it.
- **Bring your own AI** — sign in with **Claude** (Pro/Max) or **ChatGPT** (Plus/Pro) through your browser.
- **Minimal and native** — light/dark theme aware, a single small icon, no windows to manage.
- **Private by design** — only the text you choose to rewrite is sent, only to the provider you picked. Tokens live in your macOS Keychain.
- **Stays up to date** — optional in-app updates from GitHub Releases: get notified, install automatically, or never check.
- **Open source** — MIT-licensed, about 2,000 lines of Swift, no third-party dependencies.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash
```

Requires macOS 14 (Sonoma) or newer · Apple Silicon and Intel. Prefer a manual download? Get `Usami.dmg` from the [latest release](https://github.com/raousama391/usami/releases/latest).

## Set up (about 30 seconds)

1. **Allow access.** Click the ✨ icon in the menu bar → **Fix Accessibility access…** and switch Usami on. macOS needs this so Usami can read the text you select.
2. **Sign in.** Open **Settings…**, choose **Claude** or **ChatGPT**, and sign in through your browser.

> Claude requests run through the [Claude Code](https://docs.claude.com/en/docs/claude-code) CLI, so it needs to be installed. ChatGPT needs nothing extra.

## Use

Select text in any editable field → click **⌄** next to it → choose **Improve**, **Rephrase**, **Translate** or **More** → **Accept** to replace your text (or **Copy**).

The card stays open until you close it with **✕**. It belongs to the window where you selected the text: it moves with that window, appears only there (not in other apps or desktops), and you can **drag it by its header** to put it anywhere.

Settings lets you switch provider and model, set the default translation language, and choose the icon style (blue outline or solid).

## Usami vs Grammarly

| | Usami | Grammarly |
| --- | --- | --- |
| Price | Free; uses your existing Claude or ChatGPT plan | Free tier and paid plans |
| Source code | Open source (MIT) | Closed source |
| Where your text goes | Only to the AI provider you chose | Grammarly's servers |
| Account with the app's vendor | None | Required |
| Platforms | macOS | macOS, Windows, web, mobile |
| Real-time underlines & plagiarism check | No | Yes |

Usami is intentionally small: it is an on-demand rewriting tool, not a full replacement for everything Grammarly offers. If you want inline underlines as you type, plagiarism detection or Windows support, Grammarly covers that and Usami does not.

## Documentation

| | |
| --- | --- |
| [How it works](docs/how-it-works.md) | Architecture, permissions and sign-in flows |
| [Privacy](docs/privacy.md) | Exactly what is read, stored and sent |
| [Troubleshooting](docs/troubleshooting.md) | Permission, sign-in and app-compatibility fixes |
| [FAQ](docs/faq.md) | Common questions |
| [Contributing](CONTRIBUTING.md) · [Security](SECURITY.md) · [Changelog](CHANGELOG.md) | Project info |

## Build from source

```bash
git clone https://github.com/raousama391/usami && cd usami
./scripts/build_dmg.sh        # → build/Usami.app and build/Usami.dmg
```

Needs the Xcode command line tools (`xcode-select --install`). Details are in [CONTRIBUTING.md](CONTRIBUTING.md).

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- uninstall
```

Removes the app, saved sign-in tokens, preferences and the Accessibility entry.

## Personal use

Usami is designed for **personal use with your own subscription**. The code is MIT-licensed, so the license itself places no such limit — this is a request, not a license term. Please don't run it as a shared or resold service on one person's subscription; AI providers' terms generally don't allow that.

Signing in reuses the official Claude Code and Codex login flows. Check your plan's terms; staying logged in to the `claude` CLI is the most conservative option for Claude.

## Contributing

Bug reports, ideas and pull requests are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md) and the [Code of Conduct](CODE_OF_CONDUCT.md).

## Author

Built by **Usama Javed**.

- GitHub: [@raousama391](https://github.com/raousama391)
- LinkedIn: [linkedin.com/in/raousama391](https://www.linkedin.com/in/raousama391/)

If Usami is useful to you, a ⭐ on the repo helps others find it.

## License

[MIT](LICENSE) © 2026 Usama Javed

Usami is an independent project and is not affiliated with, endorsed by or sponsored by Grammarly, Anthropic or OpenAI. Grammarly, Claude, ChatGPT and Codex are trademarks of their respective owners.
