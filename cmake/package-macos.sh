#!/bin/bash
set -euo pipefail

# Build a native launcher around an already-built game. Game data stays separate.
root=$(cd "$(dirname "$0")/.." && pwd)
architecture=$(uname -m)
case "$architecture" in
    arm64) dist_arch=arm64 ;;
    x86_64) dist_arch=x64 ;;
    *) echo "Unsupported Mac architecture: $architecture" >&2; exit 1 ;;
esac
engine_dir=${1:-"$root/dist/$dist_arch-macos-rwdi-local"}
deployment=${MACOSX_DEPLOYMENT_TARGET:-15.0}
identity=${CWR_CODESIGN_IDENTITY:--}
bundle_id=io.github.novalis78.poseidon-launcher
output="$root/dist/Poseidon Launcher.app"
mkdir -p "$root/build" "$root/dist"
staging=$(mktemp -d "$root/build/macos-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
bundle="$staging/Poseidon Launcher.app"
resources="$bundle/Contents/Resources"
mkdir -p "$bundle/Contents/MacOS" "$resources/Engine" "$resources/Licenses"

for name in PoseidonGame PoseidonGameDemo libopenal.dylib; do
    if [ ! -f "$engine_dir/$name" ]; then
        echo "Missing $engine_dir/$name. Build the native game targets first." >&2
        exit 1
    fi
    if ! /usr/bin/lipo "$engine_dir/$name" -verify_arch "$architecture" >/dev/null 2>&1; then
        echo "$name does not contain native $architecture code." >&2
        exit 1
    fi
    cp "$engine_dir/$name" "$resources/Engine/$name"
done
if [ -f "$engine_dir/PoseidonTools" ]; then
    cp "$engine_dir/PoseidonTools" "$resources/Engine/"
fi
cp "$root/LICENSE" "$resources/Licenses/Engine-LICENSE.txt"
cp "$root/THIRD_PARTY_NOTICES.md" "$resources/Licenses/THIRD_PARTY_NOTICES.md"
cat > "$resources/Licenses/SOURCE.txt" <<SOURCE
Source: https://github.com/novalis78/CWR-CE/tree/$(git -C "$root" rev-parse HEAD)
Launcher checkout: $(git -C "$root" rev-parse HEAD)
Built on: $(date -u '+%Y-%m-%dT%H:%M:%SZ')
The engine is GPL-3.0-or-later with additional terms; see Engine-LICENSE.txt.
SOURCE
if [ -f "$engine_dir/OpenAL-Soft.LICENSE.txt" ]; then
    cp "$engine_dir/OpenAL-Soft.LICENSE.txt" "$resources/Licenses/"
elif [ -f "$engine_dir/OpenAL-Soft-LGPL.txt" ]; then
    cp "$engine_dir/OpenAL-Soft-LGPL.txt" "$resources/Licenses/"
else
    echo "Missing OpenAL license notice in $engine_dir." >&2
    exit 1
fi
cp "$root/docs/macos-creator-guide.html" "$resources/Creator Guide.html"

xcrun swiftc -O -parse-as-library -target "$architecture-apple-macos$deployment" \
    -framework AppKit -framework SwiftUI \
    "$root/apps/macos/Launcher/LauncherCore.swift" "$root/apps/macos/Launcher/PoseidonLauncher.swift" \
    -o "$bundle/Contents/MacOS/PoseidonLauncher"
xcrun swift "$root/apps/macos/Launcher/MakeIcon.swift" "$staging/AppIcon.iconset"
iconutil -c icns "$staging/AppIcon.iconset" -o "$resources/AppIcon.icns"
cat > "$bundle/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$bundle_id</string>
<key>CFBundleName</key><string>Poseidon Launcher</string>
<key>CFBundleDisplayName</key><string>Poseidon Launcher</string>
<key>CFBundleExecutable</key><string>PoseidonLauncher</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>$deployment</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSMicrophoneUsageDescription</key><string>The game uses the microphone for in-game voice chat when you enable it.</string>
<key>NSHumanReadableCopyright</key><string>Community launcher. Engine credits and license notices are included in Resources/Licenses.</string>
</dict></plist>
PLIST
plutil -lint "$bundle/Contents/Info.plist"
for file in "$resources"/Engine/*; do
    codesign --force --sign "$identity" --timestamp=none "$file"
done
codesign --force --sign "$identity" --timestamp=none "$bundle"
codesign --verify --deep --strict "$bundle"

if [ -e "$output" ]; then
    existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output/Contents/Info.plist" 2>/dev/null || true)
    if [ "$existing_id" != "$bundle_id" ]; then
        echo "Refusing to replace an unrelated app at $output." >&2
        exit 1
    fi
    rm -rf "$output"
fi
mv "$bundle" "$output"
archive="$root/dist/PoseidonLauncher-macos-$dist_arch.zip"
ditto -c -k --keepParent "$output" "$archive"
printf 'App: %s\nArchive: %s\n' "$output" "$archive"
