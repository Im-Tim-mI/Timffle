// prompt.html serves two windows: the first-use question and "install the socket helper first". Its script and its
// page have to agree, and the install window has to start with nothing offered that cannot work yet.
import test from "node:test";
import assert from "node:assert/strict";
import {
    fakeI18n,
    languages,
    readCatalog,
    readSources,
} from "./catalog-support.mjs";
import {
    HELPER_INSTALLERS,
    installStep,
    linuxCommand,
} from "../src/helper-download.ts";

const html = readSources("assets", ".html")["prompt.html"];
const script = readSources("src", ".ts")["prompt.ts"];

/** The element with this id, as written in the page: its opening tag. */
function tag(id) {
    const match = html.match(
        new RegExp(`<[a-z0-9]+\\b[^>]*\\bid="${id}"[^>]*>`, "u"),
    );
    assert.ok(match, `prompt.html has no element #${id}`);
    return match[0];
}

test("every element the script looks for is in the page", () => {
    // Looked up by name, or handed over by name (showOrigin takes the ids of the three elements it fills).
    const ids = new Set([
        ...[...script.matchAll(/getElementById\("([^"]+)"\)/gu)].map(
            (m) => m[1],
        ),
        ...[
            ...script.matchAll(
                /\b(?:origin|embedded|embeddedOrigin): "([^"]+)"/gu,
            ),
        ].map((m) => m[1]),
    ]);
    assert.ok(
        ids.size >= 12,
        "the script looks up the elements of both windows",
    );
    for (const id of ids) {
        tag(id);
    }
    // Both windows, and the place for a request that has ended.
    for (const id of ["prompt", "helper", "expired"]) {
        assert.match(tag(id), /<main\b/u);
        assert.match(tag(id), /\bhidden\b/u, `#${id} starts hidden`);
    }
});

test("ids are not used twice, and the page runs one script of its own and nothing inline", () => {
    const ids = [...html.matchAll(/\bid="([^"]+)"/gu)].map((m) => m[1]);
    assert.equal(new Set(ids).size, ids.length);
    assert.deepEqual(
        [...html.matchAll(/<script\b[^>]*>/gu)].map((m) => m[0]),
        ['<script src="dist/prompt.js">'],
    );
    assert.doesNotMatch(html, /\son[a-z]+="/u);
});

test("the install window offers a download only once it knows what it would download, and its controls are plain buttons", () => {
    // Hidden until the system is known; the name of the system also starts hidden.
    assert.match(tag("helper-download"), /\bhidden\b/u);
    assert.match(tag("helper-for"), /\bhidden\b/u);
    assert.match(tag("helper-embedded"), /\bhidden\b/u);
    // What is wrong is announced to screen readers; the window has a title of its own.
    assert.match(tag("helper-text"), /\brole="status"/u);
    assert.match(
        script,
        /document\.title = text\("timffle_helper_prompt_title"\)/u,
    );
    for (const id of ["helper-download", "helper-more", "helper-close", "helper-continue"]) {
        assert.match(tag(id), /<button\b[^>]*\btype="button"/u, id);
    }
    // The link to the other installers is a button, so that the window's input guard sees every way out of the page.
    assert.doesNotMatch(
        html.slice(html.indexOf('id="helper"'), html.indexOf('id="expired"')),
        /<a\b/u,
    );
    // The window says whose connection it was with text, never markup.
    assert.match(
        script,
        /getElementById\("helper-origin"\)!?\.textContent|ids\.origin\)!\.textContent/u,
    );
    assert.doesNotMatch(script, /innerHTML|insertAdjacentHTML/u);
});

test("the install window has a heading in every language, and it is not the install page's heading", () => {
    assert.equal(
        readCatalog("en")["timffle_helper_prompt_title"].message,
        "Install the socket helper first",
    );
    assert.equal(
        readCatalog("zh_TW")["timffle_helper_prompt_title"].message,
        "請先安裝連線小幫手",
    );
    const english = readCatalog("en")["timffle_helper_prompt_title"].message;
    for (const language of languages) {
        const catalog = readCatalog(language);
        const heading = catalog["timffle_helper_prompt_title"]?.message;
        assert.equal(typeof heading, "string", language);
        assert.ok(
            heading.length > 0 && heading.length <= 60,
            `${language}: ${heading}`,
        );
        assert.doesNotMatch(heading, /[$<>{}]/u, language);
        // It says "first": more than the page's heading, which it would otherwise repeat.
        assert.notEqual(
            heading,
            catalog["timffle_helper_page_heading"].message,
            language,
        );
        if (language !== "en") {
            assert.notEqual(heading, english, `${language} is still English`);
        }
    }
});

