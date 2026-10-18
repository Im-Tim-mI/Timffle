import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import { URL } from "node:url";
import { registerSocketBridge } from "../src/socket-bridge-background.ts";
import {
    HELPER_STATUS_REQUEST,
    MAX_ASKING_SOCKETS,
    MAX_FRAME_SOCKETS,
    MAX_GLOBAL_SOCKETS,
    MAX_TAB_ASKING_SOCKETS,
    SOCKET_PORT_NAME,
    STALL_TIMEOUT_MS,
} from "../src/socket-bridge-protocol.ts";
import {
    PROMPT_ANSWER_REQUEST,
    PROMPT_GET_REQUEST,
    PROMPT_PORT_NAME,
    MAX_PROMPTS_PER_MINUTE,
    MAX_PROMPTS_PER_TAB,
} from "../src/socket-prompt.ts";
import {
    VISIT_FORGET_REQUEST,
    VISIT_GET_REQUEST,
} from "../src/socket-visit.ts";

const ID = "eandddnbchclalbjkhfelhjhpijifcog";
const originalBrowser = globalThis.browser;
const MOLE = "https://mole.61.com.tw";
const NEW = "https://new.example";
const OTHER = "https://other.example";
const tick = () => new Promise((r) => setImmediate(r));
function event() {
    const listeners = new Set();
    return {
        addListener: (f) => listeners.add(f),
        removeListener: (f) => listeners.delete(f),
        emit: (...args) => [...listeners].map((f) => f(...args)),
        get size() {
            return listeners.size;
        },
    };
}
function port(sender, name = SOCKET_PORT_NAME) {
    return {
        name,
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
/** A frame of a web page, as the browser reports it. */
const frame = ({ origin = NEW, tab = 1, frameId = 0, top = origin } = {}) => ({
    id: ID,
    url: origin + "/game",
    origin,
    tab: { id: tab, windowId: 10 + tab, url: top + "/" },
    frameId,
});
const promptUI = (windowId, overrides = {}) => ({
    id: ID,
    url: "chrome-extension://" + ID + "/prompt.html?id=x",
    origin: "chrome-extension://" + ID,
    frameId: 0,
    tab: { id: 900, windowId },
    ...overrides,
});
const popupUI = () => ({
    id: ID,
    url: "chrome-extension://" + ID + "/popup.html",
    origin: "chrome-extension://" + ID,
    frameId: 0,
});
const base = (extra = {}) => ({
    enabled: true,
    mode: "helper",
    proxyUrl: "",
    allowedOrigins: [MOLE],
    deniedOrigins: [],
    ...extra,
});

const teardowns = new WeakMap();
/** One teardown per test, however many service workers it starts. */
function onTeardown(t, cleanup) {
    let list = teardowns.get(t);
    if (!list) {
        list = [];
        teardowns.set(t, list);
        t.mock.timers.enable({ apis: ["setTimeout"] });
        t.after(async () => {
            for (const run of list.reverse()) {
                run();
            }
            // Work that was waiting when the test ended still needs `browser`.
            await tick();
            await tick();
            globalThis.browser = originalBrowser;
        });
    }
    list.push(cleanup);
}

function setup(
    t,
    {
        settings = base(),
        session = {},
        noWindows = false,
        slowSession = false,
    } = {},
) {
    let stored = settings;
    let releaseSession = () => {};
    const sessionReady = slowSession
        ? new Promise((resolve) => (releaseSession = resolve))
        : Promise.resolve();
    let playerEnabled = true;
    let nextWindow = 500;
    const natives = [];
    const windows = { created: [], removed: [], failNext: false };
    const sessionData = session;
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
            local: {
                get: async () => ({ socketProxySettings: stored }),
                async set(items) {
                    const old = stored;
                    stored = JSON.parse(
                        JSON.stringify(items.socketProxySettings),
                    );
                    browser.storage.onChanged.emit(
                        {
                            socketProxySettings: {
                                oldValue: old,
                                newValue: stored,
                            },
                        },
                        "local",
                    );
                },
            },
            sync: { get: async () => ({ ruffleEnable: playerEnabled }) },
            session: {
                async get() {
                    await sessionReady;
                    return JSON.parse(JSON.stringify(sessionData));
                },
                async set(items) {
                    Object.assign(
                        sessionData,
                        JSON.parse(JSON.stringify(items)),
                    );
                },
                async remove(keys) {
                    for (const key of [keys].flat()) {
                        delete sessionData[key];
                    }
                },
            },
            onChanged: event(),
        },
        tabs: { onRemoved: event(), onUpdated: event(), onReplaced: event() },
        windows: noWindows
            ? undefined
            : {
                  onRemoved: event(),
                  async create(options) {
                      if (windows.failNext) {
                          windows.failNext = false;
                          throw new Error("no windows");
                      }
                      windows.created.push(options);
                      return { id: nextWindow++ };
                  },
                  async get() {
                      return { left: 100, top: 50, width: 1280, height: 900 };
                  },
                  async remove(windowId) {
                      windows.removed.push(windowId);
                      // The browser reports every closed window, ours included.
                      browser.windows.onRemoved.emit(windowId);
                  },
              },
    };
    globalThis.browser = browser;
    onTeardown(t, registerSocketBridge());
    const send = (message, sender) => {
        let reply;
        const returned = browser.runtime.onMessage
            .emit(message, sender, (r) => (reply = r))
            .find((r) => r !== undefined);
        return {
            returned,
            get reply() {
                return reply;
            },
        };
    };
    const open = async (sender = frame(), host = "public.example") => {
        const p = port(sender);
        browser.runtime.onConnect.emit(p);
        p.onMessage.emit({ type: "open", host, port: 1234 });
        await tick();
        return p;
    };
    const promptId = (index = windows.created.length - 1) =>
        new URL(windows.created[index].url).searchParams.get("id");
    const answer = async (
        choice,
        windowId = 500 + windows.created.length - 1,
    ) => {
        const r = send(
            { type: PROMPT_ANSWER_REQUEST, id: promptId(), choice },
            promptUI(windowId),
        );
        await tick();
        return r;
    };
    const connectNative = async () => {
        const n = natives.at(-1);
        n.onMessage.emit({ type: "hello", version: "1.2.0", protocol: 2 });
        n.onMessage.emit({ type: "opened" });
        await tick();
        return n;
    };
    return {
        browser,
        natives,
        windows,
        open,
        send,
        answer,
        promptId,
        connectNative,
        sessionData,
        releaseSession: () => releaseSession(),
        get stored() {
            return stored;
        },
        /** Changes the stored settings without the change event having arrived yet. */
        quietlyStore(value) {
            stored = value;
        },
        setSettings(value) {
            stored = value;
            browser.storage.onChanged.emit(
                { socketProxySettings: { newValue: value } },
                "local",
            );
        },
        setPlayer(value) {
            playerEnabled = value;
            browser.storage.onChanged.emit(
                { ruffleEnable: { newValue: value } },
                "sync",
            );
        },
    };
}
const errors = (p) =>
    p.sent.filter((m) => m.type === "error").map((m) => m.code);

