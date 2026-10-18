import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import {
    createPromptManager,
    MAX_PROMPTS_PER_TAB,
    MAX_QUEUED_PROMPTS,
} from "../src/socket-prompt.ts";

const { AbortController } = globalThis;
const tick = () => new Promise((r) => setImmediate(r));
const A = "https://a.example";
const B = "https://b.example";
const TOP = "https://portal.example";

function setup({ failOpen = false, slowOpen = false } = {}) {
    let nextWindow = 100;
    let releaseOpen;
    const host = {
        opened: [],
        closed: [],
        async open(id, near) {
            if (failOpen) {
                throw new Error("no window");
            }
            const windowId = nextWindow++;
            host.opened.push({ id, near, windowId });
            if (slowOpen) {
                await new Promise((resolve) => (releaseOpen = resolve));
            }
            return windowId;
        },
        async close(windowId) {
            host.closed.push(windowId);
        },
    };
    const effects = {
        remembered: [],
        visits: [],
        counts: new Map(),
        async remember(origin, choice) {
            this.remembered.push([origin, choice]);
        },
        async recordVisit(tabId, origin, decision, top) {
            this.visits.push([tabId, origin, decision, top]);
        },
        async countPrompt(tabId) {
            const n = (this.counts.get(tabId) ?? 0) + 1;
            this.counts.set(tabId, n);
            return n;
        },
    };
    const manager = createPromptManager(host, effects);
    const results = [];
    const ask = (request, signal = new AbortController().signal) => {
        const slot = { outcome: undefined };
        results.push(slot);
        manager
            .ask(
                { origin: A, tabId: 1, frameId: 0, top: A, ...request },
                signal,
            )
            .then((outcome) => (slot.outcome = outcome));
        return slot;
    };
    return {
        host,
        effects,
        manager,
        ask,
        release: () => releaseOpen(),
    };
}

test("one question per website: asking opens a window, the answer is stored and the window closes", async () => {
    const h = setup();
    const waiter = h.ask({});
    await tick();
    assert.equal(h.host.opened.length, 1);
    const { id, windowId } = h.host.opened[0];
    assert.deepEqual(h.manager.view(id, windowId), { origin: A });
    assert.equal(waiter.outcome, undefined);
    assert.equal(await h.manager.answer(id, windowId, "allow-always"), true);
    await tick();
    assert.deepEqual(h.effects.remembered, [[A, "allow"]]);
    assert.deepEqual(h.effects.visits, []);
    assert.equal(waiter.outcome, "answered");
    assert.deepEqual(h.host.closed, [windowId]);
    // The question is gone: a second answer (or a replay) does nothing.
    assert.equal(h.manager.view(id, windowId), undefined);
    assert.equal(await h.manager.answer(id, windowId, "deny-always"), false);
    assert.equal(h.effects.remembered.length, 1);
});

test("each of the four answers is stored as what it says", async () => {
    for (const [choice, remembered, visit] of [
        ["allow-always", [[A, "allow"]], []],
        ["deny-always", [[A, "deny"]], []],
        ["allow-once", [], [[1, A, "allow", A]]],
        ["deny-once", [], [[1, A, "deny", A]]],
    ]) {
        const h = setup();
        h.ask({});
        await tick();
        const { id, windowId } = h.host.opened[0];
        assert.equal(await h.manager.answer(id, windowId, choice), true);
        assert.deepEqual(h.effects.remembered, remembered, choice);
        assert.deepEqual(h.effects.visits, visit, choice);
    }
});

test("a website that is already being asked about shares the question", async () => {
    const h = setup();
    const first = h.ask({ tabId: 1, top: A });
    const second = h.ask({ tabId: 2, top: TOP, frameId: 3 });
    const third = h.ask({ tabId: 2, top: TOP, frameId: 3 });
    await tick();
    assert.equal(h.host.opened.length, 1);
    // One window is one count, charged to the tab that asked first.
    assert.equal(h.effects.counts.get(1), 1);
    assert.equal(h.effects.counts.get(2), undefined);
    const { id, windowId } = h.host.opened[0];
    // "This visit" applies to every tab that asked.
    await h.manager.answer(id, windowId, "allow-once");
    await tick();
    assert.deepEqual(h.effects.visits, [
        [1, A, "allow", A],
        [2, A, "allow", TOP],
    ]);
    assert.deepEqual(
        [first, second, third].map((slot) => slot.outcome),
        ["answered", "answered", "answered"],
    );
});