test("a website on the local network is told what it may reach: the address it comes from, twice, in every language", () => {
    // The page has the usual text; for such a website the script puts the other one in its place before the question is shown.
    assert.match(tag("prompt-what"), /\bclass="what"[^>]*\bdata-i18n="timffle_prompt_what"/u);
    assert.match(script, /const lan = lanHostOf\(view\.origin\);/u);
    assert.match(
        script,
        /getElementById\("prompt-what"\)!\.textContent = text\(\s*"timffle_prompt_what_lan",\s*lan,\s*\)/u,
    );
    const question = script.slice(script.indexOf("function runQuestion"));
    assert.ok(
        question.indexOf('"timffle_prompt_what_lan"') <
            question.indexOf('show("prompt")'),
    );
    for (const language of languages) {
        const i18n = fakeI18n(language);
        const what = i18n.getMessage("timffle_prompt_what_lan", "192.168.0.5");
        assert.equal(what.split("192.168.0.5").length, 3, `${language}: ${what}`);
        assert.doesNotMatch(what, /\$/u, language);
        assert.notEqual(what, i18n.getMessage("timffle_prompt_what"), language);
    }
    assert.equal(
        fakeI18n("en").getMessage("timffle_prompt_what_lan", "fd00::1"),
        "Flash content on this website wants to open TCP (socket) connections. The website is on your local network (fd00::1). Only online games need this. If allowed, it can reach fd00::1 (the computer this website comes from) and any server on the internet. Other devices on your local network stay out of reach.",
    );
});

/** The install window's part of the page, and of the script. */
const helperHtml = html.slice(html.indexOf('<main id="helper"'), html.indexOf('<main id="expired"'));
const helperScript = script.slice(
    script.indexOf("async function runHelperNotice"),
    script.indexOf("function runQuestion"),
);

