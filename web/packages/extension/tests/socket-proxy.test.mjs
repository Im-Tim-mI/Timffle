import test from "node:test";
import assert from "node:assert/strict";
import { URL } from "node:url";
import {
    defaultProxySettings,
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
        defaultsVersion: DEFAULTS_VERSION,
    });
    assert.deepEqual(defaults.allowedOrigins, DEFAULT_ALLOWED_ORIGINS);
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
    assert.deepEqual(r.settings, settings);
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
test("enabled settings require an explicit trusted origin", () =>
    assert.equal(
        validateProxySettings({ ...settings, allowedOrigins: [] }).valid,
        false,
    ));
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
