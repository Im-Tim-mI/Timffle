import test from "node:test";
import assert from "node:assert/strict";
import { URL } from "node:url";
import {
    askSocketProxies,
    defaultProxySettings,
    promptsForUnlisted,
    setSocketChoice,
    socketPermission,
    validateProxySettings,
    applyProxySettings,
    normalizeWebsiteOrigin,
    mergeSocketProxies,
    resolveSocketAccess,
    upgradeLegacyDefaults,
    DEFAULTS_VERSION,
    DEFAULT_ALLOWED_ORIGINS,
    HELPER_PROXY_URL,
} from "../src/socket-proxy.ts";
const GAME_HOSTS = [
    "mole.61.com.tw",
    "seer.61.com.tw",
    "hua.61.com.tw",
    "ddt.61.com.tw",
];
const url =
    "ws://127.0.0.1:18770/connect?host={host}&port={port}&token=test-only";
const settings = {
    enabled: true,
    mode: "websocket",
    proxyUrl: url,
    allowedOrigins: ["https://mole.61.com.tw"],
};
test("defaults use the helper for Taomee's four game sites only, with no token", () => {
    const defaults = defaultProxySettings();
    assert.deepEqual(defaults, {
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: GAME_HOSTS.flatMap((host) => [
            `https://${host}`,
            `http://${host}`,
        ]),
        proxyOrigins: GAME_HOSTS.flatMap((host) => [
            `https://${host}`,
            `http://${host}`,
        ]),
        deniedOrigins: [],
        defaultsVersion: DEFAULTS_VERSION,
    });
    assert.deepEqual(defaults.allowedOrigins, DEFAULT_ALLOWED_ORIGINS);
    assert.deepEqual(defaults.proxyOrigins, DEFAULT_ALLOWED_ORIGINS);
    assert.equal(validateProxySettings(defaults).valid, true);
    for (const host of GAME_HOSTS) {
        for (const origin of [`https://${host}`, `http://${host}`]) {
            assert.deepEqual(
                applyProxySettings({}, defaults, origin).socketProxy,
                [{ host: "*", port: 0, proxyUrl: HELPER_PROXY_URL }],
                origin,
            );
        }
    }
    for (const origin of [
        undefined,
        "https://evil.example",
        "https://www.61.com.tw",
        "https://seer.61.com.tw.evil.example",
        "https://evil-ddt.61.com.tw",
        "http://ddt.61.com.tw:8080",
        "https://mole.61.com.tw:8443",
    ]) {
        assert.deepEqual(applyProxySettings({}, defaults, origin), {}, origin);
    }
});
test("a game page URL with a path maps to its origin", () => {
    assert.equal(
        normalizeWebsiteOrigin("http://ddt.61.com.tw/main_index.php"),
        undefined,
        "paths are rejected in the list...",
    );
    assert.equal(
        new URL("http://ddt.61.com.tw/main_index.php").origin,
        "http://ddt.61.com.tw",
    );
    assert.equal(
        resolveSocketAccess(
            defaultProxySettings(),
            new URL("http://ddt.61.com.tw/main_index.php").origin,
        )?.mode,
        "helper",
    );
});
test("never-edited settings of the Mole-only release follow the new defaults", () => {
    for (const legacy of [
        ["https://mole.61.com.tw", "http://mole.61.com.tw"],
        ["http://mole.61.com.tw", "https://mole.61.com.tw"],
        [
            "https://mole.61.com.tw",
            "http://mole.61.com.tw",
            "https://mole.61.com.tw",
        ],
    ]) {
        const upgraded = upgradeLegacyDefaults({
            enabled: true,
            mode: "helper",
            proxyUrl: "",
            allowedOrigins: legacy,
        });
        assert.deepEqual(upgraded.allowedOrigins, DEFAULT_ALLOWED_ORIGINS);
        assert.equal(upgraded.defaultsVersion, DEFAULTS_VERSION);
        assert.equal(upgraded.mode, "helper");
    }
    // The connection method and the proxy URL belong to the user.
    const manual = upgradeLegacyDefaults({
        enabled: false,
        mode: "websocket",
        proxyUrl: url,
        allowedOrigins: ["https://mole.61.com.tw", "http://mole.61.com.tw"],
    });
    assert.deepEqual(manual.allowedOrigins, DEFAULT_ALLOWED_ORIGINS);
    assert.equal(manual.enabled, false);
    assert.equal(manual.mode, "websocket");
    assert.equal(manual.proxyUrl, url);
});
test("lists the user chose or saved with this release are left alone", () => {
    const base = { enabled: true, mode: "helper", proxyUrl: "" };
    for (const allowedOrigins of [
        ["https://mole.61.com.tw"],
        ["http://mole.61.com.tw"],
        ["https://seer.61.com.tw", "http://seer.61.com.tw"],
        [
            "https://mole.61.com.tw",
            "http://mole.61.com.tw",
            "https://x.example",
        ],
        [],
    ]) {
        const saved = { ...base, allowedOrigins };
        assert.deepEqual(upgradeLegacyDefaults(saved), saved);
    }
    // Saved again on purpose after the upgrade: Mole-only stays Mole-only.
    const deliberate = {
        ...base,
        allowedOrigins: ["https://mole.61.com.tw", "http://mole.61.com.tw"],
        defaultsVersion: DEFAULTS_VERSION,
    };
    assert.deepEqual(upgradeLegacyDefaults(deliberate), deliberate);
    assert.deepEqual(
        resolveSocketAccess(deliberate, "https://seer.61.com.tw"),
        undefined,
    );
});
test("defaultsVersion survives validation only as a positive integer", () => {
    const base = { ...settings, mode: "helper", proxyUrl: "" };
    assert.equal(
        validateProxySettings({ ...base, defaultsVersion: 2 }).settings
            .defaultsVersion,
        2,
    );
    for (const bad of ["2", 0, -1, 1.5, NaN, null, {}]) {
        const result = validateProxySettings({ ...base, defaultsVersion: bad });
        assert.equal(result.valid, true);
        assert.equal("defaultsVersion" in result.settings, false);
    }
    assert.equal(
        "defaultsVersion" in validateProxySettings(base).settings,
        false,
    );
});
test("helper URL never reaches the network and keeps both placeholders", () => {
    const helper = new URL(
        HELPER_PROXY_URL.replace("{host}", "h").replace("{port}", "1"),
    );
    assert.equal(helper.protocol, "ws:");
    assert.ok(helper.hostname.endsWith(".invalid"));
    assert.ok(
        HELPER_PROXY_URL.includes("{host}") &&
            HELPER_PROXY_URL.includes("{port}"),
    );
});
test("valid template remains intact and origins normalized/deduplicated", () => {
    const r = validateProxySettings({
        ...settings,
        allowedOrigins: [
            "HTTPS://MOLE.61.COM.TW/",
            "https://mole.61.com.tw",
            "",
        ],
    });
    assert.equal(r.valid, true);
    // Settings that predate the separate lists use their one list for both modes.
    assert.deepEqual(r.settings, {
        ...settings,
        proxyOrigins: settings.allowedOrigins,
        deniedOrigins: [],
    });
});
test("settings saved before modes existed keep using their proxy", () => {
    const legacy = { ...settings };
    delete legacy.mode;
    const r = validateProxySettings(legacy);
    assert.equal(r.valid, true);
    assert.equal(r.settings.mode, "websocket");
    assert.equal(
        validateProxySettings({ ...legacy, enabled: false, proxyUrl: "" })
            .settings.mode,
        "helper",
    );
});
test("modes: helper needs no URL, websocket does, unknown modes are refused", () => {
    assert.equal(
        validateProxySettings({ ...settings, mode: "helper", proxyUrl: "" })
            .valid,
        true,
    );
    assert.deepEqual(validateProxySettings({ ...settings, proxyUrl: "" }), {
        valid: false,
        error: "url_required",
    });
    assert.equal(
        validateProxySettings({ ...settings, mode: "native" }).valid,
        false,
    );
    assert.deepEqual(
        resolveSocketAccess(
            { ...settings, mode: "helper" },
            "https://mole.61.com.tw",
        ),
        { mode: "helper", proxyUrl: HELPER_PROXY_URL },
    );
    assert.deepEqual(resolveSocketAccess(settings, "https://mole.61.com.tw"), {
        mode: "websocket",
        proxyUrl: url,
    });
});
test("refuse invalid schemes and missing placeholders", () => {
    for (const proxyUrl of [
        "http://localhost/?host={host}&port={port}",
        "ws://localhost/no-placeholders",
        "ws://localhost/?host={host}",
    ]) {
        assert.equal(
            validateProxySettings({ ...settings, proxyUrl }).valid,
            false,
        );
    }
});
test("refuse dynamic proxy authority, credentials and fragments", () => {
    for (const proxyUrl of [
        "ws://{host}:{port}/",
        "ws://user:pass@localhost/?host={host}&port={port}",
        url + "#fragment",
        "ws://localhost/?host={host}&port={port}&x={unknown}",
    ]) {
        assert.equal(
            validateProxySettings({ ...settings, proxyUrl }).valid,
            false,
        );
    }
});
test("origin list rejects wildcard, path, query, credentials, null and file URLs", () => {
    for (const origin of [
        "*",
        "https://*.example",
        "https://example/path",
        "https://example?x=y",
        "https://u:p@example",
        "null",
        "file:///tmp/a.swf",
    ]) {
        assert.equal(normalizeWebsiteOrigin(origin), undefined);
    }
});
test("a custom proxy needs an allowed origin; the helper asks instead", () => {
    // A custom WebSocket proxy has no prompt, so it is useless without one.
    assert.deepEqual(
        validateProxySettings({ ...settings, allowedOrigins: [] }),
        { valid: false, error: "origins_required" },
    );
    assert.equal(
        validateProxySettings({
            ...settings,
            enabled: false,
            allowedOrigins: [],
        }).valid,
        true,
    );
    // The helper asks about every website that is not listed.
    assert.equal(
        validateProxySettings({ ...defaultProxySettings(), allowedOrigins: [] })
            .valid,
        true,
    );
});
test("missing, malformed and disabled settings do not inject proxy", () => {
    for (const s of [
        undefined,
        null,
        {},
        [],
        { ...settings, enabled: false },
        { ...settings, allowedOrigins: "*" },
    ]) {
        assert.deepEqual(
            applyProxySettings({}, s, "https://mole.61.com.tw"),
            {},
        );
    }
});
test("no credentials/config reach an unapproved origin or file player", () => {
    for (const o of [
        undefined,
        "null",
        "https://evil.example",
        "http://mole.61.com.tw",
        "file:///movie.swf",
    ]) {
        assert.deepEqual(applyProxySettings({}, settings, o), {});
    }
});
test("trusted origin receives a catch-all preserving template", () =>
    assert.deepEqual(
        applyProxySettings({}, settings, "https://mole.61.com.tw").socketProxy,
        [{ host: "*", port: 0, proxyUrl: url }],
    ));
