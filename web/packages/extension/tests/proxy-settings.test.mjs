import test from "node:test";
import assert from "node:assert/strict";
import {
    getProxySettings,
    replaceProxySettings,
    sameProxySettings,
    saveProxySettings,
    SettingsConflictError,
    updateProxySettings,
} from "../src/proxy-settings.ts";
import {
    DEFAULT_ALLOWED_ORIGINS,
    DEFAULTS_VERSION,
    defaultProxySettings,
    resolveSocketAccess,
    setSocketChoice,
    socketPermission,
} from "../src/socket-proxy.ts";

const originalBrowser = globalThis.browser;
const locksDescriptor = Object.getOwnPropertyDescriptor(
    globalThis.navigator,
    "locks",
);
const X = "https://x.example";

/** A storage area with the delays of the real one; `onWrite` runs after each write. */
function install({ locks = false } = {}) {
    const state = { stored: undefined, writes: 0, lockRequests: [] };
    globalThis.browser = {
        storage: {
            local: {
                async get() {
                    const copy = JSON.parse(
                        JSON.stringify(state.stored ?? null),
                    );
                    await new Promise((r) => setImmediate(r));
                    return copy === null ? {} : { socketProxySettings: copy };
                },
                async set(items) {
                    await new Promise((r) => setImmediate(r));
                    state.writes++;
                    state.stored = JSON.parse(
                        JSON.stringify(items.socketProxySettings),
                    );
                },
                async remove() {
                    state.stored = undefined;
                },
            },
        },
    };
    if (locks) {
        // A lock that really excludes: tasks run one after the other.
        let tail = Promise.resolve();
        Object.defineProperty(globalThis.navigator, "locks", {
            configurable: true,
            value: {
                request(name, task) {
                    state.lockRequests.push(name);
                    const run = tail.then(task, task);
                    tail = run.catch(() => undefined);
                    return run;
                },
            },
        });
    }
    return state;
}
test.afterEach(() => {
    globalThis.browser = originalBrowser;
    if (locksDescriptor) {
        Object.defineProperty(globalThis.navigator, "locks", locksDescriptor);
    } else {
        delete globalThis.navigator.locks;
    }
});

test("saving returns the settings as they are stored", async () => {
    const state = install();
    const saved = await saveProxySettings({
        ...defaultProxySettings(),
        defaultsVersion: undefined,
    });
    assert.equal(saved.defaultsVersion, DEFAULTS_VERSION);
    assert.deepEqual(state.stored, saved);
    assert.deepEqual(await getProxySettings(), saved);
    await assert.rejects(
        saveProxySettings({ ...saved, allowedOrigins: ["*"] }),
        /invalid_origin/u,
    );
});

test("settings stored by a release before the default list grew follow the new defaults in both modes", async () => {
    const proxyUrl =
        "ws://127.0.0.1:18770/connect?host={host}&port={port}&token=T";
    for (const mode of ["helper", "websocket"]) {
        const state = install();
        // One Mole-only list, no defaultsVersion, no separate proxy list.
        state.stored = {
            enabled: true,
            mode,
            proxyUrl: mode === "websocket" ? proxyUrl : "",
            allowedOrigins: ["https://mole.61.com.tw", "http://mole.61.com.tw"],
        };
        const settings = await getProxySettings();
        assert.deepEqual(settings.allowedOrigins, DEFAULT_ALLOWED_ORIGINS);
        assert.deepEqual(settings.proxyOrigins, DEFAULT_ALLOWED_ORIGINS);
        assert.equal(settings.defaultsVersion, DEFAULTS_VERSION);
        // Whichever way sockets are reached, every default site gets it.
        for (const origin of DEFAULT_ALLOWED_ORIGINS) {
            assert.equal(resolveSocketAccess(settings, origin)?.mode, mode);
        }
        // Reading writes nothing; the next save keeps what was read.
        assert.equal(state.writes, 0);
        const saved = await saveProxySettings(settings);
        assert.deepEqual(saved, settings);
        assert.deepEqual(await getProxySettings(), saved);
    }
});

