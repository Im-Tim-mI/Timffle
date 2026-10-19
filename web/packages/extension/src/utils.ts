import type { Options } from "./common";
import { Config } from "ruffle-core";
import { getProxySettings } from "./proxy-settings";
import {
    applyProxySettings,
    defaultProxySettings,
    PROXY_STORAGE_KEY,
} from "./socket-proxy";

const DEFAULT_OPTIONS: Required<Options> = {
    ...Config.DEFAULT_CONFIG,
    ruffleEnable: true,
    ignoreOptout: false,
    autostart: false,
    showReloadButton: false,
    swfTakeover: true,
};

// TODO: Once Chromium 148 is old enough to be the
// oldest version we want to support, remove this.
export function enableBrowserOnOutdatedChromium() {
    if (!globalThis.browser) {
        globalThis.browser = chrome;
    }
}

function promisify<T>(
    func: (callback: (result: T) => void) => void,
): Promise<T> {
    return new Promise((resolve, reject) => {
        func((result) => {
            const error = browser.runtime.lastError;
            if (error) {
                reject(error);
            } else {
                resolve(result);
            }
        });
    });
}

export const openOptionsPage: () => Promise<void> = () =>
    browser.runtime.openOptionsPage();
export const openPlayerPage: () => Promise<void> = () =>
    promisify((cb: () => void) =>
        browser.tabs.create({ url: "/player.html" }, cb),
    );
export const openOnboardPage: () => Promise<void> = () =>
    promisify((cb: () => void) =>
        browser.tabs.create({ url: "/onboard.html" }, cb),
    );
/** The page that walks through installing the socket helper. */
export const openHelperPage: () => Promise<void> = () =>
    promisify((cb: () => void) =>
        browser.tabs.create({ url: "/helper.html" }, cb),
    );

export async function getOptions(origin?: string): Promise<Options> {
    const [synced, proxySettings] = await Promise.all([
        browser.storage.sync.get(),
        // A local storage failure must not enable sockets or break normal playback.
        getProxySettings().catch(() => ({
            ...defaultProxySettings(),
            enabled: false,
        })),
    ]);
    // Never pass private settings through as arbitrary player config, even if
    // an old/manual storage edit placed this key in the wrong storage area.
    const { [PROXY_STORAGE_KEY]: _privateSettings, ...options } = synced;

    // Ruffle's own text engine has no Chinese glyphs, so device text (SimSun,
    // _sans, ...) is drawn with the browser's fonts unless the user picked a
    // renderer explicitly. This must not depend on what the user decided about
    // sockets for the website: a game that is asked about, refused, or opened
    // with sockets switched off still shows its Chinese text.
    const fonts =
        options["deviceFontRenderer"] === undefined
            ? { deviceFontRenderer: Config.DeviceFontRenderer.Canvas }
            : {};

    // Copy over default options if they don't exist yet.
    return applyProxySettings(
        { ...DEFAULT_OPTIONS, ...fonts, ...options },
        proxySettings,
        origin,
    );
}

/**
 * Gets the options that are explicitly different from the defaults.
 *
 * In the future we should just not store options we don't want to set.
 */
export async function getExplicitOptions(origin?: string): Promise<Options> {
    const options = await getOptions(origin);
    const defaultOptions = DEFAULT_OPTIONS;
    for (const key in defaultOptions) {
        // @ts-expect-error: Element implicitly has an any type
        if (key in options && defaultOptions[key] === options[key]) {
            // @ts-expect-error: Element implicitly has an any type
            // eslint-disable-next-line @typescript-eslint/no-dynamic-delete
            delete options[key];
        }
    }
    // This value is specific to the internal extension pages, and is always "default"
    if ("responseHeadersUnsupported" in options) {
        delete options["responseHeadersUnsupported"];
    }

    return options;
}

export const hasAllUrlsPermission = async () => {
    const allPermissions = await browser.permissions.getAll();
    return allPermissions.origins?.includes("<all_urls>") ?? false;
};

export async function hasHostPermissionForSpecifiedTab(
    origin: string | undefined,
) {
    try {
        return origin
            ? await browser.permissions.contains({
                  origins: [origin],
              })
            : await hasAllUrlsPermission();
    } catch {
        // catch error that occurs for special urls like about:
        return false;
    }
}

export async function hasHostPermissionForActiveTab() {
    const [activeTab] = await browser.tabs.query({
        active: true,
        currentWindow: true,
    });

    return await hasHostPermissionForSpecifiedTab(activeTab?.url);
}

export function setPageLanguage() {
    document.documentElement.lang = browser.i18n
        .getMessage("@@ui_locale")
        .replace("_", "-");
    // "rtl" for Arabic and Hebrew, "ltr" for the others.
    document.documentElement.dir = browser.i18n.getMessage("@@bidi_dir");
}
