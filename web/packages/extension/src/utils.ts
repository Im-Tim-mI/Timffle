import type { Options } from "./common";
import { Config } from "ruffle-core";
import { getProxySettings } from "./proxy-settings";
import {
    applyProxySettings,
    defaultProxySettings,
    PROXY_STORAGE_KEY,
} from "./socket-proxy";
import type { ProxySettings } from "./socket-proxy";
import { explicitOptionsFrom } from "./startup-options";

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

/**
 * One read of each storage area: the options for `origin`, and the socket
 * settings they were derived from (nothing when they could not be read), for
 * the content script, which needs both before the page may load.
 */
export async function loadOptions(
    origin?: string,
): Promise<{ options: Options; proxySettings: ProxySettings | undefined }> {
    const [synced, proxySettings] = await Promise.all([
        browser.storage.sync.get(),
        getProxySettings().catch(() => undefined),
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
    return {
        options: applyProxySettings(
            { ...DEFAULT_OPTIONS, ...fonts, ...options },
            // A local storage failure must not enable sockets or break normal playback.
            proxySettings ?? { ...defaultProxySettings(), enabled: false },
            origin,
        ),
        proxySettings,
    };
}

export async function getOptions(origin?: string): Promise<Options> {
    return (await loadOptions(origin)).options;
}

/** The options that are explicitly different from the defaults; a copy. */
export function explicitOptions(options: Options): Options {
    return explicitOptionsFrom(options, DEFAULT_OPTIONS);
}

/**
 * Gets the options that are explicitly different from the defaults.
 */
export async function getExplicitOptions(origin?: string): Promise<Options> {
    return explicitOptions(await getOptions(origin));
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
