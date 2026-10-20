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
    // The sentence that turns into "Download started" is announced to screen readers; the window has a title of its own.
    assert.match(tag("helper-text"), /\brole="status"/u);
    assert.match(
        script,
        /document\.title = text\("timffle_helper_prompt_title"\)/u,
    );
    for (const id of ["helper-download", "helper-more", "helper-close"]) {
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
