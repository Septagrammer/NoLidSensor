#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$PWD/dist/NoLidSensor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"
cp .build/release/NoLidSensor "$APP/Contents/MacOS/NoLidSensor"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.pavlo.DarkSleep</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleName</key><string>NoLidSensor</string>
<key>CFBundleExecutable</key><string>NoLidSensor</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSCameraUsageDescription</key><string>Briefly check light after inactivity to put your Mac to sleep. Frames are not saved.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr "$APP"
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
printf '%s\n' "$APP"
