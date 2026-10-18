/**
 * The first-use question: "this website wants to use sockets - allow it?".
 *
 * The question is asked in a window that belongs to the extension, never
 * inside the page, so a page can neither draw a look-alike over it nor click
 * through it. Only one question is open at a time; a website that is already
 * being asked about waits for the same answer, and a page cannot make the
 * extension open more than a few windows.
 */
import { socketPermission } from "./socket-proxy";
import type { SocketChoice } from "./socket-proxy";
import type { VisitDecision } from "./socket-visit";

export const PROMPT_PAGE = "prompt.html";
/** The prompt window keeps this port open (and pings it) so that the service worker stays alive. */
export const PROMPT_PORT_NAME = "timffle-socket-prompt";
export const PROMPT_GET_REQUEST = "socket_prompt_get";
export const PROMPT_ANSWER_REQUEST = "socket_prompt_answer";
/** Waiting websites beyond this are refused without a question. */
export const MAX_QUEUED_PROMPTS = 8;
/** Question windows one tab may cause during one visit. */
export const MAX_PROMPTS_PER_TAB = 3;

export type PromptChoice =
    "allow-once" | "allow-always" | "deny-once" | "deny-always";

export const PROMPT_CHOICES: readonly PromptChoice[] = [
    "allow-once",
    "allow-always",
    "deny-once",
    "deny-always",
];

/**
 * "answered": a decision was stored (or someone else made one); look it up.
 * "dismissed": the window was closed or the tab went away; nothing was stored
 * for waiters that are gone. "unavailable": no question could be asked.
 */
export type PromptOutcome = "answered" | "dismissed" | "unavailable";

export interface PromptRequest {
    /** The asking frame's origin, from the browser's sender. */
    origin: string;
    tabId: number;
    /** The tab's top-level origin, when the browser tells. */
    top?: string;
    frameId: number;
    /** The tab's window, to open the question next to it. */
    windowId?: number;
}

/** What the prompt window shows. */
export interface PromptView {
    origin: string;
    /** Set when the asking frame is embedded in a page of another origin. */
    embeddedIn?: string;
}

/** Browser capabilities, replaceable in tests. */
export interface PromptHost {
    /** Opens the prompt window for `id` and returns its window id. */
    open(id: string, near?: number): Promise<number>;
    close(windowId: number): Promise<void>;
}

/** How answers are kept. */
export interface PromptEffects {
    /** An always-allow / always-deny answer, or "ask" to forget. */
    remember(origin: string, choice: SocketChoice): Promise<void>;
    /** An answer for this visit of one tab. */
    recordVisit(
        tabId: number,
        origin: string,
        decision: VisitDecision,
        top?: string,
    ): Promise<void>;
    /** Counts a question window for the tab; returns how many it has caused. */
    countPrompt(tabId: number, top?: string): Promise<number>;
}

export interface PromptManager {
    /**
     * Asks about `request.origin`, or joins the question already open for it.
     * Aborting `signal` withdraws this waiter (the question stays open).
     */
    ask(request: PromptRequest, signal: AbortSignal): Promise<PromptOutcome>;
    /** The question in window `windowId`, if `id` is its open question. */
    view(id: string, windowId: number | undefined): PromptView | undefined;
    /** Applies the user's answer from window `windowId`. */
    answer(
        id: string,
        windowId: number | undefined,
        choice: PromptChoice,
    ): Promise<boolean>;
    /** The user closed a window. */
    windowRemoved(windowId: number): void;
    /** A tab was closed or left the site it asked from. */
    tabGone(tabId: number): void;
    /** Settings changed: questions that were answered elsewhere end. */
    settingsChanged(settings: unknown): void;
    dispose(): void;
}

interface Waiter {
    tabId: number;
    resolve: (outcome: PromptOutcome) => void;
}

interface Entry {
    id: string;
    origin: string;
    view: PromptView;
    near: number | undefined;
    windowId: number | undefined;
    waiters: Set<Waiter>;
    /** Every tab that asked, with its top-level origin: "once" answers apply to them. */
    tabs: Map<number, string | undefined>;
    /** The tab whose budget this window is charged to: the first one that asked. */
    charge: { tabId: number; top: string | undefined };
    settled: boolean;
}