test("an allowed website connects without a question", async (t) => {
    const h = setup(t);
    const p = await h.open(frame({ origin: MOLE }));
    assert.equal(h.windows.created.length, 0);
    assert.equal(h.natives.length, 1);
    assert.deepEqual(errors(p), []);
});

test("an unlisted website is asked about, and waits for the answer", async (t) => {
    const h = setup(t);
    const p = await h.open();
    assert.equal(h.windows.created.length, 1);
    const window = h.windows.created[0];
    assert.match(
        window.url,
        /^chrome-extension:\/\/[a-p]{32}\/prompt\.html\?id=[0-9a-f-]{36}$/u,
    );
    assert.equal(window.type, "popup");
    assert.equal(window.focused, true);
    // Centered over the window of the page that asked.
    assert.equal(window.left, Math.round(100 + (1280 - window.width) / 2));
    assert.equal(window.top, Math.round(50 + (900 - window.height) / 2));
    // No helper is started and the page is not answered while the user decides.
    assert.equal(h.natives.length, 0);
    assert.deepEqual(p.sent, []);
    assert.equal(p.disconnected, false);
    // Not answering is not a way to keep a connection waiting forever.
    t.mock.timers.tick(STALL_TIMEOUT_MS);
    await tick();
    assert.deepEqual(errors(p), ["prompt_timeout"]);
    assert.equal(p.disconnected, true);
});

test("always allow: the socket connects, the site is saved, later sockets do not ask", async (t) => {
    const h = setup(t);
    const p = await h.open();
    const reply = await h.answer("allow-always");
    assert.equal(reply.reply, true);
    assert.equal(h.natives.length, 1);
    assert.deepEqual(h.stored.allowedOrigins, [MOLE, NEW]);
    // The helper's list only: the site does not get the custom proxy's token.
    assert.deepEqual(h.stored.proxyOrigins, [MOLE]);
    assert.deepEqual(h.stored.deniedOrigins, []);
    await h.connectNative();
    assert.deepEqual(p.sent, [{ type: "opened" }]);
    // The question window is closed, once.
    assert.deepEqual(h.windows.removed, [500]);
    // Another socket, even from another tab, is just allowed now.
    await h.open(frame({ tab: 2 }));
    assert.equal(h.windows.created.length, 1);
    assert.equal(h.natives.length, 2);
});

