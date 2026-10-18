import test from "node:test";
import assert from "node:assert/strict";
import { createVisitStore, MAX_VISIT_ORIGINS } from "../src/socket-visit.ts";

const A = "https://a.example";
const B = "https://b.example";
const TOP = "https://portal.example";

/** An in-memory stand-in for browser.storage.session. */
function area(initial = {}) {
    const data = { ...initial };
    return {
        data,
        writes: 0,
        async get() {
            return { ...data };
        },
        async set(items) {
            this.writes++;
            Object.assign(data, JSON.parse(JSON.stringify(items)));
        },
        async remove(keys) {
            this.writes++;
            for (const key of [keys].flat()) {
                delete data[key];
            }
        },
    };
}

test("an answer belongs to one tab and one website", async () => {
    const store = createVisitStore(area());
    await store.record(1, A, "allow", TOP);
    await store.record(1, B, "deny", TOP);
    await store.record(2, A, "deny");
    assert.equal(store.decision(1, A), "allow");
    assert.equal(store.decision(1, B), "deny");
    assert.equal(store.decision(2, A), "deny");
    assert.equal(store.decision(2, B), undefined);
    assert.equal(store.decision(3, A), undefined);
    assert.equal(store.get(1).top, TOP);
    assert.equal(store.get(2).top, undefined);
});

test("answers survive a restarted service worker, not a restarted browser", async () => {
    const session = area();
    const first = createVisitStore(session);
    await first.record(7, A, "allow", TOP);
    await first.countPrompt(7, TOP);
    // A new service worker reads the same session storage.
    const second = createVisitStore(session);
    assert.equal(second.hydrated, false);
    await second.ready;
    assert.equal(second.hydrated, true);
    assert.equal(second.decision(7, A), "allow");
    assert.equal(second.get(7).prompts, 1);
    assert.equal(second.get(7).top, TOP);
    // A browser restart empties session storage.
    const third = createVisitStore(area());
    await third.ready;
    assert.equal(third.decision(7, A), undefined);
});

test("without session storage answers last as long as the service worker", async () => {
    const store = createVisitStore(undefined);
    assert.equal(store.hydrated, true);
    await store.record(1, A, "deny");
    assert.equal(store.decision(1, A), "deny");
});

test("an answer recorded during start-up wins over a stored one", async () => {
    const session = area({
        "socketVisit:1": {
            decisions: { [A]: "deny" },
            prompts: 0,
        },
    });
    const store = createVisitStore(session);
    await store.record(1, A, "allow");
    await store.ready;
    assert.equal(store.decision(1, A), "allow");
});

test("damaged stored data is ignored, valid entries around it are kept", async () => {
    const session = area({
        "socketVisit:1": { decisions: { [A]: "allow" }, prompts: 2, top: TOP },
        "socketVisit:2": "nonsense",
        "socketVisit:3": { decisions: [], prompts: -1 },
        "socketVisit:x": { decisions: {}, prompts: 0 },
        "socketVisit:4": {
            decisions: {
                "https://evil.example/path": "allow",
                [B]: "maybe",
                "not an origin": "allow",
                [A]: "deny",
            },
            prompts: 0,
            top: "javascript:alert(1)",
        },
        unrelated: { decisions: { [A]: "allow" }, prompts: 0 },
    });
    const store = createVisitStore(session);
    await store.ready;
    assert.equal(store.decision(1, A), "allow");
    assert.equal(store.get(2), undefined);
    assert.equal(store.get(3), undefined);
    assert.deepEqual(store.get(4).decisions, { [A]: "deny" });
    assert.equal(store.get(4).top, undefined);
    assert.equal(store.get(NaN), undefined);
});

test("unreadable session storage means no earlier answers", async () => {
    const broken = {
        async get() {
            throw new Error("denied");
        },
        async set() {
            throw new Error("denied");
        },
        async remove() {
            throw new Error("denied");
        },
    };
    const store = createVisitStore(broken);
    await store.ready;
    assert.equal(store.hydrated, true);
    // Memory still works when writing fails.
    await store.record(1, A, "allow");
    assert.equal(store.decision(1, A), "allow");
});

test("forgetting one website keeps the others; forgetting the tab keeps nothing", async () => {
    const session = area();
    const store = createVisitStore(session);
    await store.record(1, A, "allow", TOP);
    await store.record(1, B, "allow", TOP);
    await store.forget(1, A);
    assert.equal(store.decision(1, A), undefined);
    assert.equal(store.decision(1, B), "allow");
    await store.forget(1);
    assert.equal(store.get(1), undefined);
    assert.deepEqual(Object.keys(session.data), []);
    // Forgetting what is not there does nothing.
    const before = session.writes;
    await store.forget(9);
    await store.forget(9, A);
    assert.equal(session.writes, before);
});

test("answers end when the tab goes to another site, not within the same one", async () => {
    const store = createVisitStore(area());
    await store.record(1, A, "allow", TOP);
    // Same site, another page (and same-document navigations).
    assert.equal(await store.leftSite(1, TOP), false);
    assert.equal(store.decision(1, A), "allow");
    // Another site.
    assert.equal(await store.leftSite(1, "https://elsewhere.example"), true);
    assert.equal(store.get(1), undefined);
    // Nothing to forget for a tab without answers.
    assert.equal(await store.leftSite(1, TOP), false);
    // Without a known site there is no way to tell, so the answers end.
    await store.record(2, A, "allow");
    assert.equal(await store.leftSite(2, TOP), true);
    assert.equal(store.get(2), undefined);
    // A site that becomes known later is remembered from then on.
    await store.record(3, A, "allow");
    await store.countPrompt(3, TOP);
    assert.equal(store.get(3).top, TOP);
    assert.equal(await store.leftSite(3, TOP), false);
});

test("a tab's prompt count grows and its answers have a ceiling", async () => {
    const store = createVisitStore(area());
    assert.equal(await store.countPrompt(1, TOP), 1);
    assert.equal(await store.countPrompt(1, TOP), 2);
    assert.equal(await store.countPrompt(2, TOP), 1);
    for (let i = 0; i < MAX_VISIT_ORIGINS + 5; i++) {
        await store.record(1, `https://site${i}.example`, "allow", TOP);
    }
    assert.equal(Object.keys(store.get(1).decisions).length, MAX_VISIT_ORIGINS);
    // A website that already has an answer can still change it.
    await store.record(1, "https://site0.example", "deny", TOP);
    assert.equal(store.decision(1, "https://site0.example"), "deny");
});
