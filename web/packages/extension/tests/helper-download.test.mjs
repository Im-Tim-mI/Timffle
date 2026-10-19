// The socket helper's installers: which file belongs to which system, how the system is told, where the file is
// downloaded from, and that all of it agrees with what the helper and its packager really produce.
import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import fs from "node:fs";
import path from "node:path";
import {
    bindHelperDownload,
    chooseInstaller,
    detectInstaller,
    HELPER_INSTALLERS,
    HELPER_RELEASE,
    HELPER_RELEASES_URL,
    HELPER_REPOSITORY,
    installerUrl,
    linuxCommand,
    readSystemHints,
    startHelperDownload,
} from "../src/helper-download.ts";
import { fakeI18n, packageDir } from "./catalog-support.mjs";

const id = (hints) => chooseInstaller(hints)?.id;

test("every installer is one file of the repository's release, and no two share a name", () => {
    assert.deepEqual(
        HELPER_INSTALLERS.map((installer) => installer.id),
        [
            "windows-x64",
            "windows-arm64",
            "windows-x86",
            "macos-arm64",
            "macos-x64",
            "linux-x64",
            "linux-arm64",
        ],
    );
    for (const installer of HELPER_INSTALLERS) {
        assert.match(
            installer.file,
            /^timffle-helper-(?:windows|macos|linux)-[a-z0-9]+\.(?:exe|zip|tar\.gz)$/u,
            installer.id,
        );
        assert.ok(installer.file.includes(installer.id), installer.id);
        assert.equal(
            installerUrl(installer),
            `https://github.com/Im-Tim-mI/Timffle-Helper/releases/download/${HELPER_RELEASE}/${installer.file}`,
        );
    }
    assert.equal(
        new Set(HELPER_INSTALLERS.map((installer) => installer.file)).size,
        HELPER_INSTALLERS.length,
    );
    assert.equal(
        new Set(HELPER_INSTALLERS.map((installer) => installer.label)).size,
        HELPER_INSTALLERS.length,
    );
    assert.equal(
        HELPER_REPOSITORY,
        "https://github.com/Im-Tim-mI/Timffle-Helper",
    );
    assert.equal(
        HELPER_RELEASES_URL,
        `${HELPER_REPOSITORY}/releases/tag/${HELPER_RELEASE}`,
    );
});

test("the installers are the ones of the helper this extension is made for", () => {
    const repository = path.resolve(packageDir, "..", "..", "..");
    const main = path.join(repository, "timffle", "helper", "main.go");
    if (!fs.existsSync(main)) {
        return; // The extension sources without the rest of the repository.
    }
    const version = fs
        .readFileSync(main, "utf8")
        .match(/const version = "([^"]+)"/u)?.[1];
    assert.equal(
        HELPER_RELEASE,
        `v${version}`,
        "the release the extension downloads from is not the helper's version",
    );
    const packager = path.join(
        repository,
        "timffle",
        "helper",
        "package-installers.py",
    );
    if (fs.existsSync(packager)) {
        const written = new Set(
            fs
                .readFileSync(packager, "utf8")
                .match(/timffle-helper-[a-z0-9-]+\.(?:exe|zip|tar\.gz)/gu),
        );
        assert.deepEqual(
            [...written].sort(),
            HELPER_INSTALLERS.map((installer) => installer.file).sort(),
            "the packager writes other files than the extension downloads",
        );
    }
});

