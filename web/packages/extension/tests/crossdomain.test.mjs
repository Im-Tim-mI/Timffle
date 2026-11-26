import test from "node:test";
import assert from "node:assert/strict";
import {
    domainMatches,
    parsePolicy,
    policyAllows,
    senderOrigin,
} from "../src/crossdomain.ts";

const TAOMEE = `﻿<?xml version="1.0" encoding="UTF-8"?>
<cross-domain-policy>
\t<allow-http-request-headers-from domain="*" headers="*" />
\t<allow-access-from domain="*" />
</cross-domain-policy>`;

test("a policy that allows every domain lets any web page read the host", () => {
    const policy = parsePolicy(TAOMEE, false);
    assert.deepEqual(policy, { permitted: true, entries: [{ domain: "*", secure: false }] });
    assert.equal(policyAllows(policy, { host: "sddt.61.com.tw", https: false }), true);
    assert.equal(policyAllows(policy, { host: "anything.example", https: true }), true);
});

test("domain patterns match like Flash Player's", () => {
    assert.equal(domainMatches("*", "a.example"), true);
    assert.equal(domainMatches("*.example.com", "example.com"), true);
    assert.equal(domainMatches("*.example.com", "www.example.com"), true);
    assert.equal(domainMatches("*.example.com", "WWW.EXAMPLE.COM"), true);
    assert.equal(domainMatches("*.example.com", "notexample.com"), false);
    assert.equal(domainMatches("*.example.com", "example.com.evil"), false);
    assert.equal(domainMatches("game.example", "game.example"), true);
    assert.equal(domainMatches("game.example", "sub.game.example"), false);
});

test("only the named domains are allowed, and secure entries only over HTTPS", () => {
    const xml = `<cross-domain-policy>
        <allow-access-from domain="*.game.example"/>
        <allow-access-from domain="partner.example" secure="false" />
        <allow-access-from domain='quoted.example' />
    </cross-domain-policy>`;
    const http = parsePolicy(xml, false);
    assert.equal(policyAllows(http, { host: "www.game.example", https: false }), true);
    assert.equal(policyAllows(http, { host: "other.example", https: true }), false);
    // Single-quoted attributes are not what the format uses: ignored, not misread.
    assert.equal(policyAllows(http, { host: "quoted.example", https: false }), false);
    const https = parsePolicy(xml, true);
    assert.equal(policyAllows(https, { host: "www.game.example", https: false }), false);
    assert.equal(policyAllows(https, { host: "www.game.example", https: true }), true);
    assert.equal(policyAllows(https, { host: "partner.example", https: false }), true);
});

test("site-control none forbids everything; no entries allow nothing", () => {
    const none = parsePolicy(
        `<cross-domain-policy><site-control permitted-cross-domain-policies="none"/><allow-access-from domain="*"/></cross-domain-policy>`,
        false,
    );
    assert.equal(policyAllows(none, { host: "a.example", https: false }), false);
    assert.equal(policyAllows(parsePolicy("<cross-domain-policy/>", false), { host: "a.example", https: false }), false);
    assert.equal(policyAllows(parsePolicy("not xml at all", false), { host: "a.example", https: false }), false);
});

test("the asking page's origin comes from the sender, web origins only", () => {
    assert.equal(senderOrigin({ origin: "http://sddt.61.com.tw" }), "http://sddt.61.com.tw");
    assert.equal(senderOrigin({ url: "https://game.example:8443/play?x=1" }), "https://game.example:8443");
    assert.equal(senderOrigin({ origin: "null" }), null);
    assert.equal(senderOrigin({ url: "chrome-extension://abc/player.html" }), null);
    assert.equal(senderOrigin({ url: "file:///tmp/a.html" }), null);
    assert.equal(senderOrigin({}), null);
});
