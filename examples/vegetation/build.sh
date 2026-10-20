#!/bin/bash
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
output=${1:-"$root/build/grass-study"}
blender=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
tools=${POSEIDON_TOOLS:-"$root/dist/arm64-macos-rwdi-local/PoseidonTools"}
"$blender" --background --factory-startup --python-exit-code 1 \
    --python "$root/examples/vegetation/create_grass.py" -- --output "$output" --render
"$tools" image convert "$output/grass.png" "$output/source/nvl_grass/grass.paa" --format DXT1
"$tools" model inspect "$output/source/nvl_grass/grass.p3d" --all
mkdir -p "$output/@grass-study/AddOns"
"$tools" pbo pack "$output/source/nvl_grass" "$output/@grass-study/AddOns/nvl_grass.pbo"
"$tools" pbo list "$output/@grass-study/AddOns/nvl_grass.pbo"
printf '\nAdd this folder in the launcher: %s/@grass-study\n' "$output"
