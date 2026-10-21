// "Install the socket helper first": the window that opens when a game needed a TCP connection and the helper is not there.
import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import {
    MAX_HELPER_PROMPTS_PER_MINUTE,
    MAX_TOLD_DOCUMENTS,
    createHelperPromptManager,
    createToldDocuments,
    isHelperPromptView,
} from "../src/helper-prompt.ts";

const MOLE = "https://mole.61.com.tw";
const PORTAL = "https://portal.example";
const tick = () => new Promise((resolve) => setImmediate(resolve));

/** An in-memory stand-in for browser.storage.session. */
function area(initial = {}) {
    const data = { ...initial };
    return {
        data,
        fail: false,
        async get() {
            if (this.fail) {
                throw new Error("unreadable");
            }
            return JSON.parse(JSON.stringify(data));
        },
        async set(items) {
            if (this.fail) {
                throw new Error("unwritable");
            }
            Object.assign(data, JSON.parse(JSON.stringify(items)));
        },
        async remove() {},
    };
}

/** A browser that opens numbered windows; `holdOpen` makes the next open wait until `release` is called. */
function host() {
    const state = {
        opened: [],
        closed: [],
        next: 700,
        fail: false,
        release: undefined,
    };
    return {
        state,
        async open(id, near) {
            state.opened.push({ id, near });
            if (state.fail) {
                throw new Error("no windows");
            }
            const windowId = state.next++;
            if (state.hold) {
                await new Promise((resolve) => (state.release = resolve));
            }
            return windowId;
        },
        async close(windowId) {
            state.closed.push(windowId);
        },
    };
}

function setup({ session, clock = { now: 1_000_000 } } = {}) {
    const fake = host();
    const told = createToldDocuments(session);
    const manager = createHelperPromptManager(fake, told, () => clock.now);
    return { fake, told, manager, clock };
}
const request = (overrides = {}) => ({
    problem: "missing",
    origin: MOLE,
    tabId: 1,
    frameId: 0,
    documentId: "doc-1",
    windowId: 10,
    ...overrides,
});

test("a game that needs the helper gets a window next to its own, which says whose connection it was", async () => {
    const { fake, manager } = setup();
    assert.equal(await manager.show(request()), true);
    assert.equal(fake.state.opened.length, 1);
    const { id, near } = fake.state.opened[0];
    assert.equal(near, 10);
    assert.match(id, /^[0-9a-f-]{36}$/u);
    // Only the window the browser opened for it is told what to show.
    assert.deepEqual(manager.view(id, 700), {
        helper: "missing",
        origin: MOLE,
    });
    assert.equal(manager.view(id, 701), undefined);
    assert.equal(manager.view(id, undefined), undefined);
    assert.equal(manager.view("other", 700), undefined);
});

test("a helper that is there but not the right one is told apart from one that is missing", async () => {
    const { fake, manager } = setup();
    await manager.show(request({ problem: "incompatible" }));
    assert.equal(
        manager.view(fake.state.opened[0].id, 700)?.helper,
        "incompatible",
    );
});

test("a frame in a page of another site is shown with that page's origin; a frame of its own page is not", async () => {
    const embedded = setup();
    await embedded.manager.show(request({ frameId: 3, top: PORTAL }));
    assert.deepEqual(
        embedded.manager.view(embedded.fake.state.opened[0].id, 700),
        {
            helper: "missing",
            origin: MOLE,
            embeddedIn: PORTAL,
        },
    );
    for (const overrides of [
        { frameId: 3, top: MOLE },
        { frameId: 0, top: PORTAL },
        { frameId: 3 },
    ]) {
        const own = setup();
        await own.manager.show(request(overrides));
        assert.equal(
            own.manager.view(own.fake.state.opened[0].id, 700)?.embeddedIn,
            undefined,
            JSON.stringify(overrides),
        );
    }
});

test("sockets that fail together share one window", async () => {
    const { fake, manager } = setup();
    const results = await Promise.all([
        manager.show(request()),
        manager.show(
            request({ origin: PORTAL, tabId: 2, documentId: "doc-2" }),
        ),
        manager.show(request()),
    ]);
    assert.deepEqual(results, [true, false, false]);
    assert.equal(fake.state.opened.length, 1);
});

