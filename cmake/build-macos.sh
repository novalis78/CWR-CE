#!/usr/bin/env bash
# Native macOS build using Xcode's tools and a project-local vcpkg checkout.
set -euo pipefail

if [[ "${1:-}" == "--help" ]]; then
    cat <<'HELP'
Usage: bash cmake/build-macos.sh [CMake target ...]

Defaults to PoseidonGame and PoseidonGameDemo. Requires Xcode command-line
tools, CMake >= 3.25, Git, and internet access for the first build.

Downloads vcpkg into build/tools/vcpkg, pinned to vcpkg.json's baseline.
Uses Apple's make; neither Ninja nor ccache needs a system installation.
Dependencies may download their own build tools through vcpkg.

Optional environment variables:
  CWR_BUILD_JOBS   Concurrent compile jobs (default: 4).
  VCPKG_ROOT      Use an existing bootstrapped vcpkg installation instead.
  MACOSX_DEPLOYMENT_TARGET  Minimum supported macOS version (default: 15.0).

The executables still need separately obtained game data to run.
HELP
    exit 0
fi

fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail 'This script requires macOS.'
case "$(uname -m)" in
    arm64) cwr_arch=arm64 ;;
    x86_64) cwr_arch=x64 ;;
    *) fail 'Unsupported Mac architecture.' ;;
esac

for cwr_tool in cmake git xcrun make; do
    command -v "$cwr_tool" >/dev/null || fail "Missing prerequisite: $cwr_tool"
done
cwr_cc="$(xcrun --find clang)"
cwr_cxx="$(xcrun --find clang++)"
cwr_format="$(xcrun --find clang-format)"
cwr_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$cwr_root"

cwr_jobs="${CWR_BUILD_JOBS:-4}"
[[ "$cwr_jobs" =~ ^[1-9][0-9]*$ ]] || fail 'CWR_BUILD_JOBS must be a positive integer.'
export VCPKG_MAX_CONCURRENCY="$cwr_jobs"
export VCPKG_DISABLE_METRICS=1
# Allow builds on a newer Mac to run on this project's macOS 15 machine.
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"
export OFPR_BUILD_VERSION_TAG="${OFPR_BUILD_VERSION_TAG:-macos-ce-local}"

# Keep downloads and binary caches with the ignored build output.
mkdir -p "$cwr_root/build/tools/downloads" "$cwr_root/build/vcpkg-cache" "$cwr_root/build/cache"
export VCPKG_DOWNLOADS="$cwr_root/build/tools/downloads"
export VCPKG_DEFAULT_BINARY_CACHE="$cwr_root/build/vcpkg-cache"
export XDG_CACHE_HOME="$cwr_root/build/cache"

if [[ -z "${VCPKG_ROOT:-}" ]]; then
    export VCPKG_ROOT="$cwr_root/build/tools/vcpkg"
    cwr_baseline="$(sed -n 's/.*"builtin-baseline": *"\([0-9a-f]*\)".*/\1/p' vcpkg.json)"
    [[ "$cwr_baseline" =~ ^[0-9a-f]{40}$ ]] || fail 'Cannot read vcpkg baseline.'
    if [[ ! -d "$VCPKG_ROOT/.git" ]]; then
        git clone https://github.com/microsoft/vcpkg.git "$VCPKG_ROOT"
    fi
    git -C "$VCPKG_ROOT" checkout --detach "$cwr_baseline"
    "$VCPKG_ROOT/bootstrap-vcpkg.sh" -disableMetrics
fi
[[ -f "$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" && -x "$VCPKG_ROOT/vcpkg" ]] ||
    fail 'VCPKG_ROOT must point to a bootstrapped vcpkg installation.'

cwr_preset="macos-${cwr_arch}-clang-rwdi"
cwr_build="$cwr_root/build/${cwr_preset}-local"
cmake --preset "$cwr_preset" -B "$cwr_build" -G 'Unix Makefiles' \
    -DCMAKE_MAKE_PROGRAM=/usr/bin/make \
    -DCMAKE_C_COMPILER="$cwr_cc" \
    -DCMAKE_CXX_COMPILER="$cwr_cxx" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET" \
    -DCMAKE_C_COMPILER_LAUNCHER= \
    -DCMAKE_CXX_COMPILER_LAUNCHER= \
    -DCLANG_FORMAT_EXE="$cwr_format" \
    -DVCPKG_INSTALL_OPTIONS=--clean-after-build

if [[ "$#" -eq 0 ]]; then
    set -- PoseidonGame PoseidonGameDemo
fi
cmake --build "$cwr_build" --parallel "$cwr_jobs" --target "$@"
printf '\nBuild complete. Distribution: %s/dist/%s-macos-rwdi-local\n' "$cwr_root" "$cwr_arch"