test("always deny: the socket is refused, the site is saved, nobody asks again", async (t) => {
    const h = setup(t);
    const p = await h.open();
    await h.answer("deny-always");
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(p.disconnected, true);
    assert.deepEqual(h.stored.deniedOrigins, [NEW]);
    assert.deepEqual(h.stored.allowedOrigins, [MOLE]);
    assert.equal(h.natives.length, 0);
    const again = await h.open(frame({ tab: 2 }));
    assert.deepEqual(errors(again), ["not_allowed"]);
    assert.equal(h.windows.created.length, 1);
});

test("allow this time: connects now and for this tab's visit, asks again in another tab", async (t) => {
    const h = setup(t);
    const settingsBefore = JSON.stringify(h.stored);
    const p = await h.open();
    await h.answer("allow-once");
    assert.equal(h.natives.length, 1);
    await h.connectNative();
    assert.deepEqual(p.sent, [{ type: "opened" }]);
    // Nothing lasting was saved.
    assert.equal(JSON.stringify(h.stored), settingsBefore);
    // The same tab and website do not ask again...
    await h.open();
    assert.equal(h.windows.created.length, 1);
    assert.equal(h.natives.length, 2);
    // ...a frame of the same website in the same tab neither...
    await h.open(frame({ frameId: 5, top: OTHER }));
    assert.equal(h.windows.created.length, 1);
    // ...but another tab is another visit.
    const second = await h.open(frame({ tab: 2 }));
    assert.equal(h.windows.created.length, 2);
    assert.deepEqual(second.sent, []);
});

test("deny this time: refused for this visit without asking again, asked again after leaving", async (t) => {
    const h = setup(t);
    const p = await h.open();
    await h.answer("deny-once");
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.deepEqual(h.stored, base());
    // A game that retries is refused quietly.
    for (let i = 0; i < 5; i++) {
        const again = await h.open();
        assert.deepEqual(errors(again), ["not_allowed"]);
    }
    assert.equal(h.windows.created.length, 1);
    // Closing the tab ends the visit.
    h.browser.tabs.onRemoved.emit(1);
    await tick();
    const next = await h.open();
    assert.deepEqual(next.sent, []);
    assert.equal(h.windows.created.length, 2);
});

test("an answer for this visit ends when the tab goes to another site, not within the site", async (t) => {
    const h = setup(t);
    await h.open();
    await h.answer("allow-once");
    // Another page of the same site, and same-document navigation.
    h.browser.tabs.onUpdated.emit(1, { url: NEW + "/page2" });
    h.browser.tabs.onUpdated.emit(1, { url: NEW + "/page2#part" });
    await tick();
    await h.open();
    assert.equal(h.windows.created.length, 1);
    // Another site.
    h.browser.tabs.onUpdated.emit(1, { url: OTHER + "/" });
    await tick();
    await h.open(frame({ origin: NEW, top: NEW }));
    assert.equal(h.windows.created.length, 2);
});

test("closing the question window without answering refuses", async (t) => {
    const h = setup(t);
    const p = await h.open();
    h.browser.windows.onRemoved.emit(500);
    await tick();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.natives.length, 0);
    assert.deepEqual(h.stored, base());
    const again = await h.open();
    assert.deepEqual(errors(again), ["not_allowed"]);
    assert.equal(h.windows.created.length, 1);
});

test("a page that gives up while the user decides leaves the question open for the next try", async (t) => {
    const h = setup(t);
    const p = await h.open();
    p.onMessage.emit({ type: "close" });
    await tick();
    assert.equal(p.disconnected, true);
    assert.deepEqual(h.windows.removed, []);
    // The user still answers; a later attempt (the player retries) connects.
    await h.answer("allow-once");
    const retry = await h.open();
    assert.equal(h.natives.length, 1);
    assert.deepEqual(errors(retry), []);
    assert.equal(h.windows.created.length, 1);
});

test("sockets opened together share one question and all connect after the answer", async (t) => {
    const h = setup(t);
    const pages = [];
    for (let i = 0; i < 3; i++) {
        pages.push(await h.open());
    }
    assert.equal(h.windows.created.length, 1);
    assert.equal(h.natives.length, 0);
    await h.answer("allow-once");
    assert.equal(h.natives.length, 3);
    assert.ok(pages.every((p) => errors(p).length === 0));
});

