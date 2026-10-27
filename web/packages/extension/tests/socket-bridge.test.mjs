// Page shim (BridgeSocket/installSocketBridge) and shared message validation.
import test from "node:test";
import assert from "node:assert/strict";
import { Blob } from "node:buffer";
import { setImmediate } from "node:timers";
import { URL } from "node:url";
import { execFileSync } from "node:child_process";
import process from "node:process";
import { HELPER_PROXY_URL } from "../src/socket-proxy.ts";
import {
    BridgeSocket,
    installSocketBridge,
    parseHelperUrl,
} from "../src/socket-bridge-page.ts";
import {
    MAX_BUFFERED_BYTES,
    MAX_FRAME_SOCKETS,
    MAX_QUEUED_SENDS,
    MAX_RECEIVE_BYTES,
    MAX_SEND_BYTES,
    STALL_TIMEOUT_MS,
    base64ToBytes,
    bytesToBase64,
    isCompatibleHello,
    isHelperReply,
    isOpenRequest,
    isPageEvent,
    isPageRequest,
    isSendRequest,
} from "../src/socket-bridge-protocol.ts";

const { structuredClone, btoa } = globalThis;

// Ruffle form-encodes the host, with %20 for spaces.
const helperUrl = (host, port) =>
    HELPER_PROXY_URL.replace("{host}", encodeURIComponent(host)).replace(
        "{port}",
        String(port),
    );

const tick = () => new Promise((resolve) => setImmediate(resolve));
async function until(predicate, what) {
    for (let i = 0; i < 100 && !predicate(); i++) {
        await tick();
    }
    assert.ok(predicate(), `timed out waiting for ${what}`);
}

/** A page-side MessagePort stand-in with real clone/transfer semantics. */
function fakePort() {
    return {
        sent: [],
        closed: false,
        onmessage: null,
        onmessageerror: null,
        postMessage(message, transfer = []) {
            this.sent.push(structuredClone(message, { transfer }));
        },
        close() {
            this.closed = true;
        },
    };
}

/** Deterministic timers: nothing keeps the process alive, timeouts are ticked. */
function harness(t) {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const port = fakePort();
    const sockets = new Map();
    const open = (sid, host = "9.9.9.9", tcpPort = 8888) => {
        const ws = new BridgeSocket(
            sid,
            parseHelperUrl(helperUrl(host, tcpPort)),
            port,
            sockets,
        );
        ws.binaryType = "arraybuffer";
        return ws;
    };
    const ops = () => port.sent.map((message) => message.op);
    const sends = () => port.sent.filter((message) => message.op === "send");
    return { port, sockets, open, ops, sends };
}

/** Every event as a compact tuple, in dispatch order. */
function record(ws) {
    const events = [];
    ws.addEventListener("open", () => events.push(["open"]));
    ws.addEventListener("message", (event) =>
        events.push(["message", [...new Uint8Array(event.data)]]),
    );
    ws.addEventListener("error", () => events.push(["error"]));
    ws.addEventListener("close", (event) =>
        events.push(["close", event.code, event.reason, event.wasClean]),
    );
    return events;
}

const opened = (ws, sid) => ws.receive({ op: "opened", sid });

test("only well-formed helper URLs are intercepted", () => {
    assert.deepEqual(parseHelperUrl(helperUrl("9.9.9.9", 8888)), {
        url: helperUrl("9.9.9.9", 8888),
        host: "9.9.9.9",
        port: 8888,
    });
    assert.equal(parseHelperUrl(helperUrl("::1", 80)).host, "::1");
    assert.equal(
        parseHelperUrl(new URL(helperUrl("mole.61.com.tw", 1201))).host,
        "mole.61.com.tw",
    );
    for (const url of [
        "wss://example.com/connect?host=a&port=1",
        helperUrl("a", 1).replace("ws:", "wss:"),
        helperUrl("a", 1).replace("/connect", "/other"),
        helperUrl("a", 1).replace(".invalid/", ".invalid:81/"),
        helperUrl("a", 1).replace("ws://", "ws://user:pw@"),
        helperUrl("a", 1) + "#x",
        helperUrl("a", 1) + "&x=1",
        helperUrl("a", 1) + "&host=b",
        helperUrl("a", 0),
        helperUrl("a", 70000),
        helperUrl("a", "+1"),
        helperUrl("a b", 1),
        helperUrl("a/b", 1),
        helperUrl("a@b", 1),
        helperUrl("", 1),
        "ws://timffle-socket.invalid/connect?port=1",
        42,
        null,
    ]) {
        assert.equal(parseHelperUrl(url), null, String(url));
    }
});

