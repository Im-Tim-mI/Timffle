<p align="center"><img src="timffle/branding/timffle-logo.svg" alt="Timffle" width="480"></p>

# Timffle

> **Timffle is an unofficial fork of [Ruffle](https://ruffle.rs/)** focused on keeping the Taomee Taiwan Flash games — **摩爾莊園, 賽爾號, 小花仙 and 彈彈堂** — playable in Chrome.
> It is a patched Ruffle Flash emulator plus a connection helper that is installed once.

[中文](README.md) | version `0.8.0.26296` (based on Ruffle nightly 2026-10-13) | licence MIT OR Apache-2.0, at your option (the same as Ruffle)

> [!IMPORTANT]
> **Timffle is not affiliated with, endorsed by or sponsored by the Ruffle project or Ruffle LLC.** Almost all of the Flash emulation is the work of Ruffle and its [hundreds of contributors](https://github.com/ruffle-rs/ruffle/graphs/contributors); this repository keeps Ruffle's complete git history, authorship and licence files.
> **Please report Timffle problems to [Timffle's issues](https://github.com/Im-Tim-mI/Timffle/issues), never to Ruffle.** The name and logo "Ruffle" belong to the Ruffle project, so this fork uses its own name and artwork (see [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)). Ruffle's original README is kept as [`README.ruffle.md`](README.ruffle.md).

## What it is for

Flash reached end of life in 2020 and Chrome removed it. The games above are ActionScript 3 browser games that **talk to their servers over TCP sockets**. Two things stop them in today's Chrome:

1. Ruffle does not yet support everything they need (LocalConnection, URLStream, `Loader`/`URLLoader` cancellation, 3D perspective, `Matrix3D`, …).
2. Chrome extensions cannot open TCP connections, so the official Ruffle extension cannot reach these servers.

Timffle fixes both: Flash compatibility fixes on top of Ruffle (verified line by line against Adobe Flash Player 32 with the differential tests in [`timffle/difftest/`](timffle/difftest/)), and a Chrome extension + Native Messaging helper that lets `flash.net.Socket` reach TCP servers under strict rules (per-site allow list, public internet addresses only, no listening ports, nothing left running).

## Status

| Game | URL | Status |
|---|---|---|
| 摩爾莊園 | https://mole.61.com.tw/ | **Verified with a real account on Linux + Chrome 155** (as ruffle-mole-chrome 0.8.0.26294): login, the 3D saved-account page, entering the world, walking, changing maps, kart seats. |
| 賽爾號 | http://seer.61.com.tw/ | Sockets allowed by default; **gameplay not tested**. |
| 小花仙 | http://hua.61.com.tw/ | Sockets allowed by default; **gameplay not tested**. |
| 彈彈堂 | http://ddt.61.com.tw/main_index.php | Sockets allowed by default; **gameplay not tested**. |

Linux x64 is tested on real hardware; Windows only under Wine; macOS, Windows ARM64 and Linux ARM64 are cross-compiled only. The helper is not signed or notarized.

## Install

1. Download `timffle-chrome-<version>.zip` from [Releases](https://github.com/Im-Tim-mI/Timffle/releases) and check it against `timffle-<build>-SHA256SUMS.txt`. Unzipping gives `timffle/` with `extension/`, `helper/`, `LICENSES/`, `NOTICE.md` and `README.txt`. Keep the folder in a fixed place.
2. Install the helper once: Windows `helper\install-windows.cmd`, macOS `helper/install-macos.command`, Linux `sh helper/install-linux.sh`. It is a per-user install (HKCU registry or the user's `NativeMessagingHosts` folder); no services, no autostart, no admin rights.
3. In `chrome://extensions` turn on Developer mode, click **Load unpacked** and pick the `extension` folder. Disable the official Ruffle extension or an older ruffle-mole-chrome build first.
4. The extension's options page, section "Socket 連線", should show the helper as installed (version 1.2.0). If not, run the installer again and fully restart Chrome.
5. Open the game site and play.

**Coming from ruffle-mole-chrome:** the helper was renamed (`timffle-socket-helper`, native host `timffle_socket_helper`, folder `TimffleSocketHelper`), so it does not replace the old `ruffle-socket-helper`. Remove the old helper with the uninstaller from the *old* ZIP, remove the old extension, then install Timffle. The extension ID is unchanged (`eandddnbchclalbjkhfelhjhpijifcog`).

**Uninstall:** run `helper/uninstall-*` (removes only what the installer created), then remove the extension.

## How it works

```
game page → Timffle (WebAssembly: Ruffle core + fixes) → flash.net.Socket
  → Chrome extension (page bridge → content script → service worker; allow-listed sites only)
  → timffle-socket-helper (Go, started by Chrome per socket, exits afterwards; public addresses only)
  → game server (TCP)
```

Details: [`timffle/docs/ARCHITECTURE.md`](timffle/docs/ARCHITECTURE.md), [`timffle/docs/PROTOCOL.md`](timffle/docs/PROTOCOL.md).

## Differences from Ruffle

Base: Ruffle `nightly-2026-10-13` (commit [`46fec3f`](https://github.com/ruffle-rs/ruffle/commit/46fec3f1b2e625fae7035bb3b00d6d5c0ec0d413)). Every change after it is a separate commit: the extension socket bridge and settings; web socket backend and canvas generic fonts; AVM2 networking, LocalConnection, URLStream and loader fixes; 3D transforms, `Matrix3D` and perspective projection; rust-flash-lso as a subtree (with its history) plus an AMF3 encoder fix; and the rebrand of the user-visible web UI. Details: [`timffle/docs/CHANGES-FROM-RUFFLE.md`](timffle/docs/CHANGES-FROM-RUFFLE.md). The list of modified Ruffle files (the Apache-2.0 §4(b) notice): [`timffle/MODIFIED-FILES.md`](timffle/MODIFIED-FILES.md). Full diff: `git diff 46fec3f -- . ':!timffle'`.

## Build from source

Needs git, Rust 1.99 with `wasm32-unknown-unknown`, wasm-bindgen CLI 0.2.127 (must equal `Cargo.lock`), binaryen (`wasm-opt`), Node.js 24 + npm, Go 1.27 and Python 3. Everything is in this repository (including the patched flash-lso); nothing else has to be fetched:

```sh
git clone https://github.com/Im-Tim-mI/Timffle.git && cd Timffle
VERSION4=0.8.0.26296 timffle/scripts/build-extension.sh   # wasm + extension → web/packages/extension/dist/ruffle_extension.zip
VERSION4=0.8.0.26296 timffle/scripts/package-release.sh   # helper for 7 platforms + release ZIP with licences → timffle/build/out/
```

See [`timffle/docs/BUILD.md`](timffle/docs/BUILD.md). The other parts of Ruffle (desktop app etc.) build as upstream does, but **only the web UI is rebranded so far**: do not distribute builds of the other parts under the Timffle name before they are renamed ([`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)).

## Tests

Differential tests against real Flash (30 goldens, [`timffle/difftest/`](timffle/difftest/)); helper unit tests (`timffle/helper`, `go test ./...`); package tests (`timffle/helper/installer-tests/`); extension unit tests (`web/packages/extension/tests/`); the rebrand check (`python3 timffle/scripts/rebrand.py --check`); browser + helper integration tests ([`timffle/tools/native-regress/`](timffle/tools/native-regress/)); Ruffle's own regression suite (`cargo test -p tests --test tests`). How to run them: [`timffle/docs/TESTING.md`](timffle/docs/TESTING.md). What was actually run for each version: [`timffle/CHANGELOG.md`](timffle/CHANGELOG.md).

## Following upstream Ruffle

```sh
git remote add upstream https://github.com/ruffle-rs/ruffle.git
git fetch upstream tag nightly-YYYY-MM-DD --no-tags
git merge nightly-YYYY-MM-DD                 # merge, never rebase published history
python3 timffle/scripts/rebrand.py           # re-apply the name to new/translated upstream strings
python3 timffle/scripts/rebrand.py --check
timffle/scripts/list-modified-files.sh > timffle/MODIFIED-FILES.md
```

See [`timffle/docs/UPSTREAM.md`](timffle/docs/UPSTREAM.md).

## Licence, credits and notices

- **Ruffle**: Copyright (c) 2018-2022 Ruffle LLC and Ruffle contributors, MIT OR Apache-2.0; full texts and the third-party dependency list in [`LICENSE.md`](LICENSE.md), kept verbatim. Ruffle's contributors are preserved in this repository's git history (`git shortlog -sn 46fec3f`).
- **rust-flash-lso**: Copyright (c) 2020 Callum Thomson, MIT ([`vendor/rust-flash-lso/LICENSE`](vendor/rust-flash-lso/LICENSE)).
- **Timffle's modifications and original parts**: Copyright (c) 2026 Im-Tim-mI and Timffle contributors, **MIT OR Apache-2.0 at your option** ([`timffle/LICENSE-MIT`](timffle/LICENSE-MIT), [`timffle/LICENSE-APACHE`](timffle/LICENSE-APACHE)).
- Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in Timffle by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
- **Trademarks**: "Ruffle" and its logo belong to the Ruffle project and are used here only descriptively ("a fork of Ruffle", "based on Ruffle"). Game names, "Taomee", "Flash", "Adobe", "Chrome" etc. belong to their owners.
- **No game assets** are included (no game SWF/DLL/images, game code, server addresses, packet formats or cryptography), and game files are not modified. Use your own account and respect the games' terms of service. Full notice: [`NOTICE.md`](NOTICE.md). Where each behaviour comes from and how it was verified: [`timffle/docs/PROVENANCE.md`](timffle/docs/PROVENANCE.md) (Traditional Chinese with an English summary).
