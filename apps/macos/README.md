# Native Mac launcher

The SwiftUI launcher wraps the native game binaries in a relocatable app. It
detects compatible Remastered data, defaults to borderless fullscreen, remembers
mod folders, opens P3D files in the engine viewer, and keeps a separate log for every game session. It does not bundle
or download game data.

```sh
bash cmake/build-macos.sh PoseidonGame PoseidonGameDemo PoseidonTools PoseidonFormatsDLL
bash cmake/package-macos.sh
```

Outputs: `dist/Poseidon Launcher.app` and an architecture-specific ZIP. Pass an
existing engine directory as the first argument to `package-macos.sh` to reuse a
build. The minimum macOS version defaults to 15.0. The app is ad-hoc signed by
default; `CWR_CODESIGN_IDENTITY` can select an installed signing identity. The
script does not notarize or publish a release.

The bundled [creator guide](../../docs/macos-creator-guide.html) explains playing,
trackpad input, Blender import, and the native asset utilities.

## Validation

```sh
mkdir -p build/macos-launcher
xcrun swiftc -parse-as-library apps/macos/Launcher/LauncherCore.swift \
  apps/macos/Launcher/tests/LauncherCoreTests.swift -o build/macos-launcher/core-tests
build/macos-launcher/core-tests
"dist/Poseidon Launcher.app/Contents/MacOS/PoseidonLauncher" --check-data /path/to/Demo
codesign --verify --deep --strict "dist/Poseidon Launcher.app"
```

Run these commands from the repository root.

The core tests exercise nested/case-insensitive data discovery, paths with
spaces and quotes, fullscreen arguments, executable validation, and invalid
mod paths. GUI verification should also launch a game and check that the
launcher returns after it exits.
