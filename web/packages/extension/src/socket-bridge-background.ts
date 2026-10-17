/** One authorized content port per native process. No payloads are logged. */
import { getProxySettings } from "./proxy-settings";
import {
    defaultProxySettings,
    PROXY_STORAGE_KEY,
    resolveSocketAccess,
} from "./socket-proxy";
import {
    HELLO_TIMEOUT_MS,
    HELPER_STATUS_REQUEST,
    MAX_FRAME_SOCKETS,
    MAX_GLOBAL_SOCKETS,
    NATIVE_HOST_NAME,
    SOCKET_PORT_NAME,
    STALL_TIMEOUT_MS,
    isCompatibleHello,
    isHelperReply,
    isOpenRequest,
    isRecord,
    isSendRequest,
} from "./socket-bridge-protocol";
import type { HelperStatus, OpenRequest } from "./socket-bridge-protocol";

type Sender = chrome.runtime.MessageSender | undefined;
type FinalReply = { type: "closed" } | { type: "error"; code: string };

/** Trust only the browser's sender, never a page-supplied URL or top tab URL. */
export function senderOrigin(sender: Sender): string | undefined {
    if (
        sender?.id !== browser.runtime.id ||
        !Number.isInteger(sender.tab?.id) ||
        !Number.isInteger(sender.frameId)
    ) {
        return undefined;
    }
    try {
        const url = new URL(sender.url ?? "");
        if (
            !["http:", "https:"].includes(url.protocol) ||
            url.username ||
            url.password
        ) {
            return undefined;
        }
        // An opaque/sandboxed origin must never fall back to its nominal URL.
        if (sender.origin !== undefined && sender.origin !== url.origin) {
            return undefined;
        }
        return url.origin;
    } catch {
        return undefined;
    }
}

/** Status probes are allowed only from our top-level options/popup UI. */
export function isExtensionUI(sender: Sender): boolean {
    if (
        sender?.id !== browser.runtime.id ||
        (sender.frameId !== undefined && sender.frameId !== 0)
    ) {
        return false;
    }
    try {
        const url = new URL(sender.url ?? "");
        const own = new URL(browser.runtime.getURL("/"));
        return (
            url.protocol === own.protocol &&
            url.host === own.host &&
            !url.username &&
            !url.password &&
            ["/options.html", "/popup.html"].includes(url.pathname) &&
            (sender.origin === undefined ||
                sender.origin === own.protocol + "//" + own.host)
        );
    } catch {
        return false;
    }
}

function helperErrorCode(message: string): string {
    return /not found|not installed|no such native|specified native messaging host/iu.test(
        message,
    )
        ? "helper_missing"
        : "helper_failed";
}

function disconnect(port: chrome.runtime.Port | null): void {
    try {
        port?.disconnect();
    } catch {
        /* Already disconnected. */
    }
}

interface SocketHandle {
    sender: Sender;
    stop: (code: string) => void;
}