test("a page load is told once, even after its window was closed; another page load is told again", async () => {
    const { fake, manager } = setup();
    assert.equal(await manager.show(request()), true);
    manager.windowRemoved(700);
    assert.equal(await manager.show(request()), false, "same page load");
    assert.equal(
        await manager.show(request({ documentId: "doc-2" })),
        true,
        "reloaded page",
    );
    manager.windowRemoved(701);
    assert.equal(
        await manager.show(request({ tabId: 2 })),
        true,
        "the same document id in another tab is another page load",
    );
    assert.equal(fake.state.opened.length, 3);
});

test("without a document id a frame of one origin in one tab counts as one page load", async () => {
    const { manager } = setup();
    const bare = (overrides) =>
        request({ documentId: undefined, ...overrides });
    assert.equal(await manager.show(bare()), true);
    manager.windowRemoved(700);
    assert.equal(await manager.show(bare()), false);
    assert.equal(await manager.show(bare({ frameId: 2 })), true);
    manager.windowRemoved(701);
    assert.equal(await manager.show(bare({ origin: PORTAL })), true);
});

test("only a few windows open per minute, and a page load that was turned away is not remembered", async () => {
    const { fake, manager, clock } = setup();
    for (let tab = 1; tab <= MAX_HELPER_PROMPTS_PER_MINUTE; tab++) {
        assert.equal(
            await manager.show(request({ tabId: tab })),
            true,
            String(tab),
        );
        manager.windowRemoved(699 + tab);
    }
    const late = request({ tabId: 9, documentId: "late" });
    assert.equal(await manager.show(late), false);
    clock.now += 59_000;
    assert.equal(await manager.show(late), false);
    clock.now += 1_001;
    assert.equal(await manager.show(late), true);
    assert.equal(fake.state.opened.length, MAX_HELPER_PROMPTS_PER_MINUTE + 1);
});

test("a browser that cannot open the window is not asked again by every failing socket", async () => {
    const { fake, manager } = setup();
    fake.state.fail = true;
    assert.equal(await manager.show(request()), false);
    assert.equal(await manager.show(request()), false);
    assert.equal(fake.state.opened.length, 1, "the same page load tried once");
    fake.state.fail = false;
    assert.equal(
        await manager.show(request({ documentId: "doc-2" })),
        true,
        "the failure did not leave the manager stuck",
    );
});

test("a window that is closed before the browser says which window it is does not block the next", async () => {
    const { fake, manager } = setup();
    fake.state.hold = true;
    const first = manager.show(request());
    await tick();
    await tick();
    const { id } = fake.state.opened[0];
    // Closed while it was still opening.
    manager.windowRemoved(700);
    fake.state.release();
    assert.equal(await first, true);
    assert.equal(
        manager.view(id, 700),
        undefined,
        "nobody is left to show it to: the browser will not say so again",
    );
    fake.state.hold = false;
    assert.equal(await manager.show(request({ documentId: "doc-2" })), true);
});

test("a window that is still open makes way for the window of the next page load, and its own page load keeps it", async () => {
    const { fake, manager } = setup();
    await manager.show(request());
    const first = fake.state.opened[0].id;
    assert.equal(await manager.show(request()), false, "the same page load");
    assert.deepEqual(fake.state.closed, []);
    // Another page load (a reload, another tab): the window may be behind the browser's own, so it is replaced.
    assert.equal(await manager.show(request({ documentId: "doc-2" })), true);
    assert.deepEqual(fake.state.closed, [700]);
    const second = fake.state.opened[1].id;
    assert.equal(manager.view(first, 700), undefined);
    assert.deepEqual(manager.view(second, 701), {
        helper: "missing",
        origin: MOLE,
    });
    // The browser reports the old window gone, and some other window: the new one is not taken for either.
    manager.windowRemoved(700);
    manager.windowRemoved(12345);
    assert.ok(manager.view(second, 701));
    manager.windowRemoved(701);
    assert.equal(manager.view(second, 701), undefined);
    assert.equal(await manager.show(request({ documentId: "doc-3" })), true);
    assert.equal(fake.state.opened.length, 3);
});

test("the view can be read while the window is still being opened, and only by the window the browser says it is", async () => {
    const { fake, manager } = setup();
    fake.state.hold = true;
    const opening = manager.show(request());
    await tick();
    await tick();
    const { id } = fake.state.opened[0];
    assert.equal(
        manager.view(id, 700)?.origin,
        MOLE,
        "the page loaded before the browser replied",
    );
    assert.equal(manager.view(id, undefined), undefined);
    fake.state.release();
    assert.equal(await opening, true);
    assert.equal(manager.view(id, 700)?.origin, MOLE);
    assert.equal(manager.view(id, 701), undefined);
});