test("only one question is open; the next website waits for its turn", async () => {
    const h = setup();
    const a = h.ask({ origin: A });
    const b = h.ask({ origin: B, tabId: 2 });
    await tick();
    assert.equal(h.host.opened.length, 1);
    const first = h.host.opened[0];
    assert.equal(h.manager.view(first.id, first.windowId).origin, A);
    await h.manager.answer(first.id, first.windowId, "deny-once");
    await tick();
    assert.equal(a.outcome, "answered");
    assert.equal(h.host.opened.length, 2);
    const second = h.host.opened[1];
    assert.equal(h.manager.view(second.id, second.windowId).origin, B);
    assert.equal(b.outcome, undefined);
    // The old window's id does not answer the new question.
    assert.equal(
        await h.manager.answer(second.id, first.windowId, "allow-always"),
        false,
    );
    assert.equal(
        await h.manager.answer(first.id, second.windowId, "allow-always"),
        false,
    );
    assert.deepEqual(h.effects.remembered, []);
});

test("an answer needs the right question, window and a known choice", async () => {
    const h = setup();
    h.ask({});
    await tick();
    const { id, windowId } = h.host.opened[0];
    for (const [qid, wid, choice] of [
        ["other", windowId, "allow-always"],
        [id, windowId + 1, "allow-always"],
        [id, undefined, "allow-always"],
        [id, windowId, "always-allow"],
        [id, windowId, "allow"],
        [id, windowId, undefined],
    ]) {
        assert.equal(await h.manager.answer(qid, wid, choice), false);
        assert.equal(
            h.manager.view(qid, wid)?.origin,
            qid === id && wid === windowId ? A : undefined,
        );
    }
    assert.deepEqual(h.effects.remembered, []);
    assert.deepEqual(h.effects.visits, []);
    // The question is still open for the real window.
    assert.equal(h.manager.view(id, windowId).origin, A);
});

test("the page may ask for the text a moment before the window id is known", async () => {
    const h = setup({ slowOpen: true });
    h.ask({});
    await tick();
    const { id, windowId } = h.host.opened[0];
    // The browser has not returned from windows.create yet.
    assert.equal(h.manager.view(id, windowId).origin, A);
    assert.equal(h.manager.view(id, undefined), undefined);
    // It cannot be answered before that.
    assert.equal(await h.manager.answer(id, windowId, "allow-always"), false);
    h.release();
    await tick();
    assert.equal(await h.manager.answer(id, windowId, "allow-always"), true);
});

test("a frame in another site's page says where it is embedded", async () => {
    const h = setup();
    h.ask({ origin: B, frameId: 4, top: TOP });
    h.ask({ origin: A, frameId: 0, top: A, tabId: 2 });
    await tick();
    const first = h.host.opened[0];
    assert.deepEqual(h.manager.view(first.id, first.windowId), {
        origin: B,
        embeddedIn: TOP,
    });
    await h.manager.answer(first.id, first.windowId, "deny-once");
    await tick();
    const second = h.host.opened[1];
    assert.deepEqual(h.manager.view(second.id, second.windowId), {
        origin: A,
    });
});

test("closing the window refuses for this visit and releases everyone", async () => {
    const h = setup();
    const a = h.ask({ tabId: 1 });
    const b = h.ask({ tabId: 2, top: TOP });
    await tick();
    const { id, windowId } = h.host.opened[0];
    h.manager.windowRemoved(windowId);
    await tick();
    assert.deepEqual(h.effects.visits, [
        [1, A, "deny", A],
        [2, A, "deny", TOP],
    ]);
    assert.deepEqual([a.outcome, b.outcome], ["dismissed", "dismissed"]);
    // The browser already closed the window; nothing closes it twice.
    assert.deepEqual(h.host.closed, []);
    assert.equal(await h.manager.answer(id, windowId, "allow-always"), false);
    assert.equal(h.manager.view(id, windowId), undefined);
    // Windows we never opened are none of its business.
    h.manager.windowRemoved(9999);
});

