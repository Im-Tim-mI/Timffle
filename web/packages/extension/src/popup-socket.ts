/**
 * The popup's "Socket connections" section: what this tab's website may do,
 * and a button to allow it without typing its address anywhere.
 */
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

/** Bilingual, because the Socket section of every page is (see translate="no" in the markup). */
export function stateText(state: SiteState): string {
    if (state.kind === "off") {
        return "Socket 連線已在設定頁停用。 / Sockets are switched off in the settings.";
    }
    switch (state.permission) {
        case "allow":
            return "一律允許 / Always allowed";
        case "deny":
            return "一律拒絕 / Always denied";
        case "ask":
            if (!state.asks) {
                return "尚未允許（自訂代理模式不會詢問） / Not allowed (a custom proxy never asks)";
            }
            if (state.visit === "allow") {
                return "本次造訪已允許，關閉分頁後會再詢問 / Allowed for this visit; asks again after you close the tab";
            }
            if (state.visit === "deny") {
                return "本次造訪已拒絕，關閉分頁後會再詢問 / Denied for this visit; asks again after you close the tab";
            }
            return "每次造訪時詢問 / Ask on every visit";
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

const CHOICE_LABELS: Record<SocketChoice, string> = {
    ask: "每次造訪時詢問 / Ask on every visit",
    allow: "一律允許 / Always allow",
    deny: "一律拒絕 / Always deny",
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

    const choose = async (origin: string, choice: SocketChoice) => {
        await updateProxySettings((settings) =>
            setSocketChoice(settings, origin, choice),
        );
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
        site.append(element("p", "socket-origin", origin));
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
                primary
                    ? "允許此網站使用 Socket 連線 / Allow this site to use sockets"
                    : "允許 / Allow",
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
            element("span", "socket-choice-label", "此網站 / This site"),
        );
        const select = element("select", "socket-select");
        for (const value of ["ask", "allow", "deny"] as const) {
            const option = element("option", "", CHOICE_LABELS[value]);
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