test("exact mappings ordered before wildcard without mutating inputs", () => {
    const exact = {
            host: "1.2.3.4",
            port: 80,
            proxyUrl: "ws://localhost/fixed",
        },
        wild = { host: "*", port: 0, proxyUrl: url };
    const input = [wild, exact];
    assert.deepEqual(mergeSocketProxies(input), [exact, wild]);
    assert.deepEqual(input, [wild, exact]);
    assert.deepEqual(
        applyProxySettings(
            { socketProxy: [exact] },
            settings,
            "https://mole.61.com.tw",
        ).socketProxy,
        [exact, wild],
    );
});

const helperSettings = (extra = {}) => ({
    enabled: true,
    mode: "helper",
    proxyUrl: "",
    allowedOrigins: ["https://mole.61.com.tw", "https://ok.example"],
    deniedOrigins: ["https://no.example"],
    ...extra,
});
test("every website is allowed, refused or asked about; nothing else is a question", () => {
    const s = helperSettings();
    assert.equal(socketPermission(s, "https://ok.example"), "allow");
    assert.equal(socketPermission(s, "https://no.example"), "deny");
    assert.equal(socketPermission(s, "https://new.example"), "ask");
    // Origins compare exactly: scheme, host and port all count.
    assert.equal(socketPermission(s, "http://ok.example"), "ask");
    assert.equal(socketPermission(s, "https://ok.example:8443"), "ask");
    // No website origin, or sockets switched off or unusable: never a question.
    for (const origin of [undefined, "null", "file:///a.swf", "about:blank"]) {
        assert.equal(socketPermission(s, origin), "off", String(origin));
    }
    for (const bad of [
        undefined,
        null,
        {},
        [],
        "x",
        { ...s, enabled: false },
    ]) {
        assert.equal(socketPermission(bad, "https://ok.example"), "off");
    }
});
test("a website in both lists is refused, whichever list was edited last", () => {
    const both = helperSettings({
        allowedOrigins: ["https://both.example", "https://ok.example"],
        deniedOrigins: ["https://both.example"],
    });
    const r = validateProxySettings(both);
    assert.equal(r.valid, true);
    assert.deepEqual(r.settings.allowedOrigins, ["https://ok.example"]);
    assert.deepEqual(r.settings.deniedOrigins, ["https://both.example"]);
    assert.equal(socketPermission(both, "https://both.example"), "deny");
    assert.equal(resolveSocketAccess(both, "https://both.example"), undefined);
});
test("settings saved before the first-use prompt have no refused sites", () => {
    const old = {
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: ["https://mole.61.com.tw"],
        defaultsVersion: 2,
    };
    const r = validateProxySettings(old);
    assert.equal(r.valid, true);
    assert.deepEqual(r.settings.deniedOrigins, []);
    assert.equal(socketPermission(old, "https://mole.61.com.tw"), "allow");
    assert.equal(socketPermission(old, "https://other.example"), "ask");
});
test("the refused list is validated like the allowed list", () => {
    for (const deniedOrigins of ["https://no.example", [1], [{}]]) {
        assert.deepEqual(
            validateProxySettings({ ...helperSettings(), deniedOrigins }),
            { valid: false, error: "invalid_settings" },
            JSON.stringify(deniedOrigins),
        );
    }
    for (const entry of [
        "*",
        "https://*.example",
        "https://a.example/path",
        "file:///a",
        "https://u:p@a.example",
    ]) {
        assert.deepEqual(
            validateProxySettings({
                ...helperSettings(),
                deniedOrigins: [entry],
            }),
            { valid: false, error: "invalid_origin" },
            entry,
        );
    }
    const r = validateProxySettings(
        helperSettings({
            deniedOrigins: ["HTTPS://NO.EXAMPLE/", "https://no.example", ""],
        }),
    );
    assert.deepEqual(r.settings.deniedOrigins, ["https://no.example"]);
});
test("choosing for a website moves it between the lists", () => {
    const start = validateProxySettings(helperSettings()).settings;
    const allowed = setSocketChoice(start, "https://New.Example/", "allow");
    assert.deepEqual(allowed.allowedOrigins, [
        "https://mole.61.com.tw",
        "https://ok.example",
        "https://new.example",
    ]);
    const denied = setSocketChoice(allowed, "https://new.example", "deny");
    assert.ok(!denied.allowedOrigins.includes("https://new.example"));
    assert.deepEqual(denied.deniedOrigins, [
        "https://no.example",
        "https://new.example",
    ]);
    const asked = setSocketChoice(denied, "https://new.example", "ask");
    assert.ok(!asked.allowedOrigins.includes("https://new.example"));
    assert.ok(!asked.deniedOrigins.includes("https://new.example"));
    assert.equal(socketPermission(asked, "https://new.example"), "ask");
    // Choosing again does not duplicate; other settings and the input stay as they were.
    assert.deepEqual(
        setSocketChoice(allowed, "https://new.example", "allow"),
        allowed,
    );
    assert.deepEqual(start.deniedOrigins, ["https://no.example"]);
    assert.equal(asked.mode, "helper");
    assert.equal(asked.defaultsVersion, start.defaultsVersion);
    for (const bad of ["null", "file:///a", "https://a.example/x", "*", ""]) {
        assert.throws(() => setSocketChoice(start, bad, "allow"), bad);
    }
});
test("only the helper asks; a custom proxy never reaches an unlisted site", () => {
    assert.equal(promptsForUnlisted(helperSettings()), true);
    assert.equal(promptsForUnlisted(helperSettings({ enabled: false })), false);
    assert.equal(promptsForUnlisted(settings), false);
    assert.equal(promptsForUnlisted(undefined), false);
    // A site that is asked gets the helper URL (no secret) so an attempt reaches the check.
    assert.deepEqual(
        askSocketProxies(helperSettings(), "https://new.example"),
        [{ host: "*", port: 0, proxyUrl: HELPER_PROXY_URL }],
    );
    // Listed, refused, switched off, no origin, and websocket mode: nothing to ask.
    for (const [s, origin] of [
        [helperSettings(), "https://ok.example"],
        [helperSettings(), "https://no.example"],
        [helperSettings({ enabled: false }), "https://new.example"],
        [helperSettings(), undefined],
        [helperSettings(), "file:///a.swf"],
        [{ ...settings, deniedOrigins: [] }, "https://new.example"],
    ]) {
        assert.deepEqual(askSocketProxies(s, origin), [], String(origin));
    }
    // The Ruffle config of a site that is only asked about stays untouched.
    assert.deepEqual(
        applyProxySettings({}, helperSettings(), "https://new.example"),
        {},
    );
});

