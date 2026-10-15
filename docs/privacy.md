# Privacy

Usami has **no server, no account and no analytics**. This page lists exactly what it touches.

## What it reads

- The **text you select** and its position on screen, through the macOS Accessibility API. This is read locally on every selection so the icon can appear; it is not stored or logged.
- Nothing is read from password fields.

## What it sends, and where

| When | What | To |
| --- | --- | --- |
| You click an action (Improve, Rephrase, …) | The selected text and the action's instruction | The provider you selected: Anthropic (via the Claude Code CLI) or OpenAI (`chatgpt.com`) |
| You sign in | Standard OAuth requests | `claude.ai` / `console.anthropic.com`, or `auth.openai.com` |
| Every few hours, if updates are enabled | A request for this project's latest release (your IP and the app version are visible to GitHub) | `api.github.com`; the update itself comes from `github.com/raousama391/usami` releases |

Set **Settings → Updates → Never check** to turn off all update traffic.

Nothing is sent when you merely select text. Nothing is sent to the project maintainers or any third party. What the AI providers do with your text is governed by *their* terms and privacy policies.

## What it stores

| Data | Where |
| --- | --- |
| Sign-in tokens (access + refresh) | macOS Keychain, service `io.prodify.usami` |
| Preferences (provider, model, icon style, language) | macOS user defaults (`io.prodify.usami`) |
| Diagnostic log | `~/Library/Logs/Usami.log` — metadata only: app bundle ID, field role, selection length, permission state. **Never your text.** |

## The clipboard

For apps that reject direct Accessibility writes, Usami briefly puts the rewritten text on the clipboard to paste it, then restores what was there before (all pasteboard types).

## Removing everything

```bash
curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- uninstall
```

This removes the app, Keychain tokens, preferences, the log and the Accessibility entry.