test("the install window starts waiting: no step before the system is known, a wait line that says it waits, Continue off", () => {
    // The step is filled in once the system is known; its first child is the place of the Linux command.
    assert.match(tag("helper-step"), /\bhidden\b/u);
    assert.match(html, /<p id="helper-step" class="helper-step" hidden><code dir="ltr" translate="no"><\/code><\/p>/u);
    // The wait line is read out when it changes, and says what the window waits for from the start.
    const wait = tag("helper-wait");
    for (const attribute of ['role="status"', 'aria-live="polite"', 'data-state="waiting"', 'data-i18n="timffle_helper_waiting"']) {
        assert.ok(wait.includes(attribute), `${wait} lacks ${attribute}`);
    }
    assert.doesNotMatch(wait, /\bhidden\b/u);
    // Continue is off, plain and not yet marked; it sits next to Close, after it.
    const proceed = tag("helper-continue");
    assert.match(proceed, /\sdisabled[\s>]/u);
    assert.match(proceed, /data-i18n="timffle_helper_continue"/u);
    assert.doesNotMatch(proceed, /recommended|data-ready/u);
    assert.match(
        helperHtml,
        /<div class="helper-end">\s*<button type="button" id="helper-close" data-i18n="timffle_close"><\/button>\s*<button type="button" id="helper-continue" [^>]*><\/button>\s*<\/div>/u,
    );
    // Top to bottom: the download, the way to the others, how to run it, the wait, the two buttons.
    const at = (id) => helperHtml.indexOf(`id="${id}"`);
    const order = ["helper-download", "helper-more", "helper-step", "helper-wait", "helper-close", "helper-continue"];
    assert.deepEqual([...order].sort((a, b) => at(a) - at(b)), order);
    // Inside the box whose recommended button is highlighted, so that Continue can be.
    assert.ok(helperHtml.indexOf('class="helper-actions"') < at("helper-continue"));
    const css = readSources("assets/css", ".css")["prompt.css"];
    assert.match(css, /\.helper-actions \.recommended \{/u);
    assert.match(css, /\.helper-end \{\s*display: grid;\s*grid-template-columns: 1fr 1fr;/u);
});

test("the install window keeps no text of its own, and has no room for the install page's introduction", () => {
    assert.equal(helperHtml.replace(/<[^>]*>/gu, "").trim(), "");
    assert.doesNotMatch(helperHtml, /timffle_helper_page_intro/u);
});

test("the window waits with the background's status question, from the start and at once when the visitor comes back, until the page goes", () => {
    assert.match(
        helperScript,
        /waitForHelper\(\{\s*query: queryHelper,\s*minVersion: view\.minVersion,\s*ready: \(version\) =>\s*showHelperReady\(wait, proceed, version, download\),\s*\}\)/u,
    );
    // The default pace: the window does not choose one of its own.
    assert.doesNotMatch(helperScript, /pollMs|active:/u);
    assert.match(helperScript, /window\.addEventListener\("focus", \(\) => waiting\.check\(\)\)/u);
    assert.match(
        helperScript,
        /document\.addEventListener\("visibilitychange", \(\) => \{\s*if \(document\.visibilityState === "visible"\) \{\s*waiting\.check\(\);/u,
    );
    assert.match(helperScript, /window\.addEventListener\("pagehide", \(\) => waiting\.stop\(\)\)/u);
    assert.match(script, /from "\.\/helper-status"/u);
});

test("Continue goes through the window's input guard and sends nothing but the window's id; only the background closes the window", () => {
    assert.match(helperScript, /for \(const control of \[download, more, close, proceed\]\) \{\s*watch\(control\);/u);
    const handler = helperScript.slice(
        helperScript.indexOf('proceed.addEventListener("click"'),
        helperScript.indexOf("waitForHelper("),
    );
    assert.match(handler, /if \(continuing \|\| proceed\.disabled \|\| !counts\(proceed, event\)\) \{\s*return;/u);
    assert.match(handler, /\.sendMessage\(\{ type: HELPER_CONTINUE_REQUEST, id \}\)/u);
    assert.equal([...handler.matchAll(/sendMessage/gu)].length, 1);
    assert.doesNotMatch(handler, /window\.close\(\)|browser\.tabs|\.reload\(/u);
    // A reply that is not "reloaded" means the window's request has ended.
    assert.match(handler, /if \(!reloaded\) \{[^}]*show\("expired"\);/u);
});

test("the download no longer changes what the window says is wrong: the wait line tells what comes next", () => {
    assert.doesNotMatch(script, /timffle_helper_download_started/u);
    assert.match(helperScript, /started: \(\) => \{\},/u);
    assert.equal([...helperScript.matchAll(/message\.textContent =/gu)].length, 1);
});

test("the step under the download is that system's line of the install page, and the Linux one names the file that was offered", () => {
    const original = globalThis.browser;
    try {
        for (const language of ["en", "zh_TW", "de", "ar"]) {
            const i18n = fakeI18n(language);
            globalThis.browser = { i18n };
            for (const installer of HELPER_INSTALLERS) {
                const want =
                    installer.family === "linux"
                        ? i18n.getMessage("timffle_helper_step_linux", [linuxCommand(installer)])
                        : i18n.getMessage(`timffle_helper_step_${installer.family}`);
                assert.equal(installStep(installer), want, `${language}/${installer.id}`);
                if (installer.family === "linux") {
                    assert.ok(
                        installStep(installer).includes(`<1>tar xzf ${installer.file} && ./${installer.file.replace(".tar.gz", "")}</1>`),
                        `${language}/${installer.id}`,
                    );
                } else {
                    assert.doesNotMatch(installStep(installer), /<\/?\d>|\$/u, `${language}/${installer.id}`);
                }
            }
        }
    } finally {
        globalThis.browser = original;
    }
    // Shown only for a system that has an installer, after the button knows what it downloads.
    assert.match(
        helperScript,
        /download\.hidden = installer === undefined;\s*if \(installer !== undefined\) \{\s*fillRich\(step, installStep\(installer\)\);\s*step\.hidden = false;\s*\}/u,
    );
});