test("each mode has its own allow-list: a website allowed for the helper never gets the proxy token", () => {
    const both = {
        ...defaultProxySettings(),
        allowedOrigins: ["https://helper.example"],
        proxyOrigins: ["https://proxy.example"],
        proxyUrl: url,
    };
    // Helper mode: only the helper list counts, and its sites get the helper URL.
    assert.equal(socketPermission(both, "https://helper.example"), "allow");
    assert.equal(socketPermission(both, "https://proxy.example"), "ask");
    assert.deepEqual(
        applyProxySettings({}, both, "https://helper.example").socketProxy,
        [{ host: "*", port: 0, proxyUrl: HELPER_PROXY_URL }],
    );
    assert.deepEqual(applyProxySettings({}, both, "https://proxy.example"), {});
    // Custom proxy mode: the other list, the token only for its sites.
    const custom = { ...both, mode: "websocket" };
    assert.equal(socketPermission(custom, "https://helper.example"), "ask");
    assert.equal(socketPermission(custom, "https://proxy.example"), "allow");
    assert.deepEqual(
        applyProxySettings({}, custom, "https://helper.example"),
        {},
    );
    assert.deepEqual(
        applyProxySettings({}, custom, "https://proxy.example").socketProxy,
        [{ host: "*", port: 0, proxyUrl: url }],
    );
    assert.equal(
        resolveSocketAccess(custom, "https://helper.example"),
        undefined,
    );
});
test("one click in helper mode, then switching to a custom proxy: the clicked website gets no token", () => {
    const start = defaultProxySettings();
    const clicked = setSocketChoice(start, "https://evil.example", "allow");
    assert.equal(socketPermission(clicked, "https://evil.example"), "allow");
    const switched = { ...clicked, mode: "websocket", proxyUrl: url };
    assert.equal(validateProxySettings(switched).valid, true);
    assert.deepEqual(
        applyProxySettings({}, switched, "https://evil.example"),
        {},
    );
    assert.equal(socketPermission(switched, "https://evil.example"), "ask");
    // The default sites were on both lists and keep the token they were given.
    assert.deepEqual(
        applyProxySettings({}, switched, "https://mole.61.com.tw").socketProxy,
        [{ host: "*", port: 0, proxyUrl: url }],
    );
});
test("settings saved before the lists were separated use their list for both modes", () => {
    const legacy = {
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: ["https://typed.example"],
        deniedOrigins: [],
        defaultsVersion: DEFAULTS_VERSION,
    };
    const r = validateProxySettings(legacy);
    assert.equal(r.valid, true);
    assert.deepEqual(r.settings.proxyOrigins, ["https://typed.example"]);
    // Nothing aliases: changing one list leaves the other list alone.
    const changed = setSocketChoice(
        r.settings,
        "https://more.example",
        "allow",
    );
    assert.deepEqual(changed.proxyOrigins, ["https://typed.example"]);
    // A saved separate list is kept as it is, even when empty.
    assert.deepEqual(
        validateProxySettings({ ...legacy, proxyOrigins: [] }).settings
            .proxyOrigins,
        [],
    );
});
test("the proxy list is validated like the other lists, and refusing wins on both", () => {
    for (const proxyOrigins of ["https://a.example", [1], [{}]]) {
        assert.deepEqual(
            validateProxySettings({ ...helperSettings(), proxyOrigins }),
            { valid: false, error: "invalid_settings" },
            JSON.stringify(proxyOrigins),
        );
    }
    for (const entry of ["*", "https://a.example/path", "file:///a"]) {
        assert.deepEqual(
            validateProxySettings({
                ...helperSettings(),
                proxyOrigins: [entry],
            }),
            { valid: false, error: "invalid_origin" },
            entry,
        );
    }
    const r = validateProxySettings(
        helperSettings({
            allowedOrigins: ["https://both.example"],
            proxyOrigins: ["https://both.example", "https://ok.example"],
            deniedOrigins: ["https://both.example"],
        }),
    );
    assert.deepEqual(r.settings.allowedOrigins, []);
    assert.deepEqual(r.settings.proxyOrigins, ["https://ok.example"]);
    // A custom proxy needs a website on ITS list, whatever the helper list holds.
    assert.deepEqual(
        validateProxySettings({
            ...settings,
            allowedOrigins: ["https://helper.example"],
            proxyOrigins: [],
        }),
        { valid: false, error: "origins_required" },
    );
});
test("allowing and forgetting concern the current mode's list; refusing is final for both", () => {
    const custom = {
        ...validateProxySettings({
            ...helperSettings(),
            mode: "websocket",
            proxyUrl: url,
            proxyOrigins: ["https://p.example"],
            allowedOrigins: ["https://h.example"],
        }).settings,
    };
    const allowed = setSocketChoice(custom, "https://new.example", "allow");
    assert.deepEqual(allowed.proxyOrigins, [
        "https://p.example",
        "https://new.example",
    ]);
    assert.deepEqual(allowed.allowedOrigins, ["https://h.example"]);
    // "Ask" in custom proxy mode does not silently take the site off the helper list.
    const forgotten = setSocketChoice(allowed, "https://h.example", "ask");
    assert.deepEqual(forgotten.allowedOrigins, ["https://h.example"]);
    const forgottenHere = setSocketChoice(allowed, "https://p.example", "ask");
    assert.deepEqual(forgottenHere.proxyOrigins, ["https://new.example"]);
    // Refusing takes the site off both lists, whichever mode the click was in.
    const refused = setSocketChoice(
        { ...allowed, allowedOrigins: ["https://new.example"] },
        "https://new.example",
        "deny",
    );
    assert.deepEqual(refused.allowedOrigins, []);
    assert.deepEqual(refused.proxyOrigins, ["https://p.example"]);
    assert.ok(refused.deniedOrigins.includes("https://new.example"));
    // Allowing a refused site lifts the refusal.
    assert.ok(
        !setSocketChoice(
            refused,
            "https://new.example",
            "allow",
        ).deniedOrigins.includes("https://new.example"),
    );
});