test("opens only after the helper reports TCP connected; send() before that throws", (t) => {
    const { port, sockets, open } = harness(t);
    const ws = open(7);
    const events = record(ws);
    assert.equal(ws.readyState, BridgeSocket.CONNECTING);
    assert.deepEqual(port.sent, [
        { op: "open", sid: 7, host: "9.9.9.9", port: 8888 },
    ]);
    assert.throws(() => ws.send(new Uint8Array([1])), {
        name: "InvalidStateError",
    });
    assert.throws(() => ws.send(), TypeError);
    assert.equal(ws.bufferedAmount, 0);
    assert.equal(port.sent.length, 1);

    opened(ws, 7);
    assert.equal(ws.readyState, BridgeSocket.OPEN);
    assert.deepEqual(events, [["open"]]);

    ws.close();
    assert.equal(ws.readyState, BridgeSocket.CLOSING);
    assert.deepEqual(port.sent.at(-1), { op: "close", sid: 7 });
    ws.receive({ op: "closed", sid: 7 });
    assert.equal(ws.readyState, BridgeSocket.CLOSED);
    assert.deepEqual(events, [["open"], ["close", 1005, "", true]]);
    assert.equal(sockets.size, 0);
});

test("a received chunk is acknowledged only after it has been dispatched", async (t) => {
    const { port, open, ops } = harness(t);
    const ws = open(3);
    opened(ws, 3);
    const seen = [];
    ws.onmessage = (event) =>
        seen.push({
            data: [...new Uint8Array(event.data)],
            origin: event.origin,
            acksBefore: ops().filter((op) => op === "ack").length,
        });
    ws.receive({ op: "data", sid: 3, data: new Uint8Array([128, 10]).buffer });
    assert.deepEqual(seen, [
        {
            data: [128, 10],
            origin: new URL(helperUrl("9.9.9.9", 8888)).origin,
            acksBefore: 0,
        },
    ]);
    assert.deepEqual(port.sent.at(-1), { op: "ack", sid: 3 });

    // A listener may reply synchronously; that write goes out before the ack.
    ws.onmessage = () => ws.send(new Uint8Array([1]));
    ws.receive({ op: "data", sid: 3, data: new Uint8Array([1]).buffer });
    assert.deepEqual(ops().slice(-2), ["send", "ack"]);

    // Even if dispatching throws, the helper is not left waiting for an ack.
    ws.dispatchEvent = () => {
        throw new Error("listener failure");
    };
    assert.throws(
        () => ws.receive({ op: "data", sid: 3, data: new ArrayBuffer(1) }),
        /listener failure/,
    );
    assert.deepEqual(port.sent.at(-1), { op: "ack", sid: 3 });
    delete ws.dispatchEvent;

    // The default binaryType delivers a Blob.
    ws.binaryType = "blob";
    ws.binaryType = "nonsense";
    assert.equal(ws.binaryType, "blob");
    let blob;
    ws.onmessage = (event) => (blob = event.data);
    ws.receive({ op: "data", sid: 3, data: new Uint8Array([7, 8]).buffer });
    assert.ok(blob instanceof Blob);
    assert.deepEqual([...new Uint8Array(await blob.arrayBuffer())], [7, 8]);
    assert.equal(ops().filter((op) => op === "ack").length, 4);
});

