/** Isolated-world relay. The background independently authorizes the actual sender. */
import {
    MAX_FRAME_SOCKETS,
    SOCKET_PORT_NAME,
    base64ToBytes,
    bytesToBase64,
    isHelperReply,
    isPageRequest,
    isRecord,
    isSocketId,
} from "./socket-bridge-protocol";
import type { PageEvent } from "./socket-bridge-protocol";

export function startContentSocketBridge(
    sendPortToPage: (port: MessagePort) => void,
): () => void {
    const channel = new MessageChannel();
    const page = channel.port1;
    const sockets = new Map<
        number,
        {
            port: chrome.runtime.Port;
            fail: (code: string) => void;
            opened: boolean;
            sending: boolean;
            receiving: boolean;
            closing: boolean;
        }
    >();
    let stopped = false;
    const post = (event: PageEvent, transfer: Transferable[] = []) => {
        try {
            page.postMessage(event, transfer);
        } catch {
            stop();
        }
    };
    const closeSockets = () => {
        for (const socket of sockets.values()) {
            socket.fail("bridge_closed");
        }
    };
    const stop = () => {
        if (stopped) {
            return;
        }
        stopped = true;
        closeSockets();
        page.close();
        window.removeEventListener("pagehide", closeSockets);
    };
    page.onmessageerror = stop;
    // Navigation/bfcache closes every socket, but keeps the channel itself: the
    // page shim cannot be installed twice, so a page restored from the
    // back/forward cache must still be able to open new sockets.
    window.addEventListener("pagehide", closeSockets);
    page.onmessage = (event: MessageEvent<unknown>) => {
        if (stopped) {
            return;
        }
        const request = event.data;
        if (!isPageRequest(request)) {
            if (isRecord(request) && isSocketId(request["sid"])) {
                sockets.get(request["sid"])?.fail("invalid");
            }
            return;
        }
        const { sid } = request;
        if (request.op === "open") {
            if (sockets.has(sid)) {
                sockets.get(sid)!.fail("invalid");
                return;
            }
            if (sockets.size >= MAX_FRAME_SOCKETS) {
                post({ op: "error", sid, code: "socket_limit" });
                return;
            }
            let runtimePort: chrome.runtime.Port;
            try {
                runtimePort = browser.runtime.connect({
                    name: SOCKET_PORT_NAME,
                });
            } catch {
                post({ op: "error", sid, code: "bridge_closed" });
                return;
            }
            let done = false;
            const finish = (final: PageEvent) => {
                if (done) {
                    return;
                }
                done = true;
                sockets.delete(sid);
                post(final);
                try {
                    runtimePort.disconnect();
                } catch {
                    /* Already disconnected. */
                }
            };
            const socket = {
                port: runtimePort,
                fail: (code: string) => finish({ op: "error", sid, code }),
                opened: false,
                sending: false,
                receiving: false,
                closing: false,
            };
            sockets.set(sid, socket);
            runtimePort.onMessage.addListener((reply: unknown) => {
                if (done) {
                    return;
                }
                if (!isHelperReply(reply)) {
                    socket.fail("invalid");
                    return;
                }
                switch (reply.type) {
                    case "opened":
                        if (socket.opened || socket.closing) {
                            socket.fail("invalid");
                            return;
                        }
                        socket.opened = true;
                        post({ op: "opened", sid });
                        break;
                    case "sent":
                        if (!socket.sending) {
                            socket.fail("invalid");
                            return;
                        }
                        socket.sending = false;
                        post({ op: "sent", sid });
                        break;
                    case "data": {
                        if (!socket.opened || socket.receiving) {
                            socket.fail("invalid");
                            return;
                        }
                        socket.receiving = true;
                        const data = base64ToBytes(reply.data).buffer;
                        post({ op: "data", sid, data }, [data]);
                        break;
                    }
                    case "closed":
                        finish({ op: "closed", sid });
                        break;
                    case "error":
                        socket.fail(reply.code);
                        break;
                    default:
                        socket.fail("invalid");
                }
            });
            runtimePort.onDisconnect.addListener(() => {
                void browser.runtime.lastError;
                socket.fail("bridge_closed");
            });
            try {
                runtimePort.postMessage({
                    type: "open",
                    host: request.host,
                    port: request.port,
                });
            } catch {
                socket.fail("bridge_closed");
            }
            return;
        }
        const socket = sockets.get(sid);
        if (!socket) {
            return;
        }
        try {
            switch (request.op) {
                case "send":
                    if (!socket.opened || socket.sending || socket.closing) {
                        socket.fail("invalid");
                        return;
                    }
                    socket.sending = true;
                    socket.port.postMessage({
                        type: "send",
                        data: bytesToBase64(new Uint8Array(request.data)),
                    });
                    break;
                case "ack":
                    if (!socket.receiving) {
                        socket.fail("invalid");
                        return;
                    }
                    socket.receiving = false;
                    socket.port.postMessage({ type: "ack" });
                    break;
                case "close":
                    if (!socket.closing) {
                        socket.closing = true;
                        // Unlike disconnect, close drains bytes already accepted by the helper.
                        socket.port.postMessage({ type: "close" });
                    }
                    break;
            }
        } catch {
            socket.fail("bridge_closed");
        }
    };
    try {
        sendPortToPage(channel.port2);
    } catch {
        channel.port2.close();
        stop();
    }
    return stop;
}
