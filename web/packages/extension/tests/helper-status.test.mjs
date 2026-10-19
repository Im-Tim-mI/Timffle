// What the settings page, the popup's notice and the install page say about the socket helper.
import test from "node:test";
import assert from "node:assert/strict";
import {
    helperVerdict,
    needsInstaller,
    noticeMessage,
    statusMessage,
} from "../src/helper-status.ts";
import { fakeI18n, languages } from "./catalog-support.mjs";

const originalBrowser = globalThis.browser;
test.afterEach(() => {
    globalThis.browser = originalBrowser;
});

test("the background's answer becomes one of four verdicts", () => {
    assert.deepEqual(helperVerdict({ installed: true, version: "1.2.0", protocol: 2 }), {
        kind: "installed",
        version: "1.2.0",
    });
    assert.deepEqual(helperVerdict({ installed: true }), { kind: "installed", version: "?" });
    assert.deepEqual(helperVerdict({ installed: false, error: "helper_missing" }), { kind: "missing" });
    assert.deepEqual(
        helperVerdict({ installed: false, version: "1.0.0", protocol: 1, error: "helper_incompatible" }),
        { kind: "incompatible" },
    );
    for (const error of ["helper_timeout", "helper_failed", "socket_limit", "bridge_closed", "no_response", undefined]) {
        assert.deepEqual(
            helperVerdict({ installed: false, ...(error === undefined ? {} : { error }) }),
            { kind: "unavailable" },
            String(error),
        );
    }
});

test("only a missing or mismatched helper is fixed by running the installer", () => {
    assert.equal(needsInstaller({ kind: "missing" }), true);
    assert.equal(needsInstaller({ kind: "incompatible" }), true);
    assert.equal(needsInstaller({ kind: "installed", version: "1.2.0" }), false);
    assert.equal(needsInstaller({ kind: "unavailable" }), false);
});

const VERDICTS = [
    [{ kind: "installed", version: "1.2.0" }, "timffle_helper_installed"],
    [{ kind: "missing" }, "timffle_helper_missing"],
    [{ kind: "incompatible" }, "timffle_helper_incompatible"],
    [{ kind: "unavailable" }, "timffle_helper_unavailable"],
];

test("every verdict has its own status line, in every language", () => {
    for (const language of languages) {
        globalThis.browser = { i18n: fakeI18n(language) };
        const shown = new Set();
        for (const [verdict, key] of VERDICTS) {
            const expected = fakeI18n(language).getMessage(key, verdict.version === undefined ? undefined : [verdict.version]);
            assert.notEqual(expected, "", `${language}/${key}`);
            assert.equal(statusMessage(verdict), expected, `${language}/${key}`);
            shown.add(statusMessage(verdict));
        }
        assert.equal(shown.size, 4, language);
    }
});

test("the installed line names the version the helper reported", () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    assert.equal(statusMessage({ kind: "installed", version: "1.2.0" }), "Installed (version 1.2.0)");
    globalThis.browser = { i18n: fakeI18n("zh_TW") };
    assert.equal(statusMessage({ kind: "installed", version: "1.2.0" }), "已安裝（版本 1.2.0）");
});

test("the popup's notice says what is wrong, and says nothing when the installer is not the fix", () => {
    for (const language of languages) {
        const catalog = fakeI18n(language);
        globalThis.browser = { i18n: catalog };
        const missing = noticeMessage({ kind: "missing" });
        const mismatch = noticeMessage({ kind: "incompatible" });
        assert.equal(missing, catalog.getMessage("timffle_helper_notice_missing"), language);
        assert.equal(mismatch, catalog.getMessage("timffle_helper_notice_incompatible"), language);
        assert.ok(missing && mismatch && missing !== mismatch, language);
        assert.equal(noticeMessage({ kind: "installed", version: "1.2.0" }), undefined, language);
        assert.equal(noticeMessage({ kind: "unavailable" }), undefined, language);
    }
});

test("the notice and its button are in the language of the browser, not a fixed pair of languages", () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    assert.equal(
        noticeMessage({ kind: "missing" }),
        "The socket helper is not installed, so online games cannot connect.",
    );
    globalThis.browser = { i18n: fakeI18n("zh_TW") };
    assert.equal(noticeMessage({ kind: "missing" }), "尚未安裝連線小幫手，線上遊戲無法連線。");
    globalThis.browser = { i18n: fakeI18n("ja") };
    assert.doesNotMatch(noticeMessage({ kind: "missing" }), /[A-Za-z]{6}/u);
});