test("one send in flight; large writes are split into 64 KiB chunks, in order", async (t) => {
    const { open, sends } = harness(t);
    const ws = open(4);
    opened(ws, 4);
    const big = Uint8Array.from({ length: 150000 }, (_, i) => (i * 7) & 255);
    // gloo-net writes Blobs; a view of WASM memory must be copied at send().
    const wasm = new Uint8Array(new ArrayBuffer(16), 4, 3);
    wasm.set([9, 9, 9]);
    ws.send(big);
    ws.send(new Blob([new Uint8Array([0, 1, 255])]));
    ws.send(wasm);
    wasm.fill(0);
    ws.send("hé");
    ws.send(new Uint8Array(0)); // TCP has no empty message
    let buffered = 150000 + 3 + 3 + 3;
    assert.equal(ws.bufferedAmount, buffered);

    const chunks = [];
    for (let chunkIndex = 0; chunkIndex < 5; chunkIndex++) {
        await until(() => sends().length === chunkIndex + 1, "next chunk");
        await tick();
        assert.equal(sends().length, chunkIndex + 1, "one send in flight");
        const { data } = sends().at(-1);
        assert.ok(data.byteLength > 0 && data.byteLength <= MAX_SEND_BYTES);
        chunks.push(...new Uint8Array(data));
        ws.receive({ op: "sent", sid: 4 });
        buffered -= data.byteLength;
        assert.equal(ws.bufferedAmount, buffered);
    }
    // A Blob is never merged; the two small writes after it travel together.
    assert.deepEqual(
        sends().map(({ data }) => data.byteLength),
        [65536, 65536, 18928, 3, 6],
    );
    assert.deepEqual(chunks, [
        ...big,
        ...[0, 1, 255],
        ...[9, 9, 9],
        ...[0x68, 0xc3, 0xa9],
    ]);
    await tick();
    assert.equal(sends().length, 5);
    assert.equal(ws.bufferedAmount, 0);
});

test("queued small writes are merged into one send; whole writes are handed over without a copy", async (t) => {
    const { open, sends } = harness(t);
    const ws = open(40);
    opened(ws, 40);
    const first = new Uint8Array([1, 2, 3]).buffer;
    ws.send(first);
    await tick();
    // The caller's buffer is copied at send(); that copy is transferred as is.
    assert.equal(first.byteLength, 3, "the caller's buffer is untouched");
    assert.equal(sends().length, 1);
    assert.deepEqual([...new Uint8Array(sends()[0].data)], [1, 2, 3]);
    // Three flushes while the first is in flight: one send, bytes in order.
    ws.send(new Uint8Array([4]));
    ws.send(new Uint8Array([5, 6]));
    ws.send("7");
    await tick();
    assert.equal(sends().length, 1, "one send in flight");
    assert.equal(ws.bufferedAmount, 3 + 1 + 2 + 1);
    ws.receive({ op: "sent", sid: 40 });
    await tick();
    assert.equal(sends().length, 2);
    assert.deepEqual([...new Uint8Array(sends()[1].data)], [4, 5, 6, 0x37]);
    assert.equal(ws.bufferedAmount, 4);
    ws.receive({ op: "sent", sid: 40 });
    await tick();
    assert.equal(sends().length, 2);
    assert.equal(ws.bufferedAmount, 0);
    // No "sent" is owed any more: a stray one is a protocol error, as before.
    ws.receive({ op: "sent", sid: 40 });
    assert.equal(ws.readyState, BridgeSocket.CLOSED);

    // Merging stops at the send limit and never splits the order of bytes.
    const big = open(41);
    opened(big, 41);
    big.send(new Uint8Array(10).fill(1));
    await tick();
    big.send(new Uint8Array(MAX_SEND_BYTES - 4).fill(2));
    big.send(new Uint8Array(8).fill(3));
    big.receive({ op: "sent", sid: 41 });
    await tick();
    const second = new Uint8Array(sends().at(-1).data);
    assert.equal(second.byteLength, MAX_SEND_BYTES);
    assert.deepEqual([...second.slice(-5)], [2, 3, 3, 3, 3]);
    big.receive({ op: "sent", sid: 41 });
    await tick();
    assert.deepEqual([...new Uint8Array(sends().at(-1).data)], [3, 3, 3, 3]);
    big.receive({ op: "sent", sid: 41 });
    assert.equal(big.bufferedAmount, 0);
    assert.equal(big.readyState, BridgeSocket.OPEN);
});