test("websites that are refused, or any website in a custom-proxy setup, are never asked about", async (t) => {
    for (const settings of [
        base({ deniedOrigins: [NEW] }),
        base({ enabled: false }),
        {
            enabled: true,
            mode: "websocket",
            proxyUrl: "ws://127.0.0.1:1/connect?host={host}&port={port}",
            allowedOrigins: [MOLE],
            deniedOrigins: [],
        },
    ]) {
        const h = setup(t, { settings });
        const p = await h.open();
        assert.deepEqual(errors(p), ["not_allowed"], JSON.stringify(settings));
        assert.equal(h.windows.created.length, 0);
        assert.equal(h.natives.length, 0);
    }
    // The player switched off.
    const h = setup(t);
    h.setPlayer(false);
    const p = await h.open();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.windows.created.length, 0);
});

test("without a website origin there is nothing to ask about", async (t) => {
    const h = setup(t);
    for (const sender of [
        frame({ origin: "null" }),
        { ...frame(), url: "file:///a.html", origin: "null" },
        { ...frame(), tab: undefined },
    ]) {
        const p = await h.open(sender);
        assert.deepEqual(errors(p), ["not_allowed"]);
    }
    assert.equal(h.windows.created.length, 0);
});

test("if the window cannot be opened the socket is refused, not left hanging", async (t) => {
    const h = setup(t);
    h.windows.failNext = true;
    const p = await h.open();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(p.disconnected, true);
    // Nothing is remembered about it: the next try asks.
    const next = await h.open();
    assert.equal(h.windows.created.length, 1);
    assert.deepEqual(next.sent, []);
});

test("one tab cannot keep opening question windows", async (t) => {
    const h = setup(t);
    for (let i = 0; i < MAX_PROMPTS_PER_TAB; i++) {
        const origin = `https://site${i}.example`;
        await h.open(frame({ origin, top: NEW, frameId: 1 }));
        await h.answer("deny-once");
    }
    assert.equal(h.windows.created.length, MAX_PROMPTS_PER_TAB);
    const p = await h.open(
        frame({ origin: "https://more.example", top: NEW, frameId: 1 }),
    );
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.windows.created.length, MAX_PROMPTS_PER_TAB);
});

test("a tab that has used up its windows cannot use up the extension's for everybody else", async (t) => {
    const h = setup(t);
    const hostile = (n) =>
        frame({
            origin: `https://e${n}.evil.example`,
            top: "https://evil.example",
            frameId: n,
        });
    for (let n = 1; n <= MAX_PROMPTS_PER_TAB; n++) {
        await h.open(hostile(n));
        await h.answer("deny-once");
    }
    // It keeps asking, from one more website, more often than the extension
    // may open windows in a minute. Nothing is recorded about the refusals.
    for (let k = 0; k < MAX_PROMPTS_PER_MINUTE; k++) {
        assert.deepEqual(errors(await h.open(hostile(9))), ["not_allowed"]);
    }
    assert.equal(h.windows.created.length, MAX_PROMPTS_PER_TAB);
    // A game in another tab is still asked.
    const game = await h.open(
        frame({ origin: "https://game.example", tab: 2 }),
    );
    assert.equal(h.windows.created.length, MAX_PROMPTS_PER_TAB + 1);
    assert.deepEqual(game.sent, []);
    await h.answer("allow-once");
    await h.connectNative();
    assert.deepEqual(game.sent, [{ type: "opened" }]);
});

test("a tab that has used up its windows is refused at once while another question is open", async (t) => {
    const h = setup(t);
    const hostile = (n) =>
        frame({
            origin: `https://e${n}.evil.example`,
            top: "https://evil.example",
            frameId: n,
        });
    for (let n = 1; n <= MAX_PROMPTS_PER_TAB; n++) {
        await h.open(hostile(n));
        await h.answer("deny-once");
    }
    // A game in another tab is being asked about.
    const game = await h.open(
        frame({ origin: "https://game.example", tab: 2 }),
    );
    assert.equal(h.windows.created.length, MAX_PROMPTS_PER_TAB + 1);
    // The hostile tab's next websites do not wait behind it (holding
    // waiting-socket places until they time out): they are refused now.
    for (let n = 9; n < 9 + MAX_TAB_ASKING_SOCKETS + 1; n++) {
        const p = await h.open(hostile(n));
        assert.deepEqual(errors(p), ["not_allowed"]);
        assert.equal(p.disconnected, true);
    }
    // The game's question is still open, and answering it still works.
    assert.deepEqual(game.sent, []);
    await h.answer("allow-once");
    await h.connectNative();
    assert.deepEqual(game.sent, [{ type: "opened" }]);
});