test("comparing settings looks at every field and the order of the lists", () => {
    const a = defaultProxySettings();
    assert.equal(sameProxySettings(a, structuredClone(a)), true);
    for (const change of [
        { enabled: false },
        { mode: "websocket" },
        { proxyUrl: "ws://x/{host}{port}" },
        { defaultsVersion: 1 },
        { allowedOrigins: [X] },
        { proxyOrigins: [] },
        { deniedOrigins: [X] },
        { allowedOrigins: [...a.allowedOrigins].reverse() },
    ]) {
        assert.equal(sameProxySettings(a, { ...a, ...change }), false);
    }
});

test("a form made from the current settings can save", async () => {
    install();
    const baseline = await getProxySettings();
    const next = { ...baseline, allowedOrigins: [X] };
    const stored = await replaceProxySettings(baseline, next);
    assert.deepEqual(stored.allowedOrigins, [X]);
    assert.deepEqual((await getProxySettings()).allowedOrigins, [X]);
});

test("a stale form cannot undo what the popup decided meanwhile", async () => {
    const state = install();
    await saveProxySettings({ ...defaultProxySettings(), allowedOrigins: [X] });
    // The options page is opened: X is allowed there.
    const baseline = await getProxySettings();
    const form = { ...baseline };
    // The popup then sets X to "always deny".
    await updateProxySettings((s) => setSocketChoice(s, X, "deny"));
    assert.equal(socketPermission(state.stored, X), "deny");
    const writes = state.writes;
    // Saving the old form (with X still listed as allowed) is refused...
    await assert.rejects(
        replaceProxySettings(baseline, form),
        (error) => error instanceof SettingsConflictError,
    );
    // ...and nothing was written.
    assert.equal(state.writes, writes);
    assert.equal(socketPermission(state.stored, X), "deny");
    assert.ok(!state.stored.allowedOrigins.includes(X));
    // After reloading the form the save works again.
    const fresh = await getProxySettings();
    await replaceProxySettings(fresh, { ...fresh, enabled: false });
    assert.equal(state.stored.enabled, false);
    assert.equal(socketPermission(state.stored, X), "off");
});

test("updates are ordered, and go through the shared lock when there is one", async () => {
    const state = install({ locks: true });
    // Two quick answers: neither may be lost.
    await Promise.all([
        updateProxySettings((s) => setSocketChoice(s, X, "allow")),
        updateProxySettings((s) =>
            setSocketChoice(s, "https://y.example", "deny"),
        ),
    ]);
    assert.ok(state.stored.allowedOrigins.includes(X));
    assert.ok(state.stored.deniedOrigins.includes("https://y.example"));
    assert.deepEqual(state.lockRequests, [
        "timffle-socket-settings",
        "timffle-socket-settings",
    ]);
});

test("another context holding the lock makes an update wait, not overwrite", async () => {
    const state = install({ locks: true });
    // The "other context": takes the lock, reads, and writes after a delay.
    const other = globalThis.navigator.locks.request("other", async () => {
        const current = await getProxySettings();
        await new Promise((r) => setTimeout(r, 20));
        await saveProxySettings(setSocketChoice(current, X, "allow"));
    });
    // The other context's request went first and is still running; our update
    // is queued behind it and then sees its result.
    await new Promise((r) => setImmediate(r));
    await updateProxySettings((s) =>
        setSocketChoice(s, "https://y.example", "allow"),
    );
    await other;
    assert.ok(state.stored.allowedOrigins.includes(X));
    assert.ok(state.stored.allowedOrigins.includes("https://y.example"));
});

test("a cancelled update leaves the settings alone and the next update still runs", async () => {
    const state = install({ locks: true });
    await saveProxySettings(defaultProxySettings());
    const writes = state.writes;
    await assert.rejects(
        updateProxySettings(() => {
            throw new Error("not_asking");
        }),
        /not_asking/u,
    );
    assert.equal(state.writes, writes);
    await updateProxySettings((s) => setSocketChoice(s, X, "allow"));
    assert.ok(state.stored.allowedOrigins.includes(X));
});

test("without Web Locks updates still work", async () => {
    const state = install({ locks: false });
    await updateProxySettings((s) => setSocketChoice(s, X, "allow"));
    assert.ok(state.stored.allowedOrigins.includes(X));
    assert.deepEqual(state.lockRequests, []);
});
