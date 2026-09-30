#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/toolchain.sh
configuration="${CONFIGURATION:-release}"
swift build -c "$configuration"
bin_dir=$(swift build -c "$configuration" --show-bin-path)
app="$PWD/dist/Miho.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/Miho" "$app/Contents/MacOS/Miho.new"
mv "$app/Contents/MacOS/Miho.new" "$app/Contents/MacOS/Miho"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Miho</string>
<key>CFBundleDisplayName</key><string>Miho 迷糊</string>
<key>CFBundleIdentifier</key><string>app.miho.desktop</string>
<key>CFBundleExecutable</key><string>Miho</string>
<key>CFBundleIconFile</key><string>Miho</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.2.1</string>
<key>CFBundleVersion</key><string>3</string>
<key>LSMinimumSystemVersion</key><string>14.2</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSAudioCaptureUsageDescription</key><string>Miho 需要分析电脑播放的声音，才能跟随节奏跳舞。声音仅在本机实时处理，不保存、不上传，也不使用麦克风。</string>
</dict></plist>
PLIST
"$app/Contents/MacOS/Miho" --export-artifacts "$PWD/dist/artwork"
iconutil -c icns "$PWD/dist/artwork/Miho.iconset" -o "$app/Contents/Resources/Miho.icns"
# Ad-hoc signing supports local use. Distribution requires a Developer ID.
codesign --force --sign - --identifier app.miho.desktop "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