test("bufferedAmount is bounded; overflow fails the socket instead of queueing", async (t) => {
    const { port, open } = harness(t);
    const ws = open(5);
    const events = record(ws);
    opened(ws, 5);
    ws.send(new Uint8Array(MAX_BUFFERED_BYTES - 1));
    assert.equal(ws.bufferedAmount, MAX_BUFFERED_BYTES - 1);
    assert.equal(ws.readyState, BridgeSocket.OPEN);
    ws.send(new Uint8Array(2));
    assert.equal(ws.readyState, BridgeSocket.CLOSED);
    assert.deepEqual(events, [
        ["open"],
        ["error"],
        ["close", 1006, "buffer_limit", false],
    ]);
    assert.deepEqual(port.sent.at(-1), { op: "close", sid: 5 });
    // Like a native WebSocket, later writes only count, and never throw.
    ws.send(new Uint8Array(10));
    assert.ok(ws.bufferedAmount <= MAX_BUFFERED_BYTES);

    // Huge strings are measured before they are encoded or copied.
    const text = open(6);
    opened(text, 6);
    text.send("x".repeat(MAX_BUFFERED_BYTES + 1));
    assert.equal(text.readyState, BridgeSocket.CLOSED);

    // The number of queued writes is bounded too.
    const many = open(8);
    opened(many, 8);
    for (let i = 0; i < MAX_QUEUED_SENDS; i++) {
        many.send(new Uint8Array(1));
    }
    assert.equal(many.readyState, BridgeSocket.OPEN);
    assert.equal(many.bufferedAmount, MAX_QUEUED_SENDS);
    many.send(new Uint8Array(1));
    assert.equal(many.readyState, BridgeSocket.CLOSED);
});

test("close() drains queued writes before posting close; late data is acked, not delivered", async (t) => {
    const { port, sockets, open, ops } = harness(t);
    const ws = open(9);
    const events = record(ws);
    opened(ws, 9);
    ws.send(new Uint8Array(70000));
    ws.close(1000, "bye");
    assert.equal(ws.readyState, BridgeSocket.CLOSING);
    ws.close(); // idempotent
    assert.deepEqual(ops(), ["open", "send"]);
    ws.send(new Uint8Array(5)); // after close(): counted, never sent
    assert.equal(ws.bufferedAmount, 70005);
    ws.receive({ op: "data", sid: 9, data: new Uint8Array([1]).buffer });
    assert.deepEqual(ops(), ["open", "send", "ack"]);
    ws.receive({ op: "sent", sid: 9 });
    assert.deepEqual(ops(), ["open", "send", "ack", "send"]);
    ws.receive({ op: "sent", sid: 9 });
    assert.deepEqual(ops(), ["open", "send", "ack", "send", "close"]);
    assert.equal(ws.bufferedAmount, 5);
    ws.receive({ op: "closed", sid: 9 });
    assert.deepEqual(events, [["open"], ["close", 1000, "bye", true]]);
    assert.equal(sockets.size, 0);

    // A Blob still being read when close() is called is sent first.
    const blob = open(10);
    opened(blob, 10);
    blob.send(new Blob([new Uint8Array([4, 2])]));
    blob.close();
    await until(() => ops().at(-1) === "send", "the Blob chunk");
    assert.deepEqual([...new Uint8Array(port.sent.at(-1).data)], [4, 2]);
    blob.receive({ op: "sent", sid: 10 });
    assert.deepEqual(port.sent.at(-1), { op: "close", sid: 10 });

    // The remote side closing before the drain finished is not clean.
    const cut = open(11);
    const cutEvents = record(cut);
    opened(cut, 11);
    cut.send(new Uint8Array(1));
    cut.close();
    cut.receive({ op: "closed", sid: 11 });
    assert.deepEqual(cutEvents.slice(1), [
        ["error"],
        ["close", 1006, "bridge_closed", false],
    ]);

    // Invalid arguments throw like a native WebSocket, without closing.
    const args = open(12);
    opened(args, 12);
    assert.throws(() => args.close(999), { name: "InvalidAccessError" });
    assert.throws(() => args.close(1000, "x".repeat(124)), {
        name: "SyntaxError",
    });
    assert.equal(args.readyState, BridgeSocket.OPEN);
    args.close(4000, "é".repeat(61));
    assert.equal(args.readyState, BridgeSocket.CLOSING);
});

