#!/bin/bash
# prepare: local preview. xcode: notarized ZIP via Xcode account. notarize: DMG via notarytool.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="${1:-prepare}"
case "$MODE" in prepare|xcode|notarize) ;; *) echo 'Usage: bash scripts/package-beta.sh [prepare|xcode|notarize]' >&2; exit 1 ;; esac
[[ "$(uname -m)" == arm64 ]] || { echo 'This beta is currently validated on Apple Silicon only.' >&2; exit 1; }
if [[ "$MODE" != prepare ]]; then
  case "${LITTLE_EARTH_SIGNING_IDENTITY:-}" in
    "Developer ID Application: "*) ;;
    *) echo 'Set LITTLE_EARTH_SIGNING_IDENTITY to the full Developer ID Application certificate name.' >&2; exit 1 ;;
  esac
  if [[ "$MODE" == notarize ]]; then
    : "${LITTLE_EARTH_NOTARY_PROFILE:?Set the name of an existing notarytool Keychain profile, not a password.}"
    # Validate credentials before building; never export or print the stored secret.
    xcrun notarytool history --keychain-profile "$LITTLE_EARTH_NOTARY_PROFILE" --output-format json >/dev/null
  fi
else
  export LITTLE_EARTH_SIGNING_IDENTITY=-
fi
# Keep signed bundles out of the cloud-backed project directory: sync software
# can add FinderInfo after signing and invalidate the distributable.
RELEASE_ROOT="${LITTLE_EARTH_RELEASE_ROOT:-$HOME/Downloads/LittleEarth-Betas}"
mkdir -p "$RELEASE_ROOT"
RELEASE_ROOT=$(cd "$RELEASE_ROOT" && pwd -P)
RELEASE_DIR=$(mktemp -d "$RELEASE_ROOT/beta-$MODE.XXXXXX")
PAYLOAD="$RELEASE_DIR/payload"
mkdir -p "$PAYLOAD"
printf '%s\n' 'NOT READY TO DISTRIBUTE: local preparation or notarization is incomplete.' > "$RELEASE_DIR/NOT-READY-TO-DISTRIBUTE.txt"
LITTLE_EARTH_OUTPUT="$PAYLOAD/Little Earth.app" bash scripts/build-app.sh > "$RELEASE_DIR/build.log" 2>&1
APP="$PAYLOAD/Little Earth.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")
[[ "$(lipo -archs "$APP/Contents/MacOS/LittleEarth")" == arm64 ]] || { echo 'Unexpected architecture in beta.' >&2; exit 1; }
cp docs/beta/START-HERE.txt docs/beta/PRIVACY.txt THIRD_PARTY_NOTICES.md "$PAYLOAD/"
ln -s /Applications "$PAYLOAD/Applications"
if [[ "$MODE" == prepare ]]; then
  printf 'Local preview only (not notarized): %s\n' "$RELEASE_DIR"
  exit 0
fi
# The preview branch above cannot upload anything or produce a ready marker.
codesign --verify --deep --strict "$APP"
codesign -dv --verbose=4 "$APP" 2> "$RELEASE_DIR/signature.txt"
grep -q '^Authority=Developer ID Application:' "$RELEASE_DIR/signature.txt"
grep -q 'flags=.*runtime' "$RELEASE_DIR/signature.txt"
if [[ "$MODE" == xcode ]]; then
  python3 scripts/make-xcode-archive.py "$APP" "$RELEASE_DIR"
  xcodebuild -exportArchive -archivePath "$RELEASE_DIR/Little Earth.xcarchive" \
    -exportOptionsPlist "$RELEASE_DIR/ExportOptions.plist" -exportPath "$RELEASE_DIR/notarized" \
    -allowProvisioningUpdates > "$RELEASE_DIR/xcode-upload.log" 2>&1
  # Upload success is not acceptance. If Apple is still processing, this fails
  # closed; resume this export for the same archive instead of uploading again.
  xcodebuild -exportNotarizedApp -archivePath "$RELEASE_DIR/Little Earth.xcarchive" \
    -exportPath "$RELEASE_DIR/notarized" > "$RELEASE_DIR/xcode-export.log" 2>&1
  FINAL_NAME="Little-Earth-$VERSION-beta-$BUILD-apple-silicon"
  FINAL="$RELEASE_DIR/$FINAL_NAME"
  mkdir "$FINAL"
  ditto --norsrc "$RELEASE_DIR/notarized/Little Earth.app" "$FINAL/Little Earth.app"
  cp docs/beta/START-HERE.txt docs/beta/PRIVACY.txt THIRD_PARTY_NOTICES.md "$FINAL/"
  ditto -c -k --sequesterRsrc --keepParent "$FINAL" "$RELEASE_DIR/$FINAL_NAME.zip"
  mkdir "$RELEASE_DIR/verification"
  ditto -x -k "$RELEASE_DIR/$FINAL_NAME.zip" "$RELEASE_DIR/verification"
  VERIFIED_APP="$RELEASE_DIR/verification/$FINAL_NAME/Little Earth.app"
  xcrun stapler validate "$VERIFIED_APP"
  codesign --verify --deep --strict "$VERIFIED_APP"
  spctl --assess --type execute --verbose=2 "$VERIFIED_APP"
  shasum -a 256 "$RELEASE_DIR/$FINAL_NAME.zip" > "$RELEASE_DIR/SHA256SUMS.txt"
  rm "$RELEASE_DIR/NOT-READY-TO-DISTRIBUTE.txt"
  printf '%s\n' 'ZIP extraction passed signing, ticket and Gatekeeper checks. Separate-Mac runtime acceptance remains outstanding.' > "$RELEASE_DIR/PACKAGING-VERIFIED.txt"
  printf 'Notarized beta ZIP: %s\n' "$RELEASE_DIR/$FINAL_NAME.zip"
  exit 0
fi
ditto -c -k --keepParent "$APP" "$RELEASE_DIR/notary-app.zip"
notarize() {
  local archive="$1" receipt="$2"
  xcrun notarytool submit "$archive" --keychain-profile "$LITTLE_EARTH_NOTARY_PROFILE" \
    --wait --timeout 10m --output-format json > "$receipt"
  [[ "$(plutil -extract status raw -o - "$receipt")" == Accepted ]] || {
    echo "Notarization not accepted. Inspect $receipt; do not distribute this candidate." >&2; exit 1;
  }
}
notarize "$RELEASE_DIR/notary-app.zip" "$RELEASE_DIR/notary-app.json"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=2 "$APP"
DMG="$RELEASE_DIR/Little-Earth-$VERSION-beta-$BUILD-apple-silicon.dmg"
hdiutil create -volname 'Little Earth Beta' -srcfolder "$PAYLOAD" -format UDZO "$DMG"
codesign --timestamp --sign "$LITTLE_EARTH_SIGNING_IDENTITY" "$DMG"
notarize "$DMG" "$RELEASE_DIR/notary-dmg.json"
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
codesign --verify --strict "$DMG"
hdiutil verify "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
shasum -a 256 "$DMG" > "$RELEASE_DIR/SHA256SUMS.txt"
rm "$RELEASE_DIR/NOT-READY-TO-DISTRIBUTE.txt"
printf '%s\n' 'Signing and notarization passed. Clean-Mac acceptance and owner review are still required before sharing.' > "$RELEASE_DIR/PACKAGING-VERIFIED.txt"
printf 'Notarized beta candidate: %s\n' "$DMG"