test("a window closed after the answer changes nothing", async () => {
    const h = setup();
    h.ask({});
    await tick();
    const { id, windowId } = h.host.opened[0];
    await h.manager.answer(id, windowId, "allow-once");
    h.manager.windowRemoved(windowId);
    await tick();
    assert.deepEqual(h.effects.visits, [[1, A, "allow", A]]);
});

test("a withdrawn waiter stops waiting but leaves an open question open", async () => {
    const h = setup();
    const gone = new AbortController();
    const stays = new AbortController();
    const a = h.ask({ tabId: 1 }, gone.signal);
    const b = h.ask({ tabId: 2 }, stays.signal);
    await tick();
    gone.abort();
    await tick();
    assert.equal(a.outcome, "dismissed");
    assert.equal(b.outcome, undefined);
    assert.deepEqual(h.host.closed, []);
    // Even the last waiter leaving does not take the question away from the user...
    stays.abort();
    await tick();
    assert.equal(b.outcome, "dismissed");
    assert.deepEqual(h.host.closed, []);
    // ...and the answer still counts for the tabs that asked.
    const { id, windowId } = h.host.opened[0];
    await h.manager.answer(id, windowId, "allow-once");
    assert.deepEqual(h.effects.visits, [
        [1, A, "allow", A],
        [2, A, "allow", A],
    ]);
});

test("a question nobody waits for any more is never shown", async () => {
    const h = setup();
    h.ask({ origin: A });
    const gone = new AbortController();
    const queued = h.ask({ origin: B, tabId: 2 }, gone.signal);
    await tick();
    gone.abort();
    await tick();
    assert.equal(queued.outcome, "dismissed");
    const { id, windowId } = h.host.opened[0];
    await h.manager.answer(id, windowId, "deny-once");
    await tick();
    assert.equal(h.host.opened.length, 1);
    // Asking after the signal was aborted does not even count.
    const late = h.ask({ origin: B, tabId: 3 }, gone.signal);
    await tick();
    assert.equal(late.outcome, "dismissed");
    assert.equal(h.host.opened.length, 1);
});

test("a tab that closes or leaves takes its part of the question with it", async () => {
    const h = setup();
    const a = h.ask({ tabId: 1 });
    const b = h.ask({ tabId: 2 });
    await tick();
    const { id, windowId } = h.host.opened[0];
    h.manager.tabGone(1);
    await tick();
    assert.equal(a.outcome, "dismissed");
    assert.equal(b.outcome, undefined);
    assert.deepEqual(h.host.closed, []);
    // The answer no longer applies to the tab that is gone.
    await h.manager.answer(id, windowId, "allow-once");
    assert.deepEqual(h.effects.visits, [[2, A, "allow", A]]);

    const g = setup();
    const only = g.ask({ tabId: 5 });
    await tick();
    g.manager.tabGone(5);
    await tick();
    assert.equal(only.outcome, "dismissed");
    assert.deepEqual(g.host.closed, [g.host.opened[0].windowId]);
    assert.deepEqual(g.effects.visits, []);
    // The next question can use the freed turn.
    const next = g.ask({ origin: B, tabId: 6 });
    await tick();
    assert.equal(g.host.opened.length, 2);
    assert.equal(next.outcome, undefined);
});

test("a question that was answered elsewhere ends by itself", async () => {
    const h = setup();
    const a = h.ask({ origin: A });
    const b = h.ask({ origin: B, tabId: 2 });
    await tick();
    const settings = (allowedOrigins, deniedOrigins = []) => ({
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins,
        deniedOrigins,
    });
    // Unrelated change: both questions stay.
    h.manager.settingsChanged(settings(["https://other.example"]));
    await tick();
    assert.equal(a.outcome, undefined);
    assert.equal(h.host.closed.length, 0);
    // A is decided (e.g. in the options page), B is still open for the user.
    h.manager.settingsChanged(settings([A]));
    await tick();
    assert.equal(a.outcome, "answered");
    assert.deepEqual(h.host.closed, [h.host.opened[0].windowId]);
    // B is queued and now shown; deciding it ends it too, without being shown twice.
    assert.equal(h.host.opened.length, 2);
    h.manager.settingsChanged(settings([A], [B]));
    await tick();
    assert.equal(b.outcome, "answered");
    assert.equal(h.host.opened.length, 2);
    // Sockets switched off end every question.
    const c = h.ask({ origin: "https://c.example", tabId: 3 });
    await tick();
    h.manager.settingsChanged({ ...settings([]), enabled: false });
    await tick();
    assert.equal(c.outcome, "answered");
});

