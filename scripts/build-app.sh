#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
SIGNING_IDENTITY="${LITTLE_EARTH_SIGNING_IDENTITY:--}"
case "$SIGNING_IDENTITY" in
  -|"Developer ID Application: "*) ;;
  *) echo 'Use a Developer ID Application identity for distribution, or - for local preview.' >&2; exit 1 ;;
esac
if [[ ! -f Sources/LittleEarth/Resources/earth-felt.png ]]; then
  swift Tools/GenerateTextures.swift Assets/land.geojson Sources/LittleEarth/Resources
fi
if [[ ! -f Sources/LittleEarth/Resources/wool-world-mask.png || ! -f Sources/LittleEarth/Resources/wool-world-normal.png || Sources/LittleEarth/Resources/wool-world.png -nt Sources/LittleEarth/Resources/wool-world-mask.png || Tools/GenerateWoolRelief.swift -nt Sources/LittleEarth/Resources/wool-world-mask.png ]]; then
  swift Tools/GenerateWoolRelief.swift Sources/LittleEarth/Resources
fi
if [[ ! -f Sources/LittleEarth/Resources/wool-world-v3-normal.png || Sources/LittleEarth/Resources/wool-world-v3.png -nt Sources/LittleEarth/Resources/wool-world-v3-normal.png || Tools/GenerateWoolRelief.swift -nt Sources/LittleEarth/Resources/wool-world-v3-normal.png ]]; then
  swift Tools/GenerateWoolRelief.swift Sources/LittleEarth/Resources wool-world-v3
fi
if [[ ! -f Sources/LittleEarth/Resources/cloud-felt-normal.png || Sources/LittleEarth/Resources/cloud-felt.png -nt Sources/LittleEarth/Resources/cloud-felt-normal.png || Tools/GenerateWoolRelief.swift -nt Sources/LittleEarth/Resources/cloud-felt-normal.png ]]; then
  swift Tools/GenerateWoolRelief.swift Sources/LittleEarth/Resources cloud-felt
fi
swift build -c release --disable-sandbox
DESTINATION="${LITTLE_EARTH_OUTPUT:-$HOME/Applications/Little Earth.app}"
if [[ -e "$DESTINATION" ]]; then
  EXISTING_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist" 2>/dev/null || true)
  [[ "$EXISTING_ID" == "com.littleearth.companion" ]] || { echo "Refusing to overwrite unrelated app: $DESTINATION" >&2; exit 1; }
fi
STAGING_DIR=$(mktemp -d "${TMPDIR:-/tmp}/little-earth-package.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
APP="$STAGING_DIR/Little Earth.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/LittleEarth "$APP/Contents/MacOS/LittleEarth"
cp -R .build/release/LittleEarth_LittleEarth.bundle "$APP/Contents/Resources/"
cp -R .build/release/LittleEarth_EarthCore.bundle "$APP/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.littleearth.companion</string>
<key>CFBundleExecutable</key><string>LittleEarth</string>
<key>CFBundleName</key><string>Little Earth</string>
<key>CFBundleDisplayName</key><string>Little Earth</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>zh-Hans</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.8.4</string>
<key>CFBundleVersion</key><string>21</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Finder/cloud storage can attach FinderInfo to generated bundle directories.
# Remove that packaging metadata only; do not alter quarantine/security attributes.
xattr -r -d com.apple.FinderInfo "$APP" 2>/dev/null || true
if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --timestamp --options runtime --sign "$SIGNING_IDENTITY" "$APP"
fi
codesign --verify --deep --strict "$APP"
mkdir -p "$(dirname "$DESTINATION")"
ditto --norsrc "$APP" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
printf '%s\n' "$DESTINATION"
