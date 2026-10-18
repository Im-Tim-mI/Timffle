/**
 * The popup's "Socket connections" section: what this tab's website may do,
 * and a button to allow it without typing its address anywhere.
 */
import { text } from "./i18n";
import { getProxySettings, updateProxySettings } from "./proxy-settings";
import {
    normalizeWebsiteOrigin,
    promptsForUnlisted,
    setSocketChoice,
    socketPermission,
} from "./socket-proxy";
import type { ProxySettings, SocketChoice } from "./socket-proxy";
import { VISIT_FORGET_REQUEST, VISIT_GET_REQUEST } from "./socket-visit";
import type { VisitDecision } from "./socket-visit";

export type SiteState =
    | { kind: "off" }
    | {
          kind: "site";
          permission: SocketChoice;
          /** The answer for this visit of the tab, which only counts while the permission is "ask". */
          visit: VisitDecision | undefined;
          /** Whether a website with no answer is asked (helper mode) or just refused. */
          asks: boolean;
      };

export function describeSite(
    settings: ProxySettings,
    origin: string,
    visit?: VisitDecision,
): SiteState {
    const permission = socketPermission(settings, origin);
    if (permission === "off") {
        return { kind: "off" };
    }
    return {
        kind: "site",
        permission,
        visit: permission === "ask" ? visit : undefined,
        asks: promptsForUnlisted(settings),
    };
}

/** What the section says about a website, in the language of the browser. */
export function stateText(state: SiteState): string {
    if (state.kind === "off") {
        return text("timffle_popup_off");
    }
    switch (state.permission) {
        case "allow":
            return text("timffle_popup_always_allowed");
        case "deny":
            return text("timffle_popup_always_denied");
        case "ask":
            if (!state.asks) {
                return text("timffle_popup_proxy_not_allowed");
            }
            if (state.visit === "allow") {
                return text("timffle_popup_visit_allowed");
            }
            if (state.visit === "deny") {
                return text("timffle_popup_visit_denied");
            }
            return text("timffle_choice_ask");
    }
}

interface VisitInfo {
    decisions: Record<string, VisitDecision>;
}

async function queryVisit(tabId: number | undefined): Promise<VisitInfo> {
    if (tabId === undefined) {
        return { decisions: {} };
    }
    try {
        const reply: unknown = await browser.runtime.sendMessage({
            type: VISIT_GET_REQUEST,
            tabId,
        });
        if (typeof reply === "object" && reply !== null) {
            const decisions = (reply as { decisions?: unknown }).decisions;
            if (typeof decisions === "object" && decisions !== null) {
                return {
                    decisions: decisions as Record<string, VisitDecision>,
                };
            }
        }
    } catch {
        /* The background is not reachable: no answers to show. */
    }
    return { decisions: {} };
}

async function forgetVisit(
    tabId: number | undefined,
    origin: string,
): Promise<void> {
    if (tabId === undefined) {
        return;
    }
    try {
        await browser.runtime.sendMessage({
            type: VISIT_FORGET_REQUEST,
            tabId,
            origin,
        });
    } catch {
        /* Nothing was remembered, or the background is gone. */
    }
}

/** The origin of the tab's address, if it is a website. */
export function tabWebsiteOrigin(url: string | undefined): string | undefined {
    if (!url) {
        return undefined;
    }
    try {
        return normalizeWebsiteOrigin(new URL(url).origin);
    } catch {
        return undefined;
    }
}

function element<K extends keyof HTMLElementTagNameMap>(
    tag: K,
    className: string,
    text?: string,
): HTMLElementTagNameMap[K] {
    const node = document.createElement(tag);
    node.className = className;
    if (text !== undefined) {
        node.textContent = text;
    }
    return node;
}

const CHOICE_KEYS: Record<SocketChoice, string> = {
    ask: "timffle_choice_ask",
    allow: "timffle_choice_allow",
    deny: "timffle_choice_deny",
};

export interface SocketSectionOptions {
    tab: chrome.tabs.Tab | undefined;
    /** Used when the browser does not tell the tab's address. */
    fallbackOrigin: string | undefined;
    /** Called after the user changed something. */
    onChange?: () => void;
}