test("close() while connecting cancels the helper socket immediately", (t) => {
    const { port, sockets, open } = harness(t);
    const ws = open(13);
    const events = record(ws);
    ws.close();
    assert.deepEqual(port.sent, [
        { op: "open", sid: 13, host: "9.9.9.9", port: 8888 },
        { op: "close", sid: 13 },
    ]);
    assert.equal(ws.readyState, BridgeSocket.CLOSED);
    assert.deepEqual(events, [
        ["error"],
        ["close", 1006, "connection_cancelled", false],
    ]);
    assert.equal(sockets.size, 0);
    // Late replies for the cancelled socket change nothing.
    opened(ws, 13);
    ws.receive({ op: "closed", sid: 13 });
    ws.close();
    assert.equal(events.length, 2);
    assert.equal(port.sent.length, 2);
});

test("error and close are each reported once, whatever arrives afterwards", (t) => {
    const { open, ops } = harness(t);
    const failed = open(14);
    const events = record(failed);
    failed.receive({ op: "error", sid: 14, code: "refused" });
    failed.receive({ op: "error", sid: 14, code: "timeout" });
    failed.receive({ op: "closed", sid: 14 });
    opened(failed, 14);
    failed.close();
    assert.deepEqual(events, [["error"], ["close", 1006, "refused", false]]);
    // The content script already finished it, so no close is posted.
    assert.deepEqual(ops(), ["open"]);

    // Re-entrant close() from the error/close handlers adds nothing.
    const reentrant = open(15);
    const reentrantEvents = record(reentrant);
    reentrant.onerror = () => reentrant.close();
    reentrant.onclose = () => reentrant.close(1000);
    opened(reentrant, 15);
    reentrant.receive({ op: "error", sid: 15, code: "unreachable" });
    assert.deepEqual(reentrantEvents, [
        ["open"],
        ["error"],
        ["close", 1006, "unreachable", false],
    ]);

    // A clean remote close after open.
    const remote = open(16);
    const remoteEvents = record(remote);
    opened(remote, 16);
    remote.receive({ op: "closed", sid: 16 });
    remote.receive({ op: "closed", sid: 16 });
    remote.receive({ op: "error", sid: 16, code: "invalid" });
    assert.deepEqual(remoteEvents, [["open"], ["close", 1000, "", true]]);
});

test("out-of-order events from the content script fail the socket", (t) => {
    const { port, open } = harness(t);
    let sid = 20;
    for (const steps of [
        [{ op: "data", data: new ArrayBuffer(1) }],
        [{ op: "sent" }],
        [{ op: "opened" }, { op: "sent" }],
        [{ op: "opened" }, { op: "opened" }],
    ]) {
        const ws = open(++sid);
        const events = record(ws);
        for (const step of steps) {
            ws.receive({ ...step, sid });
        }
        assert.deepEqual(
            events.filter(([type]) => type !== "open"),
            [["error"], ["close", 1006, "invalid", false]],
            JSON.stringify(steps),
        );
        // The rest of the chain is told to drop the helper socket.
        assert.deepEqual(port.sent.at(-1), { op: "close", sid });
    }
});