test("the window of a closed tab goes with it; the window of another tab stays", async () => {
    const { fake, manager } = setup();
    await manager.show(request());
    const { id } = fake.state.opened[0];
    manager.tabGone(2);
    assert.deepEqual(fake.state.closed, []);
    assert.ok(manager.view(id, 700));
    manager.tabGone(1);
    assert.deepEqual(fake.state.closed, [700]);
    assert.equal(manager.view(id, 700), undefined);
    // Its removal event (ours) is not taken for a window the next request opens.
    manager.windowRemoved(700);
    assert.equal(await manager.show(request({ documentId: "doc-2" })), true);
    assert.ok(manager.view(fake.state.opened[1].id, 701));
});

test("a window whose tab closes while it is still opening is closed as soon as it exists", async () => {
    const { fake, manager } = setup();
    fake.state.hold = true;
    const opening = manager.show(request());
    await tick();
    await tick();
    manager.tabGone(1);
    fake.state.release();
    assert.equal(await opening, false);
    assert.deepEqual(fake.state.closed, [700]);
});

test("a tab that closes while its request is still being decided gets no window; another tab's closing changes nothing", async () => {
    // The two waits before the window: the session storage is read when the
    // service worker has just started, and the page load is written down.
    for (const waiting of ["ready", "add"]) {
        for (const closed of [1, 2]) {
            const label = `${waiting}, tab ${closed} closes`;
            const fake = host();
            let release;
            let written = 0;
            const gate = new Promise((resolve) => (release = resolve));
            const slow = {
                ready: waiting === "ready" ? gate : Promise.resolve(),
                has: () => false,
                add: () => {
                    written++;
                    return waiting === "add" ? gate : Promise.resolve();
                },
                forgetTab: async () => {},
            };
            const manager = createHelperPromptManager(
                fake,
                slow,
                () => 1_000_000,
            );
            const showing = manager.show(request());
            await tick();
            await tick();
            manager.tabGone(closed);
            release();
            if (closed === 1) {
                assert.equal(await showing, false, label);
                assert.equal(fake.state.opened.length, 0, label);
                assert.deepEqual(fake.state.closed, [], label);
                assert.equal(
                    written,
                    waiting === "ready" ? 0 : 1,
                    `${label}: a gone tab's page load is not written down once that is known`,
                );
                assert.equal(
                    manager.view("any", 700),
                    undefined,
                    `${label}: nothing to show`,
                );
            } else {
                assert.equal(await showing, true, label);
                assert.equal(fake.state.opened.length, 1, label);
            }
            // Whatever happened, the manager is usable again.
            assert.equal(
                await manager.show(request({ tabId: 3, documentId: "doc-3" })),
                true,
                `${label}: usable again`,
            );
        }
    }
});

test("turning the player off while the page load is still being written down opens nothing", async () => {
    const fake = host();
    let release;
    const slow = {
        ready: Promise.resolve(),
        has: () => false,
        add: () => new Promise((resolve) => (release = resolve)),
        forgetTab: async () => {},
    };
    const manager = createHelperPromptManager(fake, slow, () => 1_000_000);
    const showing = manager.show(request());
    await tick();
    await tick();
    manager.dispose();
    release();
    assert.equal(await showing, false);
    assert.equal(fake.state.opened.length, 0);
    // The manager is usable again afterwards.
    const again = manager.show(request({ documentId: "doc-2" }));
    await tick();
    await tick();
    release();
    assert.equal(await again, true);
});

test("turning the player off closes the window; one that was still opening is closed as soon as it exists", async () => {
    const open = setup();
    await open.manager.show(request());
    open.manager.dispose();
    assert.deepEqual(open.fake.state.closed, [700]);
    assert.equal(
        open.manager.view(open.fake.state.opened[0].id, 700),
        undefined,
    );

    const opening = setup();
    opening.fake.state.hold = true;
    const pending = opening.manager.show(request());
    await tick();
    await tick();
    opening.manager.dispose();
    opening.fake.state.release();
    assert.equal(await pending, false);
    assert.deepEqual(opening.fake.state.closed, [700]);
});

