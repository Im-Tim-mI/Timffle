import test from "node:test";
import assert from "node:assert/strict";
import { armSocketBridge } from "../src/socket-bridge-arm.ts";

test("the bridge is installed when the socket list is first read, once", () => {
    const config = { socketProxy: [{ host: "*", port: 0, proxyUrl: "u" }] };
    let installs = 0;
    assert.equal(
        armSocketBridge(config, () => installs++),
        true,
    );
    assert.equal(installs, 0, "arming alone installs nothing");
    assert.equal(Object.keys(config).includes("socketProxy"), true);
    assert.equal(config.socketProxy.length, 1);
    assert.equal(installs, 1);
    void config.socketProxy;
    assert.equal(installs, 1);
});

test("spreading the config (what Ruffle's frame polyfill does) reads it too", () => {
    const config = { socketProxy: [] };
    let installs = 0;
    armSocketBridge(config, () => installs++);
    const copy = { ...config };
    assert.deepEqual(copy.socketProxy, []);
    assert.equal(installs, 1);
});

test("writing the list does not install, and the new list is what is read", () => {
    const config = { socketProxy: [] };
    let installs = 0;
    armSocketBridge(config, () => installs++);
    config.socketProxy = [{ host: "a", port: 1, proxyUrl: "x" }];
    assert.equal(installs, 0);
    assert.equal(config.socketProxy[0].host, "a");
    assert.equal(installs, 1);
});

test("a bridge that fails to install does not break the code that read the list", () => {
    const config = { socketProxy: [1, 2, 3] };
    let installs = 0;
    armSocketBridge(config, () => {
        installs++;
        throw new Error("boom");
    });
    assert.deepEqual(config.socketProxy, [1, 2, 3]);
    // It is not tried again on every read.
    void config.socketProxy;
    assert.equal(installs, 1);
});

test("a config that cannot be armed is left alone", () => {
    assert.equal(
        armSocketBridge({}, () => assert.fail("not installed")),
        false,
    );
    const frozen = Object.freeze({ socketProxy: [] });
    assert.equal(
        armSocketBridge(frozen, () => assert.fail("not installed")),
        false,
    );
    const accessor = {
        get socketProxy() {
            return [];
        },
    };
    assert.equal(
        armSocketBridge(accessor, () => assert.fail("not installed")),
        false,
    );
});