test("the system is told from what Chrome reports about the processor", () => {
    const cases = [
        [
            { platform: "Windows", architecture: "x86", bitness: "64" },
            "windows-x64",
        ],
        [
            { platform: "Windows", architecture: "arm", bitness: "64" },
            "windows-arm64",
        ],
        [
            { platform: "Windows", architecture: "x86", bitness: "32" },
            "windows-x86",
        ],
        [
            { platform: "Windows", architecture: "arm", bitness: "32" },
            undefined,
        ],
        [
            { platform: "macOS", architecture: "arm", bitness: "64" },
            "macos-arm64",
        ],
        [
            { platform: "macOS", architecture: "x86", bitness: "64" },
            "macos-x64",
        ],
        [
            { platform: "Linux", architecture: "x86", bitness: "64" },
            "linux-x64",
        ],
        [
            { platform: "Linux", architecture: "arm", bitness: "64" },
            "linux-arm64",
        ],
        [{ platform: "Linux", architecture: "x86", bitness: "32" }, undefined],
        [{ platform: "Linux", architecture: "arm", bitness: "32" }, undefined],
        // Systems the helper does not run on.
        [
            { platform: "Chrome OS", architecture: "x86", bitness: "64" },
            undefined,
        ],
        [
            { platform: "Android", architecture: "arm", bitness: "64" },
            undefined,
        ],
        [
            { platform: "Fuchsia", architecture: "x86", bitness: "64" },
            undefined,
        ],
        // A name in another case, or with a version after it, is the same system.
        [
            { platform: "windows", architecture: "x86", bitness: "64" },
            "windows-x64",
        ],
        [
            { platform: "Windows 11", architecture: "x86", bitness: "64" },
            "windows-x64",
        ],
    ];
    for (const [hints, want] of cases) {
        assert.equal(id(hints), want, JSON.stringify(hints));
    }
});

test("an Intel Mac and an Apple silicon Mac are told apart by the processor, not by the User-Agent", () => {
    const agent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36";
    // Both report Intel in the User-Agent; the processor hint is what decides.
    assert.equal(
        id({
            platform: "macOS",
            architecture: "arm",
            bitness: "64",
            userAgent: agent,
        }),
        "macos-arm64",
    );
    assert.equal(
        id({
            platform: "macOS",
            architecture: "x86",
            bitness: "64",
            userAgent: agent,
        }),
        "macos-x64",
    );
    // Without it nothing is guessed: a wrong guess would give a program that cannot start.
    assert.equal(id({ platform: "macOS", userAgent: agent }), undefined);
    assert.equal(id({ userAgent: agent }), undefined);
});

test("without client hints the User-Agent is read, and only where it says enough", () => {
    const chrome = (platform) =>
        `Mozilla/5.0 (${platform}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36`;
    const cases = [
        [chrome("Windows NT 10.0; Win64; x64"), "windows-x64"],
        [chrome("Windows NT 10.0; WOW64"), "windows-x64"],
        [chrome("Windows NT 10.0; ARM64"), "windows-arm64"],
        [chrome("Windows NT 6.1"), "windows-x86"],
        [chrome("X11; Linux x86_64"), "linux-x64"],
        [chrome("X11; Linux aarch64"), "linux-arm64"],
        [chrome("X11; Linux i686"), undefined],
        [chrome("X11; CrOS x86_64 15662.76.0"), undefined],
        [chrome("Linux; Android 14; Pixel 8"), undefined],
        // An Android User-Agent that names its processor is still not a Linux computer.
        [chrome("Linux; Android 14; Pixel 8; aarch64"), undefined],
        [chrome("iPhone; CPU iPhone OS 17_0 like Mac OS X"), undefined],
        [chrome("Macintosh; Intel Mac OS X 10_15_7"), undefined],
        ["", undefined],
    ];
    for (const [userAgent, want] of cases) {
        assert.equal(id({ userAgent }), want, userAgent);
    }
});

test("Chrome's own answers are read, a refused question falls back to what it says outright, nothing at all is no system", async () => {
    const full = {
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        userAgentData: {
            platform: "Windows",
            getHighEntropyValues: async (asked) => {
                assert.deepEqual(asked, [
                    "architecture",
                    "bitness",
                    "platform",
                ]);
                return {
                    architecture: "arm",
                    bitness: "64",
                    platform: "Windows",
                };
            },
        },
    };
    assert.deepEqual(await readSystemHints(full), {
        platform: "Windows",
        architecture: "arm",
        bitness: "64",
        userAgent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    });
    assert.equal((await detectInstaller(full))?.id, "windows-arm64");
    const refused = {
        userAgent: "Mozilla/5.0 (X11; Linux x86_64)",
        userAgentData: {
            platform: "Linux",
            getHighEntropyValues: async () => {
                throw new Error("blocked");
            },
        },
    };
    assert.equal((await detectInstaller(refused))?.id, "linux-x64");
    assert.equal(await detectInstaller({}), undefined);
    assert.equal(await detectInstaller({ userAgent: "curl/8" }), undefined);
});

