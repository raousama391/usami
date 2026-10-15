# How Usami works

Usami is a menu-bar app (`LSUIElement`, no Dock icon) written in Swift with AppKit for system integration and SwiftUI for the UI. There is no server component.

## The flow

```
select text ──► detect selection ──► show ⌄ trigger ──► click ──► card opens
                  (Accessibility)                                     │
                                                                      ▼
              replace selection ◄── Accept ◄── result ◄── AI provider (Claude / ChatGPT)
```

1. **Detect.** A global mouse-up monitor plus an `AXObserver` on the frontmost app notice that the selection changed. Usami reads the focused element's `AXSelectedText`, `AXSelectedTextRange` and the on-screen bounds of the range.
2. **Show.** A small floating, non-activating `NSPanel` places a chevron icon to the left of the first selected line. Because the panel never becomes key, the app you're typing in keeps focus and the selection stays intact.
3. **Rewrite.** Clicking the icon expands the same panel into a card below the selection and runs **Improve**. Tabs and menus run other actions. Each action is a system prompt plus your selected text.
4. **Accept.** The result is written back via `AXSelectedText`. If the app ignores Accessibility writes, Usami temporarily puts the text on the clipboard, sends ⌘V, then restores your previous clipboard.

## Permissions

Reading other apps' text requires the macOS **Accessibility** permission. macOS stores that grant as a *code requirement* describing which app may use it.

- Release builds are ad-hoc signed with an explicit designated requirement: `identifier "io.prodify.usami"`. Without it, an ad-hoc build's requirement would be the exact build hash, and every update would look like a different app.
- If a stale entry exists (listed as enabled but no longer matching), **Fix Accessibility access…** runs `tccutil reset Accessibility io.prodify.usami` for Usami only and asks macOS again.
- Password fields (`AXSecureTextField`) are always skipped.
- For Chromium/Electron apps, Usami sets `AXManualAccessibility` on the app so their text fields are exposed.

## Providers and sign-in

| | Claude | ChatGPT |
| --- | --- | --- |
| Sign-in | OAuth 2.0 + PKCE in your browser; you paste back the code shown | Device-code flow in your browser; Usami polls until you approve |
| Storage | macOS Keychain (`io.prodify.usami`) | macOS Keychain (`io.prodify.usami`) |
| Requests | Runs the local `claude` CLI (`-p`, no tools, no session persistence) with the token in `CLAUDE_CODE_OAUTH_TOKEN` | Streams from the Codex Responses endpoint on `chatgpt.com` |
| Refresh | Automatic before expiry | Automatic before expiry |

If you're already logged in to the `claude` CLI, Claude works without signing in again in Usami.

The sign-in flows follow the same approach as the open-source [byaan](https://github.com/byaan-ai/byaan) project.

## Source map

| File | Role |
| --- | --- |
| `main.swift` | Entry point; `--render-previews` mode for README screenshots |
| `AppDelegate.swift` | Menu-bar item, Edit menu, permission polling |
| `SelectionMonitor.swift` | Selection detection (mouse + AXObserver) |
| `AccessibilityText.swift` | AX helpers: read, bounds, replace, permission reset |
| `PopupController.swift` | Floating panel placement, resizing, clamping to screen |
| `PopupModel.swift` / `PopupViews.swift` | Card state machine and SwiftUI views |
| `Rewrite.swift` | The actions and their system prompts |
| `Providers.swift` | Claude and ChatGPT providers |
| `ClaudeAuth.swift` / `CodexAuth.swift` | Sign-in flows and token refresh |
| `Keychain.swift`, `Settings.swift`, `SettingsView.swift` | Storage and settings UI |
| `DebugLog.swift` | Metadata-only log at `~/Library/Logs/Usami.log` |

## Known limits

- Apps that don't expose their text through Accessibility won't show the icon.
- Selections can't be replaced in read-only text (the card offers **Copy** instead, if enabled in Settings).
- Builds are not notarized; the installer avoids Gatekeeper prompts by downloading with `curl`.
