#!/usr/bin/env bash
#
# Usami installer
#
#   Install:      curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash
#   Uninstall:    curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- uninstall
#   From source:  curl -fsSL https://raw.githubusercontent.com/raousama391/usami/main/install.sh | bash -s -- --source
#
# Environment overrides: USAMI_REPO (owner/name), USAMI_DMG_URL, USAMI_DEST, USAMI_NO_LAUNCH=1

set -euo pipefail

REPO="${USAMI_REPO:-raousama391/usami}"
APP_NAME="Usami"
BUNDLE_ID="io.prodify.usami"
DMG_URL="${USAMI_DMG_URL:-https://github.com/${REPO}/releases/latest/download/${APP_NAME}.dmg}"

BOLD=$'\033[1m'; GREEN=$'\033[32m'; RED=$'\033[31m'; DIM=$'\033[2m'; NC=$'\033[0m'
step() { printf '%s▸%s %s\n' "$BOLD" "$NC" "$*"; }
ok()   { printf '%s✓%s %s\n' "$GREEN" "$NC" "$*"; }
fail() { printf '%s✗ %s%s\n' "$RED" "$*" "$NC" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Usami only runs on macOS."

MODE="install"
for arg in "$@"; do
    case "$arg" in
        uninstall|--uninstall) MODE="uninstall" ;;
        --source) MODE="source" ;;
        -h|--help) sed -n '2,10p' "$0" 2>/dev/null || true; exit 0 ;;
        *) fail "Unknown option: $arg" ;;
    esac
done

# ── Uninstall ───────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "uninstall" ]; then
    step "Uninstalling ${APP_NAME}…"
    pkill -x "$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME.app" "$HOME/Applications/$APP_NAME.app"
    tccutil reset Accessibility "$BUNDLE_ID" >/dev/null 2>&1 || true
    security delete-generic-password -s "$BUNDLE_ID" -a claude.tokens >/dev/null 2>&1 || true
    security delete-generic-password -s "$BUNDLE_ID" -a codex.tokens  >/dev/null 2>&1 || true
    defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Logs/$APP_NAME.log"
    ok "$APP_NAME removed (app, sign-in tokens, preferences and permission)."
    exit 0
fi

# ── Preflight ───────────────────────────────────────────────────────────────────────────────
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 14 ] || fail "Usami needs macOS 14 (Sonoma) or newer. You have $(sw_vers -productVersion)."

if [ -n "${USAMI_DEST:-}" ]; then
    DEST="$USAMI_DEST"
elif [ -w /Applications ]; then
    DEST="/Applications"
else
    DEST="$HOME/Applications"
fi
mkdir -p "$DEST"

TMP="$(mktemp -d)"
MOUNT="$TMP/mount"
cleanup() {
    hdiutil detach "$MOUNT" -quiet >/dev/null 2>&1 || true
    rm -rf "$TMP"
}
trap cleanup EXIT

# ── Get the DMG ─────────────────────────────────────────────────────────────────────────────
DMG="$TMP/$APP_NAME.dmg"

if [ "$MODE" = "source" ]; then
    command -v git   >/dev/null || fail "git not found. Install the Xcode command line tools: xcode-select --install"
    command -v swift >/dev/null || fail "swift not found. Install the Xcode command line tools: xcode-select --install"
    step "Cloning ${REPO}…"
    git clone --depth 1 "https://github.com/${REPO}.git" "$TMP/src" >/dev/null 2>&1 || fail "Could not clone $REPO."
    step "Building from source (a few minutes)…"
    (cd "$TMP/src" && ./scripts/build_dmg.sh >/dev/null) || fail "Build failed."
    cp "$TMP/src/build/$APP_NAME.dmg" "$DMG"
else
    step "Downloading ${APP_NAME}…"
    if ! curl -fL --progress-bar -o "$DMG" "$DMG_URL"; then
        fail "Download failed from $DMG_URL
  No release published yet? Build from source instead:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- --source"
    fi

    # Verify the checksum when the release provides one.
    if EXPECTED="$(curl -fsSL "${DMG_URL}.sha256" 2>/dev/null | awk '{print $1}')" && [ -n "$EXPECTED" ]; then
        ACTUAL="$(shasum -a 256 "$DMG" | awk '{print $1}')"
        [ "$EXPECTED" = "$ACTUAL" ] || fail "Checksum mismatch — refusing to install."
        ok "Checksum verified"
    fi
fi

# ── Install ─────────────────────────────────────────────────────────────────────────────────
step "Installing to ${DEST}…"
mkdir -p "$MOUNT"
hdiutil attach "$DMG" -nobrowse -readonly -quiet -mountpoint "$MOUNT" >/dev/null || fail "Could not open the disk image."
[ -d "$MOUNT/$APP_NAME.app" ] || fail "$APP_NAME.app not found in the disk image."

if [ -d "$DEST/$APP_NAME.app" ]; then
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 1
    rm -rf "$DEST/$APP_NAME.app"
fi
cp -R "$MOUNT/$APP_NAME.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME.app" 2>/dev/null || true
ok "Installed $DEST/$APP_NAME.app"

if [ -z "${USAMI_NO_LAUNCH:-}" ]; then
    open "$DEST/$APP_NAME.app"
fi

cat <<EOF

${BOLD}Almost done — two quick steps:${NC}
  1. Click the ✨ icon in your menu bar → ${BOLD}Fix Accessibility access…${NC} and switch ${APP_NAME} on.
  2. Open ${BOLD}Settings…${NC} and sign in with Claude or ChatGPT.

Then select text in any text field and click the ⌄ icon next to it.
${DIM}Uninstall any time: curl -fsSL https://raw.githubusercontent.com/${REPO}/main/install.sh | bash -s -- uninstall${NC}
EOF
