<p align="center">
  <img src="timffle/branding/timffle-icon.svg" alt="" width="112" height="112">
</p>

<h1 align="center">
  <img src="timffle/branding/timffle-logo.svg" alt="Timffle" width="420">
</h1>

<p align="center"><b>Keep the Taomee Taiwan Flash games playable in Chrome.</b></p>

<p align="center">摩爾莊園 ・ 賽爾號 ・ 小花仙 ・ 彈彈堂</p>

<p align="center">
  <a href="https://github.com/Im-Tim-mI/Timffle/releases/latest"><b>Download the latest release</b></a> ・
  <a href="#install">Install</a> ・
  <a href="#troubleshooting">Troubleshooting</a> ・
  <a href="README.md">中文</a>
</p>

<p align="center">Version <code>0.8.0.26299</code> (based on Ruffle nightly 2026-10-13) | licence MIT OR Apache-2.0, at your option</p>

> [!IMPORTANT]
> **Timffle is an unofficial fork of [Ruffle](https://ruffle.rs/). It is not affiliated with, endorsed by or sponsored by the Ruffle project, Ruffle LLC or Taomee.** Almost all of the Flash emulation is the work of Ruffle and its [hundreds of contributors](https://github.com/ruffle-rs/ruffle/graphs/contributors); this repository keeps Ruffle's complete git history, authorship and licence files.
> **Please report Timffle problems to [Timffle's issues](https://github.com/Im-Tim-mI/Timffle/issues), never to Ruffle.** The name and logo "Ruffle" belong to the Ruffle project, so this fork uses its own name and artwork (see [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)). Ruffle's original README is kept as [`README.ruffle.md`](README.ruffle.md).

---

## About

Flash reached end of life at the end of 2020 and Chrome removed it long ago. Taomee Taiwan's games 摩爾莊園, 賽爾號, 小花仙 and 彈彈堂 are still ActionScript 3 Flash browser games, and they **talk to their servers over TCP sockets**. A Flash emulator alone is not enough in today's Chrome:

1. The emulator has to support everything these games use (`LocalConnection`, `URLStream`, `Loader`/`URLLoader` cancellation, 3D perspective, `Matrix3D`, …); otherwise the game hangs, ignores clicks or draws things in the wrong place.
2. Chrome extensions cannot open TCP connections, so a small local program has to relay them.

Timffle does both: **a patched Ruffle (WebAssembly) plus a connection helper that is installed once**, shipped as one Chrome extension package. Download it, install it, open the game's address and log in.

> [!NOTE]
> Timffle only lets the browser run these games. It does not change the games' content, rules or data, and it contains no game assets. It is not official software of the games' operator; whether a third-party runtime is allowed by a game's terms of service is for you to check, at your own risk. Use your own account only.

## Features

- **One package**: [Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) provides `timffle-chrome-<version>.zip` with the Chrome extension, the connection helper (Windows, macOS, Linux) and the installers.
- **No proxy to set up**: the four game sites are allowed to use sockets by default; nothing else has to be started. Any other site is asked about the first time it wants sockets (we recommend denying; only online games should be allowed).
- **Real Flash as the reference**: every compatibility fix for Ruffle is compared line by line with the output of Adobe Flash Player 32 (30 golden files).
- **Conservative security design**: only sites you allow can use sockets (a site that is not listed needs your approval first); the helper connects to public internet addresses only, listens on no port, does not stay running and records no traffic.
- **Open source, upstream history kept**: Ruffle's complete git history, authorship and licences are preserved; Timffle's own parts are MIT OR Apache-2.0 at your option, like Ruffle.

## Quick start

1. Download `timffle-chrome-<version>.zip` (**the Chrome extension package**) from [Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) and unzip it somewhere permanent.
2. Run the installer in the `helper` folder: Windows `install-windows.cmd`, macOS `install-macos.command`, Linux `sh install-linux.sh`. **Once.**
3. Open `chrome://extensions` → turn on **Developer mode** → **Load unpacked** → pick the `extension` folder.
4. Open a game site, for example https://mole.61.com.tw/ , press the player's play button and log in as usual.

Details are in [Install](#install).

## Status

| Game | URL | Status |
|---|---|---|
| 摩爾莊園 | https://mole.61.com.tw/ | **Verified with a real account** (Linux + Chrome 155, version 0.8.0.26294; later versions behave the same, only names, artwork and repository layout changed): login, the 3D saved-account page, entering the world, walking, changing maps, kart seats. |
| 賽爾號 | http://seer.61.com.tw/ | Sockets allowed by default; **gameplay not tested**. |
| 小花仙 | http://hua.61.com.tw/ | Sockets allowed by default; **gameplay not tested**. |
| 彈彈堂 | http://ddt.61.com.tw/main_index.php | Sockets allowed by default; **gameplay not tested**. |

| Platform | How far it is verified |
|---|---|
| Linux x64 + Chrome 155 | **Real hardware**: install/uninstall, automatic start/stop, binary transfer, connection failures, 摩爾莊園 gameplay |
| Windows 10/11 x64 | Helper and installer tested under **Wine** (Wine is not real Windows) |
| Windows 32-bit and ARM64, macOS (Intel/Apple Silicon), Linux ARM64 | Cross-compiled only, **not tested on real machines** |

The installer registers the helper for **Google Chrome** (on Linux/macOS, Beta/Dev/Canary and Chromium only if their user data folder already exists); Edge, Brave and other Chromium browsers are not registered. The helper is not signed or notarized by Microsoft or Apple.

## Install

### Requirements

- **Desktop Chrome** (Windows 10/11, macOS, Linux; tested with Chrome 155) with Manifest V3 extensions and Native Messaging.
- No Node.js, no administrator rights, nothing else to start.

### Steps

1. **Download** `timffle-chrome-<version>.zip` from [Releases](https://github.com/Im-Tim-mI/Timffle/releases/latest) and verify it:

   ```sh
   sha256sum -c timffle-<build>-SHA256SUMS.txt     # Linux
   shasum -a 256 -c timffle-<build>-SHA256SUMS.txt # macOS
   ```

   Unzipping gives `timffle/` with `extension/` (the Chrome extension), `helper/` (the connection helper and its installers), `LICENSES/`, `NOTICE.md` and `README.txt`. **Keep the whole folder in a fixed place** and do not move or delete it afterwards.

2. **Install the connection helper (once)**; it lets the extension reach the game servers:

   | System | How |
   |---|---|
   | Windows 10/11 | Open the `helper` folder and double-click `install-windows.cmd`. If Windows says it protected your PC, check that this is the file you meant, then "More info" → "Run anyway". "已安裝連線小幫手" means it worked. |
   | macOS | Double-click `helper/install-macos.command`. The helper has no Apple signature; if it is blocked: System Settings → Privacy & Security → "Open Anyway" for the blocked item, then double-click again. |
   | Linux | In the `helper` folder: `sh install-linux.sh` |

   The installer is per-user: it puts the helper into the user's folder and registers Native Messaging for Chrome (the `HKCU` registry on Windows, the user's `NativeMessagingHosts` folder on macOS/Linux). No service, no autostart, no administrator rights, and it never removes download flags or turns off a security feature.

3. **Load the extension**:
   1. Open `chrome://extensions` and turn on **Developer mode** (top right).
   2. Click **Load unpacked** and pick the unzipped `extension` folder.
   3. If the official Ruffle extension is installed, disable or remove it first so the two do not fight over the same pages.

4. **Check the helper**: on the extension's options page, section "Socket 連線", the "連線小幫手" entry should read "Installed (version 1.2.0)". If it says the helper cannot be found, run the installer again and **fully quit Chrome** before starting it.

5. **Play**: open https://mole.61.com.tw/ , press the player's play button and log in as usual; no proxy needed. 賽爾號, 小花仙 and 彈彈堂 work the same way from their own sites. After loading the extension for the first time, reload any game page that was already open; if it still shows the "download Flash" message, wait a few seconds and reload once more.

### Update

Copy the `extension/` contents of the new ZIP over the folder you loaded → press "Reload" for the extension on `chrome://extensions` → hard-reload the game page (`Ctrl+Shift+R`, `Cmd+Shift+R` on macOS). Run the installer again only if the [CHANGELOG](timffle/CHANGELOG.md) says the helper was updated.

### Uninstall

1. Run `uninstall-windows.cmd`, `uninstall-macos.command` or `uninstall-linux.sh` from the `helper` folder (it removes only what the installer created).
2. Remove the extension on `chrome://extensions`.

The helper lives in `%LOCALAPPDATA%\TimffleSocketHelper` (Windows), `~/Library/Application Support/TimffleSocketHelper` (macOS) or `~/.local/share/timffle-socket-helper` (Linux).

## Settings

The extension's options page has a section "**Socket 連線（遊戲伺服器） / Socket connections (game servers)**" (bilingual):

<p align="center"><img src="timffle/docs/images/options-socket.png" alt="The socket section of the extension's options page: the connection helper is shown as installed, followed by the list of allowed website origins" width="560"></p>

- **Connection method**: "Socket helper" is the default and recommended. Advanced users can switch to "Custom WebSocket proxy" and run the local WebSocket↔TCP proxy in [`timffle/relay/`](timffle/relay/) themselves (needs Node.js 22+; Chrome may ask for local network access).
- **Always-allowed website origins (one per line)**: the listed origins (scheme + host + optional port; no `*`, no paths) may use sockets directly, without being asked. The default is `mole`, `seer`, `hua` and `ddt` `.61.com.tw`, each with `http://` and `https://`. You do **not have to type** other sites: use "The first-use question" or "Setting a site from the popup" below. **Allow only online games you trust**, because an allowed site can reach any TCP address on the public internet through the helper.
- **Always-denied website origins (one per line)**: these sites are never asked about and never get sockets (with either connection method). A site cannot be on both the allowed and the denied list (saving warns you; if it is in both anyway, refusing wins).
- **Each connection method has its own always-allowed list**: switch to "Custom WebSocket proxy" and the box shows the proxy's own list; only the sites on that list are given the proxy URL and its token. So a site you allowed in Socket helper mode never gets the token just because you switched to a custom proxy later.
- **While the settings page is open**, if you change something in the popup (for example set a site to "Always deny"), a form with no edits updates itself; a form with edits is stopped when you save and shows the latest settings, so it never changes that decision back.
- Reload the game page after saving or disabling.

### The first-use question

With the connection method "Socket helper", a site that is **on neither list** is asked about the first time it tries to open a socket, in a **window of the extension's own**. It is a separate window, not part of the page, so the page can neither cover it nor click it for you:

<p align="center"><img src="timffle/docs/images/socket-question.png" alt="The question window: the website origin https://game.example, the warning 'We recommend denying. Only online games should be allowed.', and four buttons: Deny (recommended), Allow, Always deny, Always allow" width="420"></p>

| Button | Effect |
|---|---|
| **Deny (recommended)** | Refused for this visit of this tab. Asked again after the tab is closed or goes to another site |
| **Allow** | Allowed for this visit of this tab. Asked again later in the same way (reloading the same page is not a new visit) |
| **Always deny** | Saved to the always-denied list; never asked again |
| **Always allow** | Saved to the always-allowed list; never asked again |

- **We recommend denying; only online games should be allowed.** The window says so, and the "Deny" button is the highlighted one with the focus.
- Closing the window counts as "Deny" (for this visit). So that a click or keystroke meant for the game is not taken as an answer: all input in the first 0.7 s after the window appears or gets focus is ignored; "Allow" accepts **only a mouse (or touch) click, never the keyboard** (Tab, Enter and Space are the keys of a game's login form), and the mouse must move onto the button after that 0.7 s; "Deny" accepts any input. To allow with the keyboard, use the button in the toolbar popup.
- Several connections from one site at once share one question; only one window is open at a time; one tab causes at most 3 windows per visit and the whole extension at most 6 per minute, and sites beyond that are refused without a question. Connections waiting for your answer do not use up connection slots, so an ignored question cannot affect games that are already allowed.
- By the time you answer, the game has usually timed out and shown a connection failure: **after allowing, try again in the game**; if text looks wrong, reload the page.
- A game embedded in another site's page (an `iframe`) is asked about with **its own origin**; the window also shows the origin of the page around it.
- Only "Socket helper" mode asks. "Custom WebSocket proxy" mode never asks and refuses sites that are not listed (the proxy URL contains a token and is never given to a site nobody approved).
- Pages without Flash content are unaffected, and Timffle does not touch the browser's `WebSocket` on them (one exception: when a page has a same-origin `iframe`, Ruffle's own frame detection reads the settings and the bridge is installed early; it behaves like the native `WebSocket`).
- The extension's own pages (popup, settings, welcome page, question window) **cannot be framed by a web page**, so a page can neither fake nor cover them.

### Setting a site from the popup

Click the Timffle icon on the browser toolbar; the "Socket connections" section of the popup shows the **current tab's website**:

<p align="center"><img src="timffle/docs/images/socket-popup.png" alt="The popup's Socket connections section: https://game.example with the state 'Ask on every visit', a yellow 'Allow this site to use sockets' button, the setting drop-down and the reminder to deny by default" width="300"></p>

- **Allow this site to use sockets**: adds the site to the always-allowed list in one click, no typing. A tab that is already open must be reloaded to pick it up (the popup's "Reload Tab" button lights up).
- The drop-down switches the site to "**Ask on every visit**" (removed from both lists; asked again next time), "**Always allow**" or "**Always deny**". To cancel an always-allow or always-deny, switch it back to "Ask on every visit".
- **Frames of other websites** in this tab that were asked about are listed below, each with its own button and drop-down.
- The status line also shows this tab's allow or deny for "this visit".
- The other options on that page are Ruffle's usual playback settings (device fonts, emulated Flash version, ActionScript time limit, …).

## Troubleshooting

| Symptom | What to do |
|---|---|
| The options page cannot find the helper | Run the installer in `helper` again, then **fully quit Chrome** (including background processes) and start it. Chrome reads Native Messaging registrations only at start-up. |
| The game still shows "download Flash" | Make sure the extension is enabled and the official Ruffle extension is not; reload, wait a few seconds and reload once more. |
| The first click (play button or the game's "start") does nothing | Click again. In automated tests the first click occasionally had no effect; the cause was not found. |
| Chinese text turns into boxes or disappears | Linux lacks CJK fonts: install a package such as `fonts-noto-cjk` and restart Chrome. The extension draws device text with browser fonts for these games by default. |
| Windows/macOS blocks the installer or helper | Expected for unsigned programs; check where the file came from and follow the prompts. Do not turn off system protections for this. |
| `Error #2030` in the console after login (from the game's login-gift module) | Known: a race inside the game; real Flash 32 throws the same error in a reproduction. |
| Reporting a problem | Open an issue in [Timffle's issues](https://github.com/Im-Tim-mI/Timffle/issues) with your Chrome version, operating system and the DevTools console output (blank out account names, passwords and tokens first). **Never report Timffle problems to Ruffle.** If you suspect a security problem, do not post details; open an issue that only says you have a security problem to report privately. |

## How it works, and the security design

```
game page  https://mole.61.com.tw/
   │   Timffle (WebAssembly: Ruffle core + fixes) takes over the Flash element; the game calls flash.net.Socket
   ▼
Chrome extension (Manifest V3)
   │   page bridge → content script → service worker
   │   allow-listed origins only, other sites are asked first; one Native Messaging connection per socket
   ▼
connection helper timffle-socket-helper (Go; started by Chrome on demand, exits afterwards)
   │   public addresses only: private, loopback, link-local, multicast and reserved addresses are refused (including IPv4-mapped IPv6)
   ▼
game server (TCP)
```

- **Chrome does not let extensions open TCP connections**, hence a native program; Native Messaging is Chrome's supported way. The helper **listens on no port, installs no service and does not stay running**: one process per socket, gone when the connection ends.
- **Only one extension ID may call the helper**: `eandddnbchclalbjkhfelhjhpijifcog` (determined by the public key in [`timffle/extension-key/`](timffle/extension-key/)).
- The helper **does not record traffic** and enforces limits (≤ 64 KiB per send, ≤ 32 KiB per receive, ≤ 1 MiB buffered, 30 s stall timeout, at most 16 sockets overall).
- Install and uninstall touch only files the installer created; they refuse to overwrite a changed native component, a foreign file of the same name, or a symbolic link in a directory they operate on.

Details: [`timffle/docs/ARCHITECTURE.md`](timffle/docs/ARCHITECTURE.md), [`timffle/docs/PROTOCOL.md`](timffle/docs/PROTOCOL.md).

## Known limitations

- **Platforms**: Windows was tested under Wine only, macOS not at all; the helper is **not signed**. The question window and the popup were verified only in desktop Chrome 155 (headless); not in headed Chrome, on Windows, macOS, Firefox or Safari.
- **Other games**: 賽爾號, 小花仙 and 彈彈堂 merely have sockets allowed by default; gameplay was not tested.
- **Branding**: only the web UI (extension, web demo, player screens) is renamed Timffle; the texts and identifiers of the desktop app, the Safari extension and the npm packages are still upstream Ruffle's, so **do not distribute builds of those under the Timffle name** (see [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md)).
- **3D**: nested "projection owners" differ from Flash; Flash bilinear-filters 3D pictures by about 1 px, Timffle's edges are crisper; perspective is implemented in the wgpu renderer only. `Matrix3D.determinant`/`invert` differ from Flash in the last significant digit.
- **Hit testing**: Flash's `hitTestPoint(x, y, true)` works on whole pixels, Timffle on exact coordinates; edges occasionally differ by 1–2 cells.
- **Recursion depth on the web**: the WebAssembly call stack is shallower than Flash's; the guard limit is 900 levels, and a few long kart-map paths are cut short.
- More known differences: the end of [`timffle/docs/CHANGES-FROM-RUFFLE.md`](timffle/docs/CHANGES-FROM-RUFFLE.md) and [`timffle/docs/FLASH-NOTES.md`](timffle/docs/FLASH-NOTES.md).

## Relationship with Ruffle

Timffle is based on Ruffle `nightly-2026-10-13` (commit [`46fec3f`](https://github.com/ruffle-rs/ruffle/commit/46fec3f1b2e625fae7035bb3b00d6d5c0ec0d413)). Every change after it is a separate commit: the extension socket bridge and settings; the web socket backend and canvas generic fonts; AVM2 networking, `LocalConnection`, `URLStream` and loader fixes; 3D transforms, `Matrix3D` and perspective projection; rust-flash-lso as a subtree (with its history) plus an AMF3 encoder fix; and the rebrand of the user-visible web UI. Details: [`timffle/docs/CHANGES-FROM-RUFFLE.md`](timffle/docs/CHANGES-FROM-RUFFLE.md). The list of modified Ruffle files (the Apache-2.0 §4(b) notice): [`timffle/MODIFIED-FILES.md`](timffle/MODIFIED-FILES.md). Full diff: `git diff 46fec3f -- . ':!timffle'`.

## Development

### Build from source

Needs git, Rust 1.99 with `wasm32-unknown-unknown`, wasm-bindgen CLI 0.2.127 (must equal `Cargo.lock`), binaryen (`wasm-opt`), Node.js 24 + npm, Go 1.27 and Python 3. Everything is in this repository (including the patched flash-lso); nothing else has to be fetched:

```sh
git clone https://github.com/Im-Tim-mI/Timffle.git && cd Timffle
VERSION4=0.8.0.26299 timffle/scripts/build-extension.sh   # wasm + extension → web/packages/extension/dist/ruffle_extension.zip
VERSION4=0.8.0.26299 timffle/scripts/package-release.sh   # helper for 7 platforms + release ZIP with licences → timffle/build/out/
```

The build script rewrites the build machine's home directory and user name out of the wasm by default, and the packaging script checks before and after packaging and refuses to produce a release ZIP that still carries them. See [`timffle/docs/BUILD.md`](timffle/docs/BUILD.md). The other parts of Ruffle (desktop app etc.) build as upstream does ([`README.ruffle.md`](README.ruffle.md)), but read [`timffle/docs/BRANDING.md`](timffle/docs/BRANDING.md) first.

### Tests

Differential tests against real Flash (30 golden files, [`timffle/difftest/`](timffle/difftest/)); helper unit tests (`timffle/helper`, `go test ./...`); package tests (`timffle/helper/installer-tests/`); extension unit tests (`web/packages/extension/tests/`); the rebrand check (`python3 timffle/scripts/rebrand.py --check`); browser + helper integration tests ([`timffle/tools/native-regress/`](timffle/tools/native-regress/)); Ruffle's own regression suite (`cargo test -p tests --test tests`). How to run them: [`timffle/docs/TESTING.md`](timffle/docs/TESTING.md). What was actually run for each version: [`timffle/CHANGELOG.md`](timffle/CHANGELOG.md).

### Following upstream Ruffle

```sh
git remote add upstream https://github.com/ruffle-rs/ruffle.git
git fetch upstream tag nightly-YYYY-MM-DD --no-tags
git merge nightly-YYYY-MM-DD                 # merge, never rebase published history
python3 timffle/scripts/rebrand.py           # re-apply the name to new/translated upstream strings
python3 timffle/scripts/rebrand.py --check
timffle/scripts/list-modified-files.sh > timffle/MODIFIED-FILES.md
```

See [`timffle/docs/UPSTREAM.md`](timffle/docs/UPSTREAM.md).

### Contributing

Bug reports, ideas and pull requests are welcome in [Timffle's issues](https://github.com/Im-Tim-mI/Timffle/issues). Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) (upstream Ruffle's guide, kept as is) and the contribution rules in [`timffle/docs/UPSTREAM.md`](timffle/docs/UPSTREAM.md) first. Fixes to Flash behaviour should come with a differential test that has a real-Flash golden, or a Ruffle-style SWF regression test.

## Licence, credits and notices

- **Ruffle**: Copyright (c) 2018-2022 Ruffle LLC and Ruffle contributors, MIT OR Apache-2.0; full texts and the third-party dependency list in [`LICENSE.md`](LICENSE.md), kept verbatim. Ruffle's contributors are preserved in this repository's git history (`git shortlog -sn 46fec3f`).
- **rust-flash-lso**: Copyright (c) 2020 Callum Thomson, MIT ([`vendor/rust-flash-lso/LICENSE`](vendor/rust-flash-lso/LICENSE)).
- **Timffle's modifications and original parts**: Copyright (c) 2026 Im-Tim-mI and Timffle contributors, **MIT OR Apache-2.0 at your option** ([`timffle/LICENSE-MIT`](timffle/LICENSE-MIT), [`timffle/LICENSE-APACHE`](timffle/LICENSE-APACHE)). Timffle's icon and logo are original works under the same licences.
- Unless you explicitly state otherwise, any contribution intentionally submitted for inclusion in Timffle by you, as defined in the Apache-2.0 license, shall be dual licensed as above, without any additional terms or conditions.
- **Trademarks**: "Ruffle" and its logo belong to the Ruffle project and are used here only descriptively ("a fork of Ruffle", "based on Ruffle"). The game names, "Taomee", "Flash", "Adobe", "Chrome" etc. belong to their owners.
- **No game assets** are included (no game SWF/DLL/images, game code, server addresses, packet formats or cryptography), and game files are not modified. Use your own account and respect the games' terms of service. Full notice: [`NOTICE.md`](NOTICE.md). Where each behaviour comes from and how it was verified: [`timffle/docs/PROVENANCE.md`](timffle/docs/PROVENANCE.md) (Traditional Chinese with an English summary).