test("the download is a tab of its own on the file's address, opened without taking over the window", async () => {
    const opened = [];
    const installer = HELPER_INSTALLERS[0];
    await startHelperDownload(installer, async (properties) => {
        opened.push(properties);
    });
    assert.deepEqual(opened, [{ url: installerUrl(installer), active: false }]);
    await assert.rejects(
        startHelperDownload(installer, async () => {
            throw new Error("no tab");
        }),
    );
    // The default goes through the browser's tabs API.
    const created = [];
    globalThis.browser = {
        tabs: { create: async (properties) => created.push(properties) },
    };
    try {
        await startHelperDownload(installer);
    } finally {
        delete globalThis.browser;
    }
    assert.deepEqual(created, [
        { url: installerUrl(installer), active: false },
    ]);
});

test("the command for a Linux download unpacks that file and runs the program inside", () => {
    const linux = Object.fromEntries(
        HELPER_INSTALLERS.filter(
            (installer) => installer.family === "linux",
        ).map((installer) => [installer.id, installer]),
    );
    assert.equal(
        linuxCommand(linux["linux-x64"]),
        "tar xzf timffle-helper-linux-x64.tar.gz && ./timffle-helper-linux-x64",
    );
    assert.equal(
        linuxCommand(linux["linux-arm64"]),
        "tar xzf timffle-helper-linux-arm64.tar.gz && ./timffle-helper-linux-arm64",
    );
});

test("the extension asks for no permission to download, and the sources do not fetch or run anything", () => {
    const manifest = fs.readFileSync(
        path.join(packageDir, "manifest.json5"),
        "utf8",
    );
    assert.doesNotMatch(manifest, /"downloads"/u);
    const source = fs.readFileSync(
        path.join(packageDir, "src", "helper-download.ts"),
        "utf8",
    );
    assert.doesNotMatch(
        source,
        /\bfetch\s*\(|XMLHttpRequest|chrome\.downloads|browser\.downloads|eval\s*\(|new Function/u,
    );
});

test("a second click counts as the same click for two seconds, then it downloads again", async () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    try {
        let clock = 10_000;
        const listeners = [];
        const button = {
            addEventListener: (type, listener) =>
                type === "click" && listeners.push(listener),
        };
        const label = { textContent: "", hidden: true };
        const downloads = [];
        const installer = await bindHelperDownload({
            button,
            label,
            started: () => {},
            detect: async () => HELPER_INSTALLERS[0],
            download: async (chosen) => {
                downloads.push(chosen.id);
            },
            now: () => clock,
        });
        assert.equal(installer, HELPER_INSTALLERS[0]);
        assert.equal(label.textContent, "For Windows 64-bit");
        assert.equal(label.hidden, false);
        const click = async (isTrusted = true) => {
            listeners.forEach((listener) => listener({ isTrusted }));
            await new Promise((resolve) => setImmediate(resolve));
        };
        await click();
        clock += 1999;
        await click();
        assert.deepEqual(downloads, ["windows-x64"], "inside the two seconds");
        clock += 2;
        await click();
        assert.deepEqual(
            downloads,
            ["windows-x64", "windows-x64"],
            "after them",
        );
        await click(false);
        assert.equal(downloads.length, 2, "a script's click never counts");
    } finally {
        delete globalThis.browser;
    }
});

test("without an installer for the system nothing is shown and nothing is wired", async () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    try {
        const listeners = [];
        const button = {
            addEventListener: (type, listener) =>
                listeners.push([type, listener]),
        };
        const label = { textContent: "", hidden: true };
        const installer = await bindHelperDownload({
            button,
            label,
            started: () => {},
            detect: async () => undefined,
        });
        assert.equal(installer, undefined);
        assert.deepEqual(listeners, []);
        assert.equal(label.hidden, true);
        assert.equal(label.textContent, "");
    } finally {
        delete globalThis.browser;
    }
});
