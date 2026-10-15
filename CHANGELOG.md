# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.3] - 2026-10-16

### Added
- **In-app updates.** Usami checks GitHub Releases every few hours. Choose in Settings → Updates to be notified, to install automatically, or to never check. The menu bar has **Check for Updates…**, and a one-click **Update to vX.Y.Z** when one is available. Downloads are limited to this repository's releases, verified against the published SHA-256, and swapped in after a restart.
- **Draggable card.** Drag the card by its header to move it anywhere; it keeps that position relative to its window.
- `Usami --check-updates` and `Usami --update` command-line modes.

### Changed
- The card now only appears in the window (and desktop Space) where you selected the text. It no longer follows you to other apps, windows or Spaces, and returns when you go back to its window.

### Fixed
- The one-line installer failing with `APP_NAME…: unbound variable` under UTF-8 locales on macOS's bash 3.2, now covered by a CI check.
- A mounted-volume leak in the updater's staging step (found in testing before release).

## [0.1.2] - 2026-10-16

### Changed
- The suggestion card now stays open until you close it with the **✕** button (or accept the result). Clicking elsewhere, changing the selection or typing no longer dismisses it.
- The card is attached to the window where you selected the text: it moves with that window, hides while another window or app is in front, and returns when you come back. It closes if that window is closed.

## [0.1.1] - 2026-10-16

### Added
- One-line installer (`install.sh`) with install, uninstall and build-from-source modes.
- GitHub Actions release workflow that builds and attaches the universal DMG and a SHA-256 checksum.
- README screenshots rendered from the real UI (`Usami --render-previews`).
- Project documentation: how it works, privacy, troubleshooting, FAQ, contributing and security policy.
- Chevron trigger icon placed to the left of the selection, with **blue outline** and **solid** styles.
- Minimal card that follows the system light/dark theme and opens below the selection.
- App icon.
- **Fix Accessibility access…** action in the menu bar and Settings to clear a stale permission entry.

### Changed
- Builds embed a stable designated requirement so the Accessibility grant survives rebuilds and updates.
- Edit menu installed so ⌘V/⌘C/⌘A work in Settings fields.

## [0.1.0] - 2026-10-16

### Added
- Menu-bar app that detects text selection system-wide through the Accessibility API.
- Improve, Rephrase, Translate and More (grammar, shorter, longer, formal, casual, summarize) actions.
- Claude sign-in (browser PKCE flow, runs through the Claude Code CLI) and ChatGPT sign-in (Codex device-code flow).
- In-place replacement of the selection with a clipboard-paste fallback.
- Universal (Apple Silicon + Intel) DMG packaging script.

[Unreleased]: https://github.com/raousama391/usami/compare/v0.1.3...HEAD
[0.1.3]: https://github.com/raousama391/usami/compare/v0.1.2...v0.1.3
[0.1.2]: https://github.com/raousama391/usami/compare/v0.1.1...v0.1.2
[0.1.1]: https://github.com/raousama391/usami/releases/tag/v0.1.1
[0.1.0]: https://github.com/raousama391/usami/releases/tag/v0.1.0