test("stalled connects, writes and close drains time out; idle sockets do not", (t) => {
    const { port, open } = harness(t);
    const connecting = open(30);
    const connectingEvents = record(connecting);
    t.mock.timers.tick(STALL_TIMEOUT_MS - 1);
    assert.deepEqual(connectingEvents, []);
    t.mock.timers.tick(1);
    assert.deepEqual(connectingEvents, [
        ["error"],
        ["close", 1006, "stall_timeout", false],
    ]);
    assert.deepEqual(port.sent.at(-1), { op: "close", sid: 30 });

    // Every acknowledged chunk restarts the write stall timer.
    const writing = open(31);
    const writingEvents = record(writing);
    opened(writing, 31);
    writing.send(new Uint8Array(1));
    t.mock.timers.tick(STALL_TIMEOUT_MS - 1);
    writing.receive({ op: "sent", sid: 31 });
    writing.send(new Uint8Array(1));
    t.mock.timers.tick(STALL_TIMEOUT_MS - 1);
    assert.equal(writing.readyState, BridgeSocket.OPEN);
    t.mock.timers.tick(1);
    assert.deepEqual(writingEvents.slice(1), [
        ["error"],
        ["close", 1006, "stall_timeout", false],
    ]);

    // An open socket with nothing to send never times out.
    const idle = open(32);
    opened(idle, 32);
    t.mock.timers.tick(10 * STALL_TIMEOUT_MS);
    assert.equal(idle.readyState, BridgeSocket.OPEN);

    // The whole close drain is bounded, even while it keeps progressing.
    const draining = open(33);
    const drainingEvents = record(draining);
    opened(draining, 33);
    draining.send(new Uint8Array(4 * MAX_SEND_BYTES));
    draining.close();
    t.mock.timers.tick(STALL_TIMEOUT_MS / 2);
    draining.receive({ op: "sent", sid: 33 });
    t.mock.timers.tick(STALL_TIMEOUT_MS / 2);
    assert.deepEqual(drainingEvents.slice(1), [
        ["error"],
        ["close", 1006, "close_timeout", false],
    ]);
    assert.deepEqual(port.sent.at(-1), { op: "close", sid: 33 });
});

test("each frame has a finite number of helper sockets", async (t) => {
    const { port, sockets, open } = harness(t);
    const all = Array.from({ length: MAX_FRAME_SOCKETS }, (_, i) =>
        open(100 + i),
    );
    assert.equal(sockets.size, MAX_FRAME_SOCKETS);
    const extra = open(200);
    const events = record(extra);
    await tick();
    assert.deepEqual(events, [
        ["error"],
        ["close", 1006, "socket_limit", false],
    ]);
    // It never reached the content script.
    assert.equal(port.sent.filter(({ sid }) => sid === 200).length, 0);
    // Cancelling one frees its slot at once.
    all[0].close();
    open(201);
    assert.deepEqual(port.sent.at(-1), {
        op: "open",
        sid: 201,
        host: "9.9.9.9",
        port: 8888,
    });
});

test("the global WebSocket only changes for helper URLs", async (t) => {
    t.mock.timers.enable({ apis: ["setTimeout"] });
    const constructed = [];
    class NativeLike {
        constructor(url, protocols) {
            if (String(url) === "not a url") {
                throw new SyntaxError("Invalid URL");
            }
            this.url = String(url);
            this.protocols = protocols;
            constructed.push(this);
        }
    }
    NativeLike.OPEN = 1;
    const original = globalThis.WebSocket;
    globalThis.WebSocket = NativeLike;
    const port = fakePort();
    const unused = fakePort();
    try {
        assert.equal(installSocketBridge(port), true);
        // A second channel (e.g. forged by page script) is refused and closed.
        assert.equal(installSocketBridge(unused), false);
        assert.equal(unused.closed, true);
        assert.equal(port.closed, false);
        const Shim = globalThis.WebSocket;
        assert.notEqual(Shim, NativeLike);
        assert.equal(Shim.OPEN, 1);
        assert.equal(Shim.prototype, NativeLike.prototype);

        const plain = new Shim("wss://example.com/chat", ["chat"]);
        assert.equal(Object.getPrototypeOf(plain), NativeLike.prototype);
        assert.equal(plain, constructed.at(-1));
        assert.equal(plain.url, "wss://example.com/chat");
        assert.deepEqual(plain.protocols, ["chat"]);
        assert.ok(plain instanceof Shim && plain instanceof NativeLike);
        assert.throws(() => new Shim("not a url"), SyntaxError);
        class Subclass extends Shim {
            extra() {
                return 1;
            }
        }
        const sub = new Subclass("wss://example.com/");
        assert.ok(sub instanceof Subclass && sub.extra() === 1);
        // Near misses are ordinary (unresolvable) WebSockets, not the bridge.
        const nearMiss = new Shim(helperUrl("a", 1) + "&x=1");
        assert.ok(nearMiss instanceof NativeLike);
        assert.equal(port.sent.length, 0);

        assert.throws(() => new Shim(helperUrl("1.1.1.1", 1201), "x"), {
            name: "NotSupportedError",
        });
        const bridged = new Shim(helperUrl("1.1.1.1", 1201), []);
        assert.ok(bridged instanceof BridgeSocket && bridged instanceof Shim);
        assert.ok(!(bridged instanceof NativeLike));
        assert.equal(bridged.url, helperUrl("1.1.1.1", 1201));
        assert.deepEqual(port.sent.at(-1), {
            op: "open",
            sid: 1,
            host: "1.1.1.1",
            port: 1201,
        });
        // Protocol-rejected attempts do not allocate an ID or post a message.
        assert.equal(port.sent.length, 1);

        const events = record(bridged);
        bridged.binaryType = "arraybuffer";
        port.onmessage({ data: { nonsense: true } });
        port.onmessage({ data: { op: "opened", sid: 99 } });
        port.onmessage({ data: { op: "opened", sid: "1" } });
        port.onmessage({ data: { op: "opened", sid: 1 } });
        const data = new Uint8Array([5]).buffer;
        port.onmessage({ data: { op: "data", sid: 1, data } });
        assert.deepEqual(events, [["open"], ["message", [5]]]);
        assert.deepEqual(port.sent.at(-1), { op: "ack", sid: 1 });
        port.onmessageerror();
        assert.deepEqual(events.slice(2), [
            ["error"],
            ["close", 1006, "bridge_closed", false],
        ]);
    } finally {
        globalThis.WebSocket = original;
    }
});