/**
 * Fills #socket-container. Does nothing for pages that are not websites, and
 * when this page is framed by a website: a web page can frame the popup (all
 * extension pages are web accessible), and must not be able to make the
 * visitor click "allow" on it.
 */
export async function bindSocketSection({
    tab,
    fallbackOrigin,
    onChange,
}: SocketSectionOptions): Promise<void> {
    const container = document.getElementById("socket-container");
    const list = document.getElementById("socket-sites");
    if (!container || !list || window.top !== window) {
        return;
    }
    const topSite =
        tabWebsiteOrigin(tab?.url) ??
        (fallbackOrigin ? normalizeWebsiteOrigin(fallbackOrigin) : undefined);
    if (!topSite) {
        return;
    }
    const tabId = tab?.id;
    /** Shown once, above the sites, after a choice that could not be kept. */
    let problem: string | undefined;

    const choose = async (origin: string, choice: SocketChoice) => {
        try {
            await updateProxySettings((settings) =>
                setSocketChoice(settings, origin, choice),
            );
        } catch (error) {
            // The list shows what is really stored again, with the reason.
            problem = text(
                error instanceof Error && error.message === "origins_required"
                    ? "timffle_popup_origins_required"
                    : "timffle_popup_save_failed",
            );
            await render();
            return;
        }
        // A lasting choice replaces the answer for this visit.
        await forgetVisit(tabId, origin);
        await render();
        onChange?.();
    };

    const renderSite = (
        origin: string,
        settings: ProxySettings,
        visit: VisitDecision | undefined,
        primary: boolean,
    ): HTMLElement => {
        const state = describeSite(settings, origin, visit);
        const site = element("section", "socket-site");
        const name = element("p", "socket-origin", origin);
        // An address reads left to right in every language.
        name.dir = "ltr";
        site.append(name);
        const status = element("p", "socket-state", stateText(state));
        status.setAttribute("role", "status");
        site.append(status);
        if (state.kind === "off") {
            return site;
        }
        if (state.permission !== "allow") {
            const allow = element(
                "button",
                "socket-allow",
                !primary
                    ? text("timffle_allow")
                    : state.asks
                      ? text("timffle_popup_allow_site")
                      : // A custom proxy hands its token to every website it allows.
                        text("timffle_popup_allow_site_proxy"),
            );
            allow.type = "button";
            allow.addEventListener("click", (event) => {
                if (event.isTrusted) {
                    void choose(origin, "allow");
                }
            });
            site.append(allow);
        }
        const label = element("label", "socket-choice");
        label.append(
            element(
                "span",
                "socket-choice-label",
                text("timffle_popup_this_site"),
            ),
        );
        const select = element("select", "socket-select");
        for (const value of ["ask", "allow", "deny"] as const) {
            const option = element("option", "", text(CHOICE_KEYS[value]));
            option.value = value;
            option.selected = value === state.permission;
            select.append(option);
        }
        select.addEventListener("change", (event) => {
            const value = select.value;
            if (
                event.isTrusted &&
                (value === "ask" || value === "allow" || value === "deny")
            ) {
                void choose(origin, value);
            }
        });
        label.append(select);
        site.append(label);
        return site;
    };

    const render = async () => {
        let settings: ProxySettings;
        try {
            settings = await getProxySettings();
        } catch {
            container.classList.add("hidden");
            return;
        }
        const visit = await queryVisit(tabId);
        list.replaceChildren();
        if (problem !== undefined) {
            const notice = element("p", "socket-error", problem);
            notice.setAttribute("role", "alert");
            list.append(notice);
            problem = undefined;
        }
        list.append(
            renderSite(topSite, settings, visit.decisions[topSite], true),
        );
        // Frames of other websites in this tab that were asked about.
        for (const origin of Object.keys(visit.decisions)) {
            if (origin !== topSite && normalizeWebsiteOrigin(origin)) {
                list.append(
                    renderSite(
                        origin,
                        settings,
                        visit.decisions[origin],
                        false,
                    ),
                );
            }
        }
        container.classList.remove("hidden");
    };

    await render();
}
