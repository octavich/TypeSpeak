#!/bin/bash
# Build TypeSpeak.app — a double-clickable, tray-only macOS bundle.
set -euo pipefail

APP="TypeSpeak"
BIN="TypeSpeak"           # SPM product name
BUNDLE="$APP.app"
CONTENTS="$BUNDLE/Contents"

echo "▶ Building release…"
swift build -c release

echo "▶ Assembling $BUNDLE…"
rm -rf "$BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp ".build/release/$BIN" "$CONTENTS/MacOS/$BIN"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP</string>
    <key>CFBundleDisplayName</key>     <string>$APP</string>
    <key>CFBundleExecutable</key>      <string>$BIN</string>
    <key>CFBundleIdentifier</key>      <string>com.octavich.typespeak</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <!-- Tray-only: no Dock icon, no menu bar app menu. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS lets it run locally.
codesign --force --deep --sign - "$BUNDLE" 2>/dev/null || true

echo "✅ Done: $BUNDLE"
echo "   Move it to /Applications and double-click. Hotkey: ⌥Space."
