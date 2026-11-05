#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
export NOTCHAGENT_BUILD_DIR="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
bash "$project_dir/Scripts/build.sh"
app="$NOTCHAGENT_BUILD_DIR/DerivedData/Build/Products/Release/NotchAgent.app"
codesign --verify --deep --strict "$app"
mkdir -p "$project_dir/Dist"
version="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")"
archive="$project_dir/Dist/Agents_on_Island-$version-macOS.zip"
if [ -e "$archive" ]; then
  printf '%s already exists. Move it aside before packaging a new build.\n' "$archive" >&2
  exit 1
fi
# Keep the existing Xcode target and executable for compatibility, but ship the new app name.
package_dir="$(mktemp -d "${TMPDIR:-/tmp}/aoi-package.XXXXXX")"
trap 'rm -rf "$package_dir"' EXIT
ditto --norsrc --noextattr "$app" "$package_dir/Agents on Island.app"
ditto -c -k --norsrc --noextattr --keepParent "$package_dir/Agents on Island.app" "$archive"
# Record the file name only, so `shasum -c` works wherever the download lands.
(cd "$(dirname "$archive")" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
printf '\nPackaged %s (local ad-hoc signature, not notarized).\n' "$archive"
