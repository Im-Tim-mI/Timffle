import type { Config } from "ruffle-core";

/** Kept separate from synced player options, including the URL's token. */
export const PROXY_STORAGE_KEY = "socketProxySettings";

/**
 * "helper": the native socket helper, which Chrome starts on demand.
 * "websocket": a WebSocket-to-TCP proxy at proxyUrl, run by the user.
 */
export type ProxyMode = "helper" | "websocket";

export interface ProxySettings {
    enabled: boolean;
    mode: ProxyMode;
    proxyUrl: string;
    /** 「一律允許」: websites that may use sockets without being asked. */
    allowedOrigins: string[];
    /**
     * 「一律拒絕」: websites that never get sockets and are never asked about.
     * Settings saved before the first-use prompt existed have none.
     */
    deniedOrigins: string[];
    /**
     * `DEFAULTS_VERSION` at the time these settings were saved. Absent in
     * settings saved before the default site list grew.
     */
    defaultsVersion?: number;
}

/**
 * Sites that may use sockets out of the box: Taomee Taiwan's 摩爾莊園 (mole),
 * 賽爾號 (seer), 小花仙 (hua) and 彈彈堂 (ddt), each over HTTP and HTTPS.
 */
export const DEFAULT_ALLOWED_ORIGINS = [
    "https://mole.61.com.tw",
    "http://mole.61.com.tw",
    "https://seer.61.com.tw",
    "http://seer.61.com.tw",
    "https://hua.61.com.tw",
    "http://hua.61.com.tw",
    "https://ddt.61.com.tw",
    "http://ddt.61.com.tw",
];

/** Bumped whenever `DEFAULT_ALLOWED_ORIGINS` gains sites. */
export const DEFAULTS_VERSION = 2;

/**
 * Default site lists of earlier releases. A saved list that is still exactly
 * one of them (and was saved before `defaultsVersion` existed) was never
 * edited by the user, so it follows the new defaults.
 */
const LEGACY_DEFAULT_ORIGINS: readonly (readonly string[])[] = [
    ["https://mole.61.com.tw", "http://mole.61.com.tw"],
];

/**
 * Brings never-edited settings from an older release up to the current
 * default site list. Anything the user chose (a different list, or any
 * settings saved by this release or later) is returned unchanged, so an
 * explicit Mole-only list stays Mole-only once it is saved again.
 */
export function upgradeLegacyDefaults(settings: ProxySettings): ProxySettings {
    if ((settings.defaultsVersion ?? 0) >= DEFAULTS_VERSION) {
        return settings;
    }
    const saved = new Set(settings.allowedOrigins);
    const untouched = LEGACY_DEFAULT_ORIGINS.some(
        (legacy) =>
            legacy.length === saved.size &&
            legacy.every((origin) => saved.has(origin)),
    );
    return untouched
        ? {
              ...settings,
              allowedOrigins: [...DEFAULT_ALLOWED_ORIGINS],
              defaultsVersion: DEFAULTS_VERSION,
          }
        : settings;
}

/**
 * Never resolvable (reserved .invalid TLD). The page bridge intercepts this
 * URL before any network access and forwards the socket to the helper.
 */
export const HELPER_SOCKET_HOST = "timffle-socket.invalid";
export const HELPER_PROXY_URL = `ws://${HELPER_SOCKET_HOST}/connect?host={host}&port={port}`;

export type ProxyValidationError =
    | "invalid_settings"
    | "url_required"
    | "invalid_url"
    | "missing_placeholders"
    | "credentials"
    | "fragment"
    | "dynamic_endpoint"
    | "invalid_origin"
    | "origins_required";

/** What the user decided for one website; "ask" is the absence of a decision. */
export type SocketChoice = "allow" | "deny" | "ask";

/**
 * How a page's sockets are treated: "off" when sockets are disabled (or the
 * page has no website origin), otherwise the user's choice for its origin.
 */
export type SocketPermission = SocketChoice | "off";

export type ProxyValidationResult =
    | { valid: true; settings: ProxySettings }
    | { valid: false; error: ProxyValidationError };

export function defaultProxySettings(): ProxySettings {
    return {
        enabled: true,
        mode: "helper",
        proxyUrl: "",
        allowedOrigins: [...DEFAULT_ALLOWED_ORIGINS],
        deniedOrigins: [],
        defaultsVersion: DEFAULTS_VERSION,
    };
}

