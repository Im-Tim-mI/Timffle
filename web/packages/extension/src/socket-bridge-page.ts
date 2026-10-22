/**
 * A WebSocket-shaped TCP transport for Ruffle/gloo-net. Only the reserved
 * helper URL is intercepted; all ordinary WebSocket construction is native.
 * It is not a general-purpose WebSocket protocol implementation.
 */
import { HELPER_SOCKET_HOST } from "./socket-proxy";
import {
    MAX_BUFFERED_BYTES,
    MAX_FRAME_SOCKETS,
    MAX_QUEUED_SENDS,
    MAX_SEND_BYTES,
    STALL_TIMEOUT_MS,
    isPageEvent,
    isValidHost,
    isValidPort,
} from "./socket-bridge-protocol";
import type { PageEvent, PageRequest } from "./socket-bridge-protocol";

const CONNECTING = 0;
const OPEN = 1;
const CLOSING = 2;
const CLOSED = 3;
interface Destination {
    url: string;
    host: string;
    port: number;
}
interface QueuedWrite {
    data: ArrayBuffer | Blob;
    offset: number;
    length: number;
}
type Handler<E extends Event> =
    ((this: BridgeSocket, event: E) => unknown) | null;
const utf8 = new TextEncoder();

export function parseHelperUrl(value: unknown): Destination | null {
    if (typeof value !== "string" && !(value instanceof URL)) {
        return null;
    }
    let url: URL;
    try {
        url = new URL(String(value));
    } catch {
        return null;
    }
    if (
        url.protocol !== "ws:" ||
        url.hostname !== HELPER_SOCKET_HOST ||
        url.pathname !== "/connect" ||
        url.port ||
        url.username ||
        url.password ||
        url.hash
    ) {
        return null;
    }
    if (
        url.searchParams.getAll("host").length !== 1 ||
        url.searchParams.getAll("port").length !== 1 ||
        [...url.searchParams.keys()].some(
            (key) => key !== "host" && key !== "port",
        )
    ) {
        return null;
    }
    const host = url.searchParams.get("host");
    const rawPort = url.searchParams.get("port") ?? "";
    const port = Number(rawPort);
    if (
        !isValidHost(host) ||
        !/^[0-9]+$/u.test(rawPort) ||
        !isValidPort(port)
    ) {
        return null;
    }
    return { url: url.href, host, port };
}

/** Count before copying/encoding; huge input must not allocate a huge queue. */
function utf8Length(text: string, limit = MAX_BUFFERED_BYTES): number {
    let bytes = 0;
    for (const character of text) {
        const point = character.codePointAt(0)!;
        bytes += point < 0x80 ? 1 : point < 0x800 ? 2 : point < 0x10000 ? 3 : 4;
        if (bytes > limit) {
            break;
        }
    }
    return bytes;
}

export class BridgeSocket extends EventTarget {
    static readonly CONNECTING = CONNECTING;
    static readonly OPEN = OPEN;
    static readonly CLOSING = CLOSING;
    static readonly CLOSED = CLOSED;
    readonly CONNECTING = CONNECTING;
    readonly OPEN = OPEN;
    readonly CLOSING = CLOSING;
    readonly CLOSED = CLOSED;
    readonly url: string;
    readonly extensions = "";
    readonly protocol = "";
    #binaryType: BinaryType = "blob";
    #state = CONNECTING;
    #buffered = 0;
    #queue: QueuedWrite[] = [];
    #inFlight = 0;
    #reading = false;
    #timer: ReturnType<typeof setTimeout> | undefined;
    #closeTimer: ReturnType<typeof setTimeout> | undefined;
    #localClose: { code: number; reason: string } | undefined;
    #closePosted = false;
    readonly #handlers = new Map<string, EventListener>();
    readonly #sid: number;
    /** Of the helper URL; computed once, not per received chunk. */
    readonly #origin: string;
    readonly #port: MessagePort;
    readonly #sockets: Map<number, BridgeSocket>;

