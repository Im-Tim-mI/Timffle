// The install page (helper.html, src/helper.ts) looks again by itself while it is shown and the helper is not there,
// so that its status line changes after the installer has run without a click on "Check again".
import test from "node:test";
import assert from "node:assert/strict";
import { setImmediate } from "node:timers";
import { helperVerdict, showStatus } from "../src/helper-status.ts";
import { HELPER_PAGE_REFRESH_MS, waitForHelper } from "../src/helper-wait.ts";
import { fakeI18n, readSources } from "./catalog-support.mjs";

const page = readSources("src", ".ts")["helper.ts"];
const html = readSources("assets", ".html")["helper.html"];
const tick = () => new Promise((resolve) => setImmediate(resolve));
const MISSING = { installed: false, error: "helper_missing" };
const INSTALLED = { installed: true, version: "1.4.0", protocol: 2 };

const originalBrowser = globalThis.browser;
test.beforeEach(() => {
    globalThis.browser = { i18n: fakeI18n("en") };
});
test.afterEach(() => {
    globalThis.browser = originalBrowser;
});

/** The status line: it counts every time it is written, text or state. */
function statusLine(text = "", state = undefined) {
    const written = [];
    const data = state === undefined ? {} : { state };
    return {
        written,
        get textContent() {
            return text;
        },
        set textContent(value) {
            written.push(["text", value]);
            text = value;
        },
        dataset: new Proxy(data, {
            set(target, key, value) {
                written.push([key, value]);
                target[key] = value;
                return true;
            },
        }),
    };
}

test("the status line is written when what it says changes, and left alone when it says that already", () => {
    const en = fakeI18n("en");
    const line = statusLine();
    showStatus(line, { kind: "missing" });
    assert.equal(line.textContent, en.getMessage("timffle_helper_missing"));
    assert.equal(line.dataset.state, "error");
    assert.equal(line.written.length, 2);
    showStatus(line, { kind: "missing" });
    assert.equal(line.written.length, 2, "the same again: not touched");
    showStatus(line, { kind: "unavailable" });
    assert.equal(line.textContent, en.getMessage("timffle_helper_unavailable"));
    assert.equal(line.written.length, 4);
    showStatus(line, { kind: "installed", version: "1.4.0" });
    assert.equal(
        line.textContent,
        en.getMessage("timffle_helper_installed", ["1.4.0"]),
    );
    assert.equal(line.dataset.state, "info");
    showStatus(line, { kind: "installed", version: "1.4.0" });
    assert.equal(line.written.length, 6);
    // The same words in another state (the page's "Checking…" is info) are written again.
    const checking = statusLine(
        en.getMessage("timffle_helper_missing"),
        "info",
    );
    showStatus(checking, { kind: "missing" });
    assert.deepEqual(checking.written, [
        ["text", en.getMessage("timffle_helper_missing")],
        ["state", "error"],
    ]);
});

/**
 * The install page's refresh, put together as src/helper.ts does (the last test checks that it does): a page that can
 * be shown or not, a check of its own under way or not, and a helper whose answers the test gives one at a time.
 */
function installPage(t) {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const doc = { visibilityState: "visible" };
    let checking = false;
    const status = statusLine(
        fakeI18n("en").getMessage("timffle_helper_missing"),
        "error",
    );
    const answers = [];
    let asked = 0;
    const queryHelper = async () => {
        asked++;
        return answers.shift() ?? MISSING;
    };
    const refresh = waitForHelper({
        query: queryHelper,
        pollMs: HELPER_PAGE_REFRESH_MS,
        active: () => doc.visibilityState === "visible" && !checking,
        notYet: (answer) => showStatus(status, helperVerdict(answer)),
        ready: (version) => showStatus(status, { kind: "installed", version }),
    });
    return {
        doc,
        status,
        answers,
        refresh,
        get asked() {
            return asked;
        },
        setChecking: (value) => (checking = value),
        async wait(ms) {
            t.mock.timers.tick(ms);
            await tick();
        },
    };
}

test("while it is shown the page asks every 3 seconds, writes nothing while the answer stays the same, and stops once the helper is there", async (t) => {
    const p = installPage(t);
    await p.wait(HELPER_PAGE_REFRESH_MS - 1);
    assert.equal(p.asked, 0);
    await p.wait(1);
    assert.equal(p.asked, 1);
    await p.wait(HELPER_PAGE_REFRESH_MS);
    await p.wait(HELPER_PAGE_REFRESH_MS);
    assert.equal(p.asked, 3);
    assert.deepEqual(
        p.status.written,
        [],
        "still missing: no flicker, nothing read out again",
    );
    p.answers.push(INSTALLED);
    await p.wait(HELPER_PAGE_REFRESH_MS);
    assert.equal(p.asked, 4);
    assert.equal(
        p.status.textContent,
        fakeI18n("en").getMessage("timffle_helper_installed", ["1.4.0"]),
    );
    assert.equal(p.status.dataset.state, "info");
    await p.wait(HELPER_PAGE_REFRESH_MS * 10);
    assert.equal(p.asked, 4, "no more questions once it is installed");
});

test("the page does not ask while it is hidden or while its own check is under way", async (t) => {
    const p = installPage(t);
    p.doc.visibilityState = "hidden";
    await p.wait(HELPER_PAGE_REFRESH_MS * 4);
    assert.equal(p.asked, 0);
    p.doc.visibilityState = "visible";
    p.setChecking(true);
    await p.wait(HELPER_PAGE_REFRESH_MS * 2);
    assert.equal(p.asked, 0);
    p.setChecking(false);
    await p.wait(HELPER_PAGE_REFRESH_MS);
    assert.equal(p.asked, 1);
    // Another answer than before (the helper started but did not answer) is written.
    p.answers.push({ installed: false, error: "helper_timeout" });
    await p.wait(HELPER_PAGE_REFRESH_MS);
    assert.equal(
        p.status.textContent,
        fakeI18n("en").getMessage("timffle_helper_unavailable"),
    );
});

test("the page is wired as tested: the refresh above, the check of its own kept, and the refresh stopped when that check finds the helper", () => {
    assert.match(
        page,
        /const refresh = waitForHelper\(\{\s*query: queryHelper,\s*pollMs: HELPER_PAGE_REFRESH_MS,\s*active: \(\) => document\.visibilityState === "visible" && !checking,\s*notYet: \(answer\) => showStatus\(status, helperVerdict\(answer\)\),\s*ready: \(version\) => showStatus\(status, \{ kind: "installed", version \}\),\s*\}\);/u,
    );
    const run = page.slice(
        page.indexOf("async function run()"),
        page.indexOf('check.addEventListener("click"'),
    );
    // "Check again" still says "Checking…" and is off while it checks.
    assert.match(
        run,
        /check\.disabled = true;\s*status\.textContent = text\("timffle_helper_checking"\);/u,
    );
    assert.match(
        run,
        /showStatus\(status, verdict\);\s*if \(verdict\.kind === "installed"\) \{\s*refresh\.stop\(\);\s*\}/u,
    );
    assert.match(
        page,
        /check\.addEventListener\("click", \(\) => void run\(\)\);/u,
    );
    assert.match(
        page,
        /document\.addEventListener\("visibilitychange", \(\) => \{\s*if \(document\.visibilityState === "visible"\) \{\s*void run\(\);/u,
    );
    // No Continue there, and no new text.
    assert.doesNotMatch(
        html,
        /continue|timffle_helper_waiting|timffle_helper_ready/u,
    );
});