test("a tab can only cause a few windows per visit", async () => {
    const h = setup();
    for (let i = 0; i < MAX_PROMPTS_PER_TAB; i++) {
        const slot = h.ask({ origin: `https://site${i}.example` });
        await tick();
        const { id, windowId } = h.host.opened.at(-1);
        await h.manager.answer(id, windowId, "deny-once");
        await tick();
        assert.equal(slot.outcome, "answered");
    }
    const over = h.ask({ origin: "https://one-too-many.example" });
    await tick();
    assert.equal(over.outcome, "unavailable");
    assert.equal(h.host.opened.length, MAX_PROMPTS_PER_TAB);
    // Another tab has its own budget.
    const other = h.ask({ origin: "https://one-too-many.example", tabId: 2 });
    await tick();
    assert.equal(other.outcome, undefined);
    assert.equal(h.host.opened.length, MAX_PROMPTS_PER_TAB + 1);
});

test("a flood of websites queues a few and refuses the rest", async () => {
    const h = setup();
    const slots = [];
    for (let i = 0; i < MAX_QUEUED_PROMPTS + 6; i++) {
        slots.push(
            h.ask({ origin: `https://site${i}.example`, tabId: 100 + i }),
        );
        await tick();
    }
    assert.equal(h.host.opened.length, 1);
    const refused = slots.filter((slot) => slot.outcome === "unavailable");
    // One is shown, MAX_QUEUED_PROMPTS wait, the others are refused.
    assert.equal(refused.length, slots.length - 1 - MAX_QUEUED_PROMPTS);
    assert.equal(
        slots.filter((slot) => slot.outcome === undefined).length,
        MAX_QUEUED_PROMPTS + 1,
    );
});

test("when no window can be opened nobody is left waiting", async () => {
    const h = setup({ failOpen: true });
    const a = h.ask({ origin: A });
    const b = h.ask({ origin: B, tabId: 2 });
    await tick();
    await tick();
    assert.equal(a.outcome, "unavailable");
    assert.equal(b.outcome, "unavailable");
    assert.deepEqual(h.effects.visits, []);
    assert.deepEqual(h.effects.remembered, []);
});

test("a failed bookkeeping step refuses instead of guessing", async () => {
    const h = setup();
    h.effects.remember = async () => {
        throw new Error("storage");
    };
    const a = h.ask({});
    await tick();
    const { id, windowId } = h.host.opened[0];
    assert.equal(await h.manager.answer(id, windowId, "allow-always"), false);
    await tick();
    assert.equal(a.outcome, "unavailable");
    assert.deepEqual(h.host.closed, [windowId]);

    const g = setup();
    g.effects.countPrompt = async () => {
        throw new Error("storage");
    };
    const b = g.ask({});
    await tick();
    assert.equal(b.outcome, "unavailable");
    assert.equal(g.host.opened.length, 0);
});

test("a window that finishes opening after the question ended is closed again", async () => {
    const h = setup({ slowOpen: true });
    const a = h.ask({});
    await tick();
    h.manager.tabGone(1);
    await tick();
    assert.equal(a.outcome, "dismissed");
    h.release();
    await tick();
    assert.deepEqual(h.host.closed, [h.host.opened[0].windowId]);
});

test("disposing releases every waiter", async () => {
    const h = setup();
    const a = h.ask({ origin: A });
    const b = h.ask({ origin: B, tabId: 2 });
    await tick();
    h.manager.dispose();
    await tick();
    assert.deepEqual([a.outcome, b.outcome], ["dismissed", "dismissed"]);
    assert.equal(h.host.opened.length, 1);
});
