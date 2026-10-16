#!/usr/bin/env bash
# Builds Usami.app (universal) and wraps it in build/Usami.dmg
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
APP_NAME="Usami"
BUNDLE_ID="io.prodify.usami"
VERSION="${VERSION:-0.2.1}"
BUILD="$ROOT/build"
APP="$BUILD/$APP_NAME.app"

echo "▸ Compiling (release, arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/assets/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Copyright © 2026 Usama Javed. MIT License.</string>
</dict>
</plist>
PLIST

# macOS stores the Accessibility grant as a code requirement. A plain ad-hoc signature's
# requirement is the exact build hash, so every rebuild looks like a different app and the grant
# stops matching. We embed an explicit requirement based on the bundle identifier instead, so the
# grant survives rebuilds. (Local use only: any ad-hoc app with this identifier would match.)
# To sign with a real identity instead:
#   SIGN_ID="Apple Development: Your Name (TEAMID)" scripts/build_dmg.sh
SIGN_ID="${SIGN_ID:--}"
echo "▸ Signing with identity: $SIGN_ID"
if [ "$SIGN_ID" = "-" ]; then
    codesign --force --deep --sign - -r="designated => identifier \"$BUNDLE_ID\"" "$APP"
else
    codesign --force --deep --sign "$SIGN_ID" "$APP"
fi

echo "▸ Creating DMG…"
STAGE="$BUILD/dmg-stage"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/$APP_NAME.dmg" >/dev/null
rm -rf "$STAGE"

echo "✓ $APP"
echo "✓ $BUILD/$APP_NAME.dmg"
