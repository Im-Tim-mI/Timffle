// The popup's notice that the socket helper has to be installed: when it appears, what it says, which installer its
// button downloads, and when the helper is not even asked.
import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import { bindHelperNotice, usesHelper } from "../src/popup-helper.ts";
import { HELPER_INSTALLERS } from "../src/helper-download.ts";
import { HELPER_STATUS_REQUEST } from "../src/socket-bridge-protocol.ts";
import { defaultProxySettings } from "../src/socket-proxy.ts";
import { fakeI18n } from "./catalog-support.mjs";

const originalBrowser = globalThis.browser;
const originalDocument = globalThis.document;
const originalWindow = globalThis.window;
test.afterEach(() => {
    globalThis.browser = originalBrowser;
    globalThis.document = originalDocument;
    globalThis.window = originalWindow;
});

const PROXY = {
    ...defaultProxySettings(),
    mode: "websocket",
    proxyUrl: "ws://127.0.0.1:1/c?host={host}&port={port}",
};
const WINDOWS = HELPER_INSTALLERS.find(
    (installer) => installer.id === "windows-x64",
);

/** The elements of the popup's notice, and everything the notice code reads from the browser. */
function setup({
    settings,
    playerEnabled = true,
    status = { installed: false, error: "helper_missing" },
    nativeMessaging = true,
    framed = false,
    storageFails = false,
    language = "en",
    installer = WINDOWS,
    downloadFails = false,
} = {}) {
    const classes = new Set(["hidden"]);
    const notice = {
        classList: {
            add: (name) => classes.add(name),
            remove: (name) => classes.delete(name),
        },
    };
    const message = { textContent: "" };
    const clicks = [];
    const button = {
        hidden: false,
        addEventListener: (type, listener) =>
            type === "click" && clicks.push(listener),
    };
    const label = { hidden: true, textContent: "" };
    const elements = {
        "helper-notice": notice,
        "helper-notice-text": message,
        "helper-notice-button": button,
        "helper-notice-for": label,
    };
    const probes = [];
    const win = {};
    win.top = framed ? {} : win;
    globalThis.window = win;
    globalThis.document = { getElementById: (id) => elements[id] ?? null };
    globalThis.browser = {
        i18n: fakeI18n(language),
        runtime: {
            ...(nativeMessaging ? { connectNative() {} } : {}),
            async sendMessage(request) {
                probes.push(request);
                return status;
            },
        },
        storage: {
            local: {
                async get() {
                    if (storageFails) {
                        throw new Error("storage is gone");
                    }
                    return settings === undefined
                        ? {}
                        : { socketProxySettings: settings };
                },
            },
            sync: { get: async () => ({ ruffleEnable: playerEnabled }) },
        },
    };
    const downloads = [];
    return {
        probes,
        downloads,
        run: () =>
            bindHelperNotice({
                detect: async () => installer ?? undefined,
                download: async (chosen) => {
                    downloads.push(chosen);
                    if (downloadFails) {
                        throw new Error("no tab");
                    }
                },
            }),
        message,
        button,
        label,
        shown: () => !classes.has("hidden"),
        click: async (isTrusted) => {
            clicks.forEach((listener) => listener({ isTrusted }));
            // The download and what follows it are promises: let them settle.
            await new Promise((resolve) => setImmediate(resolve));
        },
    };
}

test("the helper matters only when sockets are on, Timffle is on and the helper is the method", () => {
    const base = defaultProxySettings();
    assert.equal(usesHelper(base, true), true);
    assert.equal(usesHelper({ ...base, enabled: false }, true), false);
    assert.equal(usesHelper(base, false), false);
    assert.equal(usesHelper(PROXY, true), false);
});

test("a missing helper shows the notice, the system it will download for, and a button", async () => {
    const popup = setup();
    await popup.run();
    assert.deepEqual(popup.probes, [{ type: HELPER_STATUS_REQUEST }]);
    assert.equal(popup.shown(), true);
    assert.equal(
        popup.message.textContent,
        "The socket helper is not installed, so online games cannot connect.",
    );
    assert.equal(popup.label.textContent, "For Windows 64-bit");
    assert.equal(popup.label.hidden, false);
    assert.equal(popup.button.hidden, false);
    assert.deepEqual(
        popup.downloads,
        [],
        "nothing is downloaded before a click",
    );
});

