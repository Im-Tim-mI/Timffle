import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import {
    registerSocketBridge,
    senderOrigin,
    isExtensionUI,
} from "../src/socket-bridge-background.ts";
import {
    SOCKET_PORT_NAME,
    HELPER_STATUS_REQUEST,
    MAX_FRAME_SOCKETS,
} from "../src/socket-bridge-protocol.ts";
const ID = "eandddnbchclalbjkhfelhjhpijifcog",
    ORIGIN = "https://mole.61.com.tw";
const tick = () => new Promise((r) => setImmediate(r));
function event() {
    const listeners = new Set();
    return {
        addListener: (f) => listeners.add(f),
        removeListener: (f) => listeners.delete(f),
        emit: (...args) => [...listeners].map((f) => f(...args)),
    };
}
function port(sender) {
    return {
        name: SOCKET_PORT_NAME,
        sender,
        sent: [],
        disconnected: false,
        onMessage: event(),
        onDisconnect: event(),
        postMessage(m) {
            if (this.disconnected) {
                throw new Error("gone");
            }
            this.sent.push(m);
        },
        disconnect() {
            if (!this.disconnected) {
                this.disconnected = true;
                this.onDisconnect.emit();
            }
        },
    };
}
const content = (overrides = {}) => ({
    id: ID,
    url: ORIGIN + "/game",
    origin: ORIGIN,
    tab: { id: 1 },
    frameId: 0,
    ...overrides,
});
const ui = () => ({
    id: ID,
    url: "chrome-extension://" + ID + "/options.html",
    origin: "chrome-extension://" + ID,
    frameId: 0,
});
function setup(t, deps = {}) {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    let settings = {
            enabled: true,
            mode: "helper",
            proxyUrl: "",
            allowedOrigins: [ORIGIN],
        },
        enabled = true;
    const natives = [],
        prior = globalThis.browser;
    const browser = {
        runtime: {
            id: ID,
            getURL: (p) => "chrome-extension://" + ID + p,
            onConnect: event(),
            onMessage: event(),
            lastError: undefined,
            connectNative() {
                const n = port();
                natives.push(n);
                return n;
            },
        },
        storage: {
            local: { get: async () => ({ socketProxySettings: settings }) },
            sync: { get: async () => ({ ruffleEnable: enabled }) },
            onChanged: event(),
        },
        tabs: { onRemoved: event(), onUpdated: event() },
        windows: { onRemoved: event() },
    };
    globalThis.browser = browser;
    const cleanup = registerSocketBridge(deps);
    t.after(() => {
        cleanup();
        globalThis.browser = prior;
    });
    const open = async (sender = content()) => {
        const p = port(sender);
        browser.runtime.onConnect.emit(p);
        p.onMessage.emit({ type: "open", host: "public.example", port: 1234 });
        await tick();
        return p;
    };
    const connected = async () => {
        const p = await open(),
            n = natives.at(-1);
        n.onMessage.emit({ type: "hello", version: "1.1.0", protocol: 2 });
        n.onMessage.emit({ type: "opened" });
        return { p, n };
    };
    return {
        browser,
        natives,
        open,
        connected,
        settings(value) {
            settings = value;
            browser.storage.onChanged.emit(
                { socketProxySettings: { newValue: value } },
                "local",
            );
        },
        disable() {
            enabled = false;
            browser.storage.onChanged.emit(
                { ruffleEnable: { newValue: false } },
                "sync",
            );
        },
    };
}
test("frame identity and extension UI cannot be spoofed by nominal URL", (t) => {
    setup(t);
    assert.equal(senderOrigin(content()), ORIGIN);
    for (const sender of [
        content({ id: "other" }),
        content({ tab: undefined }),
        content({ frameId: undefined }),
        content({ origin: "null" }),
        content({ origin: "https://evil.example" }),
        content({ url: "about:blank" }),
        content({ url: "file:///tmp/a" }),
    ]) {
        assert.equal(senderOrigin(sender), undefined);
    }
    assert.equal(isExtensionUI(ui()), true);
    for (const sender of [
        content(),
        { ...ui(), id: "other" },
        { ...ui(), frameId: 1 },
        { ...ui(), origin: "null" },
        { ...ui(), url: "chrome-extension://" + ID + "/player.html" },
    ]) {
        assert.equal(isExtensionUI(sender), false);
    }
});
test("unapproved and opaque origins cannot start a native process", async (t) => {
    const h = setup(t);
    for (const sender of [
        content({
            url: "https://evil.example/x",
            origin: "https://evil.example",
        }),
        content({ origin: "null" }),
    ]) {
        const p = await h.open(sender);
        assert.equal(p.disconnected, true);
        assert.ok(p.sent.some((x) => x.code === "not_allowed"));
    }
    assert.equal(h.natives.length, 0);
});
test("hello v2 is required before TCP open", async (t) => {
    const h = setup(t),
        p = await h.open(),
        n = h.natives[0];
    assert.deepEqual(n.sent, [{ type: "hello" }]);
    assert.equal(p.sent.length, 0);
    n.onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.equal(n.disconnected, true);
    assert.equal(p.disconnected, true);
    assert.ok(p.sent.some((x) => x.code === "helper_incompatible"));
    assert.equal(
        n.sent.some((x) => x.type === "open"),
        false,
    );
});
test("one in-flight send and receive; ack forwarding; flood terminates", async (t) => {
    const h = setup(t),
        { p, n } = await h.connected();
    assert.ok(n.sent.some((x) => x.type === "open"));
    assert.deepEqual(p.sent, [{ type: "opened" }]);
    p.onMessage.emit({ type: "send", data: "AQID" });
    assert.deepEqual(n.sent.at(-1), { type: "send", data: "AQID" });
    n.onMessage.emit({ type: "data", data: "BAUG" });
    assert.deepEqual(p.sent.at(-1), { type: "data", data: "BAUG" });
    p.onMessage.emit({ type: "ack" });
    assert.deepEqual(n.sent.at(-1), { type: "ack" });
    n.onMessage.emit({ type: "sent" });
    assert.deepEqual(p.sent.at(-1), { type: "sent" });
    p.onMessage.emit({ type: "send", data: "AQ==" });
    p.onMessage.emit({ type: "send", data: "Ag==" });
    assert.equal(n.disconnected, true);
    assert.equal(p.sent.filter((x) => x.type === "error").length, 1);
});
test("authorization cancellation and disabled player close all handles", async (t) => {
    const h = setup(t),
        p = port(content());
    h.browser.runtime.onConnect.emit(p);
    p.onMessage.emit({ type: "open", host: "public.example", port: 1234 });
    h.settings({
        enabled: false,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: [ORIGIN],
    });
    await tick();
    assert.equal(h.natives.length, 0);
    assert.equal(p.disconnected, true);
    h.settings({
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: [ORIGIN],
    });
    const { p: active, n } = await h.connected();
    h.disable();
    assert.equal(active.disconnected, true);
    assert.equal(n.disconnected, true);
});
test("same-document navigation preserves sockets; origin change closes", async (t) => {
    const h = setup(t),
        { p, n } = await h.connected();
    h.browser.tabs.onUpdated.emit(1, { url: ORIGIN + "/game#part2" });
    assert.equal(n.disconnected, false);
    h.browser.tabs.onUpdated.emit(1, { url: "https://evil.example/" });
    assert.equal(n.disconnected, true);
    assert.equal(p.disconnected, true);
});
test("per-frame cap and freed slots bound native processes", async (t) => {
    const h = setup(t),
        pages = [];
    for (let i = 0; i < MAX_FRAME_SOCKETS; i++) {
        pages.push(await h.open());
    }
    assert.equal(h.natives.length, MAX_FRAME_SOCKETS);
    const extra = await h.open();
    assert.equal(extra.sent[0].code, "socket_limit");
    assert.equal(h.natives.length, MAX_FRAME_SOCKETS);
    pages[0].disconnect();
    await h.open();
    assert.equal(h.natives.length, MAX_FRAME_SOCKETS + 1);
});
test("content cannot probe helper status; concurrent UI checks share one process", async (t) => {
    const h = setup(t),
        replies = [];
    h.browser.runtime.onMessage.emit(
        { type: HELPER_STATUS_REQUEST },
        content(),
        (r) => replies.push(r),
    );
    assert.equal(h.natives.length, 0);
    h.browser.runtime.onMessage.emit(
        { type: HELPER_STATUS_REQUEST },
        ui(),
        (r) => replies.push(r),
    );
    h.browser.runtime.onMessage.emit(
        { type: HELPER_STATUS_REQUEST },
        ui(),
        (r) => replies.push(r),
    );
    assert.equal(h.natives.length, 1);
    h.natives[0].onMessage.emit({
        type: "hello",
        version: "1.1.0",
        protocol: 2,
    });
    await tick();
    assert.equal(h.natives[0].disconnected, true);
    assert.equal(replies.length, 2);
    assert.ok(replies.every((x) => x.installed && x.protocol === 2));
});

