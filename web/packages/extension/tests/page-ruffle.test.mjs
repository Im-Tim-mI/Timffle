import test from "node:test";
import assert from "node:assert/strict";
import {
    absorbPageConfig,
    keepTimffleInSlot,
    silencePageRuffle,
} from "../src/page-ruffle.ts";

const open = () => {};

/** The shape of a page's own Ruffle public API (any version). */
function foreignApi(config = {}) {
    return {
        config,
        sources: { local: { version: "0.1.0" } },
        invoked: false,
        newestName: null,
        superseded() {
            this.invoked = true;
        },
    };
}

function ourApi() {
    return {
        config: { autoplay: "off", openInNewTab: open },
        sources: { extension: { version: "0.8.0-nightly.2026.10.13" } },
        invoked: false,
        newestName: null,
        superseded() {
            this.invoked = true;
        },
    };
}

test("the page's own Ruffle assigned over the slot: Timffle stays, the page copy is silenced", () => {
    const win = {};
    const ours = ourApi();
    win.RufflePlayer = ours;
    keepTimffleInSlot(win, ours, { openInNewTab: open });

    const page = foreignApi({ quality: "high" });
    win.RufflePlayer = page; // what `ee.negotiate(window.RufflePlayer, "local")` does
    assert.equal(win.RufflePlayer, ours);
    assert.equal(page.invoked, true, "the page's init() must return at once");
    assert.equal(ours.invoked, false, "our init still runs");
    assert.deepEqual(Object.keys(ours.sources), ["extension"]);
    assert.equal(ours.config.quality, "high", "page config is honoured");
    assert.equal(ours.config.openInNewTab, open);
});

test("a page config object put in the slot is merged, page values win, publicPath is ignored", () => {
    const win = {};
    const ours = ourApi();
    keepTimffleInSlot(win, ours, { openInNewTab: open });
    win.RufflePlayer = {
        config: {
            autoplay: "on",
            publicPath: "/play/ruffle/",
            openInNewTab: null,
        },
    };
    assert.equal(win.RufflePlayer, ours);
    assert.equal(ours.config.autoplay, "on");
    assert.equal("publicPath" in ours.config, false);
    assert.equal(ours.config.openInNewTab, open);
});

test("socketProxy: the page's exact mappings first, the extension's as fallback", () => {
    const ours = ourApi();
    const changed = absorbPageConfig(
        ours,
        {
            socketProxy: [
                { host: "game.example", port: 843, proxyUrl: "wss://a" },
            ],
        },
        { socketProxy: [{ host: "*", port: 0, proxyUrl: "ws://helper" }] },
    );
    assert.equal(changed, true);
    assert.deepEqual(
        ours.config.socketProxy.map((p) => p.proxyUrl),
        ["wss://a", "ws://helper"],
    );
});

test("page Ruffle ran first: foreign sources are dropped and our init is re-armed", () => {
    // What `new PublicAPI(prev)` leaves when prev was the page's API that had already initialised.
    const ours = ourApi();
    ours.sources.local = { version: "9.9.9" };
    ours.invoked = true;
    ours.newestName = "local";
    const win = { RufflePlayer: ours };
    keepTimffleInSlot(win, ours, { openInNewTab: open });
    assert.deepEqual(Object.keys(ours.sources), ["extension"]);
    assert.equal(ours.invoked, false);
    assert.equal(ours.newestName, null);
    ours.superseded();
    assert.equal(
        ours.invoked,
        false,
        "a newer page copy cannot supersede Timffle",
    );
});

test("assigning our own API, null or a non-object changes nothing", () => {
    const win = {};
    const ours = ourApi();
    keepTimffleInSlot(win, ours);
    win.RufflePlayer = ours;
    win.RufflePlayer = null;
    win.RufflePlayer = "ruffle";
    assert.equal(win.RufflePlayer, ours);
    assert.equal(ours.config.autoplay, "off");
});

test("silencePageRuffle only sets invoked", () => {
    const page = foreignApi();
    silencePageRuffle(page);
    assert.equal(page.invoked, true);
    assert.equal(page.newestName, null);
});