/** Accept only an HTTP(S) origin, not a URL path or a match pattern. */
export function normalizeWebsiteOrigin(value: string): string | undefined {
    if (!/^https?:\/\/[^/?#\s\\]+\/?$/iu.test(value)) {
        return undefined;
    }
    try {
        const url = new URL(value);
        if (
            url.username ||
            url.password ||
            value.includes("@") ||
            url.hostname.includes("*")
        ) {
            return undefined;
        }
        return url.origin;
    } catch {
        return undefined;
    }
}

/** Errors are codes only: never include a potentially secret URL in an error. */
export function validateProxySettings(value: unknown): ProxyValidationResult {
    if (
        !value ||
        typeof value !== "object" ||
        !("enabled" in value) ||
        typeof value.enabled !== "boolean" ||
        !("proxyUrl" in value) ||
        typeof value.proxyUrl !== "string" ||
        !("allowedOrigins" in value) ||
        !Array.isArray(value.allowedOrigins) ||
        !value.allowedOrigins.every((origin) => typeof origin === "string") ||
        // Absent in settings saved before the first-use prompt existed.
        ("deniedOrigins" in value &&
            value.deniedOrigins !== undefined &&
            (!Array.isArray(value.deniedOrigins) ||
                !value.deniedOrigins.every(
                    (origin) => typeof origin === "string",
                )))
    ) {
        return { valid: false, error: "invalid_settings" };
    }

    const proxyUrl = value.proxyUrl.trim();
    let mode: ProxyMode;
    if (!("mode" in value) || value.mode === undefined) {
        // Settings saved before the helper existed only had the WebSocket proxy.
        mode = proxyUrl ? "websocket" : "helper";
    } else if (value.mode === "helper" || value.mode === "websocket") {
        mode = value.mode;
    } else {
        return { valid: false, error: "invalid_settings" };
    }
    if (!proxyUrl && value.enabled && mode === "websocket") {
        return { valid: false, error: "url_required" };
    }
    if (proxyUrl) {
        if (!proxyUrl.includes("{host}") || !proxyUrl.includes("{port}")) {
            return { valid: false, error: "missing_placeholders" };
        }
        // Resolve only in the path/query. The companion's endpoint must stay
        // fixed, rather than sending its token to a host supplied by a SWF.
        const authority = /^wss?:\/\/([^/?#]+)/iu.exec(proxyUrl)?.[1];
        if (!authority || /[\s\\]/u.test(proxyUrl)) {
            return { valid: false, error: "invalid_url" };
        }
        if (authority.includes("{") || authority.includes("}")) {
            return { valid: false, error: "dynamic_endpoint" };
        }
        if (authority.includes("@")) {
            return { valid: false, error: "credentials" };
        }
        if (proxyUrl.includes("#")) {
            return { valid: false, error: "fragment" };
        }
        const resolved = proxyUrl
            .replaceAll("{host}", "example.invalid")
            .replaceAll("{port}", "1234");
        if (/[{}]/u.test(resolved)) {
            return { valid: false, error: "invalid_url" };
        }
        try {
            const url = new URL(resolved);
            if (
                !["ws:", "wss:"].includes(url.protocol) ||
                !url.hostname ||
                url.hostname.includes("*")
            ) {
                return { valid: false, error: "invalid_url" };
            }
            if (url.username || url.password) {
                return { valid: false, error: "credentials" };
            }
        } catch {
            return { valid: false, error: "invalid_url" };
        }
    }

    const allowedOrigins = normalizeOriginList(value.allowedOrigins);
    const deniedOrigins = normalizeOriginList(
        "deniedOrigins" in value && Array.isArray(value.deniedOrigins)
            ? value.deniedOrigins
            : [],
    );
    if (!allowedOrigins || !deniedOrigins) {
        return { valid: false, error: "invalid_origin" };
    }
    // A website cannot be both: refusing wins, whichever list was edited last.
    for (const origin of deniedOrigins) {
        allowedOrigins.delete(origin);
    }
    // Helper mode asks about unlisted websites, so an empty list is fine there;
    // a custom proxy has no prompt and is useless without an allowed website.
    if (value.enabled && mode === "websocket" && allowedOrigins.size === 0) {
        return { valid: false, error: "origins_required" };
    }

    // Anything but a positive integer counts as "saved before versioning".
    const defaultsVersion =
        "defaultsVersion" in value &&
        typeof value.defaultsVersion === "number" &&
        Number.isSafeInteger(value.defaultsVersion) &&
        value.defaultsVersion > 0
            ? value.defaultsVersion
            : undefined;

    return {
        valid: true,
        settings: {
            enabled: value.enabled,
            mode,
            proxyUrl,
            allowedOrigins: Array.from(allowedOrigins),
            deniedOrigins: Array.from(deniedOrigins),
            ...(defaultsVersion === undefined ? {} : { defaultsVersion }),
        },
    };
}

/** Trimmed, normalized and de-duplicated; undefined if any entry is not an origin. */
function normalizeOriginList(lines: unknown[]): Set<string> | undefined {
    const origins = new Set<string>();
    for (const line of lines) {
        const input = (line as string).trim();
        if (!input) {
            continue;
        }
        const origin = normalizeWebsiteOrigin(input);
        if (!origin) {
            return undefined;
        }
        origins.add(origin);
    }
    return origins;
}

/**
 * What the user decided for the site at this origin. No origin (extension
 * pages, local files, opaque origins) or disabled/invalid settings is "off":
 * never an opt-in, and never a question either.
 */
export function socketPermission(
    settings: unknown,
    origin?: string,
): SocketPermission {
    const validation = validateProxySettings(settings);
    const websiteOrigin = origin ? normalizeWebsiteOrigin(origin) : undefined;
    if (!validation.valid || !validation.settings.enabled || !websiteOrigin) {
        return "off";
    }
    const { allowedOrigins, deniedOrigins } = validation.settings;
    if (deniedOrigins.includes(websiteOrigin)) {
        return "deny";
    }
    return allowedOrigins.includes(websiteOrigin) ? "allow" : "ask";
}

/**
 * Whether an unlisted website is asked about (helper mode) or simply refused
 * (a custom WebSocket proxy has no prompt: its token must never reach a page
 * that nobody has approved).
 */
export function promptsForUnlisted(settings: unknown): boolean {
    const validation = validateProxySettings(settings);
    return (
        validation.valid &&
        validation.settings.enabled &&
        validation.settings.mode === "helper"
    );
}

/**
 * Settings after the user chose "allow", "deny" or "ask" (forget) for a
 * website; the other list never keeps the origin.
 */
export function setSocketChoice(
    settings: ProxySettings,
    origin: string,
    choice: SocketChoice,
): ProxySettings {
    const websiteOrigin = normalizeWebsiteOrigin(origin);
    if (!websiteOrigin) {
        throw new Error("invalid_origin");
    }
    const without = (list: string[]) =>
        list.filter((entry) => entry !== websiteOrigin);
    return {
        ...settings,
        allowedOrigins:
            choice === "allow"
                ? [...without(settings.allowedOrigins), websiteOrigin]
                : without(settings.allowedOrigins),
        deniedOrigins:
            choice === "deny"
                ? [...without(settings.deniedOrigins), websiteOrigin]
                : without(settings.deniedOrigins),
    };
}

/**
 * How the site at this origin reaches TCP, if it is allowed to without being
 * asked. No origin means no opt-in (in particular, extension pages and local
 * files).
 */
export function resolveSocketAccess(
    settings: unknown,
    origin?: string,
): { mode: ProxyMode; proxyUrl: string } | undefined {
    const validation = validateProxySettings(settings);
    if (
        !validation.valid ||
        socketPermission(validation.settings, origin) !== "allow"
    ) {
        return undefined;
    }
    const { mode, proxyUrl } = validation.settings;
    return { mode, proxyUrl: mode === "helper" ? HELPER_PROXY_URL : proxyUrl };
}

/**
 * The Ruffle socket proxy list for a website that is asked before it may use
 * sockets: the helper URL (it holds no secret), so that a connection attempt
 * reaches the permission check. Unlisted websites never get a custom proxy.
 */
export function askSocketProxies(
    settings: unknown,
    origin?: string,
): Config.SocketProxy[] {
    return socketPermission(settings, origin) === "ask" &&
        promptsForUnlisted(settings)
        ? [{ host: "*", port: 0, proxyUrl: HELPER_PROXY_URL }]
        : [];
}

/** Preserve preferred exact mappings before any wildcard fallback. */
export function mergeSocketProxies(
    preferred: readonly Config.SocketProxy[] = [],
    fallback: readonly Config.SocketProxy[] = [],
): Config.SocketProxy[] {
    const isWildcard = (proxy: Config.SocketProxy) =>
        proxy.host === "*" || proxy.port === 0;
    return [...preferred, ...fallback].sort(
        (a, b) => Number(isWildcard(a)) - Number(isWildcard(b)),
    );
}

export function applyProxySettings<T extends Config.BaseLoadOptions>(
    options: T,
    settings: unknown,
    origin?: string,
): T {
    const access = resolveSocketAccess(settings, origin);
    if (!access) {
        return options;
    }
    return {
        ...options,
        socketProxy: mergeSocketProxies(options.socketProxy, [
            { host: "*", port: 0, proxyUrl: access.proxyUrl },
        ]),
    };
}
