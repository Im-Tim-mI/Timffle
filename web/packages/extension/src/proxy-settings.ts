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

export async function saveProxySettings(
    settings: ProxySettings,
): Promise<void> {
    const result = validateProxySettings(settings);
    if (!result.valid) {
        throw new Error(result.error);
    }
    // What the user saves is their choice, whatever the current defaults are.
    await browser.storage.local.set({
        [PROXY_STORAGE_KEY]: {
            ...result.settings,
            defaultsVersion: DEFAULTS_VERSION,
        },
    });
}

let pendingUpdate: Promise<unknown> = Promise.resolve();

/**
 * Reads the settings fresh, applies `change` and saves the result. Updates
 * made through this function in one context run one after the other, so two
 * quick answers cannot overwrite each other.
 */
export function updateProxySettings(
    change: (settings: ProxySettings) => ProxySettings,
): Promise<ProxySettings> {
    const run = async () => {
        const next = change(await getProxySettings());
        await saveProxySettings(next);
        return next;
    };
    const result = pendingUpdate.then(run, run);
    pendingUpdate = result.catch(() => undefined);
    return result;
}

export async function resetProxySettings(): Promise<void> {
    await browser.storage.local.remove(PROXY_STORAGE_KEY);
}