/** The pages of the extension, as a message sender: only the settings, the popup and the install page may ask about the helper. */
const pageAt = (path, overrides = {}) => ({
    id: ID,
    url: "chrome-extension://" + ID + path,
    origin: "chrome-extension://" + ID,
    frameId: 0,
    ...overrides,
});

test("the install page, the popup and the settings page may ask whether the helper is installed; no other page may", async (t) => {
    const h = setup(t);
    const ask = async (sender) => {
        const before = h.natives.length;
        h.browser.runtime.onMessage.emit({ type: HELPER_STATUS_REQUEST }, sender, () => {});
        const started = h.natives.length - before;
        if (started > 0) {
            // The probe is shared: let the one that is running finish before the next sender asks.
            h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.2.0", protocol: 2 });
            await tick();
        }
        return started;
    };
    for (const path of ["/helper.html", "/popup.html", "/options.html"]) {
        assert.equal(await ask(pageAt(path)), 1, path);
    }
    for (const sender of [
        pageAt("/prompt.html"),
        pageAt("/onboard.html"),
        pageAt("/player.html"),
        pageAt("/helper.html", { frameId: 2 }),
        pageAt("/helper.html", { id: "other" }),
        pageAt("/helper.html", { origin: "https://evil.example" }),
        content(),
    ]) {
        assert.equal(await ask(sender), 0, JSON.stringify(sender));
    }
});

