/**
 * Timffle: Flash Player's cross-domain policy where the browser enforces CORS.
 *
 * A movie may read data from another host when that host's `crossdomain.xml`
 * names the movie's domain. The browser knows nothing of that file and refuses
 * the cross-origin response unless the host sends CORS headers, which the Flash
 * era's servers do not. When Ruffle's fetch is refused, the page asks here (via
 * the content script); the background reads the host's policy file and, when
 * it allows the asking page, adds a session rule that supplies the CORS headers
 * for that page–host pair only. Ruffle then repeats the request. Nothing is
 * lifted that Flash Player would not have granted the same page.
 */

export interface PolicyEntry {
    /** Domain pattern of `allow-access-from`: `*`, `*.example.com` or a host. */
    domain: string;
    /** Only pages served over HTTPS may use it. */
    secure: boolean;
}

export interface Policy {
    /** `site-control permitted-cross-domain-policies="none"` forbids everything. */
    permitted: boolean;
    entries: PolicyEntry[];
}

/** Parse a master policy file (regular expressions: service workers have no DOMParser). */
export function parsePolicy(xml: string, policyIsHttps: boolean): Policy {
    const entries: PolicyEntry[] = [];
    let permitted = true;
    const siteControl = /<site-control\b[^>]*permitted-cross-domain-policies\s*=\s*"([^"]*)"/iu.exec(xml);
    if (siteControl && siteControl[1]!.trim().toLowerCase() === "none") {
        permitted = false;
    }
    const tag = /<allow-access-from\b([^>]*)>/giu;
    let match: RegExpExecArray | null;
    while ((match = tag.exec(xml)) !== null) {
        const attributes = match[1]!;
        const domain = /\bdomain\s*=\s*"([^"]*)"/iu.exec(attributes);
        if (!domain) {
            continue;
        }
        const secureAttribute = /\bsecure\s*=\s*"([^"]*)"/iu.exec(attributes);
        // Over HTTPS a policy is secure unless it says otherwise; over HTTP
        // the attribute means nothing.
        const secure = policyIsHttps
            ? secureAttribute?.[1]!.trim().toLowerCase() !== "false"
            : false;
        entries.push({ domain: domain[1]!.trim().toLowerCase(), secure });
    }
    return { permitted, entries };
}

/** Whether a pattern of `allow-access-from` covers `host` (`*.example.com` also covers `example.com`). */
export function domainMatches(pattern: string, host: string): boolean {
    const wanted = host.toLowerCase();
    if (pattern === "*") {
        return wanted.length > 0;
    }
    if (pattern.startsWith("*.")) {
        const suffix = pattern.slice(2);
        return wanted === suffix || wanted.endsWith("." + suffix);
    }
    return pattern === wanted;
}

/** Whether a page at `requester` may read the host that published `policy`. */
export function policyAllows(
    policy: Policy,
    requester: { host: string; https: boolean },
): boolean {
    if (!policy.permitted) {
        return false;
    }
    return policy.entries.some(
        (entry) =>
            (!entry.secure || requester.https) &&
            domainMatches(entry.domain, requester.host),
    );
}

const MAX_POLICY_BYTES = 256 * 1024;
const RULE_ID_BASE = 60000;
const RULE_ID_LIMIT = 65000;

const policies = new Map<string, Promise<Policy | null>>();
/** `pageHost|targetHost` -> session rule id. */
let rules: Map<string, number> | undefined;

async function fetchPolicy(targetOrigin: string): Promise<Policy | null> {
    const url = targetOrigin + "/crossdomain.xml";
    try {
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 15000);
        const response = await fetch(url, {
            credentials: "omit",
            redirect: "follow",
            signal: controller.signal,
        });
        clearTimeout(timer);
        if (!response.ok) {
            return null;
        }
        const length = Number(response.headers.get("content-length") ?? 0);
        if (length > MAX_POLICY_BYTES) {
            return null;
        }
        const text = await response.text();
        if (text.length > MAX_POLICY_BYTES) {
            return null;
        }
        // A policy that moved to another host speaks for that host, not this one.
        if (new URL(response.url).origin !== targetOrigin) {
            return null;
        }
        return parsePolicy(text, targetOrigin.startsWith("https:"));
    } catch {
        return null;
    }
}

