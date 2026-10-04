#!/bin/sh
# Builds a universal (Apple Silicon + Intel) release, wraps it in
# "Yellow Plugin Manager.app" and zips it for distribution in dist/.
# Needs only the Xcode Command Line Tools.
set -e
cd "$(dirname "$0")"

VERSION="0.1.0"
NAME="Yellow Plugin Manager"
APP="build/$NAME.app"

# Each architecture gets its own scratch folder; sharing one confuses SwiftPM.
ARM="--triple arm64-apple-macosx14.0 --scratch-path .build/arm64"
X86="--triple x86_64-apple-macosx14.0 --scratch-path .build/x86_64"
swift build -c release $ARM
swift build -c release $X86

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create \
  "$(swift build -c release $ARM --show-bin-path)/YellowPluginManager" \
  "$(swift build -c release $X86 --show-bin-path)/YellowPluginManager" \
  -output "$APP/Contents/MacOS/YellowPluginManager"

# The icon is drawn by a script, so the repository holds no binary files.
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleDisplayName</key><string>$NAME</string>
  <key>CFBundleIdentifier</key><string>io.github.vladimirslavicek.yellowpluginmanager</string>
  <key>CFBundleExecutable</key><string>YellowPluginManager</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature: required for Apple Silicon to run the binary at all.
# This is not a Developer ID signature; Gatekeeper still asks on first launch.
codesign --force --sign - "$APP"

mkdir -p dist
ZIP="dist/YellowPluginManager-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built: $APP"
echo "Zipped: $ZIP"
