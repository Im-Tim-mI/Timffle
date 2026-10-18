import {
    defaultProxySettings,
    DEFAULTS_VERSION,
    PROXY_STORAGE_KEY,
    upgradeLegacyDefaults,
    validateProxySettings,
} from "./socket-proxy";
import type { ProxySettings } from "./socket-proxy";

export async function getProxySettings(): Promise<ProxySettings> {
    const data = await browser.storage.local.get(PROXY_STORAGE_KEY);
    const stored: unknown = data[PROXY_STORAGE_KEY];
    if (stored === undefined) {
        // Never configured (or reset): the out-of-the-box defaults.
        return defaultProxySettings();
    }
    const result = validateProxySettings(stored);
    // Malformed data fails closed, even if storage was edited manually.
    return result.valid
        ? upgradeLegacyDefaults(result.settings)
        : { ...defaultProxySettings(), enabled: false };
}

/** Saves the settings and returns them as they are stored. */
export async function saveProxySettings(
    settings: ProxySettings,
): Promise<ProxySettings> {
    const result = validateProxySettings(settings);
    if (!result.valid) {
        throw new Error(result.error);
    }
    // What the user saves is their choice, whatever the current defaults are.
    const stored = { ...result.settings, defaultsVersion: DEFAULTS_VERSION };
    await browser.storage.local.set({ [PROXY_STORAGE_KEY]: stored });
    return stored;
}

/** Whether two settings (as `getProxySettings` returns them) are the same. */
export function sameProxySettings(a: ProxySettings, b: ProxySettings): boolean {
    const same = (x: readonly string[], y: readonly string[]) =>
        x.length === y.length && x.every((entry, i) => entry === y[i]);
    return (
        a.enabled === b.enabled &&
        a.mode === b.mode &&
        a.proxyUrl === b.proxyUrl &&
        a.defaultsVersion === b.defaultsVersion &&
        same(a.allowedOrigins, b.allowedOrigins) &&
        same(a.proxyOrigins, b.proxyOrigins) &&
        same(a.deniedOrigins, b.deniedOrigins)
    );
}

/** The settings were changed by somebody else since they were read. */
export class SettingsConflictError extends Error {
    constructor() {
        super("settings_changed");
    }
}

const SETTINGS_LOCK = "timffle-socket-settings";

/**
 * The popup, the options page and the service worker all change the settings;
 * a Web Lock (shared by all of them) keeps one read-change-write from
 * overwriting another. Without Web Locks (very old browsers) only changes made
 * from one context are ordered.
 */
function withSettingsLock<T>(task: () => Promise<T>): Promise<T> {
    const locks = (globalThis.navigator as Navigator | undefined)?.locks;
    return locks ? locks.request(SETTINGS_LOCK, task) : task();
}

let pendingUpdate: Promise<unknown> = Promise.resolve();

/**
 * Reads the settings fresh, applies `change` and saves the result. Updates
 * made through this function run one after the other, in this context and
 * (with Web Locks) across the extension's pages and service worker, so two
 * quick changes cannot overwrite each other. `change` may throw to cancel.
 */
export function updateProxySettings(
    change: (settings: ProxySettings) => ProxySettings,
): Promise<ProxySettings> {
    const run = () =>
        withSettingsLock(async () => {
            const next = change(await getProxySettings());
            return saveProxySettings(next);
        });
    const result = pendingUpdate.then(run, run);
    pendingUpdate = result.catch(() => undefined);
    return result;
}

/**
 * Saves `next` only if the settings are still `expected`, the ones it was
 * made from. A form that has been open for a while must not write its old view
 * of the lists over what the popup or a question has changed since (a website
 * that was refused there would be allowed again).
 */
export function replaceProxySettings(
    expected: ProxySettings,
    next: ProxySettings,
): Promise<ProxySettings> {
    return updateProxySettings((current) => {
        if (!sameProxySettings(current, expected)) {
            throw new SettingsConflictError();
        }
        return next;
    });
}

export async function resetProxySettings(): Promise<void> {
    await browser.storage.local.remove(PROXY_STORAGE_KEY);
}
