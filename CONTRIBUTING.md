# Contributing to Usami

Thanks for helping! Usami is a small project, so the process is light.

## Ways to help

- **Report a bug** — use the [bug report form](https://github.com/raousama391/usami/issues/new?template=bug_report.yml). Please include your macOS version, the app you were using, and the last lines of `~/Library/Logs/Usami.log` (it contains metadata only, never your text).
- **Suggest a feature** — use the [feature request form](https://github.com/raousama391/usami/issues/new?template=feature_request.yml). Usami aims to stay small and minimal, so please say what problem it solves.
- **Send a pull request** — fixes and compatibility improvements for specific apps are especially welcome.

## Development setup

Requirements: macOS 14+, Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/raousama391/usami && cd usami
swift build                      # debug build
./scripts/build_dmg.sh           # release: build/Usami.app and build/Usami.dmg
open build/Usami.app
```

### Accessibility permission while developing

macOS ties the Accessibility grant to the app's code requirement. Builds from `build_dmg.sh` embed a stable requirement (`identifier "io.prodify.usami"`), so a grant survives rebuilds. If macOS lists Usami as enabled but the app still reports no access, click the ✨ menu-bar icon → **Fix Accessibility access…**.

### Useful commands

```bash
tail -f ~/Library/Logs/Usami.log                                  # selection/permission diagnostics
swift build && .build/debug/Usami --render-previews docs/images   # refresh README screenshots
swift scripts/make_icon.swift assets && iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns
```

## Code layout

| Path | What lives there |
| --- | --- |
| `Sources/Usami/SelectionMonitor.swift` | Detects text selections (mouse events + AXObserver) |
| `Sources/Usami/AccessibilityText.swift` | Reading and replacing text via the Accessibility API |
| `Sources/Usami/Popup*.swift` | Floating panel, model and SwiftUI views |
| `Sources/Usami/Providers.swift` | Claude (CLI) and ChatGPT (Codex) providers |
| `Sources/Usami/ClaudeAuth.swift`, `CodexAuth.swift` | Browser sign-in flows and token storage |
| `scripts/` | App/DMG packaging and icon generation |

See [docs/how-it-works.md](docs/how-it-works.md) for the full picture.

## Guidelines

- Keep it **minimal**: small surface area, native controls, no third-party dependencies unless clearly worth it.
- Match the surrounding code's style; prefer clarity over cleverness.
- **Never log or persist the user's selected text.** The debug log is metadata only.
- Don't add telemetry or network calls other than the user's chosen AI provider and its sign-in endpoints.
- UI must work in both light and dark appearance.
- Test in a few real apps (a native one, an Electron one, and a browser) before opening a PR.

## Pull requests

1. Fork and create a branch from `main`.
2. Make your change; update docs and the [changelog](CHANGELOG.md) under **Unreleased** if user-visible.
3. Make sure `swift build -c release` passes and `bash -n install.sh` is clean (CI runs both).
4. Open the PR and fill in the template.

## Releasing (maintainers)

1. Move the **Unreleased** changelog entries under a new version heading.
2. Tag and publish: `gh release create vX.Y.Z --generate-notes`.
3. The [release workflow](.github/workflows/release.yml) builds the universal DMG and attaches it with a SHA-256 checksum; `install.sh` downloads from there.

## Maintainer

[@raousama391](https://github.com/raousama391) · [LinkedIn](https://www.linkedin.com/in/raousama391/)

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).