    get readyState(): number {
        return this.#state;
    }
    get bufferedAmount(): number {
        return this.#buffered;
    }
    get binaryType(): BinaryType {
        return this.#binaryType;
    }
    set binaryType(value: BinaryType) {
        if (value === "blob" || value === "arraybuffer") {
            this.#binaryType = value;
        }
    }
    // Native EventTarget dispatch reports listener exceptions without breaking
    // bridge cleanup or the receive ack, including onmessage property handlers.
    get onopen(): Handler<Event> {
        return (this.#handlers.get("open") as Handler<Event>) ?? null;
    }
    set onopen(handler: Handler<Event>) {
        this.#handler("open", handler);
    }
    get onmessage(): Handler<MessageEvent> {
        return (this.#handlers.get("message") as Handler<MessageEvent>) ?? null;
    }
    set onmessage(handler: Handler<MessageEvent>) {
        this.#handler("message", handler as EventListener | null);
    }
    get onerror(): Handler<Event> {
        return (this.#handlers.get("error") as Handler<Event>) ?? null;
    }
    set onerror(handler: Handler<Event>) {
        this.#handler("error", handler);
    }
    get onclose(): Handler<CloseEvent> {
        return (this.#handlers.get("close") as Handler<CloseEvent>) ?? null;
    }
    set onclose(handler: Handler<CloseEvent>) {
        this.#handler("close", handler as EventListener | null);
    }
    #handler(type: string, handler: EventListener | null): void {
        const previous = this.#handlers.get(type);
        if (previous) {
            this.removeEventListener(type, previous);
        }
        this.#handlers.delete(type);
        if (typeof handler === "function") {
            this.#handlers.set(type, handler);
            this.addEventListener(type, handler);
        }
    }

    constructor(
        sid: number,
        destination: Destination,
        port: MessagePort,
        sockets: Map<number, BridgeSocket>,
    ) {
        super();
        this.url = destination.url;
        this.#sid = sid;
        this.#origin = new URL(destination.url).origin;
        this.#port = port;
        this.#sockets = sockets;
        if (sockets.size >= MAX_FRAME_SOCKETS) {
            queueMicrotask(() => this.#fail("socket_limit", false));
            return;
        }
        sockets.set(sid, this);
        this.#arm();
        try {
            this.#post({
                op: "open",
                sid,
                host: destination.host,
                port: destination.port,
            });
        } catch {
            queueMicrotask(() => this.#fail("bridge_closed", false));
        }
    }

    send(data: unknown): void {
        if (arguments.length === 0) {
            throw new TypeError("WebSocket.send requires an argument");
        }
        if (this.#state === CONNECTING) {
            throw new DOMException(
                "WebSocket is still connecting",
                "InvalidStateError",
            );
        }
        const input =
            data instanceof Blob ||
            data instanceof ArrayBuffer ||
            ArrayBuffer.isView(data)
                ? data
                : String(data);
        const size =
            typeof input === "string"
                ? utf8Length(input)
                : input instanceof Blob
                  ? input.size
                  : input.byteLength;
        if (this.#state !== OPEN) {
            // Native WebSockets keep counting unsent data after close. Saturate
            // this accounting at the bridge bound; retain no closed-state data.
            this.#buffered = Math.min(
                MAX_BUFFERED_BYTES,
                this.#buffered + size,
            );
            return;
        }
        if (size === 0) {
            return;
        } // TCP has no empty-message boundary.
        if (
            size > MAX_BUFFERED_BYTES - this.#buffered ||
            this.#queue.length >= MAX_QUEUED_SENDS
        ) {
            this.#fail("buffer_limit");
            return;
        }
        // Copy WASM views at send(), not after asynchronous Blob reads.
        const copy =
            typeof input === "string"
                ? utf8.encode(input).buffer
                : input instanceof Blob
                  ? input
                  : input instanceof ArrayBuffer
                    ? input.slice(0)
                    : new Uint8Array(
                          input.buffer,
                          input.byteOffset,
                          input.byteLength,
                      ).slice().buffer;
        this.#queue.push({ data: copy, offset: 0, length: size });
        this.#buffered += size;
        if (!this.#inFlight && !this.#reading) {
            this.#arm();
        }
        void this.#pump();
    }

    close(code?: number, reason = ""): void {
        if (
            code !== undefined &&
            (!Number.isInteger(code) ||
                (code !== 1000 && (code < 3000 || code > 4999)))
        ) {
            throw new DOMException(
                "Invalid WebSocket close code",
                "InvalidAccessError",
            );
        }
        reason = String(reason);
        if (utf8Length(reason, 123) > 123) {
            throw new DOMException(
                "WebSocket close reason exceeds 123 UTF-8 bytes",
                "SyntaxError",
            );
        }
        if (this.#state === CLOSING || this.#state === CLOSED) {
            return;
        }
        if (this.#state === CONNECTING) {
            this.#fail("connection_cancelled");
            return;
        }
        this.#state = CLOSING;
        this.#localClose = { code: code ?? 1005, reason };
        // Total close drain is bounded even if sends keep slowly progressing.
        this.#closeTimer = setTimeout(
            () => this.#fail("close_timeout"),
            STALL_TIMEOUT_MS,
        );
        void this.#pump();
    }

    receive(message: PageEvent): void {
        if (this.#state === CLOSED) {
            return;
        }
        switch (message.op) {
            case "opened":
                if (this.#state !== CONNECTING) {
                    this.#fail("invalid");
                    return;
                }
                clearTimeout(this.#timer);
                this.#state = OPEN;
                this.dispatchEvent(new Event("open"));
                break;
            case "sent": {
                if (!this.#inFlight) {
                    this.#fail("invalid");
                    return;
                }
                this.#buffered -= this.#inFlight;
                this.#inFlight = 0;
                // One send may have carried several whole writes.
                while (
                    this.#queue.length &&
                    this.#queue[0]!.offset === this.#queue[0]!.length
                ) {
                    this.#queue.shift();
                }
                clearTimeout(this.#timer);
                if (this.#queue.length) {
                    this.#arm();
                }
                void this.#pump();
                break;
            }
            case "data":
                if (this.#state !== OPEN && this.#state !== CLOSING) {
                    this.#fail("invalid");
                    return;
                }
                try {
                    // Like a native WebSocket, deliver only while OPEN. Bytes
                    // that race with close() are still acknowledged below.
                    if (this.#state === OPEN) {
                        const data =
                            this.#binaryType === "arraybuffer"
                                ? message.data
                                : new Blob([message.data]);
                        this.dispatchEvent(
                            new MessageEvent("message", {
                                data,
                                origin: this.#origin,
                            }),
                        );
                    }
                } finally {
                    // Ack only after synchronous dispatch to gloo/Ruffle.
                    try {
                        this.#post({ op: "ack", sid: this.#sid });
                    } catch {
                        this.#fail("bridge_closed", false);
                    }
                }
                break;
            case "closed":
                if (
                    this.#state === CONNECTING ||
                    this.#inFlight ||
                    this.#queue.length
                ) {
                    this.#fail("bridge_closed", false);
                } else {
                    this.#finish(
                        this.#localClose?.code ?? 1000,
                        this.#localClose?.reason ?? "",
                        true,
                    );
                }
                break;
            case "error":
                this.#fail(message.code, false);
                break;
        }
    }

    async #pump(): Promise<void> {
        if (this.#state === CLOSED || this.#inFlight || this.#reading) {
            return;
        }
        const first = this.#queue[0];
        if (!first) {
            if (this.#state === CLOSING && !this.#closePosted) {
                this.#closePosted = true;
                try {
                    this.#post({ op: "close", sid: this.#sid });
                } catch {
                    this.#fail("bridge_closed", false);
                }
            }
            return;
        }
        this.#reading = true;
        try {
            let buffer: ArrayBuffer;
            if (first.data instanceof Blob) {
                const end = Math.min(
                    first.offset + MAX_SEND_BYTES,
                    first.length,
                );
                buffer = await first.data
                    .slice(first.offset, end)
                    .arrayBuffer();
                if (this.readyState === CLOSED) {
                    return;
                }
                first.offset = end;
            } else {
                buffer = this.#takeBuffers();
            }
            this.#inFlight = buffer.byteLength;
            this.#post({ op: "send", sid: this.#sid, data: buffer }, [buffer]);
        } catch {
            this.#fail("bridge_closed");
        } finally {
            this.#reading = false;
        }
    }

    /**
     * The next send: the queued ArrayBuffer writes from the front of the
     * queue, in order, up to one send's worth. TCP is a byte stream, so
     * several flushes of the game may travel as one bridge send; their bytes
     * keep their order and every write is still acknowledged in order (see
     * "sent"). A single whole write is handed over without a copy.
     */
    #takeBuffers(): ArrayBuffer {
        const parts: { item: QueuedWrite; take: number }[] = [];
        let total = 0;
        for (const item of this.#queue) {
            if (
                !(item.data instanceof ArrayBuffer) ||
                total === MAX_SEND_BYTES
            ) {
                break;
            }
            const take = Math.min(
                item.length - item.offset,
                MAX_SEND_BYTES - total,
            );
            parts.push({ item, take });
            total += take;
        }
        const [only] = parts;
        if (
            only &&
            parts.length === 1 &&
            only.item.offset === 0 &&
            only.take === only.item.length
        ) {
            only.item.offset = only.item.length;
            return only.item.data as ArrayBuffer;
        }
        const out = new Uint8Array(total);
        let at = 0;
        for (const { item, take } of parts) {
            out.set(
                new Uint8Array(item.data as ArrayBuffer, item.offset, take),
                at,
            );
            item.offset += take;
            at += take;
        }
        return out.buffer;
    }

