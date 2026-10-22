// What the content script does with the stored options before the page may
// load (src/startup-options.ts): the reload flag is cleared only when it is
// set and never awaited; the explicit options are a copy without defaults.
import test from "node:test";
import assert from "node:assert/strict";
import {
    clearReloadFlag,
    explicitOptionsFrom,
} from "../src/startup-options.ts";

const DEFAULTS = {
    ruffleEnable: true,
    ignoreOptout: false,
    autostart: false,
    showReloadButton: false,
    swfTakeover: true,
    logLevel: "error",
};

/** A storage.sync stand-in that counts writes and can be made to fail. */
function syncArea({ fail = false } = {}) {
    const area = {
        writes: [],
        set(items) {
            area.writes.push(items);
            return fail
                ? Promise.reject(new Error("quota"))
                : Promise.resolve();
        },
    };
    return area;
}

test("the reload flag is written only when it is set, and the options read as cleared", async () => {
    const quiet = syncArea();
    const unchanged = { ...DEFAULTS, autostart: true };
    assert.equal(clearReloadFlag(unchanged, quiet), unchanged);
    assert.deepEqual(
        quiet.writes,
        [],
        "a frame that has nothing to clear writes nothing",
    );

    const sync = syncArea();
    const set = { ...DEFAULTS, showReloadButton: true };
    const cleared = clearReloadFlag(set, sync);
    assert.deepEqual(sync.writes, [{ showReloadButton: false }]);
    assert.equal(cleared.showReloadButton, false);
    assert.equal(set.showReloadButton, true, "the given object is not changed");
    assert.deepEqual({ ...cleared, showReloadButton: true }, set);
});

test("a failing or unavailable storage.sync neither throws nor delays the page", async () => {
    const failing = syncArea({ fail: true });
    const cleared = clearReloadFlag(
        { ...DEFAULTS, showReloadButton: true },
        failing,
    );
    assert.equal(cleared.showReloadButton, false);
    assert.equal(failing.writes.length, 1);
    // The rejection is handled: an unhandled one would fail this test run.
    await new Promise((resolve) => setImmediate(resolve));

    const throwing = {
        set() {
            throw new Error("no storage");
        },
    };
    assert.equal(
        clearReloadFlag({ ...DEFAULTS, showReloadButton: true }, throwing)
            .showReloadButton,
        false,
    );
});

test("explicit options are the values that differ from the defaults, as a copy", () => {
    const options = {
        ...DEFAULTS,
        autostart: true,
        logLevel: "warn",
        responseHeadersUnsupported: true,
        socketProxy: [{ host: "*", port: 0, proxyUrl: "ws://x" }],
    };
    const before = structuredClone(options);
    const explicit = explicitOptionsFrom(options, DEFAULTS);
    assert.deepEqual(explicit, {
        autostart: true,
        logLevel: "warn",
        socketProxy: [{ host: "*", port: 0, proxyUrl: "ws://x" }],
    });
    assert.deepEqual(
        options,
        before,
        "the full options are kept for the popup",
    );
    assert.deepEqual(explicitOptionsFrom(DEFAULTS, DEFAULTS), {});
});
