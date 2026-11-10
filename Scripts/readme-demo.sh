#!/bin/bash
# Render the app's main flows using sample data, then encode README media.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export TEST_RUNNER_NOTCHAGENT_SLOW_DEMO=1
export TEST_RUNNER_NOTCHAGENT_README_DIR="$scratch"
export TEST_RUNNER_NOTCHAGENT_SUPPORT_DIR="$scratch/support"
build_dir="${NOTCHAGENT_BUILD_DIR:-/private/tmp/NotchAgent-build-$UID}"
xcodebuild -quiet -project "$project_dir/NotchAgent.xcodeproj" -scheme NotchAgent \
  -configuration Debug -derivedDataPath "$build_dir/DerivedData" \
  -destination 'platform=macOS,arch=arm64' CODE_SIGN_IDENTITY=- \
  -only-testing:NotchAgentTests/ReadmeImagesTests/testRenderDemos test
mkdir -p "$project_dir/docs/images/demos"
for name in agent-hover dashboard workspace completion option-hide settings; do
  ffmpeg -hide_banner -loglevel error -y -framerate 120 -i "$scratch/$name/%03d.png" \
    -vf 'scale=1280:-2:flags=lanczos' -c:v libx264 -crf 19 -pix_fmt yuv420p -movflags +faststart \
    "$project_dir/docs/images/demos/$name.mp4"
done
ffmpeg -hide_banner -loglevel error -y -framerate 120 -i "$scratch/agent-hover/%03d.png" \
  -filter_complex 'fps=50,scale=960:-1:flags=lanczos,split[a][b];[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle' \
  -loop 0 "$project_dir/docs/images/hover-demo.gif"