test("only the question window can read or answer the question", async (t) => {
    const h = setup(t);
    await h.open();
    const id = h.promptId();
    const get = (sender, qid = id) =>
        h.send({ type: PROMPT_GET_REQUEST, id: qid }, sender);
    const ans = (sender, choice = "allow-always", qid = id) =>
        h.send({ type: PROMPT_ANSWER_REQUEST, id: qid, choice }, sender);
    const view = get(promptUI(500));
    assert.deepEqual(view.reply, { origin: NEW });
    const ignored = [
        // A web page, a frame of the prompt page, other pages of ours, another extension.
        frame(),
        promptUI(500, { frameId: 2 }),
        promptUI(500, { url: "chrome-extension://" + ID + "/options.html" }),
        promptUI(500, { url: "chrome-extension://" + ID + "/popup.html" }),
        promptUI(500, { id: "someone-else" }),
        promptUI(500, { origin: "https://evil.example" }),
        promptUI(500, { url: "https://evil.example/prompt.html" }),
    ];
    for (const sender of ignored) {
        const r = get(sender);
        assert.equal(r.returned, undefined, JSON.stringify(sender));
        assert.equal(r.reply, undefined);
        const a = ans(sender);
        assert.equal(a.returned, undefined, JSON.stringify(sender));
        await tick();
    }
    // The right page in the wrong window, a wrong id, a made-up answer.
    assert.equal(get(promptUI(501)).reply, null);
    assert.equal(get(promptUI(500), "nope").reply, null);
    assert.equal(get(promptUI(500), 42).reply, null);
    for (const choice of ["allow", "always", "", null, 3, {}]) {
        const r = ans(promptUI(500), choice);
        await tick();
        assert.equal(r.reply, false, String(choice));
    }
    assert.equal((await ans(promptUI(501))).reply, false);
    assert.equal(
        (await ans(promptUI(500), "allow-always", "nope")).reply,
        false,
    );
    assert.deepEqual(h.stored, base());
    assert.equal(h.natives.length, 0);
    // The real window still can.
    const done = ans(promptUI(500), "deny-once");
    await tick();
    assert.equal(done.reply, true);
});

test("the question window's keep-alive port is only for the question window", async (t) => {
    const h = setup(t);
    await h.open();
    const good = port(promptUI(500), PROMPT_PORT_NAME);
    h.browser.runtime.onConnect.emit(good);
    assert.equal(good.disconnected, false);
    good.onMessage.emit({ type: "ping" });
    for (const sender of [frame(), promptUI(500, { frameId: 1 }), popupUI()]) {
        const bad = port(sender, PROMPT_PORT_NAME);
        h.browser.runtime.onConnect.emit(bad);
        assert.equal(bad.disconnected, true, JSON.stringify(sender));
    }
    // Pinging is not a way to open sockets or to answer.
    assert.equal(h.natives.length, 0);
    assert.equal(h.windows.removed.length, 0);
});

test("a settings change that does not decide the website leaves the question and the waiting socket alone", async (t) => {
    const h = setup(t);
    const p = await h.open();
    h.setSettings(base({ allowedOrigins: [MOLE, OTHER] }));
    await tick();
    assert.equal(p.disconnected, false);
    assert.deepEqual(h.windows.removed, []);
    await h.answer("allow-once");
    assert.equal(h.natives.length, 1);
});

test("deciding the website elsewhere (options page, popup) ends the question and decides the socket", async (t) => {
    const h = setup(t);
    const allowed = await h.open();
    h.setSettings(base({ allowedOrigins: [MOLE, NEW] }));
    await tick();
    assert.equal(h.natives.length, 1);
    assert.deepEqual(errors(allowed), []);
    assert.deepEqual(h.windows.removed, [500]);

    const h2 = setup(t);
    const refused = await h2.open();
    h2.setSettings(base({ deniedOrigins: [NEW] }));
    await tick();
    assert.deepEqual(errors(refused), ["not_allowed"]);
    assert.equal(h2.natives.length, 0);
    assert.deepEqual(h2.windows.removed, [500]);
});

test("taking back an allow ends its connections; an answer for this visit keeps them", async (t) => {
    const h = setup(t, { settings: base({ allowedOrigins: [MOLE, NEW] }) });
    const p = await h.open();
    const n = await h.connectNative();
    // Taking NEW off the list (back to "ask") cuts the connection.
    h.setSettings(base());
    await tick();
    assert.equal(n.disconnected, true);
    assert.equal(p.disconnected, true);
    // An allow for this visit survives unrelated changes...
    const h2 = setup(t);
    const q = await h2.open();
    await h2.answer("allow-once");
    const n2 = await h2.connectNative();
    h2.setSettings(base({ allowedOrigins: [MOLE, OTHER] }));
    await tick();
    assert.equal(n2.disconnected, false);
    assert.equal(q.disconnected, false);
    // ...but not the website being refused for good,
    h2.setSettings(
        base({ allowedOrigins: [MOLE, OTHER], deniedOrigins: [NEW] }),
    );
    await tick();
    assert.equal(n2.disconnected, true);
});