function handleSocketPort(
    page: chrome.runtime.Port,
    authorize: () => Promise<boolean>,
    release: () => void,
): SocketHandle {
    let native: chrome.runtime.Port | null = null;
    let state:
        | "idle"
        | "checking"
        | "hello"
        | "connecting"
        | "open"
        | "closing"
        | "done" = "idle";
    let sending = false;
    let receiving = false;
    let phaseTimer: ReturnType<typeof setTimeout> | undefined;
    let sendTimer: ReturnType<typeof setTimeout> | undefined;
    let receiveTimer: ReturnType<typeof setTimeout> | undefined;

    const finish = (reply?: FinalReply) => {
        if (state === "done") {
            return;
        }
        state = "done";
        clearTimeout(phaseTimer);
        clearTimeout(sendTimer);
        clearTimeout(receiveTimer);
        release();
        if (reply) {
            try {
                page.postMessage(reply);
            } catch {
                /* Navigated away. */
            }
        }
        // Disconnect cancels DNS/connect/blocked IO as well as idle sockets.
        disconnect(native);
        disconnect(page);
    };
    const fail = (code: string) => finish({ type: "error", code });
    const arm = (ms: number, code: string) => {
        clearTimeout(phaseTimer);
        phaseTimer = setTimeout(() => fail(code), ms);
    };
    const toPage = (message: unknown) => {
        try {
            page.postMessage(message);
        } catch {
            finish();
        }
    };
    const toNative = (message: unknown) => {
        try {
            native?.postMessage(message);
        } catch {
            fail("helper_failed");
        }
    };
    const connectHelper = (open: OpenRequest) => {
        state = "hello";
        arm(HELLO_TIMEOUT_MS, "helper_timeout");
        try {
            native = browser.runtime.connectNative(NATIVE_HOST_NAME);
        } catch {
            fail("helper_missing");
            return;
        }
        native.onMessage.addListener((reply: unknown) => {
            if (state === "done") {
                return;
            }
            if (!isHelperReply(reply)) {
                fail(state === "hello" ? "helper_incompatible" : "invalid");
                return;
            }
            // A protocol 2 helper always answers hello; an older one may reject it.
            if (reply.type === "error") {
                fail(state === "hello" ? "helper_incompatible" : reply.code);
                return;
            }
            if (state === "hello") {
                if (!isCompatibleHello(reply)) {
                    fail("helper_incompatible");
                    return;
                }
                state = "connecting";
                arm(STALL_TIMEOUT_MS, "connect_timeout");
                // Do not forward arbitrary page properties (e.g. private-network overrides).
                toNative({ type: "open", host: open.host, port: open.port });
                return;
            }
            switch (reply.type) {
                case "opened":
                    if (state !== "connecting") {
                        fail("invalid");
                        return;
                    }
                    clearTimeout(phaseTimer);
                    state = "open";
                    toPage({ type: "opened" });
                    return;
                case "sent":
                    if ((state !== "open" && state !== "closing") || !sending) {
                        fail("invalid");
                        return;
                    }
                    sending = false;
                    clearTimeout(sendTimer);
                    toPage({ type: "sent" });
                    return;
                case "data":
                    if (
                        (state !== "open" && state !== "closing") ||
                        receiving
                    ) {
                        fail("invalid");
                        return;
                    }
                    receiving = true;
                    receiveTimer = setTimeout(
                        () => fail("ack_timeout"),
                        STALL_TIMEOUT_MS,
                    );
                    toPage({ type: "data", data: reply.data });
                    return;
                case "closed":
                    if (state === "connecting") {
                        fail("connect_failed");
                    } else if (sending) {
                        fail("write_failed");
                    } else {
                        finish({ type: "closed" });
                    }
                    return;
                default:
                    fail("invalid");
            }
        });
        native.onDisconnect.addListener(() => {
            const message = browser.runtime.lastError?.message ?? "";
            // A clean end must have a protocol 'closed', not a crashed process.
            fail(helperErrorCode(message));
        });
        toNative({ type: "hello" });
    };

    page.onDisconnect.addListener(() => {
        void browser.runtime.lastError;
        finish();
    });
    page.onMessage.addListener((message: unknown) => {
        if (state === "done") {
            return;
        }
        if (isRecord(message) && message["type"] === "close") {
            if (state === "closing") {
                return;
            }
            if (state !== "open") {
                finish({ type: "closed" });
                return;
            }
            state = "closing";
            arm(STALL_TIMEOUT_MS, "close_timeout");
            toNative({ type: "close" });
            return;
        }
        if (state === "idle") {
            if (!isOpenRequest(message)) {
                fail("invalid");
                return;
            }
            state = "checking";
            authorize().then(
                (allowed) => {
                    if (state !== "checking") {
                        return;
                    }
                    if (!allowed) {
                        fail("not_allowed");
                        return;
                    }
                    connectHelper(message);
                },
                () => fail("not_allowed"),
            );
            return;
        }
        if (state === "open" && isSendRequest(message) && !sending) {
            sending = true;
            sendTimer = setTimeout(
                () => fail("write_timeout"),
                STALL_TIMEOUT_MS,
            );
            toNative({ type: "send", data: message.data });
            return;
        }
        if (
            (state === "open" || state === "closing") &&
            isRecord(message) &&
            message["type"] === "ack" &&
            receiving
        ) {
            receiving = false;
            clearTimeout(receiveTimer);
            toNative({ type: "ack" });
            return;
        }
        fail("invalid");
    });
    arm(HELLO_TIMEOUT_MS, "bridge_timeout");
    return { sender: page.sender, stop: fail };
}

/** A bounded, cancellable hello-only probe; it never opens TCP. */
function probeHelper(): { result: Promise<HelperStatus>; cancel: () => void } {
    let cancel = () => {};
    const result = new Promise<HelperStatus>((resolve) => {
        let port: chrome.runtime.Port | null = null;
        let done = false;
        const finish = (status: HelperStatus) => {
            if (done) {
                return;
            }
            done = true;
            clearTimeout(timer);
            disconnect(port);
            resolve(status);
        };
        const timer = setTimeout(
            () => finish({ installed: false, error: "helper_timeout" }),
            HELLO_TIMEOUT_MS,
        );
        cancel = () => finish({ installed: false, error: "bridge_closed" });
        try {
            port = browser.runtime.connectNative(NATIVE_HOST_NAME);
            port.onMessage.addListener((reply: unknown) => {
                if (!isHelperReply(reply) || reply.type !== "hello") {
                    finish({ installed: false, error: "helper_incompatible" });
                } else {
                    finish({
                        installed: isCompatibleHello(reply),
                        version: reply.version,
                        protocol: reply.protocol,
                        ...(isCompatibleHello(reply)
                            ? {}
                            : { error: "helper_incompatible" }),
                    });
                }
            });
            port.onDisconnect.addListener(() => {
                const message = browser.runtime.lastError?.message ?? "";
                finish({ installed: false, error: helperErrorCode(message) });
            });
            port.postMessage({ type: "hello" });
        } catch {
            finish({ installed: false, error: "helper_missing" });
        }
    });
    return { result, cancel };
}

