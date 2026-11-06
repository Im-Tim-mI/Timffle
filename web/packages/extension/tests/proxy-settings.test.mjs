import test from "node:test";
import assert from "node:assert/strict";
import {
    applyInstalledDefaults,
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
    INSTALLED_DEFAULTS_KEY,
    LEGACY_DEFAULT_ORIGINS,
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
    const state = {
        stored: undefined,
        extra: {},
        writes: 0,
        lockRequests: [],
    };
    globalThis.browser = {
        storage: {
            local: {
                async get() {
                    const copy = JSON.parse(
                        JSON.stringify(state.stored ?? null),
                    );
                    const extra = JSON.parse(JSON.stringify(state.extra));
                    await new Promise((r) => setImmediate(r));
                    return copy === null
                        ? extra
                        : { ...extra, socketProxySettings: copy };
                },
                async set(items) {
                    await new Promise((r) => setImmediate(r));
                    state.writes++;
                    for (const [key, value] of Object.entries(items)) {
                        const copy = JSON.parse(JSON.stringify(value));
                        if (key === "socketProxySettings") {
                            state.stored = copy;
                        } else {
                            state.extra[key] = copy;
                        }
                    }
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

test("fresh settings allow no website", async () => {
    const state = install();
    const settings = await getProxySettings();
    assert.deepEqual(settings, defaultProxySettings());
    assert.deepEqual(settings.allowedOrigins, []);
    assert.deepEqual(settings.proxyOrigins, []);
    assert.deepEqual(DEFAULT_ALLOWED_ORIGINS, []);
    assert.equal(socketPermission(settings, "https://game.example"), "ask");
    assert.equal(state.writes, 0);
});

test("installed users' lists of earlier releases are read as saved", async () => {
    const proxyUrl =
        "ws://127.0.0.1:18770/connect?host={host}&port={port}&token=T";
    const v1 = ["https://mole.61.com.tw", "http://mole.61.com.tw"];
    const v2 = ["mole", "seer", "hua", "ddt"].flatMap((name) => [
        `https://${name}.61.com.tw`,
        `http://${name}.61.com.tw`,
    ]);
    for (const [list, extra, expected] of [
        // One list, no defaultsVersion: the first releases' list grows as before.
        [v1, {}, v2],
        [v2, { proxyOrigins: v2, deniedOrigins: [X], defaultsVersion: 2 }, v2],
    ]) {
        for (const mode of ["helper", "websocket"]) {
            const state = install();
            state.stored = {
                enabled: true,
                mode,
                proxyUrl: mode === "websocket" ? proxyUrl : "",
                allowedOrigins: list,
                ...extra,
            };
            const settings = await getProxySettings();
            assert.deepEqual(settings.allowedOrigins, expected);
            assert.deepEqual(settings.proxyOrigins, expected);
            assert.deepEqual(settings.deniedOrigins, extra.deniedOrigins ?? []);
            for (const origin of expected) {
                assert.equal(resolveSocketAccess(settings, origin)?.mode, mode);
            }
            assert.equal(state.writes, 0);
        }
    }
});

test("a new installation is marked and keeps the empty list", async () => {
    const state = install();
    await applyInstalledDefaults("install");
    assert.equal(state.stored, undefined);
    assert.equal(state.extra[INSTALLED_DEFAULTS_KEY], DEFAULTS_VERSION);
    assert.deepEqual((await getProxySettings()).allowedOrigins, []);
    // Its later updates add nothing.
    await applyInstalledDefaults("update");
    assert.equal(state.stored, undefined);
    assert.deepEqual((await getProxySettings()).allowedOrigins, []);
});

test("an update of an older installation that never saved keeps its sites", async () => {
    const state = install();
    await applyInstalledDefaults("update");
    const settings = await getProxySettings();
    assert.deepEqual(settings.allowedOrigins, [...LEGACY_DEFAULT_ORIGINS]);
    assert.deepEqual(settings.proxyOrigins, [...LEGACY_DEFAULT_ORIGINS]);
    assert.equal(socketPermission(settings, "https://mole.61.com.tw"), "allow");
    assert.equal(socketPermission(settings, X), "ask");
    // Only once: a second update changes nothing.
    const writes = state.writes;
    await applyInstalledDefaults("update");
    assert.equal(state.writes, writes);
});

test("an update never changes settings the user saved", async () => {
    const state = install();
    const mine = {
        ...defaultProxySettings(),
        allowedOrigins: [X],
        proxyOrigins: [X],
    };
    state.stored = mine;
    await applyInstalledDefaults("update");
    assert.deepEqual(state.stored, mine);
    assert.equal(state.writes, 0);
});

test("an allow-list the user edited is read as saved", async () => {
    const state = install();
    state.stored = {
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: ["https://mole.61.com.tw", X],
        proxyOrigins: [X],
        deniedOrigins: [],
        defaultsVersion: 2,
    };
    const settings = await getProxySettings();
    assert.deepEqual(settings.allowedOrigins, ["https://mole.61.com.tw", X]);
    assert.deepEqual(settings.proxyOrigins, [X]);
    assert.equal(settings.defaultsVersion, 2);
});

test("comparing settings looks at every field and the order of the lists", () => {
    const a = {
        ...defaultProxySettings(),
        allowedOrigins: [X, "https://y.example"],
        proxyOrigins: [X],
    };
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
