// What the popup's socket section says about a website, in the language of the browser.
import test from "node:test";
import assert from "node:assert/strict";
import { describeSite, stateText } from "../src/popup-socket.ts";
import { defaultProxySettings, setSocketChoice } from "../src/socket-proxy.ts";
import { fakeI18n, languages } from "./catalog-support.mjs";

const originalBrowser = globalThis.browser;
test.afterEach(() => {
    globalThis.browser = originalBrowser;
});

const SITE = "https://new.example";
const settings = (mode = "helper", enabled = true) => ({ ...defaultProxySettings(), enabled, mode });

/** Every state the section can be in for the website, with the catalog key that describes it. */
function states() {
    const proxy = { ...settings("websocket"), proxyUrl: "ws://127.0.0.1:1/c?host={host}&port={port}" };
    return [
        [describeSite(settings("helper", false), SITE), "timffle_popup_off"],
        [describeSite(setSocketChoice(settings(), SITE, "allow"), SITE), "timffle_popup_always_allowed"],
        [describeSite(setSocketChoice(settings(), SITE, "deny"), SITE), "timffle_popup_always_denied"],
        [describeSite(settings(), SITE), "timffle_choice_ask"],
        [describeSite(settings(), SITE, "allow"), "timffle_popup_visit_allowed"],
        [describeSite(settings(), SITE, "deny"), "timffle_popup_visit_denied"],
        [describeSite(proxy, SITE), "timffle_popup_proxy_not_allowed"],
        // An answer for this visit counts only while the website has no lasting choice.
        [describeSite(setSocketChoice(settings(), SITE, "allow"), SITE, "deny"), "timffle_popup_always_allowed"],
    ];
}

test("every state of a website has its own text, in every language", () => {
    for (const language of languages) {
        globalThis.browser = { i18n: fakeI18n(language) };
        const shown = new Set();
        for (const [state, key] of states()) {
            const expected = fakeI18n(language).getMessage(key);
            assert.notEqual(expected, "", `${language}/${key}`);
            assert.equal(stateText(state), expected, `${language}: ${JSON.stringify(state)}`);
            shown.add(stateText(state));
        }
        // "Always allowed" appears twice in the table above, everything else is distinct.
        assert.equal(shown.size, 7, language);
    }
});

test("the text follows the language, not a fixed pair of languages", () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    assert.equal(stateText(describeSite(settings(), SITE)), "Ask on every visit");
    globalThis.browser = { i18n: fakeI18n("zh_TW") };
    assert.equal(stateText(describeSite(settings(), SITE)), "每次造訪時詢問");
    globalThis.browser = { i18n: fakeI18n("ja") };
    assert.doesNotMatch(stateText(describeSite(settings(), SITE)), /[A-Za-z]{4}/u);
});
