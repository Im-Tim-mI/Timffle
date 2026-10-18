/**
 * "Allow" and "deny" answers that last for one visit only: they belong to one
 * tab and one website, and end when the tab is closed or leaves the site. They
 * live in session storage, so a restarted service worker still remembers them
 * and a restarted browser does not.
 */
import { normalizeWebsiteOrigin } from "./socket-proxy";

export type VisitDecision = "allow" | "deny";

export interface TabVisit {
    /** The tab's top-level origin when its first answer was recorded, if known. */
    top?: string;
    /** Frame origin to this visit's answer. */
    decisions: Record<string, VisitDecision>;
    /** Prompt windows opened for this tab during this visit. */
    prompts: number;
}

/** The popup asks what was answered for this visit of its tab ... */
export const VISIT_GET_REQUEST = "socket_visit_get";
/** ... and forgets an answer when the user picks a lasting one. */
export const VISIT_FORGET_REQUEST = "socket_visit_forget";

/** A page cannot grow this without bound by embedding many frames. */
export const MAX_VISIT_ORIGINS = 16;
const KEY_PREFIX = "socketVisit:";

/** The part of `browser.storage.session` that is used. */
export interface SessionArea {
    get(keys: null): Promise<Record<string, unknown>>;
    set(items: Record<string, unknown>): Promise<void>;
    remove(keys: string | string[]): Promise<void>;
}

export interface VisitStore {
    /** True once earlier answers are loaded; until then `ready` is pending. */
    readonly hydrated: boolean;
    readonly ready: Promise<void>;
    get(tabId: number): TabVisit | undefined;
    decision(tabId: number, origin: string): VisitDecision | undefined;
    record(
        tabId: number,
        origin: string,
        decision: VisitDecision,
        top?: string,
    ): Promise<void>;
    /** Counts one more prompt window for this tab and returns the new count. */
    countPrompt(tabId: number, top?: string): Promise<number>;
    /** Forget one origin's answer, or all of the tab's answers. */
    forget(tabId: number, origin?: string): Promise<void>;
    /**
     * The tab went to `top`. Its answers are forgotten, and true is returned,
     * unless that is the site they were given on.
     */
    leftSite(tabId: number, top: string | undefined): Promise<boolean>;
}

function readVisit(value: unknown): TabVisit | undefined {
    if (typeof value !== "object" || value === null) {
        return undefined;
    }
    const raw = value as Record<string, unknown>;
    const decisionsRaw = raw["decisions"];
    const prompts = raw["prompts"];
    if (
        typeof decisionsRaw !== "object" ||
        decisionsRaw === null ||
        typeof prompts !== "number" ||
        !Number.isSafeInteger(prompts) ||
        prompts < 0
    ) {
        return undefined;
    }
    const decisions: Record<string, VisitDecision> = {};
    for (const [origin, decision] of Object.entries(decisionsRaw)) {
        if (
            normalizeWebsiteOrigin(origin) === origin &&
            (decision === "allow" || decision === "deny")
        ) {
            decisions[origin] = decision;
        }
    }
    const top = raw["top"];
    return {
        ...(typeof top === "string" && normalizeWebsiteOrigin(top) === top
            ? { top }
            : {}),
        decisions,
        prompts,
    };
}

export function createVisitStore(area: SessionArea | undefined): VisitStore {
    const visits = new Map<number, TabVisit>();
    let hydrated = area === undefined;
    const persist = async (tabId: number) => {
        const visit = visits.get(tabId);
        try {
            if (visit) {
                await area?.set({ [KEY_PREFIX + tabId]: visit });
            } else {
                await area?.remove(KEY_PREFIX + tabId);
            }
        } catch {
            /* Memory still holds the answer for this service worker's lifetime. */
        }
    };
    const ready = (async () => {
        if (!area) {
            return;
        }
        try {
            const stored = await area.get(null);
            for (const [key, value] of Object.entries(stored)) {
                const tabId = key.startsWith(KEY_PREFIX)
                    ? Number(key.slice(KEY_PREFIX.length))
                    : NaN;
                const visit = readVisit(value);
                // Answers recorded since start-up win over stored ones.
                if (
                    Number.isSafeInteger(tabId) &&
                    visit &&
                    !visits.has(tabId)
                ) {
                    visits.set(tabId, visit);
                }
            }
        } catch {
            /* Unreadable session storage means no earlier answers. */
        }
        hydrated = true;
    })();
    const entry = (tabId: number, top?: string): TabVisit => {
        let visit = visits.get(tabId);
        if (!visit) {
            visit = {
                ...(top === undefined ? {} : { top }),
                decisions: {},
                prompts: 0,
            };
            visits.set(tabId, visit);
        } else if (visit.top === undefined && top !== undefined) {
            visit.top = top;
        }
        return visit;
    };
    return {
        get hydrated() {
            return hydrated;
        },
        ready,
        get: (tabId) => visits.get(tabId),
        decision: (tabId, origin) => visits.get(tabId)?.decisions[origin],
        async record(tabId, origin, decision, top) {
            await ready;
            const visit = entry(tabId, top);
            if (
                !(origin in visit.decisions) &&
                Object.keys(visit.decisions).length >= MAX_VISIT_ORIGINS
            ) {
                return;
            }
            visit.decisions[origin] = decision;
            await persist(tabId);
        },
        async countPrompt(tabId, top) {
            await ready;
            const visit = entry(tabId, top);
            visit.prompts++;
            await persist(tabId);
            return visit.prompts;
        },
        async forget(tabId, origin) {
            await ready;
            const visit = visits.get(tabId);
            if (!visit) {
                return;
            }
            if (origin === undefined) {
                visits.delete(tabId);
            } else {
                visit.decisions = Object.fromEntries(
                    Object.entries(visit.decisions).filter(
                        ([known]) => known !== origin,
                    ),
                );
            }
            await persist(tabId);
        },
        async leftSite(tabId, top) {
            await ready;
            const visit = visits.get(tabId);
            if (!visit || (visit.top !== undefined && visit.top === top)) {
                return false;
            }
            visits.delete(tabId);
            await persist(tabId);
            return true;
        },
    };
}