test("only a real click downloads the installer, once, and the notice then says what to do next", async () => {
    const popup = setup();
    await popup.run();
    await popup.click(false);
    assert.deepEqual(popup.downloads, [], "a script's click is not a decision");
    await popup.click(true);
    assert.deepEqual(popup.downloads, [WINDOWS]);
    assert.equal(
        popup.message.textContent,
        "Download started. When it has finished, run the downloaded installer, then reload the game page.",
    );
    // The same click twice (a double click) is one download.
    await popup.click(true);
    assert.equal(popup.downloads.length, 1);
});

test("when the browser cannot start the download, nothing is claimed and another click tries again", async () => {
    const popup = setup({ downloadFails: true });
    await popup.run();
    const text = popup.message.textContent;
    await popup.click(true);
    assert.equal(popup.downloads.length, 1);
    assert.equal(
        popup.message.textContent,
        text,
        "the notice did not say the download started",
    );
    await popup.click(true);
    assert.equal(
        popup.downloads.length,
        2,
        "a failed try does not block the next click",
    );
});

test("every installer has its own label under the button", async () => {
    for (const installer of HELPER_INSTALLERS) {
        const popup = setup({ installer });
        await popup.run();
        assert.equal(
            popup.label.textContent,
            `For ${installer.label}`,
            installer.id,
        );
        await popup.click(true);
        assert.deepEqual(popup.downloads, [installer], installer.id);
    }
});

test("a system without an installer still gets the notice, without a button to press", async () => {
    const popup = setup({ installer: null });
    await popup.run();
    assert.equal(popup.shown(), true);
    assert.equal(popup.button.hidden, true);
    assert.equal(popup.label.hidden, true);
    await popup.click(true);
    assert.deepEqual(popup.downloads, []);
    assert.equal(
        popup.message.textContent,
        "The socket helper is not installed, so online games cannot connect.",
    );
});

test("a helper that does not match says so, in the language of the browser", async () => {
    const popup = setup({
        status: {
            installed: false,
            version: "1.0.0",
            protocol: 1,
            error: "helper_incompatible",
        },
        language: "zh_TW",
    });
    await popup.run();
    assert.equal(popup.shown(), true);
    assert.equal(
        popup.message.textContent,
        fakeI18n("zh_TW").getMessage("timffle_helper_notice_incompatible"),
    );
    assert.equal(popup.label.textContent, "適用於 Windows 64-bit");
    await popup.click(true);
    assert.equal(
        popup.message.textContent,
        "已開始下載。下載完成後請執行安裝程式，再重新整理遊戲頁面。",
    );
});

test("a helper that works, or that failed for another reason, shows nothing", async () => {
    for (const status of [
        { installed: true, version: "1.4.0", protocol: 2 },
        // An older helper still works (it only cannot reach a LAN website's own address).
        { installed: true, version: "1.3.0", protocol: 2 },
        { installed: false, error: "helper_timeout" },
        { installed: false, error: "helper_failed" },
        { installed: false, error: "socket_limit" },
        { installed: false, error: "no_response" },
    ]) {
        const popup = setup({ status });
        await popup.run();
        assert.equal(popup.probes.length, 1, JSON.stringify(status));
        assert.equal(popup.shown(), false, JSON.stringify(status));
        assert.equal(popup.message.textContent, "", JSON.stringify(status));
        assert.equal(popup.label.textContent, "", JSON.stringify(status));
    }
});

test("where the helper is not needed, it is not even started to look", async () => {
    for (const [name, options] of [
        [
            "sockets switched off",
            { settings: { ...defaultProxySettings(), enabled: false } },
        ],
        ["a custom WebSocket proxy", { settings: PROXY }],
        ["Timffle switched off", { playerEnabled: false }],
        ["a browser without native messaging", { nativeMessaging: false }],
        ["a page framed by a website", { framed: true }],
    ]) {
        const popup = setup(options);
        await popup.run();
        assert.deepEqual(popup.probes, [], name);
        assert.equal(popup.shown(), false, name);
    }
});

test("settings that cannot be read give no notice and no error", async () => {
    const popup = setup({ storageFails: true });
    await popup.run();
    assert.deepEqual(popup.probes, []);
    assert.equal(popup.shown(), false);
});

test("a popup without the notice markup does nothing", async () => {
    const popup = setup();
    globalThis.document = { getElementById: () => null };
    await popup.run();
    assert.deepEqual(popup.probes, []);
});
