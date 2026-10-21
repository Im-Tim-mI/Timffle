// Waiting for the socket helper (src/helper-wait.ts): when an answer counts as "the helper is there", how often the
// window and the install page look, and that a look never piles up on another one.
import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import {
    HELPER_PAGE_REFRESH_MS,
    HELPER_WAIT_POLL_MS,
    readyVersion,
    showHelperReady,
    waitForHelper,
} from "../src/helper-wait.ts";
import { MIN_LAN_HELPER_VERSION } from "../src/socket-lan.ts";
import { fakeI18n } from "./catalog-support.mjs";

const tick = () => new Promise((resolve) => setImmediate(resolve));
const INSTALLED = { installed: true, version: "1.4.0", protocol: 2 };
const MISSING = { installed: false, error: "helper_missing" };

test("the window and the install page look every 2 and 3 seconds", () => {
    assert.equal(HELPER_WAIT_POLL_MS, 2000);
    assert.equal(HELPER_PAGE_REFRESH_MS, 3000);
});

test("only an installed helper of this protocol is one to continue with, and only one new enough when a version is asked for", () => {
    assert.equal(readyVersion(INSTALLED), "1.4.0");
    assert.equal(readyVersion(INSTALLED, "1.4.0"), "1.4.0");
    assert.equal(
        readyVersion({ ...INSTALLED, version: "1.10.0" }, "1.4.0"),
        "1.10.0",
    );
    assert.equal(
        readyVersion(
            { ...INSTALLED, version: "2.0.0" },
            MIN_LAN_HELPER_VERSION,
        ),
        "2.0.0",
    );
    // A helper from before the website's own address could be reached is installed, but not the one the window waits for.
    assert.equal(
        readyVersion(
            { ...INSTALLED, version: "1.3.0" },
            MIN_LAN_HELPER_VERSION,
        ),
        undefined,
    );
    assert.equal(
        readyVersion({ installed: true, protocol: 2 }, "1.4.0"),
        undefined,
        "no version, but one is asked for",
    );
    assert.equal(
        readyVersion({ installed: true, protocol: 2 }),
        "?",
        "no version, and none is asked for",
    );
    for (const notThere of [
        MISSING,
        {
            installed: false,
            error: "helper_incompatible",
            version: "1.0.0",
            protocol: 1,
        },
        { installed: false, error: "helper_timeout" },
        { installed: false, error: "socket_limit" },
    ]) {
        assert.equal(
            readyVersion(notThere),
            undefined,
            JSON.stringify(notThere),
        );
    }
    // An answer that is not a status means "not yet", whatever it says.
    for (const odd of [
        undefined,
        null,
        "installed",
        1,
        true,
        [],
        { installed: "yes", version: "1.4.0" },
        { installed: 1 },
        { installed: true, version: 140 },
    ]) {
        assert.equal(readyVersion(odd), undefined, JSON.stringify(odd));
        assert.equal(
            readyVersion(odd, "1.4.0"),
            undefined,
            JSON.stringify(odd),
        );
    }
});

/** Timers the test moves by hand, and a helper whose answers the test gives one at a time. */
function setup(options = {}) {
    const timers = new Map();
    let next = 1;
    let now = 0;
    const clock = {
        setTimer(callback, ms) {
            const id = next++;
            timers.set(id, { at: now + ms, callback });
            return id;
        },
        clearTimer(id) {
            timers.delete(id);
        },
        /** Runs every timer that is due within `ms`, in order. */
        advance(ms) {
            const end = now + ms;
            for (;;) {
                const due = [...timers.entries()]
                    .filter(([, timer]) => timer.at <= end)
                    .sort((a, b) => a[1].at - b[1].at)[0];
                if (!due) {
                    break;
                }
                timers.delete(due[0]);
                now = due[1].at;
                due[1].callback();
            }
            now = end;
        },
        get pending() {
            return timers.size;
        },
    };
    const asked = [];
    const query = () =>
        new Promise((resolve, reject) => asked.push({ resolve, reject }));
    const seen = { ready: [], notYet: [] };
    const wait = waitForHelper({
        query,
        ready: (version) => seen.ready.push(version),
        notYet: (status) => seen.notYet.push(status),
        setTimer: clock.setTimer,
        clearTimer: clock.clearTimer,
        ...options,
    });
    /** Gives the oldest open question its answer and lets the wait handle it. */
    const answer = async (status) => {
        const open = asked.find((q) => !q.done);
        open.done = true;
        open.resolve(status);
        await tick();
    };
    const fail = async (error = new Error("no background")) => {
        const open = asked.find((q) => !q.done);
        open.done = true;
        open.reject(error);
        await tick();
    };
    const inFlight = () => asked.filter((q) => !q.done).length;
    return { wait, clock, asked, seen, answer, fail, inFlight };
}

