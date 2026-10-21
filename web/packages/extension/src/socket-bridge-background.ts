/** One authorized content port per native process. No payloads are logged. */
import {
    createHelperPromptManager,
    createToldDocuments,
} from "./helper-prompt";
import type { HelperContinue, HelperPromptManager } from "./helper-prompt";
import { getProxySettings, updateProxySettings } from "./proxy-settings";
import {
    defaultProxySettings,
    isAsked,
    PROXY_STORAGE_KEY,
    promptsForUnlisted,
    resolveSocketAccess,
    setSocketChoice,
    socketPermission,
} from "./socket-proxy";
import {
    MAX_PROMPTS_PER_TAB,
    PROMPT_ANSWER_REQUEST,
    PROMPT_CHOICES,
    PROMPT_GET_REQUEST,
    PROMPT_PAGE,
    PROMPT_PORT_NAME,
    createPromptManager,
} from "./socket-prompt";
import type {
    PromptChoice,
    PromptEffects,
    PromptHost,
    PromptManager,
} from "./socket-prompt";
import {
    VISIT_FORGET_REQUEST,
    VISIT_GET_REQUEST,
    createVisitStore,
} from "./socket-visit";
import type { SessionArea, VisitStore } from "./socket-visit";
import {
    HELLO_TIMEOUT_MS,
    HELPER_CONTINUE_REQUEST,
    HELPER_STATUS_REQUEST,
    MAX_ASKING_SOCKETS,
    MAX_FRAME_SOCKETS,
    MAX_GLOBAL_SOCKETS,
    MAX_TAB_ASKING_SOCKETS,
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
import {
    MIN_LAN_HELPER_VERSION,
    isLanDestination,
    lanHostOf,
    versionAtLeast,
} from "./socket-lan";

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

/**
 * The top-level origin of the sender's tab, when the browser tells it. A frame
 * in a page of another origin is asking on behalf of that page's visitor, so
 * the question names both.
 */
export function topOrigin(sender: Sender): string | undefined {
    try {
        const url = new URL(sender?.tab?.url ?? "");
        return ["http:", "https:"].includes(url.protocol) &&
            !url.username &&
            !url.password
            ? url.origin
            : undefined;
    } catch {
        return undefined;
    }
}

const SETTINGS_PAGES = ["/options.html", "/popup.html"];
/**
 * The pages that may ask whether the helper is installed: the install page
 * checks it too, and the "install the helper first" window waits for it.
 */
const HELPER_STATUS_PAGES = [
    ...SETTINGS_PAGES,
    "/helper.html",
    `/${PROMPT_PAGE}`,
];

/** The toolbar icon of a tab whose game could not reach the helper: a red "!". */
const HELPER_BADGE_TEXT = "!";
const HELPER_BADGE_COLOR = "#d93025";

/**
 * Tells the visitor, on the toolbar icon, that the page in a tab needed the
 * socket helper and could not get it; the popup then says what to do. The
 * mark belongs to the tab, so it is gone when the page is.
 */
export interface HelperBadge {
    show(tabId: number): void;
}

function browserHelperBadge(): HelperBadge {
    return {
        show(tabId) {
            const action = browser.action as typeof chrome.action | undefined;
            if (!action) {
                return;
            }
            const ignore = () => {};
            try {
                void Promise.resolve(
                    action.setBadgeText({ tabId, text: HELPER_BADGE_TEXT }),
                ).catch(ignore);
                void Promise.resolve(
                    action.setBadgeBackgroundColor({
                        tabId,
                        color: HELPER_BADGE_COLOR,
                    }),
                ).catch(ignore);
            } catch {
                /* No such tab any more, or no badge in this browser. */
            }
        },
    };
}

/** The answers that mean "run the installer": the helper is not there, or not the right one. */
const NEEDS_INSTALLER = new Set(["helper_missing", "helper_incompatible"]);

/**
 * Only our own top-level pages may ask about the helper or the prompt. A
 * website can frame any extension page (they are web accessible), so a frame,
 * or a page of another origin, never counts.
 */
export function isExtensionUI(
    sender: Sender,
    pages: readonly string[] = SETTINGS_PAGES,
): boolean {
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
            pages.includes(url.pathname) &&
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
    /** Still waiting for the permission check, which may include a question to the user. */
    checking: () => boolean;
    /**
     * Waiting for a person to answer the first-use question. Such a socket
     * holds no connection slot: an ignored question must not use up the slots
     * that sockets of allowed sites need.
     */
    waiting: () => boolean;
}

/** Whether a socket may start waiting for an answer, or start connecting after one. */
interface SocketLimits {
    mayAsk: () => boolean;
    mayConnect: () => boolean;
}

function handleSocketPort(
    page: chrome.runtime.Port,
    authorize: (signal: AbortSignal, asking: () => void) => Promise<boolean>,
    release: () => void,
    limits: SocketLimits,
    /**
     * Called with the code ("helper_missing", "helper_incompatible") when the
     * socket failed because the helper has to be installed, and the version
     * the new one needs at least when the one there was too old.
     */
    helperProblem: (code: string, minVersion?: string) => void,
    /** The private address the frame is served from (lanHostOf of the browser's sender origin): the helper may connect back to it. */
    lan: string | undefined,
): SocketHandle {
    const abort = new AbortController();
    let native: chrome.runtime.Port | null = null;
    let helperVersion: string | undefined;
    let state:
        | "idle"
        | "checking"
        | "hello"
        | "connecting"
        | "open"
        | "closing"
        | "done" = "idle";
    let asking = false;
    let sending = false;
    let receiving = false;
    let phaseTimer: ReturnType<typeof setTimeout> | undefined;
    let sendTimer: ReturnType<typeof setTimeout> | undefined;
    let receiveTimer: ReturnType<typeof setTimeout> | undefined;

    const finish = (reply?: FinalReply, minVersion?: string) => {
        if (state === "done") {
            return;
        }
        state = "done";
        clearTimeout(phaseTimer);
        clearTimeout(sendTimer);
        clearTimeout(receiveTimer);
        // Withdraws a pending question's waiter, so no window stays for a gone page.
        abort.abort();
        release();
        if (reply?.type === "error" && NEEDS_INSTALLER.has(reply.code)) {
            helperProblem(reply.code, minVersion);
        }
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
    const fail = (code: string, minVersion?: string) =>
        finish({ type: "error", code }, minVersion);
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
    /**
     * A helper from before the "own address" exception (socket-lan.ts) refuses
     * the website's own address: installing the new one is what fixes that.
     * Every other refusal is the page's to see, and an old helper keeps
     * working for public destinations.
     */
    const refusedAsOutdated = (host: string, code: string) =>
        code === "blocked" &&
        lan !== undefined &&
        isLanDestination(host, lan) &&
        !versionAtLeast(helperVersion, MIN_LAN_HELPER_VERSION);
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
                if (state === "hello") {
                    fail("helper_incompatible");
                } else if (
                    state === "connecting" &&
                    refusedAsOutdated(open.host, reply.code)
                ) {
                    // It says hello like a new one: only its version tells the new one apart.
                    fail("helper_incompatible", MIN_LAN_HELPER_VERSION);
                } else {
                    fail(reply.code);
                }
                return;
            }
            if (state === "hello") {
                if (reply.type !== "hello" || !isCompatibleHello(reply)) {
                    fail("helper_incompatible");
                    return;
                }
                helperVersion = reply.version;
                state = "connecting";
                arm(STALL_TIMEOUT_MS, "connect_timeout");
                // Only the host and port of the page's request: no page property is
                // forwarded. lanHost comes from the browser's sender, and the helper
                // checks it again.
                toNative({
                    type: "open",
                    host: open.host,
                    port: open.port,
                    ...(lan === undefined ? {} : { lanHost: lan }),
                });
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
            authorize(abort.signal, () => {
                // A person is being asked: wait for the answer, not for start-up.
                if (state !== "checking") {
                    return;
                }
                if (!limits.mayAsk()) {
                    fail("socket_limit");
                    return;
                }
                asking = true;
                arm(STALL_TIMEOUT_MS, "prompt_timeout");
            }).then(
                (allowed) => {
                    if (state !== "checking") {
                        return;
                    }
                    if (!allowed) {
                        fail("not_allowed");
                        return;
                    }
                    // The slots may have been taken while the person decided.
                    if (asking && !limits.mayConnect()) {
                        fail("socket_limit");
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
    return {
        sender: page.sender,
        stop: fail,
        checking: () => state === "checking",
        waiting: () => state === "checking" && asking,
    };
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

/** What the registration is built from; tests replace the browser-backed parts. */
export interface SocketBridgeDeps {
    visits?: VisitStore;
    prompts?: PromptManager;
    helperPrompts?: HelperPromptManager;
    badge?: HelperBadge;
}

const PROMPT_SIZE = { width: 540, height: 680 };
/** The "install the helper" window: as tall as the question, for the step to run the installer and the wait for it. */
const HELPER_PROMPT_SIZE = { width: 540, height: 680 };

/** A window of prompt.html, opened next to the window of the page that causes it. */
function browserPromptHost(size = PROMPT_SIZE): PromptHost {
    return {
        async open(id, near) {
            const url = `${browser.runtime.getURL(`/${PROMPT_PAGE}`)}?id=${encodeURIComponent(id)}`;
            let position: { left?: number; top?: number } = {};
            if (near !== undefined) {
                try {
                    const anchor = await browser.windows.get(near);
                    if (
                        anchor.left !== undefined &&
                        anchor.top !== undefined &&
                        anchor.width !== undefined &&
                        anchor.height !== undefined
                    ) {
                        position = {
                            left: Math.max(
                                0,
                                Math.round(
                                    anchor.left +
                                        (anchor.width - size.width) / 2,
                                ),
                            ),
                            top: Math.max(
                                0,
                                Math.round(
                                    anchor.top +
                                        (anchor.height - size.height) / 2,
                                ),
                            ),
                        };
                    }
                } catch {
                    /* The browser places the window. */
                }
            }
            const created = await browser.windows.create({
                url,
                type: "popup",
                focused: true,
                ...size,
                ...position,
            });
            if (created?.id === undefined) {
                throw new Error("window_failed");
            }
            return created.id;
        },
        async close(windowId) {
            await browser.windows.remove(windowId);
        },
    };
}

function browserPromptEffects(visits: VisitStore): PromptEffects {
    return {
        async remember(origin, choice) {
            await updateProxySettings((settings) => {
                // Decided against the settings as they are when it is stored,
                // not as they were when the question was opened.
                if (!isAsked(settings, origin)) {
                    throw new Error("not_asking");
                }
                return setSocketChoice(settings, origin, choice);
            });
        },
        async stillAsking(origin) {
            return isAsked(await getProxySettings(), origin);
        },
        recordVisit: (tabId, origin, decision, top) =>
            visits.record(tabId, origin, decision, top),
        async countPrompt(tabId, top) {
            const visit = visits.get(tabId);
            // A tab past its budget is refused without more bookkeeping.
            return visit && visit.prompts > MAX_PROMPTS_PER_TAB
                ? visit.prompts
                : visits.countPrompt(tabId, top);
        },
        budgetSpent: (tabId) =>
            (visits.get(tabId)?.prompts ?? 0) >= MAX_PROMPTS_PER_TAB,
    };
}

/**
 * "Continue" in the "install the helper first" window: the helper is there
 * now, so the game's tab is reloaded and brought to the front. Only while the
 * tab still shows the website that needed the helper: a tab that has gone
 * elsewhere in the meantime is left alone. Resolves to whether it was reloaded.
 */
async function reloadGameTab({
    tabId,
    expectedOrigin,
}: HelperContinue): Promise<boolean> {
    let tab: chrome.tabs.Tab;
    let origin: string | undefined;
    try {
        tab = await browser.tabs.get(tabId);
        origin = new URL(tab.url ?? "").origin;
    } catch {
        // Closed in the meantime, or no page the extension may know the address of.
        return false;
    }
    if (origin !== expectedOrigin) {
        return false;
    }
    try {
        await browser.tabs.reload(tabId);
    } catch {
        return false;
    }
    try {
        await browser.tabs.update(tabId, { active: true });
    } catch {
        /* Reloaded all the same. */
    }
    try {
        await browser.windows.update(tab.windowId, { focused: true });
    } catch {
        /* Some browsers have no windows to bring forward. */
    }
    return true;
}

/** Register synchronously in the service worker. Return cleanup for isolated tests. */
export function registerSocketBridge(deps: SocketBridgeDeps = {}): () => void {
    const visits =
        deps.visits ??
        createVisitStore(
            // Absent in old browsers: answers then last as long as this service worker.
            browser.storage.session as SessionArea | undefined,
        );
    const prompts =
        deps.prompts ??
        createPromptManager(browserPromptHost(), browserPromptEffects(visits));
    const helperPrompts =
        deps.helperPrompts ??
        createHelperPromptManager(
            browserPromptHost(HELPER_PROMPT_SIZE),
            createToldDocuments(
                browser.storage.session as SessionArea | undefined,
            ),
        );
    const badge = deps.badge ?? browserHelperBadge();
    const active = new Set<SocketHandle>();
    let epoch = 0;
    let probe: ReturnType<typeof probeHelper> | undefined;

    /** The sockets that hold a connection slot: all but those waiting for an answer. */
    const holdingSlots = (except?: SocketHandle) =>
        [...active].filter((other) => other !== except && !other.waiting());
    /** Whether one more socket from this frame fits under the global and per-frame limits. */
    const hasFreeSlot = (sender: Sender, except: SocketHandle | undefined) => {
        const holding = holdingSlots(except);
        return (
            holding.length + Number(!!probe) < MAX_GLOBAL_SOCKETS &&
            holding.filter(
                (other) =>
                    other.sender?.tab?.id === sender?.tab?.id &&
                    other.sender?.frameId === sender?.frameId,
            ).length < MAX_FRAME_SOCKETS
        );
    };

    /** "ask" means a person has to decide; everything else is final. */
    const evaluate = async (
        origin: string,
        tabId: number,
    ): Promise<"allow" | "deny" | "ask"> => {
        for (let attempt = 0; attempt < 3; attempt++) {
            const started = epoch;
            const [settings, player] = await Promise.all([
                getProxySettings(),
                browser.storage.sync.get({ ruffleEnable: true }),
                visits.ready,
            ]);
            if (started !== epoch) {
                // Settings changed while they were being read: read them again.
                continue;
            }
            if (
                player["ruffleEnable"] === false ||
                settings.mode !== "helper"
            ) {
                return "deny";
            }
            const permission = socketPermission(settings, origin);
            if (permission === "allow") {
                return "allow";
            }
            if (permission !== "ask") {
                return "deny";
            }
            // Only the answer for this visit of this tab can still decide.
            return visits.decision(tabId, origin) ?? "ask";
        }
        return "deny";
    };
    const authorize = async (
        origin: string,
        sender: Sender,
        signal: AbortSignal,
        asking: () => void,
    ): Promise<boolean> => {
        const tabId = sender?.tab?.id;
        if (tabId === undefined) {
            return false;
        }
        let answer = await evaluate(origin, tabId);
        if (answer === "ask") {
            // Where there is no way to reach the helper (a browser build
            // without native messaging) a question could only mislead.
            if (typeof browser.runtime.connectNative !== "function") {
                return false;
            }
            asking();
            if (signal.aborted) {
                // Too many sockets are waiting already, or the page went away.
                return false;
            }
            const top = topOrigin(sender);
            const windowId = sender?.tab?.windowId;
            await prompts.ask(
                {
                    origin,
                    tabId,
                    frameId: sender?.frameId ?? 0,
                    ...(top === undefined ? {} : { top }),
                    ...(windowId === undefined ? {} : { windowId }),
                },
                signal,
            );
            // The answer is stored (or the question failed); decide again from the stored state.
            answer = await evaluate(origin, tabId);
        }
        return answer === "allow";
    };
    /** Whether a connection that is already open may stay open under these settings. */
    const mayStayOpen = (
        settings: unknown,
        origin: string | undefined,
        tabId: number | undefined,
    ): boolean => {
        if (!origin) {
            return false;
        }
        const permission = socketPermission(settings, origin);
        if (permission === "allow") {
            return resolveSocketAccess(settings, origin)?.mode === "helper";
        }
        return (
            permission === "ask" &&
            promptsForUnlisted(settings) &&
            tabId !== undefined &&
            visits.decision(tabId, origin) === "allow"
        );
    };

    const onConnect = (page: chrome.runtime.Port) => {
        if (page.name === PROMPT_PORT_NAME) {
            // The question window pings this port; every message restarts the
            // service worker's idle timer while a person reads the question.
            if (isExtensionUI(page.sender, [`/${PROMPT_PAGE}`])) {
                page.onMessage.addListener(() => {});
            } else {
                disconnect(page);
            }
            return;
        }
        if (page.name !== SOCKET_PORT_NAME) {
            return;
        }
        const origin = senderOrigin(page.sender);
        if (!origin || !hasFreeSlot(page.sender, undefined)) {
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
        const tabId = page.sender?.tab?.id;
        // From the browser's sender, like the origin: a page cannot name another address.
        const lan = lanHostOf(origin);
        const handle = handleSocketPort(
            page,
            (signal, asking) => authorize(origin, page.sender, signal, asking),
            () => active.delete(handle),
            {
                mayAsk: () => {
                    const waiting = [...active].filter((other) =>
                        other.waiting(),
                    );
                    return (
                        waiting.length < MAX_ASKING_SOCKETS &&
                        waiting.filter(
                            (other) => other.sender?.tab?.id === tabId,
                        ).length < MAX_TAB_ASKING_SOCKETS
                    );
                },
                mayConnect: () => hasFreeSlot(page.sender, handle),
            },
            (code, minVersion) => {
                if (tabId === undefined) {
                    return;
                }
                badge.show(tabId);
                // A browser without native messaging has no helper to install:
                // a window that asks for one could only mislead.
                if (typeof browser.runtime.connectNative !== "function") {
                    return;
                }
                // The game needs TCP and the helper is not there: say so now,
                // in a window of the extension's own, as the first-use question does.
                const top = topOrigin(page.sender);
                const windowId = page.sender?.tab?.windowId;
                const documentId = page.sender?.documentId;
                void helperPrompts.show({
                    problem:
                        code === "helper_incompatible"
                            ? "incompatible"
                            : "missing",
                    origin,
                    tabId,
                    frameId: page.sender?.frameId ?? 0,
                    ...(documentId === undefined ? {} : { documentId }),
                    ...(top === undefined ? {} : { top }),
                    ...(windowId === undefined ? {} : { windowId }),
                    // The window then waits for that version, not for any helper.
                    ...(minVersion === undefined ? {} : { minVersion }),
                });
            },
            lan,
        );
        active.add(handle);
    };
    const onMessage = (
        message: unknown,
        sender: chrome.runtime.MessageSender,
        sendResponse: (response: unknown) => void,
    ) => {
        if (!isRecord(message)) {
            return undefined;
        }
        switch (message["type"]) {
            case HELPER_STATUS_REQUEST:
                if (!isExtensionUI(sender, HELPER_STATUS_PAGES)) {
                    return undefined;
                }
                if (!probe && holdingSlots().length >= MAX_GLOBAL_SOCKETS) {
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
            case PROMPT_GET_REQUEST: {
                if (!isExtensionUI(sender, [`/${PROMPT_PAGE}`])) {
                    return undefined;
                }
                const id = message["id"];
                // The window shows either the first-use question or the "install the helper" notice.
                sendResponse(
                    (typeof id === "string"
                        ? (prompts.view(id, sender.tab?.windowId) ??
                          helperPrompts.view(id, sender.tab?.windowId))
                        : undefined) ?? null,
                );
                return false;
            }
            case PROMPT_ANSWER_REQUEST: {
                if (!isExtensionUI(sender, [`/${PROMPT_PAGE}`])) {
                    return undefined;
                }
                const id = message["id"];
                const choice = message["choice"];
                if (
                    typeof id !== "string" ||
                    typeof choice !== "string" ||
                    !PROMPT_CHOICES.includes(choice as PromptChoice)
                ) {
                    sendResponse(false);
                    return false;
                }
                void prompts
                    .answer(id, sender.tab?.windowId, choice as PromptChoice)
                    .then(sendResponse, () => sendResponse(false));
                return true;
            }
            case HELPER_CONTINUE_REQUEST: {
                // Only the window itself, for the request it shows; it names no tab.
                if (!isExtensionUI(sender, [`/${PROMPT_PAGE}`])) {
                    return undefined;
                }
                const id = message["id"];
                const target =
                    typeof id === "string"
                        ? helperPrompts.continue(id, sender.tab?.windowId)
                        : undefined;
                if (!target) {
                    sendResponse(false);
                    return false;
                }
                void reloadGameTab(target).then(sendResponse, () =>
                    sendResponse(false),
                );
                return true;
            }
            case VISIT_GET_REQUEST: {
                // The popup shows what was answered for this visit of its tab.
                const tabId = message["tabId"];
                if (!isExtensionUI(sender) || typeof tabId !== "number") {
                    return undefined;
                }
                void visits.ready.then(() => {
                    const visit = visits.get(tabId);
                    sendResponse({
                        ...(visit?.top === undefined ? {} : { top: visit.top }),
                        decisions: visit?.decisions ?? {},
                    });
                });
                return true;
            }
            case VISIT_FORGET_REQUEST: {
                const tabId = message["tabId"];
                const origin = message["origin"];
                if (
                    !isExtensionUI(sender) ||
                    typeof tabId !== "number" ||
                    typeof origin !== "string"
                ) {
                    return undefined;
                }
                void visits
                    .forget(tabId, origin)
                    // Forgetting a "this visit" allow takes the connections that relied on it.
                    .then(() => getProxySettings())
                    .then((settings) => {
                        for (const handle of active) {
                            if (
                                handle.sender?.tab?.id === tabId &&
                                senderOrigin(handle.sender) === origin &&
                                !handle.checking() &&
                                !mayStayOpen(settings, origin, tabId)
                            ) {
                                handle.stop("not_allowed");
                            }
                        }
                        sendResponse(true);
                    })
                    .catch(() => sendResponse(false));
                return true;
            }
            default:
                return undefined;
        }
    };
    const onChanged = (
        changes: Record<string, chrome.storage.StorageChange>,
        area: string,
    ) => {
        if (area === "local" && PROXY_STORAGE_KEY in changes) {
            epoch++;
            const settings: unknown =
                changes[PROXY_STORAGE_KEY]?.newValue ?? defaultProxySettings();
            prompts.settingsChanged(settings);
            const revoke = () => {
                for (const handle of active) {
                    // A check that is still running reads the new settings itself.
                    if (
                        !handle.checking() &&
                        !mayStayOpen(
                            settings,
                            senderOrigin(handle.sender),
                            handle.sender?.tab?.id,
                        )
                    ) {
                        handle.stop("not_allowed");
                    }
                }
            };
            if (visits.hydrated) {
                revoke();
            } else {
                void visits.ready.then(revoke);
            }
        } else if (area === "sync" && "ruffleEnable" in changes) {
            epoch++;
            if (changes["ruffleEnable"]?.newValue === false) {
                for (const handle of active) {
                    handle.stop("not_allowed");
                }
                // With the player off there is nothing left to ask about.
                prompts.dispose();
                helperPrompts.dispose();
            }
        }
    };
    const closeTab = (tabId: number) => {
        for (const handle of active) {
            if (handle.sender?.tab?.id === tabId) {
                handle.stop("bridge_closed");
            }
        }
        prompts.tabGone(tabId);
        helperPrompts.tabGone(tabId);
        void visits.forget(tabId);
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
        // An answer for "this visit" ends when the tab goes to another site.
        void visits.leftSite(tabId, origin).then((left) => {
            if (left) {
                prompts.tabGone(tabId);
            }
        });
    };
    const onWindowRemoved = (windowId: number) => {
        prompts.windowRemoved(windowId);
        helperPrompts.windowRemoved(windowId);
    };
    // A tab swapped for another (a prerendered page taking over) is gone as
    // far as its sockets and questions are concerned.
    const onReplaced = (_addedTabId: number, removedTabId: number) =>
        closeTab(removedTabId);
    browser.runtime.onConnect.addListener(onConnect);
    browser.runtime.onMessage.addListener(onMessage);
    browser.storage.onChanged.addListener(onChanged);
    browser.tabs.onRemoved.addListener(closeTab);
    browser.tabs.onUpdated.addListener(onUpdated);
    browser.tabs.onReplaced?.addListener(onReplaced);
    // `windows` (or its events) is missing in some browsers.
    browser.windows?.onRemoved?.addListener(onWindowRemoved);
    return () => {
        browser.runtime.onConnect.removeListener(onConnect);
        browser.runtime.onMessage.removeListener(onMessage);
        browser.storage.onChanged.removeListener(onChanged);
        browser.tabs.onRemoved.removeListener(closeTab);
        browser.tabs.onUpdated.removeListener(onUpdated);
        browser.tabs.onReplaced?.removeListener(onReplaced);
        browser.windows?.onRemoved?.removeListener(onWindowRemoved);
        for (const handle of active) {
            handle.stop("bridge_closed");
        }
        prompts.dispose();
        helperPrompts.dispose();
        probe?.cancel();
    };
}
