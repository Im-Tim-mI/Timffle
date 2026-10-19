// The popup's notice that the socket helper has to be installed: when it appears, what it says, and when the helper is not even asked.
import test from "node:test";
import assert from "node:assert/strict";
import { bindHelperNotice, usesHelper } from "../src/popup-helper.ts";
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

const PROXY = { ...defaultProxySettings(), mode: "websocket", proxyUrl: "ws://127.0.0.1:1/c?host={host}&port={port}" };

/** The three elements of the popup's notice, and everything the notice code reads from the browser. */
function setup({
    settings,
    playerEnabled = true,
    status = { installed: false, error: "helper_missing" },
    nativeMessaging = true,
    framed = false,
    storageFails = false,
    language = "en",
} = {}) {
    const classes = new Set(["hidden"]);
    const notice = {
        classList: { add: (name) => classes.add(name), remove: (name) => classes.delete(name) },
    };
    const message = { textContent: "" };
    const clicks = [];
    const button = { addEventListener: (type, listener) => type === "click" && clicks.push(listener) };
    const elements = { "helper-notice": notice, "helper-notice-text": message, "helper-notice-button": button };
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
                    return settings === undefined ? {} : { socketProxySettings: settings };
                },
            },
            sync: { get: async () => ({ ruffleEnable: playerEnabled }) },
        },
    };
    const installed = [];
    return {
        probes,
        installed,
        run: () => bindHelperNotice({ install: () => installed.push(true) }),
        message,
        shown: () => !classes.has("hidden"),
        click: (isTrusted) => clicks.forEach((listener) => listener({ isTrusted })),
    };
}

test("the helper matters only when sockets are on, Timffle is on and the helper is the method", () => {
    const base = defaultProxySettings();
    assert.equal(usesHelper(base, true), true);
    assert.equal(usesHelper({ ...base, enabled: false }, true), false);
    assert.equal(usesHelper(base, false), false);
    assert.equal(usesHelper(PROXY, true), false);
});

test("a missing helper shows the notice with its text, and the button opens the install page for a real click only", async () => {
    const popup = setup();
    await popup.run();
    assert.deepEqual(popup.probes, [{ type: HELPER_STATUS_REQUEST }]);
    assert.equal(popup.shown(), true);
    assert.equal(popup.message.textContent, "The socket helper is not installed, so online games cannot connect.");
    popup.click(false);
    assert.deepEqual(popup.installed, []);
    popup.click(true);
    assert.deepEqual(popup.installed, [true]);
});

test("a helper that does not match says so, in the language of the browser", async () => {
    const popup = setup({ status: { installed: false, version: "1.0.0", protocol: 1, error: "helper_incompatible" }, language: "zh_TW" });
    await popup.run();
    assert.equal(popup.shown(), true);
    assert.equal(popup.message.textContent, fakeI18n("zh_TW").getMessage("timffle_helper_notice_incompatible"));
});

test("a helper that works, or that failed for another reason, shows nothing", async () => {
    for (const status of [
        { installed: true, version: "1.2.0", protocol: 2 },
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
    }
});

test("where the helper is not needed, it is not even started to look", async () => {
    for (const [name, options] of [
        ["sockets switched off", { settings: { ...defaultProxySettings(), enabled: false } }],
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
