import test from "node:test";
import assert from "node:assert/strict";
import { fillRich, localizePage, splitRich, text } from "../src/i18n.ts";
import { fakeI18n } from "./catalog-support.mjs";

const originalBrowser = globalThis.browser;
const originalDocument = globalThis.document;

test.afterEach(() => {
    globalThis.browser = originalBrowser;
    globalThis.document = originalDocument;
});

/** Just enough of a DOM for fillRich and localizePage. */
class FakeNode {
    constructor(tag, attributes = {}) {
        this.tag = tag;
        this.attributes = attributes;
        this.childNodes = [];
        this.own = "";
    }
    get children() {
        return this.childNodes.filter((node) => node instanceof FakeNode);
    }
    get dataset() {
        const data = {};
        for (const [name, value] of Object.entries(this.attributes)) {
            if (name.startsWith("data-")) {
                data[name.slice(5).replace(/-(\w)/gu, (_, c) => c.toUpperCase())] = value;
            }
        }
        return data;
    }
    set textContent(value) {
        this.childNodes = [];
        this.own = value;
    }
    get textContent() {
        return this.own + this.childNodes.map((node) => node.textContent).join("");
    }
    cloneNode(deep) {
        assert.equal(deep, false, "templates are cloned without their content");
        return new FakeNode(this.tag, { ...this.attributes });
    }
    replaceChildren(...nodes) {
        this.own = "";
        this.childNodes = nodes;
    }
}
class FakeText {
    constructor(value) {
        this.textContent = value;
    }
}
function fakeDocument(marked) {
    return {
        createTextNode: (value) => new FakeText(value),
        querySelectorAll: (selector) =>
            marked.filter((node) =>
                Object.keys(node.attributes).includes(selector.slice(1, -1)),
            ),
    };
}

test("text() gives the catalog's message, and the key itself when there is none", () => {
    globalThis.browser = { i18n: fakeI18n("zh_TW") };
    assert.equal(text("timffle_choice_deny"), "一律拒絕");
    assert.equal(text("timffle_no_such_text"), "timffle_no_such_text");
});

test("text() fills placeholders from the substitutions", () => {
    globalThis.browser = { i18n: fakeI18n("en") };
    assert.equal(
        text("timffle_helper_installed", ["1.2.0"]),
        "Installed (version 1.2.0)",
    );
    globalThis.browser = { i18n: fakeI18n("zh_TW") };
    assert.equal(text("timffle_helper_installed", ["1.2.0"]), "已安裝（版本 1.2.0）");
});

test("splitRich cuts a message into text and numbered spans", () => {
    assert.deepEqual(splitRich("plain"), ["plain"]);
    assert.deepEqual(splitRich("a <1>b</1> c <2>d</2>"), [
        "a ",
        { slot: 1, text: "b" },
        " c ",
        { slot: 2, text: "d" },
    ]);
    assert.deepEqual(splitRich("<1>all</1>"), [{ slot: 1, text: "all" }]);
    // Unbalanced or unnumbered markup is just text.
    assert.deepEqual(splitRich("a <b>b</b> <1>c"), ["a <b>b</b> <1>c"]);
});

test("fillRich turns each span into a copy of the matching child", () => {
    globalThis.document = fakeDocument([]);
    const node = new FakeNode("p");
    const link = new FakeNode("a", { href: "https://example.org/" });
    const bold = new FakeNode("strong");
    node.childNodes = [link, bold];
    fillRich(node, "See <2>this</2> and <1>that</1>.");
    assert.equal(node.textContent, "See this and that.");
    const [first, second, third, fourth, fifth] = node.childNodes;
    assert.ok(first instanceof FakeText);
    assert.equal(second.tag, "strong");
    assert.equal(fourth.tag, "a");
    assert.equal(fourth.attributes.href, "https://example.org/");
    assert.ok(third instanceof FakeText && fifth instanceof FakeText);
    // The templates themselves are not reused or changed.
    assert.notEqual(second, bold);
    assert.equal(bold.textContent, "");
});

test("a span without a template stays plain text", () => {
    globalThis.document = fakeDocument([]);
    const node = new FakeNode("p");
    fillRich(node, "x <1>y</1> z");
    assert.equal(node.textContent, "x y z");
    assert.ok(node.childNodes.every((child) => child instanceof FakeText));
});

test("localizePage fills every marked element from the catalog", () => {
    globalThis.browser = { i18n: fakeI18n("de") };
    const title = new FakeNode("h2", { "data-i18n": "timffle_popup_title" });
    const note = new FakeNode("p", { "data-i18n-rich": "timffle_attribution" });
    note.childNodes = [new FakeNode("a"), new FakeNode("a")];
    const untouched = new FakeNode("p");
    untouched.own = "stays";
    globalThis.document = fakeDocument([title, note, untouched]);
    localizePage(globalThis.document);
    assert.equal(title.textContent, fakeI18n("de").getMessage("timffle_popup_title"));
    assert.match(note.textContent, /Ruffle/u);
    assert.match(note.textContent, /Timffle/u);
    assert.equal(note.children.length, 2);
    assert.equal(untouched.textContent, "stays");
});