export function createPromptManager(
    host: PromptHost,
    effects: PromptEffects,
): PromptManager {
    let current: Entry | undefined;
    const queue: Entry[] = [];

    const everyEntry = () => (current ? [current, ...queue] : [...queue]);

    const settle = (entry: Entry, outcome: PromptOutcome) => {
        if (entry.settled) {
            return;
        }
        entry.settled = true;
        const index = queue.indexOf(entry);
        if (index !== -1) {
            queue.splice(index, 1);
        }
        for (const waiter of entry.waiters) {
            waiter.resolve(outcome);
        }
        entry.waiters.clear();
        const windowId = entry.windowId;
        if (current === entry) {
            current = undefined;
        }
        if (windowId !== undefined) {
            host.close(windowId).catch(() => {
                /* Already closed. */
            });
        }
        pump();
    };

    const show = async (entry: Entry) => {
        try {
            // One count per window, however many requests share it; a tab
            // that has used up its budget is not asked again this visit.
            const asked = await effects.countPrompt(
                entry.charge.tabId,
                entry.charge.top,
            );
            if (entry.settled) {
                return;
            }
            if (asked > MAX_PROMPTS_PER_TAB) {
                settle(entry, "unavailable");
                return;
            }
            const windowId = await host.open(entry.id, entry.near);
            entry.windowId = windowId;
            if (entry.settled) {
                // Answered or withdrawn while the window was opening.
                host.close(windowId).catch(() => {
                    /* Already closed. */
                });
            }
        } catch {
            settle(entry, "unavailable");
        }
    };

    function pump() {
        while (!current) {
            const next = queue.shift();
            if (!next) {
                return;
            }
            if (next.waiters.size === 0) {
                // Everyone who asked has gone; there is nobody to answer for.
                next.settled = true;
                continue;
            }
            current = next;
            void show(next);
        }
    }

    return {
        async ask(request, signal) {
            if (signal.aborted) {
                return "dismissed";
            }
            // Created synchronously, so requests that arrive together (a game
            // opens several sockets at once) all share one entry.
            let entry = everyEntry().find(
                (candidate) =>
                    !candidate.settled && candidate.origin === request.origin,
            );
            if (!entry) {
                if (queue.length >= MAX_QUEUED_PROMPTS) {
                    return "unavailable";
                }
                entry = {
                    id: crypto.randomUUID(),
                    origin: request.origin,
                    view: {
                        origin: request.origin,
                        ...(request.frameId !== 0 &&
                        request.top !== undefined &&
                        request.top !== request.origin
                            ? { embeddedIn: request.top }
                            : {}),
                    },
                    near: request.windowId,
                    windowId: undefined,
                    waiters: new Set(),
                    tabs: new Map(),
                    charge: { tabId: request.tabId, top: request.top },
                    settled: false,
                };
                queue.push(entry);
            }
            const joined = entry;
            joined.tabs.set(request.tabId, request.top);
            return new Promise<PromptOutcome>((resolve) => {
                const waiter: Waiter = {
                    tabId: request.tabId,
                    resolve: (outcome) => {
                        signal.removeEventListener("abort", withdraw);
                        resolve(outcome);
                    },
                };
                const withdraw = () => {
                    joined.waiters.delete(waiter);
                    waiter.resolve("dismissed");
                    if (
                        joined.waiters.size === 0 &&
                        queue.includes(joined) &&
                        joined !== current
                    ) {
                        // Not shown yet and nobody left to answer for.
                        settle(joined, "dismissed");
                    }
                };
                signal.addEventListener("abort", withdraw, { once: true });
                joined.waiters.add(waiter);
                pump();
            });
        },

        view(id, windowId) {
            // The window id is only known once the browser has created the
            // window; the page may ask for its text a moment before that.
            return current &&
                !current.settled &&
                current.id === id &&
                windowId !== undefined &&
                (current.windowId === undefined ||
                    current.windowId === windowId)
                ? current.view
                : undefined;
        },

        async answer(id, windowId, choice) {
            const entry = current;
            if (
                !entry ||
                entry.settled ||
                entry.id !== id ||
                windowId === undefined ||
                entry.windowId !== windowId ||
                !PROMPT_CHOICES.includes(choice)
            ) {
                return false;
            }
            try {
                if (choice === "allow-always" || choice === "deny-always") {
                    await effects.remember(
                        entry.origin,
                        choice === "allow-always" ? "allow" : "deny",
                    );
                } else {
                    const decision = choice === "allow-once" ? "allow" : "deny";
                    for (const [tabId, top] of entry.tabs) {
                        await effects.recordVisit(
                            tabId,
                            entry.origin,
                            decision,
                            top,
                        );
                    }
                }
            } catch {
                settle(entry, "unavailable");
                return false;
            }
            settle(entry, "answered");
            return true;
        },

        windowRemoved(windowId) {
            const entry = everyEntry().find(
                (candidate) => candidate.windowId === windowId,
            );
            if (!entry || entry.settled) {
                return;
            }
            // Closing the question without answering refuses for this visit.
            const done = async () => {
                try {
                    for (const [tabId, top] of entry.tabs) {
                        await effects.recordVisit(
                            tabId,
                            entry.origin,
                            "deny",
                            top,
                        );
                    }
                } catch {
                    /* The waiters are refused below either way. */
                }
                settle(entry, "dismissed");
            };
            // Stop treating the window as open before the answer is stored.
            entry.windowId = undefined;
            void done();
        },

        tabGone(tabId) {
            for (const entry of everyEntry()) {
                entry.tabs.delete(tabId);
                for (const waiter of [...entry.waiters]) {
                    if (waiter.tabId === tabId) {
                        entry.waiters.delete(waiter);
                        waiter.resolve("dismissed");
                    }
                }
                if (entry.tabs.size === 0) {
                    settle(entry, "dismissed");
                }
            }
        },

        settingsChanged(settings) {
            for (const entry of everyEntry()) {
                if (socketPermission(settings, entry.origin) !== "ask") {
                    settle(entry, "answered");
                }
            }
        },

        dispose() {
            for (const entry of everyEntry()) {
                settle(entry, "dismissed");
            }
        },
    };
}
