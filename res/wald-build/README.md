# res/wald-build — Waldlust release build scripts

These are the scripts that produce the official Waldlust Remote binaries (decisions D33–D35, 2026-10-14).
They are part of the Corresponding Source of every release under the GNU AGPL-3.0 (§1: "scripts to control
those activities"). The working copies live in the private docs repository (`wald-remote-docs/wald-build`);
a snapshot is committed here for each release tag (this snapshot: docs commit 89cc7e9).

| Script | Output |
|---|---|
| `build-macos-local.sh <tag> bidirectional release` | macOS (Apple Silicon) .dmg — ad-hoc signed, not notarized |
| `build-android-local.sh <tag> incoming release` | Android universal APK (arm64-v8a, armeabi-v7a) — release key |
| `build-windows-local.ps1 -Ref <tag> -Variant <bidirectional\|incoming> -Target release -Inno` | Windows x64 Inno installer — unsigned |
| `build-windows-sciter.ps1 -Ref <tag> -Variant incoming -Target release -Inno` | Windows 32-bit (Sciter UI) Inno installer — unsigned |
| `collect-notices.py` (+ `about.toml`, `about.hbs`, `notices-extra.txt`) | THIRD_PARTY_NOTICES-<platform>.txt |

Installer file names: `waldlust-remote[-incoming]-<version>-<os>[-<arch>].<ext>` (e.g. `waldlust-remote-1.5.0-macos-arm64.dmg`,
`waldlust-remote-incoming-1.5.0-windows-x86.exe`). A release tag's version must equal the source version (Cargo.toml, pubspec.yaml).

Each script header lists the toolchain it expects (Rust, Flutter, vcpkg commit, NDK, LLVM, Inno Setup).
The submodule `libs/hbb_common` is pinned at 76cc24163a3dc42d61f8f3104e7d93dcf7b0ae11 (https://github.com/stevewoochoi/hbb_common).

## Values injected at build time

| Variable | Release value |
|---|---|
| `WALDLUST_HEARTBEAT_URL` | `https://remote.waldpay.co.kr/api/heartbeat` |
| `WALDLUST_API_SERVER` | `https://remote.waldpay.co.kr/rd` |
| `WALDLUST_VARIANT` | `incoming` for incoming-only builds, unset for bidirectional |
| `WALDLUST_INCOMING_PW_STORAGE`, `WALDLUST_INCOMING_PW_SALT` | hash of the common incoming-only password (made by `res/wald-variant/preset_hash.py`; the password itself is a deployment secret and is not published) |
| `WALDLUST_PRESET_PASSWORD` | unset (unmanaged builds) |
| Android `--build-number` | computed from the tag `wald-v<M>.<m>.<p>-r<N>`: M×1,000,000 + m×10,000 + p×100 + N (e.g. `wald-v1.5.0-r1` → 1050001) |

The Android release signing key and its password are not part of the source (they are kept by Waldlust Co., Ltd.).