test("the first look is due after one wait, then one after each answer, until the helper is there", async () => {
    const { clock, asked, seen, answer } = setup();
    assert.equal(
        asked.length,
        0,
        "the background has just found the helper missing",
    );
    clock.advance(HELPER_WAIT_POLL_MS - 1);
    assert.equal(asked.length, 0);
    clock.advance(1);
    assert.equal(asked.length, 1);
    await answer(MISSING);
    assert.deepEqual(seen.notYet, [MISSING]);
    clock.advance(HELPER_WAIT_POLL_MS);
    assert.equal(asked.length, 2);
    await answer(INSTALLED);
    assert.deepEqual(seen.ready, ["1.4.0"]);
    assert.equal(seen.notYet.length, 1);
    // That was the last look.
    assert.equal(clock.pending, 0);
    clock.advance(HELPER_WAIT_POLL_MS * 10);
    assert.equal(asked.length, 2);
});

test("one look at a time: a slow answer is waited for, and a look asked for meanwhile is not made", async () => {
    const { wait, clock, asked, answer, inFlight } = setup();
    clock.advance(HELPER_WAIT_POLL_MS);
    assert.equal(inFlight(), 1);
    // The answer takes long (the helper starts slowly): no timer runs meanwhile, so nothing piles up.
    assert.equal(clock.pending, 0);
    clock.advance(HELPER_WAIT_POLL_MS * 5);
    wait.check();
    wait.check();
    assert.equal(asked.length, 1);
    await answer(MISSING);
    assert.equal(inFlight(), 0);
    clock.advance(HELPER_WAIT_POLL_MS);
    assert.equal(asked.length, 2);
    assert.equal(inFlight(), 1);
});

test("coming back to the window looks at once, and the next look is due a full wait after that answer", async () => {
    const { wait, clock, asked, seen, answer } = setup();
    clock.advance(HELPER_WAIT_POLL_MS - 500);
    wait.check();
    assert.equal(asked.length, 1, "at once");
    clock.advance(500);
    assert.equal(asked.length, 1, "the look that was due is that one");
    await answer(MISSING);
    clock.advance(HELPER_WAIT_POLL_MS - 1);
    assert.equal(asked.length, 1);
    clock.advance(1);
    assert.equal(asked.length, 2);
    await answer(INSTALLED);
    assert.deepEqual(seen.ready, ["1.4.0"]);
    // Once the helper is there, coming back looks no more.
    wait.check();
    assert.equal(asked.length, 2);
});

test("a failed or odd answer is not yet, and the wait goes on", async () => {
    const { clock, asked, seen, answer, fail } = setup();
    const answers = [
        () => fail(),
        () => answer(undefined),
        () => answer(null),
        () => answer("installed"),
        () => answer({ installed: "yes", version: "1.4.0" }),
        () => answer({ installed: false, error: "helper_timeout" }),
    ];
    for (const [n, give] of answers.entries()) {
        clock.advance(HELPER_WAIT_POLL_MS);
        assert.equal(asked.length, n + 1, String(n));
        await give();
    }
    assert.deepEqual(seen.ready, []);
    // What the install page is told for each: no answer at all is "no response", anything shaped like a status is passed on.
    assert.deepEqual(
        seen.notYet.slice(0, 4),
        Array(4).fill({ installed: false, error: "no_response" }),
    );
    assert.deepEqual(seen.notYet.slice(4), [
        { installed: "yes", version: "1.4.0" },
        { installed: false, error: "helper_timeout" },
    ]);
    clock.advance(HELPER_WAIT_POLL_MS);
    await answer(INSTALLED);
    assert.deepEqual(seen.ready, ["1.4.0"]);
});

test("a look that throws at once is not yet either", async () => {
    const calls = [];
    const timers = [];
    const wait = waitForHelper({
        query: () => {
            calls.push(1);
            throw new Error("no runtime");
        },
        ready: () => assert.fail("not ready"),
        setTimer: (callback) => timers.push(callback),
        clearTimer: () => {},
    });
    wait.check();
    await tick();
    assert.equal(calls.length, 1);
    assert.ok(timers.length >= 2, "the next look is due");
});