test("a closed tab is forgotten, so its number can be told again", async () => {
    const { manager } = setup();
    await manager.show(request());
    manager.windowRemoved(700);
    manager.tabGone(1);
    await tick();
    assert.equal(await manager.show(request()), true);
});

test("which page loads were told survives a restarted service worker, newest last, and is bounded", async () => {
    const session = area();
    const first = createToldDocuments(session);
    await first.add(1, "a");
    await first.add(2, "b");
    await first.add(1, "a");
    assert.deepEqual(session.data.helperToldDocuments, [
        [1, "a"],
        [2, "b"],
    ]);
    const restarted = createToldDocuments(session);
    await restarted.ready;
    assert.equal(restarted.has(1, "a"), true);
    assert.equal(restarted.has(2, "b"), true);
    assert.equal(restarted.has(1, "b"), false);
    for (let n = 0; n < MAX_TOLD_DOCUMENTS + 8; n++) {
        await restarted.add(3, `d${n}`);
    }
    const stored = session.data.helperToldDocuments;
    assert.equal(stored.length, MAX_TOLD_DOCUMENTS);
    assert.deepEqual(stored.at(-1), [3, `d${MAX_TOLD_DOCUMENTS + 7}`]);
    assert.equal(
        restarted.has(1, "a"),
        false,
        "the oldest were forgotten first",
    );
    await restarted.forgetTab(3);
    assert.deepEqual(session.data.helperToldDocuments, []);
});

test("a stored list that grew beyond the limit is cut to the newest entries when it is read", async () => {
    const stored = Array.from({ length: MAX_TOLD_DOCUMENTS * 3 }, (_, n) => [
        1,
        `d${n}`,
    ]);
    const session = area({ helperToldDocuments: stored });
    const store = createToldDocuments(session);
    await store.ready;
    assert.equal(store.has(1, `d${stored.length - 1}`), true);
    assert.equal(store.has(1, `d${stored.length - MAX_TOLD_DOCUMENTS}`), true);
    assert.equal(
        store.has(1, `d${stored.length - MAX_TOLD_DOCUMENTS - 1}`),
        false,
    );
    await store.add(2, "new");
    assert.equal(session.data.helperToldDocuments.length, MAX_TOLD_DOCUMENTS);
});

test("damaged or unreadable storage means nothing was told yet, and nothing breaks", async () => {
    const damaged = area({
        helperToldDocuments: [
            [1, "good"],
            "text",
            [2],
            ["3", "x"],
            [4, 5],
            [1.5, "y"],
            null,
        ],
    });
    const store = createToldDocuments(damaged);
    await store.ready;
    assert.equal(store.has(1, "good"), true);
    assert.equal(store.has(2, "x"), false);
    const notAnArray = createToldDocuments(area({ helperToldDocuments: "x" }));
    await notAnArray.ready;
    assert.equal(notAnArray.has(1, "good"), false);
    const unreadable = area();
    unreadable.fail = true;
    const memoryOnly = createToldDocuments(unreadable);
    await memoryOnly.add(1, "a");
    assert.equal(memoryOnly.has(1, "a"), true);
    const none = createToldDocuments(undefined);
    await none.add(1, "a");
    assert.equal(none.has(1, "a"), true);
});

test("only a complete view is a view", () => {
    assert.equal(isHelperPromptView({ helper: "missing", origin: MOLE }), true);
    assert.equal(
        isHelperPromptView({
            helper: "incompatible",
            origin: MOLE,
            embeddedIn: PORTAL,
        }),
        true,
    );
    for (const bad of [
        undefined,
        null,
        "missing",
        { origin: MOLE },
        { helper: "missing" },
        { helper: "unavailable", origin: MOLE },
        { helper: "missing", origin: 5 },
        { helper: "missing", origin: MOLE, embeddedIn: 5 },
    ]) {
        assert.equal(isHelperPromptView(bad), false, JSON.stringify(bad));
    }
});

test("a window opened because the helper is too old carries the version it waits for; any other window waits for any helper", async () => {
    const old = setup();
    await old.manager.show(
        request({ problem: "incompatible", minVersion: "1.4.0" }),
    );
    assert.deepEqual(old.manager.view(old.fake.state.opened[0].id, 700), {
        helper: "incompatible",
        origin: MOLE,
        minVersion: "1.4.0",
    });
    for (const problem of ["missing", "incompatible"]) {
        const any = setup();
        await any.manager.show(request({ problem }));
        const view = any.manager.view(any.fake.state.opened[0].id, 700);
        assert.equal("minVersion" in view, false, problem);
    }
});