/** A stand-in for the toolbar icon: remembers which tabs were marked. */
function badge() {
    const marked = [];
    return { marked, show: (tabId) => marked.push(tabId) };
}

test("a socket that fails because the helper is missing or is not the right one marks its tab, and no other failure does", async (t) => {
    const mark = badge();
    const h = setup(t, { badge: mark });
    // Chrome knows no such native messaging host.
    const missing = await h.open(content({ tab: { id: 7 } }));
    h.browser.runtime.lastError = { message: "Specified native messaging host not found." };
    h.natives.at(-1).disconnect();
    h.browser.runtime.lastError = undefined;
    assert.ok(missing.sent.some((x) => x.code === "helper_missing"));
    assert.deepEqual(mark.marked, [7]);
    // connectNative itself refuses.
    const connectNative = h.browser.runtime.connectNative;
    h.browser.runtime.connectNative = () => {
        throw new Error("no native messaging");
    };
    const refused = await h.open(content({ tab: { id: 8 } }));
    h.browser.runtime.connectNative = connectNative;
    assert.ok(refused.sent.some((x) => x.code === "helper_missing"));
    assert.deepEqual(mark.marked, [7, 8]);
    // A helper of another protocol version.
    const old = await h.open(content({ tab: { id: 9 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.ok(old.sent.some((x) => x.code === "helper_incompatible"));
    assert.deepEqual(mark.marked, [7, 8, 9]);
    // Everything else leaves the icon alone: the server refused, the helper crashed after it said hello, the page left.
    const refusedByServer = await h.open(content({ tab: { id: 10 } }));
    const native = h.natives.at(-1);
    native.onMessage.emit({ type: "hello", version: "1.2.0", protocol: 2 });
    native.onMessage.emit({ type: "closed" });
    assert.ok(refusedByServer.sent.some((x) => x.code === "connect_failed"));
    const leaving = await h.open(content({ tab: { id: 11 } }));
    leaving.disconnect();
    assert.deepEqual(mark.marked, [7, 8, 9]);
});

test("a tab is marked once per failed socket, whichever frame asked, and the badge needs no browser support", async (t) => {
    const mark = badge();
    const h = setup(t, { badge: mark });
    for (const frameId of [0, 3]) {
        const page = await h.open(content({ tab: { id: 5 }, frameId }));
        h.natives.at(-1).onMessage.emit({ type: "hello", version: "0.9.0", protocol: 1 });
        assert.ok(page.sent.some((x) => x.code === "helper_incompatible"), String(frameId));
    }
    assert.deepEqual(mark.marked, [5, 5]);
});

test("without a badge dependency the browser's action API is used, and a browser without it is fine", async (t) => {
    const h = setup(t);
    const calls = [];
    h.browser.action = {
        setBadgeText: async (details) => calls.push(["text", details]),
        setBadgeBackgroundColor: async (details) => calls.push(["color", details]),
    };
    const page = await h.open(content({ tab: { id: 4 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.ok(page.sent.some((x) => x.code === "helper_incompatible"));
    assert.deepEqual(calls, [
        ["text", { tabId: 4, text: "!" }],
        ["color", { tabId: 4, color: "#d93025" }],
    ]);
    // A tab that is already gone makes the browser refuse: nothing breaks.
    h.browser.action = {
        setBadgeText: async () => {
            throw new Error("No tab with id: 4");
        },
        setBadgeBackgroundColor: () => {
            throw new Error("No tab with id: 4");
        },
    };
    const gone = await h.open(content({ tab: { id: 4 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.ok(gone.sent.some((x) => x.code === "helper_incompatible"));
    // Firefox has no such API in this shape.
    delete h.browser.action;
    const other = await h.open(content({ tab: { id: 6 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.ok(other.sent.some((x) => x.code === "helper_incompatible"));
});

/** A stand-in for the "install the helper" window: remembers what it was asked. */
function helperWindow() {
    const calls = { shown: [], removed: [], gone: [], disposed: 0 };
    return {
        calls,
        show: async (request) => {
            calls.shown.push(request);
            return true;
        },
        view: () => undefined,
        windowRemoved: (windowId) => calls.removed.push(windowId),
        tabGone: (tabId) => calls.gone.push(tabId),
        dispose: () => calls.disposed++,
    };
}

test("a socket that fails because the helper is missing or not the right one asks for the install window, with what the browser reported about the frame", async (t) => {
    const notice = helperWindow();
    const h = setup(t, { badge: badge(), helperPrompts: notice });
    const sender = content({
        tab: { id: 7, windowId: 70, url: "https://portal.example/page" },
        frameId: 3,
        documentId: "doc-9",
    });
    const missing = await h.open(sender);
    h.browser.runtime.lastError = { message: "Specified native messaging host not found." };
    h.natives.at(-1).disconnect();
    h.browser.runtime.lastError = undefined;
    assert.ok(missing.sent.some((x) => x.code === "helper_missing"));
    const old = await h.open(content({ tab: { id: 8 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.0.0", protocol: 1 });
    assert.ok(old.sent.some((x) => x.code === "helper_incompatible"));
    assert.deepEqual(notice.calls.shown, [
        {
            problem: "missing",
            origin: ORIGIN,
            tabId: 7,
            frameId: 3,
            documentId: "doc-9",
            top: "https://portal.example",
            windowId: 70,
        },
        { problem: "incompatible", origin: ORIGIN, tabId: 8, frameId: 0 },
    ]);
});

test("no other failure asks for the install window", async (t) => {
    const notice = helperWindow();
    const h = setup(t, { badge: badge(), helperPrompts: notice });
    // The server refused.
    await h.open(content({ tab: { id: 10 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.2.0", protocol: 2 });
    h.natives.at(-1).onMessage.emit({ type: "closed" });
    // The helper crashed after it said hello.
    await h.open(content({ tab: { id: 11 } }));
    h.natives.at(-1).onMessage.emit({ type: "hello", version: "1.2.0", protocol: 2 });
    h.browser.runtime.lastError = { message: "Native host has exited." };
    h.natives.at(-1).disconnect();
    h.browser.runtime.lastError = undefined;
    // The page left; the site is not allowed.
    const leaving = await h.open(content({ tab: { id: 12 } }));
    leaving.disconnect();
    await h.open(content({ url: "https://evil.example/x", origin: "https://evil.example", tab: { id: 13 } }));
    assert.deepEqual(notice.calls.shown, []);
});

test("the install window is told about closed tabs and windows and a player that was turned off, and is closed with the bridge", async (t) => {
    const notice = helperWindow();
    const h = setup(t, { badge: badge(), helperPrompts: notice });
    h.browser.tabs.onRemoved.emit(5);
    h.browser.windows.onRemoved.emit(77);
    h.disable();
    assert.deepEqual(notice.calls.gone, [5]);
    assert.deepEqual(notice.calls.removed, [77]);
    assert.equal(notice.calls.disposed, 1);
});

test("the prompt page gets the install window's text when the question has none, and the question wins when it has", async (t) => {
    const notice = helperWindow();
    notice.view = (id, windowId) =>
        id === "notice" && windowId === 5
            ? { helper: "missing", origin: ORIGIN }
            : undefined;
    const prompts = {
        view: (id) => (id === "question" ? { origin: "https://asked.example" } : undefined),
        ask: async () => "dismissed",
        answer: async () => false,
        windowRemoved() {},
        tabGone() {},
        settingsChanged() {},
        dispose() {},
    };
    const h = setup(t, { badge: badge(), helperPrompts: notice, prompts });
    const promptPage = (windowId) => ({
        id: ID,
        url: "chrome-extension://" + ID + "/prompt.html?id=x",
        origin: "chrome-extension://" + ID,
        frameId: 0,
        tab: { id: 900, windowId },
    });
    const ask = (id, sender) => {
        let reply;
        const returned = h.browser.runtime.onMessage
            .emit({ type: "socket_prompt_get", id }, sender, (r) => (reply = r))
            .find((r) => r !== undefined);
        return { reply, returned };
    };
    assert.deepEqual(ask("notice", promptPage(5)).reply, { helper: "missing", origin: ORIGIN });
    assert.equal(ask("notice", promptPage(6)).reply, null);
    assert.deepEqual(ask("question", promptPage(5)).reply, { origin: "https://asked.example" });
    assert.equal(ask("nothing", promptPage(5)).reply, null);
    // A web page, or a frame of the prompt page, is not the prompt page.
    assert.equal(ask("notice", content()).returned, undefined);
    assert.equal(ask("notice", { ...promptPage(5), frameId: 1 }).returned, undefined);
});