test("a helper older than the version asked for keeps the window waiting; the new one ends the wait", async () => {
    const { clock, seen, answer } = setup({
        minVersion: MIN_LAN_HELPER_VERSION,
    });
    clock.advance(HELPER_WAIT_POLL_MS);
    await answer({ ...INSTALLED, version: "1.3.0" });
    clock.advance(HELPER_WAIT_POLL_MS);
    await answer({ ...INSTALLED, version: "1.3.0" });
    assert.deepEqual(seen.ready, []);
    assert.equal(seen.notYet.length, 2);
    clock.advance(HELPER_WAIT_POLL_MS);
    await answer({ ...INSTALLED, version: "1.4.0" });
    assert.deepEqual(seen.ready, ["1.4.0"]);
});

test("stopped, it looks no more, and an answer that arrives afterwards is dropped", async () => {
    const { wait, clock, asked, seen, answer } = setup();
    clock.advance(HELPER_WAIT_POLL_MS);
    wait.stop();
    await answer(INSTALLED);
    assert.deepEqual(seen.ready, []);
    assert.deepEqual(seen.notYet, []);
    assert.equal(clock.pending, 0);
    clock.advance(HELPER_WAIT_POLL_MS * 5);
    wait.check();
    assert.equal(asked.length, 1);
});

test("while it should not look (the install page is not shown, or is checking by itself) the turn passes without a look", async () => {
    let active = false;
    const { clock, asked, answer } = setup({
        pollMs: HELPER_PAGE_REFRESH_MS,
        active: () => active,
    });
    clock.advance(HELPER_PAGE_REFRESH_MS * 3);
    assert.equal(asked.length, 0);
    assert.equal(clock.pending, 1, "still waiting for its turn");
    active = true;
    clock.advance(HELPER_PAGE_REFRESH_MS - 1);
    assert.equal(asked.length, 0);
    clock.advance(1);
    assert.equal(asked.length, 1);
    await answer(MISSING);
    active = false;
    clock.advance(HELPER_PAGE_REFRESH_MS);
    assert.equal(asked.length, 1);
});

test("without timers of its own it uses the page's, and asks again only after a full wait", async (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    let looks = 0;
    const ready = [];
    waitForHelper({
        query: async () => (++looks === 2 ? INSTALLED : MISSING),
        ready: (version) => ready.push(version),
    });
    t.mock.timers.tick(HELPER_WAIT_POLL_MS - 1);
    assert.equal(looks, 0);
    t.mock.timers.tick(1);
    assert.equal(looks, 1);
    await tick();
    t.mock.timers.tick(HELPER_WAIT_POLL_MS);
    assert.equal(looks, 2);
    await tick();
    assert.deepEqual(ready, ["1.4.0"]);
});

test("once the helper is there the wait line says so with the version and Continue can be pressed, highlighted, without taking the focus", () => {
    const original = globalThis.browser;
    try {
        for (const language of ["en", "zh_TW", "de"]) {
            globalThis.browser = { i18n: fakeI18n(language) };
            const classes = new Set();
            const line = {
                textContent: "waiting",
                dataset: { state: "waiting" },
            };
            const button = {
                disabled: true,
                dataset: {},
                classList: { add: (name) => classes.add(name) },
                focus: () => assert.fail("the focus stays where it is"),
            };
            // The installer button was the highlighted one until now.
            const installerClasses = new Set(["recommended", "other"]);
            const installer = {
                classList: { remove: (name) => installerClasses.delete(name) },
            };
            showHelperReady(line, button, "1.4.0", installer);
            assert.deepEqual([...installerClasses], ["other"], language);
            assert.equal(
                line.textContent,
                fakeI18n(language).getMessage("timffle_helper_ready", [
                    "1.4.0",
                ]),
                language,
            );
            assert.ok(line.textContent.includes("1.4.0"), language);
            assert.ok(
                line.textContent.includes(
                    fakeI18n(language).getMessage("timffle_helper_continue"),
                ),
                language,
            );
            assert.equal(line.dataset.state, "ready");
            assert.equal(button.disabled, false);
            assert.equal(button.dataset.ready, "true");
            assert.deepEqual([...classes], ["recommended"]);
        }
    } finally {
        globalThis.browser = original;
    }
});
