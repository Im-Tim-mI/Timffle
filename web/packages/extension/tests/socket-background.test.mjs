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
function setup(t) {
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
    };
    globalThis.browser = browser;
    const cleanup = registerSocketBridge();
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
