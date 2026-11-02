#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_root"
"$project_root/scripts/prepare-swagger-ui.sh"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/ModuleCache"
package_options=(--cache-path "$project_root/.build/cache" --config-path "$project_root/.build/config" --security-path "$project_root/.build/security" --disable-sandbox)
swift build "${package_options[@]}" -c release "$@"
binary_dir="$(swift build "${package_options[@]}" -c release "$@" --show-bin-path)"
app="$project_root/dist/Bracket.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary_dir/Bracket" "$app/Contents/MacOS/Bracket"
cp Support/Info.plist "$app/Contents/Info.plist"
cp Assets/Bracket.icns "$app/Contents/Resources/AppIcon.icns"
cp Assets/Assets.car "$app/Contents/Resources/Assets.car"
# Remove the previous generated icon after moving to the asset-catalog name.
rm -f "$app/Contents/Resources/Bracket.icns"
# SwiftPM and Xcode use different bundle layouts. Replace this generated copy
# so switching between single-architecture and universal builds cannot retain stale assets.
rm -rf "$app/Contents/Resources/Bracket_Bracket.bundle"
cp -R "$binary_dir/Bracket_Bracket.bundle" "$app/Contents/Resources/"
printf 'APPL????' > "$app/Contents/PkgInfo"
codesign --force --sign - "$app"
touch "$app"
printf '\nBuilt %s\n' "$app"