// bytesToBase64 as it was before it used toBase64 / joined pieces.
function oldBytesToBase64(bytes) {
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    }
    return btoa(binary);
}

const BASE64_SIZES = [0, 1, 2, 3, 100, 0x8000, 0x8001, 65536];
function base64Sample(length) {
    // Deterministic, covers every byte value.
    let x = length + 1;
    return Uint8Array.from({ length }, () => {
        x = (x * 1103515245 + 12345) >>> 0;
        return x >>> 24;
    });
}

test("bytesToBase64 output is identical to the old implementation", () => {
    for (const length of BASE64_SIZES) {
        const bytes = base64Sample(length);
        assert.equal(
            bytesToBase64(bytes),
            oldBytesToBase64(bytes),
            `${length}`,
        );
    }
    // A view into a larger buffer encodes only the view.
    const backing = base64Sample(300);
    const view = backing.subarray(7, 207);
    assert.equal(bytesToBase64(view), oldBytesToBase64(view));
});

test("bytesToBase64 with native Uint8Array.prototype.toBase64 matches too", (t) => {
    // Node 24 has toBase64 only behind --js-base-64; later versions may
    // have it by default (and drop the flag).
    const script = `
        const { bytesToBase64 } = await import(${JSON.stringify(
            new URL("../src/socket-bridge-protocol.ts", import.meta.url).href,
        )});
        const sizes = ${JSON.stringify(BASE64_SIZES)};
        ${base64Sample.toString()}
        process.stdout.write(JSON.stringify({
            native: typeof Uint8Array.prototype.toBase64 === "function",
            out: sizes.map((n) => bytesToBase64(base64Sample(n))),
        }));
    `;
    let result;
    for (const flags of [["--js-base-64"], []]) {
        try {
            result = JSON.parse(
                execFileSync(
                    process.execPath,
                    [
                        ...flags,
                        "--import",
                        "tsx",
                        "--input-type=module",
                        "-e",
                        script,
                    ],
                    { encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] },
                ),
            );
            break;
        } catch {
            // Unknown flag: try without it.
        }
    }
    if (!result?.native) {
        t.skip("this Node has no Uint8Array.prototype.toBase64");
        return;
    }
    BASE64_SIZES.forEach((length, i) => {
        assert.equal(
            result.out[i],
            oldBytesToBase64(base64Sample(length)),
            `${length}`,
        );
    });
});