function policyFor(targetOrigin: string): Promise<Policy | null> {
    let pending = policies.get(targetOrigin);
    if (!pending) {
        pending = fetchPolicy(targetOrigin);
        policies.set(targetOrigin, pending);
        // Keep failures only briefly: the host may just have been down.
        pending.then((policy) => {
            if (policy === null) {
                setTimeout(() => policies.delete(targetOrigin), 60000);
            }
        });
    }
    return pending;
}

async function loadRules(): Promise<Map<string, number>> {
    if (rules) {
        return rules;
    }
    const map = new Map<string, number>();
    try {
        for (const rule of await browser.declarativeNetRequest.getSessionRules()) {
            const page = rule.condition.initiatorDomains?.[0];
            const target = rule.condition.requestDomains?.[0];
            if (rule.id >= RULE_ID_BASE && rule.id < RULE_ID_LIMIT && page && target) {
                map.set(`${page}|${target}`, rule.id);
            }
        }
    } catch {
        // No session rules yet (or no support): start empty.
    }
    rules = map;
    return map;
}

/** A page's origin (`scheme://host[:port]`) from what the browser tells us about the sender. */
export function senderOrigin(sender: {
    origin?: string | undefined;
    url?: string | undefined;
}): string | null {
    const candidate = sender.origin ?? (sender.url ? new URL(sender.url).origin : null);
    if (!candidate || candidate === "null") {
        return null;
    }
    try {
        const url = new URL(candidate);
        return url.protocol === "http:" || url.protocol === "https:" ? url.origin : null;
    } catch {
        return null;
    }
}

/**
 * Whether `pageOrigin` may read `targetOrigin` by Flash's rules. When it may,
 * the CORS headers for that pair are supplied from now on and `true` is
 * returned, so the caller can repeat the request it was refused.
 */
export async function allowCrossDomain(
    pageOrigin: string,
    targetOrigin: string,
): Promise<boolean> {
    let page: URL;
    let target: URL;
    try {
        page = new URL(pageOrigin);
        target = new URL(targetOrigin);
    } catch {
        return false;
    }
    const web = (url: URL) => url.protocol === "http:" || url.protocol === "https:";
    if (!web(page) || !web(target) || page.origin === target.origin) {
        return false;
    }
    const key = `${page.hostname}|${target.hostname}`;
    const existing = await loadRules();
    if (existing.has(key)) {
        return true;
    }
    const policy = await policyFor(target.origin);
    if (!policy || !policyAllows(policy, { host: page.hostname, https: page.protocol === "https:" })) {
        return false;
    }
    const used = new Set(existing.values());
    let id = RULE_ID_BASE;
    while (used.has(id)) {
        id++;
    }
    if (id >= RULE_ID_LIMIT) {
        return false;
    }
    const dnr = browser.declarativeNetRequest;
    try {
        await dnr.updateSessionRules({
            addRules: [
                {
                    id,
                    priority: 1,
                    action: {
                        type: dnr.RuleActionType?.MODIFY_HEADERS ?? "modifyHeaders",
                        responseHeaders: [
                            {
                                header: "Access-Control-Allow-Origin",
                                operation: dnr.HeaderOperation?.SET ?? "set",
                                value: page.origin,
                            },
                            {
                                header: "Access-Control-Allow-Credentials",
                                operation: dnr.HeaderOperation?.SET ?? "set",
                                value: "true",
                            },
                        ],
                    },
                    condition: {
                        initiatorDomains: [page.hostname],
                        requestDomains: [target.hostname],
                        resourceTypes: [
                            dnr.ResourceType?.XMLHTTPREQUEST ?? "xmlhttprequest",
                            dnr.ResourceType?.OTHER ?? "other",
                        ],
                    },
                } as chrome.declarativeNetRequest.Rule,
            ],
        });
    } catch {
        return false;
    }
    existing.set(key, id);
    return true;
}
