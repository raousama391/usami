# Troubleshooting

Start with the diagnostic log — it explains most problems:

```bash
tail -n 30 ~/Library/Logs/Usami.log
```

## The icon never appears

| Log line | Meaning | Fix |
| --- | --- | --- |
| `launch: accessibility trusted = false` / `check: NOT TRUSTED` | macOS hasn't granted access to this build | Menu bar ✨ → **Fix Accessibility access…**, then switch Usami on |
| `no focused element` | The app doesn't expose a focused text element | See "App compatibility" below |
| `selection too short/empty` | Fewer than 3 characters selected | Select more text |
| `read-only, skipped` | The text isn't editable | Enable **Also show for read-only text** in Settings |
| `secure field, skipped` | Password field | By design |
| nothing at all | Selection events aren't arriving | Quit and reopen Usami; make sure **Show suggestions when I select text** is on |

## Usami is enabled in Accessibility but still says access is missing

This is a stale entry from an older signature. Use **Fix Accessibility access…** (menu bar or Settings → **Fix…**). Manual equivalent:

```bash
tccutil reset Accessibility io.prodify.usami
```

Then enable Usami again when prompted.

## Claude says the CLI wasn't found

Usami runs Claude through the Claude Code CLI. Install it, then reopen Usami:

```bash
npm install -g @anthropic-ai/claude-code
```

Usami finds `claude` through your login shell's `PATH`, so installs via nvm, Homebrew or the native installer all work.

## Claude sign-in fails

- Paste the **entire** code shown on the Anthropic page (it looks like `code#state`).
- Codes are single-use and expire quickly — click **Sign in with Claude…** again for a fresh one.
- Already logged in to `claude` in Terminal? You can skip signing in here.

## ChatGPT sign-in doesn't complete

- Enter the displayed code on the page that opens, and approve with the same ChatGPT account you subscribe with.
- The code expires after about 15 minutes; click **Cancel** and start again.
- A ChatGPT **Plus/Pro** plan is required for Codex access.

## The result doesn't replace my text

Some apps ignore Accessibility writes; Usami then pastes with ⌘V. If that also fails, use **Copy** and paste manually, and please [open an issue](https://github.com/raousama391/usami/issues/new?template=bug_report.yml) with the app's name.

## App compatibility

- **Native apps** (Notes, Mail, TextEdit, Messages): work best.
- **Electron apps** (Slack, VS Code, Claude): work; Usami asks them to expose accessibility.
- **Browsers**: work in standard text fields and many rich editors; some custom editors don't expose text.
- **Terminals and games**: generally not supported.

## macOS says the app can't be opened

Right-click `Usami.app` → **Open** once. The install command avoids this because it downloads with `curl`.

## Reinstall from scratch

```bash
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- uninstall
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash
```
