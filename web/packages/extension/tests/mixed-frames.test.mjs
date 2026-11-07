import test from "node:test";
import assert from "node:assert/strict";
import { upgradedFrameUrl } from "../src/mixed-frames.ts";

test("an HTTPS page asks for its plain-HTTP frames over HTTPS", () => {
    assert.equal(
        upgradedFrameUrl(
            "https://game.example/",
            "http://game.example/topbar/top_bar.html",
        ),
        "https://game.example/topbar/top_bar.html",
    );
    // Relative addresses already follow the page; other hosts are upgraded too.
    assert.equal(
        upgradedFrameUrl("https://game.example/a/", "http://other.example:80/x?y=1#z"),
        "https://other.example/x?y=1#z",
    );
    assert.equal(
        upgradedFrameUrl("https://game.example/", "http://other.example:8080/x"),
        "https://other.example:8080/x",
    );
});

test("frames that load already are left alone", () => {
    for (const [page, src] of [
        ["http://game.example/", "http://game.example/bar.html"],
        ["https://game.example/", "https://game.example/bar.html"],
        ["https://game.example/", "/bar.html"],
        ["https://game.example/", "about:blank"],
        ["https://game.example/", "javascript:void(0)"],
        ["https://game.example/", "data:text/html,hi"],
        ["https://game.example/", ""],
        ["https://game.example/", null],
        ["https://game.example/", "http://[bad"],
        ["file:///tmp/a.html", "http://game.example/"],
    ]) {
        assert.equal(upgradedFrameUrl(page, src), null, `${page} ${src}`);
    }
});