test("the popup can read what was answered for a visit and forget it, which ends its connections", async (t) => {
    const h = setup(t);
    const p = await h.open();
    await h.answer("allow-once");
    const n = await h.connectNative();
    const read = h.send({ type: VISIT_GET_REQUEST, tabId: 1 }, popupUI());
    await tick();
    assert.deepEqual(read.reply, { top: NEW, decisions: { [NEW]: "allow" } });
    // A web page cannot read it, and another tab has none.
    assert.equal(
        h.send({ type: VISIT_GET_REQUEST, tabId: 1 }, frame()).returned,
        undefined,
    );
    const empty = h.send({ type: VISIT_GET_REQUEST, tabId: 2 }, popupUI());
    await tick();
    assert.deepEqual(empty.reply, { decisions: {} });
    // A web page cannot forget answers either.
    assert.equal(
        h.send({ type: VISIT_FORGET_REQUEST, tabId: 1, origin: NEW }, frame())
            .returned,
        undefined,
    );
    assert.equal(n.disconnected, false);
    // Choosing "ask on every visit" in the popup forgets it.
    const forget = h.send(
        { type: VISIT_FORGET_REQUEST, tabId: 1, origin: NEW },
        popupUI(),
    );
    await tick();
    assert.equal(forget.reply, true);
    assert.equal(n.disconnected, true);
    assert.equal(p.disconnected, true);
    const next = await h.open();
    assert.equal(h.windows.created.length, 2);
    assert.deepEqual(next.sent, []);
    // Malformed requests do nothing.
    for (const bad of [
        { type: VISIT_FORGET_REQUEST, tabId: "1", origin: NEW },
        { type: VISIT_FORGET_REQUEST, tabId: 1, origin: 5 },
        { type: VISIT_GET_REQUEST, tabId: "1" },
    ]) {
        assert.equal(h.send(bad, popupUI()).returned, undefined);
    }
});

test("answers survive a restarted service worker", async (t) => {
    const h = setup(t);
    await h.open();
    await h.answer("allow-once");
    // A new service worker with the same session storage and settings.
    const second = setup(t, { settings: h.stored, session: h.sessionData });
    const p = await second.open();
    assert.equal(second.windows.created.length, 0);
    assert.equal(second.natives.length, 1);
    assert.deepEqual(errors(p), []);
});

test("closing a tab takes its question with it", async (t) => {
    const h = setup(t);
    const p = await h.open();
    h.browser.tabs.onRemoved.emit(1);
    await tick();
    assert.equal(p.disconnected, true);
    assert.deepEqual(h.windows.removed, [500]);
});

test("a page that navigates away from the asking site takes its question with it", async (t) => {
    const h = setup(t);
    await h.open();
    h.browser.tabs.onUpdated.emit(1, { url: OTHER + "/" });
    await tick();
    assert.deepEqual(h.windows.removed, [500]);
});

test("questions come one at a time, in order", async (t) => {
    const h = setup(t);
    const first = await h.open(frame({ origin: NEW, tab: 1 }));
    const second = await h.open(frame({ origin: OTHER, tab: 2 }));
    assert.equal(h.windows.created.length, 1);
    await h.answer("allow-once");
    assert.equal(h.windows.created.length, 2);
    assert.equal(h.natives.length, 1);
    await h.answer("deny-once", 501);
    assert.deepEqual(errors(second), ["not_allowed"]);
    assert.deepEqual(errors(first), []);
});

const CUSTOM = (extra = {}) =>
    base({
        mode: "websocket",
        proxyUrl: "ws://127.0.0.1:1/connect?host={host}&port={port}&token=t",
        proxyOrigins: [MOLE],
        ...extra,
    });

test("an unanswered question does not use up the connection slots of allowed sites", async (t) => {
    const h = setup(t);
    // One unlisted website: two frames with eight sockets each, and a question nobody answers.
    const pages = [];
    for (const frameId of [0, 1]) {
        for (let i = 0; i < MAX_FRAME_SOCKETS; i++) {
            pages.push(await h.open(frame({ frameId })));
        }
    }
    assert.equal(h.windows.created.length, 1);
    const refused = pages.filter((p) => errors(p).includes("socket_limit"));
    // A few wait for the answer; the rest were refused on the spot.
    assert.equal(pages.length - refused.length, MAX_TAB_ASKING_SOCKETS);
    assert.ok(refused.every((p) => p.disconnected));
    // An allowed game site in another tab connects as usual.
    const mole = await h.open(frame({ origin: MOLE, tab: 3 }));
    assert.deepEqual(errors(mole), []);
    assert.equal(h.natives.length, 1);
    await h.connectNative();
    assert.deepEqual(mole.sent, [{ type: "opened" }]);
});

