# FAQ

### Is Usami free?
Yes. The app is free and open source (MIT). It uses the Claude or ChatGPT subscription you already have, so there is no extra plan.

### Is it a Grammarly replacement?
It covers the "select text and fix or rewrite it" part: grammar, clarity, rephrasing and translation in any Mac app. It does not do real-time underlines as you type or plagiarism detection, and it is macOS-only.

### Which apps does it work in?
Any app that exposes text through macOS Accessibility — most native apps, Electron apps (Slack, VS Code), and browsers. See [troubleshooting](troubleshooting.md#app-compatibility).

### Does it work offline?
No. Rewrites need an AI provider, so you need an internet connection.

### Where does my text go?
Only to the provider you picked (Anthropic or OpenAI), and only when you click an action. Nothing goes to the project or any other party. See [privacy](privacy.md).

### Why does it need the Accessibility permission?
That is the only way a Mac app can read text you select in *other* apps and write the result back. It's granted in System Settings and can be revoked any time.

### Why isn't it on the Mac App Store?
App Store apps must be sandboxed, and the Accessibility API doesn't work from a sandbox.

### Why does Claude need the Claude Code CLI?
Claude requests run through the official CLI using your login. ChatGPT doesn't need anything installed.

### Which models can I use?
Claude: `haiku` (fast, default), `sonnet`, `opus`. ChatGPT: the Codex models listed in Settings. Pick them in **Settings → AI provider**.

### Is it safe to sign in with my subscription?
Sign-in tokens are stored in your Keychain and used only to call your provider. Providers' terms differ on third-party use of subscriptions — read yours. Staying logged in to the official `claude` CLI is the most conservative option.

### How do updates work?
Usami checks GitHub Releases every few hours. In **Settings → Updates** choose **Notify me** (default), **Install automatically**, or **Never check**. You can also use **Check for Updates…** from the menu bar. See [how it works](how-it-works.md#updates).

### Intel Macs? Older macOS?
Releases are universal (Apple Silicon and Intel). macOS 14 (Sonoma) or newer is required.

### Windows or Linux?
Not currently. Usami is built on macOS-specific APIs.

### How do I uninstall it?
```bash
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- uninstall
```

### How can I contribute?
See [CONTRIBUTING.md](../CONTRIBUTING.md).