test("a view's version to wait for is a plain version number", () => {
    assert.equal(
        isHelperPromptView({
            helper: "incompatible",
            origin: MOLE,
            minVersion: "1.4.0",
        }),
        true,
    );
    assert.equal(
        isHelperPromptView({
            helper: "missing",
            origin: MOLE,
            embeddedIn: PORTAL,
            minVersion: "10.20.30",
        }),
        true,
    );
    for (const minVersion of [
        5,
        "",
        "1.4.0-beta",
        "v1.4.0",
        "1..4",
        ".1",
        "1.4.",
        " 1.4.0",
        "1".repeat(33),
        null,
    ]) {
        assert.equal(
            isHelperPromptView({
                helper: "incompatible",
                origin: MOLE,
                minVersion,
            }),
            false,
            JSON.stringify(minVersion),
        );
    }
});

test("Continue in the open window closes it and says which tab to reload: the frame's origin, or that of the page that embeds it", async () => {
    const own = setup();
    await own.manager.show(request({ tabId: 4 }));
    const { id } = own.fake.state.opened[0];
    assert.deepEqual(own.manager.continue(id, 700), {
        tabId: 4,
        expectedOrigin: MOLE,
    });
    assert.deepEqual(own.fake.state.closed, [700]);
    assert.equal(own.manager.view(id, 700), undefined);

    const embedded = setup();
    await embedded.manager.show(request({ frameId: 3, top: PORTAL }));
    assert.deepEqual(
        embedded.manager.continue(embedded.fake.state.opened[0].id, 700),
        {
            tabId: 1,
            expectedOrigin: PORTAL,
        },
    );
    // A frame of its own page, or one whose page the browser did not name, is reloaded by its own origin.
    for (const overrides of [{ frameId: 3, top: MOLE }, { frameId: 3 }]) {
        const plain = setup();
        await plain.manager.show(request(overrides));
        assert.equal(
            plain.manager.continue(plain.fake.state.opened[0].id, 700)
                ?.expectedOrigin,
            MOLE,
            JSON.stringify(overrides),
        );
    }
});

test("Continue counts once, only for the open window and only from that window", async () => {
    const { fake, manager } = setup();
    await manager.show(request());
    const { id } = fake.state.opened[0];
    assert.equal(manager.continue("other", 700), undefined);
    assert.equal(manager.continue(id, 701), undefined, "another window");
    assert.equal(
        manager.continue(id, undefined),
        undefined,
        "a page outside a window",
    );
    assert.deepEqual(fake.state.closed, [], "nothing was closed for those");
    assert.ok(manager.view(id, 700), "the window is still open");
    assert.ok(manager.continue(id, 700));
    assert.equal(manager.continue(id, 700), undefined, "used up");
    assert.deepEqual(fake.state.closed, [700]);
    // Its own removal event is not taken for the next window, and the next page load gets a window again.
    manager.windowRemoved(700);
    assert.equal(await manager.show(request({ documentId: "doc-2" })), true);
    assert.ok(manager.view(fake.state.opened[1].id, 701));
});

test("Continue needs the window the browser has said is this one: not one that is still opening", async () => {
    const { fake, manager } = setup();
    fake.state.hold = true;
    const opening = manager.show(request());
    await tick();
    await tick();
    const { id } = fake.state.opened[0];
    assert.ok(manager.view(id, 700), "its text can be read already");
    assert.equal(manager.continue(id, 700), undefined);
    fake.state.release();
    assert.equal(await opening, true);
    assert.ok(manager.continue(id, 700));
});

test("a window that went with its tab, was closed by the visitor or by turning the player off cannot continue", async () => {
    for (const end of [
        (manager) => manager.tabGone(1),
        (manager) => manager.windowRemoved(700),
        (manager) => manager.dispose(),
    ]) {
        const { fake, manager } = setup();
        await manager.show(request());
        end(manager);
        assert.equal(
            manager.continue(fake.state.opened[0].id, 700),
            undefined,
            String(end),
        );
    }
    // Another tab closing changes nothing.
    const { fake, manager } = setup();
    await manager.show(request());
    manager.tabGone(2);
    assert.ok(manager.continue(fake.state.opened[0].id, 700));
});
