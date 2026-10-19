/**
 * "Install the socket helper first": the window that tells the visitor, at the
 * moment a game has tried to open a TCP connection and the helper could not be
 * reached, what is missing and offers the installer.
 *
 * It is the sibling of the first-use question (socket-prompt.ts): a window of
 * the extension's own, opened next to the game's window, never something drawn
 * inside the page. Nothing is asked here, so there is no answer to store; the
 * window can simply be closed. A page cannot make the extension flood the
 * screen with these windows: one is open at a time, a page load is told once,
 * and only a few open per minute.
 */
import type { PromptHost } from "./socket-prompt";
import type { SessionArea } from "./socket-visit";

/** The helper is not there, or it is there but not the one this extension needs. */
export type HelperProblem = "missing" | "incompatible";

/** Helper windows the extension opens per minute, whichever tabs need the helper. */
export const MAX_HELPER_PROMPTS_PER_MINUTE = 3;
/** Page loads remembered as told already; the oldest are forgotten first. */
export const MAX_TOLD_DOCUMENTS = 32;
const MINUTE_MS = 60000;
/** Window removals that arrived before the browser said which window it had opened. */
const MAX_EARLY_REMOVALS = 16;
const STORAGE_KEY = "helperToldDocuments";

/** What the window shows. */
export interface HelperPromptView {
    helper: HelperProblem;
    /** The origin of the frame whose connection needed the helper, from the browser's sender. */
    origin: string;
    /** Set when that frame is embedded in a page of another origin. */
    embeddedIn?: string;
}

export function isHelperPromptView(value: unknown): value is HelperPromptView {
    if (typeof value !== "object" || value === null) {
        return false;
    }
    const view = value as Record<string, unknown>;
    return (
        (view["helper"] === "missing" || view["helper"] === "incompatible") &&
        typeof view["origin"] === "string" &&
        (view["embeddedIn"] === undefined ||
            typeof view["embeddedIn"] === "string")
    );
}

export interface HelperPromptRequest {
    problem: HelperProblem;
    /** The asking frame's origin, from the browser's sender. */
    origin: string;
    tabId: number;
    frameId: number;
    /**
     * Tells page loads apart: the browser's document id. Without it a tab's
     * frame of one origin counts as one page load.
     */
    documentId?: string;
    /** The tab's top-level origin, when the browser tells. */
    top?: string;
    /** The tab's window, to open the helper window next to it. */
    windowId?: number;
}

export interface HelperPromptManager {
    /**
     * Opens the window, unless one is open, this page load was told already,
     * or too many opened lately. Resolves to whether a window was opened.
     */
    show(request: HelperPromptRequest): Promise<boolean>;
    /** The view in window `windowId`, if `id` is its open window. */
    view(
        id: string,
        windowId: number | undefined,
    ): HelperPromptView | undefined;
    /** The user closed a window. */
    windowRemoved(windowId: number): void;
    /** A tab was closed: its page loads need not be remembered. */
    tabGone(tabId: number): void;
    dispose(): void;
}

/** The page loads that were told already. They survive a restarted service worker, not a restarted browser. */
export interface ToldDocuments {
    readonly ready: Promise<void>;
    has(tabId: number, documentId: string): boolean;
    add(tabId: number, documentId: string): Promise<void>;
    forgetTab(tabId: number): Promise<void>;
}

type Told = [tabId: number, documentId: string];

function readTold(value: unknown): Told[] {
    if (!Array.isArray(value)) {
        return [];
    }
    const told: Told[] = [];
    for (const item of value) {
        if (
            Array.isArray(item) &&
            item.length === 2 &&
            typeof item[0] === "number" &&
            Number.isSafeInteger(item[0]) &&
            typeof item[1] === "string"
        ) {
            told.push([item[0], item[1]]);
        }
    }
    return told.slice(-MAX_TOLD_DOCUMENTS);
}

export function createToldDocuments(
    area: SessionArea | undefined,
): ToldDocuments {
    let told: Told[] = [];
    const persist = async () => {
        try {
            await area?.set({ [STORAGE_KEY]: told });
        } catch {
            /* Memory still holds them for this service worker's lifetime. */
        }
    };
    const ready = (async () => {
        if (!area) {
            return;
        }
        try {
            // Nothing is added before this is done: add() and forgetTab() wait for it.
            told = readTold((await area.get(null))[STORAGE_KEY]);
        } catch {
            /* Unreadable session storage means nothing was told yet. */
        }
    })();
    return {
        ready,
        has: (tabId, documentId) =>
            told.some((known) => known[0] === tabId && known[1] === documentId),
        async add(tabId, documentId) {
            await ready;
            if (
                !told.some(
                    (known) => known[0] === tabId && known[1] === documentId,
                )
            ) {
                told.push([tabId, documentId]);
                told = told.slice(-MAX_TOLD_DOCUMENTS);
            }
            await persist();
        },
        async forgetTab(tabId) {
            await ready;
            const kept = told.filter((known) => known[0] !== tabId);
            if (kept.length !== told.length) {
                told = kept;
                await persist();
            }
        },
    };
}