test("waiting sockets are limited per tab and in all, and hold no slot", async (t) => {
    const h = setup(t);
    const waiting = (pages) =>
        pages.filter((p) => !p.disconnected && errors(p).length === 0);
    const tabs = [];
    // Each tab asks about its own website, so each has its own question.
    for (let tab = 1; tab <= 3; tab++) {
        const pages = [];
        for (let i = 0; i < MAX_TAB_ASKING_SOCKETS + 2; i++) {
            pages.push(
                await h.open(
                    frame({
                        origin: `https://site${tab}.example`,
                        tab,
                        frameId: i % 2,
                    }),
                ),
            );
        }
        tabs.push(pages);
    }
    assert.equal(waiting(tabs[0]).length, MAX_TAB_ASKING_SOCKETS);
    assert.equal(waiting(tabs[1]).length, MAX_TAB_ASKING_SOCKETS);
    // Eight wait in all (MAX_ASKING_SOCKETS); the third tab gets none.
    assert.equal(MAX_ASKING_SOCKETS, 2 * MAX_TAB_ASKING_SOCKETS);
    assert.equal(waiting(tabs[2]).length, 0);
    assert.ok(tabs[2].every((p) => errors(p).includes("socket_limit")));
    // None of them counts against the connection slots: a full pool of
    // allowed sockets still fits next to them.
    const connected = [];
    for (
        let frameId = 0;
        frameId < MAX_GLOBAL_SOCKETS / MAX_FRAME_SOCKETS;
        frameId++
    ) {
        for (let i = 0; i < MAX_FRAME_SOCKETS; i++) {
            connected.push(
                await h.open(frame({ origin: MOLE, tab: 9, frameId })),
            );
        }
    }
    assert.equal(connected.length, MAX_GLOBAL_SOCKETS);
    assert.ok(connected.every((p) => errors(p).length === 0));
    // The pool is now full: one more is refused, as it always was...
    assert.deepEqual(
        errors(await h.open(frame({ origin: MOLE, tab: 9, frameId: 5 }))),
        ["socket_limit"],
    );
    // ...and so is the helper check of the options page.
    const probe = h.send({ type: HELPER_STATUS_REQUEST }, popupUI());
    await tick();
    assert.deepEqual(probe.reply, { installed: false, error: "socket_limit" });
});

test("a socket whose question is answered while every slot is taken is refused, not left waiting", async (t) => {
    const h = setup(t);
    const waiting = await h.open();
    assert.equal(h.windows.created.length, 1);
    for (
        let frameId = 0;
        frameId < MAX_GLOBAL_SOCKETS / MAX_FRAME_SOCKETS;
        frameId++
    ) {
        for (let i = 0; i < MAX_FRAME_SOCKETS; i++) {
            await h.open(frame({ origin: MOLE, tab: 2, frameId }));
        }
    }
    assert.equal(h.natives.length, MAX_GLOBAL_SOCKETS);
    await h.answer("allow-once");
    assert.deepEqual(errors(waiting), ["socket_limit"]);
    assert.equal(waiting.disconnected, true);
    assert.equal(h.natives.length, MAX_GLOBAL_SOCKETS);
});

test("a socket that is allowed at once is not refused because others started to wait", async (t) => {
    const h = setup(t);
    for (let i = 0; i < MAX_TAB_ASKING_SOCKETS; i++) {
        await h.open(frame({ origin: NEW, tab: 1, frameId: i }));
    }
    const mole = [];
    for (let i = 0; i < MAX_FRAME_SOCKETS; i++) {
        mole.push(await h.open(frame({ origin: MOLE, tab: 2 })));
    }
    assert.ok(mole.every((p) => errors(p).length === 0));
    assert.equal(h.natives.length, MAX_FRAME_SOCKETS);
});

test("switching to a custom proxy while a question is open ends it and refuses the socket", async (t) => {
    const h = setup(t);
    const p = await h.open();
    assert.equal(h.windows.created.length, 1);
    h.setSettings(CUSTOM());
    await tick();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.deepEqual(h.windows.removed, [500]);
    assert.equal(h.natives.length, 0);
    // The stale window cannot answer any more.
    const late = await h.answer("allow-always");
    assert.equal(late.reply, false);
    assert.deepEqual(h.stored, CUSTOM());
});