/** Register synchronously in the service worker. Return cleanup for isolated tests. */
export function registerSocketBridge(): () => void {
    const active = new Set<SocketHandle>();
    let epoch = 0;
    let probe: ReturnType<typeof probeHelper> | undefined;
    const onConnect = (page: chrome.runtime.Port) => {
        if (page.name !== SOCKET_PORT_NAME) {
            return;
        }
        const origin = senderOrigin(page.sender);
        const sameFrame = [...active].filter(
            ({ sender }) =>
                sender?.tab?.id === page.sender?.tab?.id &&
                sender?.frameId === page.sender?.frameId,
        ).length;
        if (
            !origin ||
            active.size + Number(!!probe) >= MAX_GLOBAL_SOCKETS ||
            sameFrame >= MAX_FRAME_SOCKETS
        ) {
            try {
                page.postMessage({
                    type: "error",
                    code: origin ? "socket_limit" : "not_allowed",
                });
            } catch {
                /* Gone. */
            }
            disconnect(page);
            return;
        }
        const handle = handleSocketPort(
            page,
            async () => {
                const started = epoch;
                const [settings, player] = await Promise.all([
                    getProxySettings(),
                    browser.storage.sync.get({ ruffleEnable: true }),
                ]);
                return (
                    started === epoch &&
                    player["ruffleEnable"] !== false &&
                    resolveSocketAccess(settings, origin)?.mode === "helper"
                );
            },
            () => active.delete(handle),
        );
        active.add(handle);
    };
    const onMessage = (
        message: unknown,
        sender: chrome.runtime.MessageSender,
        sendResponse: (response: HelperStatus) => void,
    ) => {
        if (
            !isRecord(message) ||
            message["type"] !== HELPER_STATUS_REQUEST ||
            !isExtensionUI(sender)
        ) {
            return undefined;
        }
        if (!probe && active.size >= MAX_GLOBAL_SOCKETS) {
            sendResponse({ installed: false, error: "socket_limit" });
            return false;
        }
        if (!probe) {
            probe = probeHelper();
            void probe.result.then(() => {
                probe = undefined;
            });
        }
        void probe.result.then(sendResponse);
        return true;
    };
    const onChanged = (
        changes: Record<string, chrome.storage.StorageChange>,
        area: string,
    ) => {
        if (area === "local" && PROXY_STORAGE_KEY in changes) {
            epoch++;
            const settings: unknown =
                changes[PROXY_STORAGE_KEY]?.newValue ?? defaultProxySettings();
            for (const handle of active) {
                if (
                    resolveSocketAccess(settings, senderOrigin(handle.sender))
                        ?.mode !== "helper"
                ) {
                    handle.stop("not_allowed");
                }
            }
        } else if (area === "sync" && "ruffleEnable" in changes) {
            epoch++;
            if (changes["ruffleEnable"]?.newValue === false) {
                for (const handle of active) {
                    handle.stop("not_allowed");
                }
            }
        }
    };
    const closeTab = (tabId: number) => {
        for (const handle of active) {
            if (handle.sender?.tab?.id === tabId) {
                handle.stop("bridge_closed");
            }
        }
    };
    // Chrome already disconnects a frame's ports when its document goes away.
    // "loading"/url updates also fire for iframe loads and same-document
    // (pushState/hash) navigations, so only a top-level origin change counts.
    const onUpdated = (tabId: number, change: chrome.tabs.OnUpdatedInfo) => {
        if (change.url === undefined) {
            return;
        }
        let origin: string | undefined;
        try {
            origin = new URL(change.url).origin;
        } catch {
            origin = undefined;
        }
        for (const handle of active) {
            if (
                handle.sender?.tab?.id === tabId &&
                handle.sender.frameId === 0 &&
                senderOrigin(handle.sender) !== origin
            ) {
                handle.stop("bridge_closed");
            }
        }
    };
    browser.runtime.onConnect.addListener(onConnect);
    browser.runtime.onMessage.addListener(onMessage);
    browser.storage.onChanged.addListener(onChanged);
    browser.tabs.onRemoved.addListener(closeTab);
    browser.tabs.onUpdated.addListener(onUpdated);
    return () => {
        browser.runtime.onConnect.removeListener(onConnect);
        browser.runtime.onMessage.removeListener(onMessage);
        browser.storage.onChanged.removeListener(onChanged);
        browser.tabs.onRemoved.removeListener(closeTab);
        browser.tabs.onUpdated.removeListener(onUpdated);
        for (const handle of active) {
            handle.stop("bridge_closed");
        }
        probe?.cancel();
    };
}
