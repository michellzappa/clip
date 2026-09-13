#!/bin/zsh
# Build Clip.app and install it to /Applications, signed with the stable
# Apple Development identity from project.yml (so the Accessibility grant
# survives rebuilds). Regenerates the Xcode project and the icon every time.
#
#   ./scripts/build-app.sh            # Release → /Applications/Clip.app
#   ./scripts/build-app.sh --debug
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
housekit="${HOUSEKIT_PATH:-$here/../housekit}"
config=Release
[[ "${1:-}" == "--debug" ]] && config=Debug

swift build -c release --package-path "$housekit" >/dev/null
"$(swift build -c release --package-path "$housekit" --show-bin-path)/housekit-icon" clip "$here/Clip/Resources/AppIcon.icns" >/dev/null

cd "$here"
xcodegen generate --quiet
build="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
xcodebuild -project Clip.xcodeproj -scheme Clip -configuration "$config" \
  -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="build/DerivedData/Build/Products/$config/Clip.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$app/Contents/Info.plist"
codesign --force --sign "Apple Development" --entitlements Clip/Resources/Clip.entitlements --options runtime "$app"

target=/Applications/Clip.app
if pgrep -xq Clip; then osascript -e 'tell application "Clip" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
codesign --verify --strict "$target"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
printf '%s (version %s, build %s)\n' "$target" "$version" "$build"
