#!/usr/bin/env bash
# release 빌드 후 "Background Check.app" 번들을 build/에 조립하고 ad-hoc 서명한다.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product BackgroundCheck

APP="build/Background Check.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/BackgroundCheck "$APP/Contents/MacOS/BackgroundCheck"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.memory.backgroundcheck</string>
    <key>CFBundleName</key><string>Background Check</string>
    <key>CFBundleDisplayName</key><string>Background Check</string>
    <key>CFBundleExecutable</key><string>BackgroundCheck</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "$APP"