    #arm(): void {
        clearTimeout(this.#timer);
        this.#timer = setTimeout(
            () => this.#fail("stall_timeout"),
            STALL_TIMEOUT_MS,
        );
    }
    #post(message: PageRequest, transfer: Transferable[] = []): void {
        this.#port.postMessage(message, transfer);
    }
    #fail(code: string, cancel = true): void {
        if (this.#state === CLOSED) {
            return;
        }
        if (cancel) {
            try {
                this.#post({ op: "close", sid: this.#sid });
            } catch {
                /* Disconnected. */
            }
        }
        // Mark closed before callbacks so a reentrant close/send cannot duplicate events.
        this.#finish(1006, code, false, true);
    }
    #finish(
        code: number,
        reason: string,
        wasClean: boolean,
        error = false,
    ): void {
        if (this.#state === CLOSED) {
            return;
        }
        this.#state = CLOSED;
        clearTimeout(this.#timer);
        clearTimeout(this.#closeTimer);
        this.#queue = [];
        this.#inFlight = 0;
        this.#sockets.delete(this.#sid);
        if (error) {
            this.dispatchEvent(new Event("error"));
        }
        this.dispatchEvent(new CloseEvent("close", { code, reason, wasClean }));
    }
}

let installed = false;

/** Install once; an untrusted page cannot replace an already attached channel. */
export function installSocketBridge(port: MessagePort): boolean {
    if (installed) {
        port.close();
        return false;
    }
    installed = true;
    const sockets = new Map<number, BridgeSocket>();
    const instances = new WeakSet<object>();
    let nextId = 1;
    port.onmessage = (event: MessageEvent<unknown>) => {
        if (isPageEvent(event.data)) {
            sockets.get(event.data.sid)?.receive(event.data);
        }
    };
    port.onmessageerror = () => {
        for (const [sid, socket] of sockets) {
            socket.receive({ op: "error", sid, code: "bridge_closed" });
        }
    };
    const NativeWebSocket = globalThis.WebSocket;
    const Shim = new Proxy(NativeWebSocket, {
        construct(target, args: unknown[], newTarget) {
            const destination = parseHelperUrl(args[0]);
            if (destination) {
                const protocols = args[1];
                if (
                    protocols !== undefined &&
                    !(Array.isArray(protocols) && protocols.length === 0)
                ) {
                    throw new DOMException(
                        "The TCP helper does not negotiate WebSocket subprotocols",
                        "NotSupportedError",
                    );
                }
                const socket = new BridgeSocket(
                    nextId++,
                    destination,
                    port,
                    sockets,
                );
                instances.add(socket);
                return socket;
            }
            // Ordinary URL coercion, exceptions, protocols, subclasses and native
            // prototype/brand checks are delegated without constructing a probe.
            return Reflect.construct(target, args, newTarget) as object;
        },
        get(target, property, receiver) {
            if (property === Symbol.hasInstance) {
                return function (this: unknown, value: unknown): boolean {
                    return (
                        (this === Shim &&
                            typeof value === "object" &&
                            value !== null &&
                            instances.has(value)) ||
                        Boolean(
                            Reflect.apply(
                                Function.prototype[Symbol.hasInstance],
                                this === Shim ? target : this,
                                [value],
                            ),
                        )
                    );
                };
            }
            return Reflect.get(target, property, receiver) as unknown;
        },
    });
    globalThis.WebSocket = Shim;
    return true;
}