test("an answer that arrives before the mode change does is not stored in the new mode", async (t) => {
    const h = setup(t);
    const p = await h.open();
    // The new settings are stored but the change has not been announced yet.
    h.quietlyStore(CUSTOM());
    const reply = await h.answer("allow-always");
    assert.equal(reply.reply, false);
    assert.deepEqual(h.stored, CUSTOM());
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.natives.length, 0);
    assert.deepEqual(h.windows.removed, [500]);
});

test("the mode is checked again at the moment the answer is stored", async (t) => {
    const h = setup(t);
    await h.open();
    // The settings change lands between "still asking?" and the write.
    let reads = 0;
    const realGet = h.browser.storage.local.get;
    h.browser.storage.local.get = async (...args) => {
        const result = await realGet(...args);
        if (++reads === 1) {
            h.quietlyStore(CUSTOM());
        }
        return result;
    };
    const reply = await h.answer("allow-always");
    assert.equal(reply.reply, false);
    assert.deepEqual(h.stored, CUSTOM());
});

test("a website allowed for the helper does not get the custom proxy afterwards", async (t) => {
    const h = setup(t);
    await h.open();
    await h.answer("allow-always");
    assert.deepEqual(h.stored.allowedOrigins, [MOLE, NEW]);
    // The owner now switches to a custom proxy, keeping the stored lists.
    h.setSettings({
        ...h.stored,
        ...CUSTOM(),
        allowedOrigins: h.stored.allowedOrigins,
    });
    await tick();
    const p = await h.open(frame({ tab: 2 }));
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.windows.created.length, 1);
});

test("turning the player off ends the question and the waiting sockets", async (t) => {
    const h = setup(t);
    const p = await h.open();
    h.setPlayer(false);
    await tick();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.deepEqual(h.windows.removed, [500]);
});

test("a tab that is replaced by another takes its question with it", async (t) => {
    const h = setup(t);
    const p = await h.open();
    h.browser.tabs.onReplaced.emit(2, 1);
    await tick();
    assert.equal(p.disconnected, true);
    assert.deepEqual(h.windows.removed, [500]);
});

test("a browser build that cannot reach the helper does not ask a question it cannot honour", async (t) => {
    const h = setup(t);
    h.browser.runtime.connectNative = undefined;
    const p = await h.open();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.windows.created.length, 0);
});

test("a browser without windows still allows listed sites and refuses the rest", async (t) => {
    const h = setup(t, { noWindows: true });
    const mole = await h.open(frame({ origin: MOLE }));
    assert.deepEqual(errors(mole), []);
    assert.equal(h.natives.length, 1);
    // Without a way to ask, the unlisted website is refused rather than left waiting.
    const p = await h.open();
    assert.deepEqual(errors(p), ["not_allowed"]);
    // A browser that has windows but not their events does not break either.
    const g = setup(t);
    g.browser.windows.onRemoved = undefined;
    assert.doesNotThrow(() => registerSocketBridge());
});

test("senders without an origin (Firefox) work like the others, and framed pages still do not", async (t) => {
    const h = setup(t);
    const noOrigin = (sender) => ({ ...sender, origin: undefined });
    const p = await h.open(noOrigin(frame()));
    assert.equal(h.windows.created.length, 1);
    assert.deepEqual(errors(p), []);
    const id = h.promptId();
    const view = h.send(
        { type: PROMPT_GET_REQUEST, id },
        noOrigin(promptUI(500)),
    );
    assert.deepEqual(view.reply, { origin: NEW });
    const framed = h.send(
        { type: PROMPT_GET_REQUEST, id },
        noOrigin(promptUI(500, { frameId: 3 })),
    );
    assert.equal(framed.returned, undefined);
    const read = h.send(
        { type: VISIT_GET_REQUEST, tabId: 1 },
        noOrigin(popupUI()),
    );
    await tick();
    // Nothing was answered for this visit yet; the tab's site is known.
    assert.deepEqual(read.reply, { top: NEW, decisions: {} });
});

test("a settings change that arrives before earlier answers are loaded still takes effect", async (t) => {
    const h = setup(t, {
        settings: base({ allowedOrigins: [MOLE, NEW] }),
        slowSession: true,
    });
    // The page connects while the session answers are still being loaded:
    // allowed sockets must not wait for that, so open the socket first.
    const p = port(frame());
    h.browser.runtime.onConnect.emit(p);
    p.onMessage.emit({ type: "open", host: "public.example", port: 1234 });
    await tick();
    h.setSettings(base({ allowedOrigins: [MOLE], deniedOrigins: [NEW] }));
    await tick();
    h.releaseSession();
    await tick();
    await tick();
    assert.deepEqual(errors(p), ["not_allowed"]);
    assert.equal(h.natives.length, 0);
});
