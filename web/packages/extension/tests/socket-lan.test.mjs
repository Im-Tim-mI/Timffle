// The "own address" exception: which website origins are on the local network, and which helper knows about it.
import test from "node:test";
import assert from "node:assert/strict";
import {
    MIN_LAN_HELPER_VERSION,
    isLanDestination,
    lanHostOf,
    versionAtLeast,
} from "../src/socket-lan.ts";

test("a website served from a private address gives that address, bare and in lower case", () => {
    for (const [origin, address] of [
        ["http://192.168.0.163", "192.168.0.163"],
        ["http://192.168.0.5:8090", "192.168.0.5"],
        ["https://192.168.0.5:8443", "192.168.0.5"],
        ["http://192.168.0.5/game/index.html?x=1#top", "192.168.0.5"],
        ["http://192.168.255.255", "192.168.255.255"],
        ["http://10.0.0.1", "10.0.0.1"],
        ["http://10.255.255.254:81", "10.255.255.254"],
        ["http://[fd00::1]:8080", "fd00::1"],
        ["http://[FD00:0:0:0:0:0:0:1]/", "fd00::1"],
        ["https://[fc00::]", "fc00::"],
        ["http://[fd12:3456:789a::1]", "fd12:3456:789a::1"],
        [
            "http://[fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff]",
            "fdff:ffff:ffff:ffff:ffff:ffff:ffff:ffff",
        ],
        ["http://[fd00::192.168.0.1]", "fd00::c0a8:1"],
    ]) {
        assert.equal(lanHostOf(origin), address, origin);
    }
    for (let second = 16; second <= 31; second++) {
        assert.equal(
            lanHostOf(`http://172.${second}.0.1`),
            `172.${second}.0.1`,
        );
    }
});

test("other spellings of an address count as the address the browser makes of them", () => {
    // The browser writes these hosts as 192.168.0.1 too: it is the same website, and the helper gets the plain form.
    for (const origin of [
        "http://192.168.0.1.:80",
        "http://0xc0a80001/",
        "http://3232235521/",
        "http://0300.0250.0.1/",
        "http://192.168.1/",
        "HTTP://192.168.0.1/",
    ]) {
        assert.equal(lanHostOf(origin), "192.168.0.1", origin);
    }
});

test("names, this computer, other special addresses and public ones have no exception", () => {
    for (const origin of [
        // Names: whatever they resolve to, no DNS answer decides the exception.
        "http://192.168.0.1.nip.io/",
        "http://localhost",
        "http://localhost:8080",
        "http://router.lan/",
        "http://xn--192-168-0-1/",
        // User names and passwords.
        "http://user:pass@192.168.0.1/",
        "http://user@192.168.0.1/",
        // This computer, link-local, carrier-grade NAT, unspecified, multicast, broadcast.
        "http://127.0.0.1",
        "http://127.1.2.3:8080",
        "http://[::1]/",
        "http://169.254.1.1",
        "http://[fe80::1]",
        "http://100.64.0.1",
        "http://100.127.255.255",
        "http://0.0.0.0",
        "http://224.0.0.1",
        "http://255.255.255.255",
        // Just outside the private ranges.
        "http://172.15.255.255",
        "http://172.32.0.1",
        "http://192.167.255.255",
        "http://192.169.0.1",
        "http://9.255.255.255",
        "http://11.0.0.1",
        // Public.
        "https://mole.61.com.tw",
        "http://8.8.8.8",
        "http://[2001:db8::1]",
        // IPv4 inside IPv6, and IPv6 outside fc00::/7 (fd::1 is 00fd::1).
        "http://[::ffff:192.168.0.1]/",
        "http://[0:0:0:0:0:ffff:c0a8:1]/",
        "http://[::192.168.0.1]/",
        "http://[fd::1]/",
        "http://[fc0::1]/",
        "http://[fb00::1]",
        "http://[fe00::1]",
        // Zones, other schemes, opaque origins and no URL at all.
        "http://[fe80::1%25eth0]/",
        "http://[fd00::1%25eth0]/",
        "file:///tmp/game.html",
        "about:blank",
        "ws://192.168.0.1/",
        "ftp://192.168.0.1/",
        "blob:http://192.168.0.1/0b2c4d1e",
        "chrome-extension://eandddnbchclalbjkhfelhjhpijifcog/",
        "data:text/html,x",
        "null",
        "",
        "192.168.0.1",
        "//192.168.0.1",
    ]) {
        assert.equal(lanHostOf(origin), undefined, origin);
    }
});

test("a destination names the website's address with or without brackets, in any letter case", () => {
    assert.ok(isLanDestination("192.168.0.5", "192.168.0.5"));
    assert.ok(isLanDestination("[fd00::1]", "fd00::1"));
    assert.ok(isLanDestination("FD00::1", "fd00::1"));
    for (const host of [
        "192.168.0.6",
        "192.168.0.5.nip.io",
        "localhost",
        "[192.168.0.5",
        "fd00::2",
    ]) {
        assert.equal(isLanDestination(host, "192.168.0.5"), false, host);
    }
});

test("helper versions compare by number, and anything that is not a version is too old", () => {
    assert.equal(MIN_LAN_HELPER_VERSION, "1.4.0");
    for (const version of ["1.4.0", "1.4.1", "1.10.0", "2.0.0", "1.4", "1.4.0.1"]) {
        assert.equal(versionAtLeast(version, "1.4.0"), true, version);
    }
    for (const version of [
        "1.3.0",
        "1.3.99",
        "0.9.0",
        "1",
        undefined,
        "",
        "1.4.0-beta",
        "v1.4.0",
        "1..4",
        " 1.4.0",
        "1.4.0.",
        "x",
        "9".repeat(40),
    ]) {
        assert.equal(versionAtLeast(version, "1.4.0"), false, String(version));
    }
    assert.equal(versionAtLeast("1.4.0", "garbage"), false);
});