interface Opening {
    id: string;
    tabId: number;
    view: HelperPromptView;
    near: number | undefined;
    windowId: number | undefined;
}

export function createHelperPromptManager(
    host: PromptHost,
    told: ToldDocuments,
    now: () => number = Date.now,
): HelperPromptManager {
    /** The window that is open, or being opened. */
    let current: Opening | undefined;
    /** A request is being decided or its window opened: others wait for their next failure. */
    let busy = false;
    /** The request being decided; `gone` is set when its tab closes meanwhile. */
    let deciding: { tabId: number; gone: boolean } | undefined;
    /** Bumped by dispose(): what was under way is dropped. */
    let epoch = 0;
    /** When the recent windows were opened. */
    let opened: number[] = [];
    const earlyRemovals = new Set<number>();
    /** Windows this manager closed itself: their removal needs no handling. */
    const closing = new Set<number>();

    const closeWindow = (windowId: number) => {
        closing.add(windowId);
        if (closing.size > MAX_EARLY_REMOVALS) {
            const oldest = closing.values().next().value;
            if (oldest !== undefined) {
                closing.delete(oldest);
            }
        }
        host.close(windowId).catch(() => {
            /* Already closed. */
        });
    };
    /** Takes the open window away, whether it is still opening or not. */
    const dropCurrent = () => {
        const windowId = current?.windowId;
        current = undefined;
        if (windowId !== undefined) {
            closeWindow(windowId);
        }
    };

    return {
        async show(request) {
            // Sockets that fail together (a game opens several at once) share
            // the window of the first.
            if (busy) {
                return false;
            }
            busy = true;
            const started = epoch;
            // Until the window exists there is nothing for tabGone() to close:
            // a tab that closes in the awaits below must stop the request.
            const asking = { tabId: request.tabId, gone: false };
            deciding = asking;
            try {
                await told.ready;
                const pageLoad =
                    request.documentId ??
                    `${request.frameId}|${request.origin}`;
                if (
                    epoch !== started ||
                    asking.gone ||
                    told.has(request.tabId, pageLoad)
                ) {
                    return false;
                }
                const time = now();
                opened = opened.filter((at) => time - at < MINUTE_MS);
                if (opened.length >= MAX_HELPER_PROMPTS_PER_MINUTE) {
                    return false;
                }
                opened.push(time);
                // Remembered before the window opens, so that a browser that
                // cannot open one is not asked again by every failing socket.
                await told.add(request.tabId, pageLoad);
                if (epoch !== started || asking.gone) {
                    return false;
                }
                // A window that is still open (it may be behind the browser's
                // own, or belong to a page that is gone) makes way for the one
                // of this page load: it must not keep every later one away.
                dropCurrent();
                const claim: Opening = {
                    id: crypto.randomUUID(),
                    tabId: request.tabId,
                    view: {
                        helper: request.problem,
                        origin: request.origin,
                        ...(request.frameId !== 0 &&
                        request.top !== undefined &&
                        request.top !== request.origin
                            ? { embeddedIn: request.top }
                            : {}),
                    },
                    near: request.windowId,
                    windowId: undefined,
                };
                current = claim;
                const windowId = await host.open(claim.id, claim.near);
                claim.windowId = windowId;
                if (current !== claim) {
                    // Disposed, or its tab closed, while the window was opening.
                    closeWindow(windowId);
                    return false;
                }
                if (earlyRemovals.delete(windowId)) {
                    // Closed before the browser told us its id: nobody will say so again.
                    current = undefined;
                }
                return true;
            } catch {
                // A window that failed to open leaves nothing behind.
                if (current !== undefined && current.windowId === undefined) {
                    current = undefined;
                }
                return false;
            } finally {
                busy = false;
                deciding = undefined;
            }
        },

        view(id, windowId) {
            // The window id is only known once the browser has created the
            // window; the page may ask for its text a moment before that.
            return current &&
                current.id === id &&
                windowId !== undefined &&
                (current.windowId === undefined ||
                    current.windowId === windowId)
                ? current.view
                : undefined;
        },

        windowRemoved(windowId) {
            if (closing.delete(windowId) || !current) {
                return;
            }
            if (current.windowId === windowId) {
                current = undefined;
            } else if (current.windowId === undefined) {
                // The removal can overtake the browser's reply to "open a window".
                earlyRemovals.add(windowId);
                if (earlyRemovals.size > MAX_EARLY_REMOVALS) {
                    const oldest = earlyRemovals.values().next().value;
                    if (oldest !== undefined) {
                        earlyRemovals.delete(oldest);
                    }
                }
            }
        },

        tabGone(tabId) {
            void told.forgetTab(tabId);
            // The page the window is about is gone with its tab.
            if (current?.tabId === tabId) {
                dropCurrent();
            }
            if (deciding?.tabId === tabId) {
                deciding.gone = true;
            }
        },

        dispose() {
            epoch++;
            earlyRemovals.clear();
            dropCurrent();
        },
    };
}