test("base64 round trip and message validation", () => {
    const all = Uint8Array.from({ length: 256 }, (_, i) => i);
    assert.deepEqual(base64ToBytes(bytesToBase64(all)), all);
    const big = Uint8Array.from({ length: 100_000 }, (_, i) => (i * 31) & 255);
    assert.deepEqual(base64ToBytes(bytesToBase64(big)), big);
    for (const length of [0, 1, 2, 3, MAX_RECEIVE_BYTES]) {
        const bytes = Uint8Array.from({ length }, (_, i) => 255 - (i & 255));
        const decoded = base64ToBytes(bytesToBase64(bytes));
        assert.ok(decoded instanceof Uint8Array);
        assert.equal(decoded.byteLength, length);
        assert.deepEqual(decoded, bytes);
    }

    assert.ok(isOpenRequest({ type: "open", host: "9.9.9.9", port: 8888 }));
    assert.ok(isOpenRequest({ type: "open", host: "::1", port: 1 }));
    for (const bad of [
        { type: "open", host: "a/b", port: 1 },
        { type: "open", host: "", port: 1 },
        { type: "open", host: "a".repeat(256), port: 1 },
        { type: "open", host: "a", port: 0 },
        { type: "open", host: "a", port: 1.5 },
        { type: "open", host: "a", port: "1" },
        { type: "send", data: "AA==" },
        null,
    ]) {
        assert.equal(isOpenRequest(bad), false, JSON.stringify(bad));
    }
    assert.ok(isSendRequest({ type: "send", data: "AAEC/w==" }));
    const max = bytesToBase64(new Uint8Array(MAX_SEND_BYTES));
    assert.ok(isSendRequest({ type: "send", data: max }));
    for (const data of [
        bytesToBase64(new Uint8Array(MAX_SEND_BYTES + 1)),
        "not base64!",
        "AB==", // non-canonical padding bits
        "AAE",
        "AA==\n",
        42,
    ]) {
        assert.equal(isSendRequest({ type: "send", data }), false, data);
    }

    assert.ok(isHelperReply({ type: "opened" }));
    assert.ok(isHelperReply({ type: "error", code: "helper_missing" }));
    assert.ok(isHelperReply({ type: "hello", version: "1.1.0", protocol: 2 }));
    assert.ok(
        isHelperReply({
            type: "data",
            data: bytesToBase64(new Uint8Array(MAX_RECEIVE_BYTES)),
        }),
    );
    for (const bad of [
        { type: "error", code: "<b>" },
        { type: "data", data: "!" },
        {
            type: "data",
            data: bytesToBase64(new Uint8Array(MAX_RECEIVE_BYTES + 1)),
        },
        { type: "hello" },
        { type: "hello", version: "1.1", protocol: 2 },
        { type: "hello", version: "1.1.0", protocol: "2" },
        { type: "open" },
        "opened",
    ]) {
        assert.equal(isHelperReply(bad), false, JSON.stringify(bad));
    }
    // The protocol number is the compatibility contract, not the version.
    assert.ok(
        isCompatibleHello({ type: "hello", version: "1.1.0", protocol: 2 }),
    );
    assert.ok(
        isCompatibleHello({ type: "hello", version: "1.2.3", protocol: 2 }),
    );
    assert.equal(
        isCompatibleHello({ type: "hello", version: "1.1.0", protocol: 1 }),
        false,
    );

    assert.ok(isPageRequest({ op: "send", sid: 1, data: new ArrayBuffer(1) }));
    for (const bad of [
        { op: "send", sid: 1, data: "AA==" },
        { op: "send", sid: 1, data: new ArrayBuffer(MAX_SEND_BYTES + 1) },
        { op: "close", sid: 0 },
        { op: "close", sid: 1.5 },
        { op: "open", sid: 1, host: "a b", port: 1 },
        { op: "hello", sid: 1 },
    ]) {
        assert.equal(isPageRequest(bad), false, JSON.stringify(bad));
    }
    assert.ok(isPageEvent({ op: "error", sid: 1, code: "not_allowed" }));
    for (const bad of [
        { op: "data", sid: 1, data: new ArrayBuffer(MAX_RECEIVE_BYTES + 1) },
        { op: "error", sid: 1, code: "Not Allowed" },
        { op: "opened", sid: -1 },
    ]) {
        assert.equal(isPageEvent(bad), false, JSON.stringify(bad));
    }
});
