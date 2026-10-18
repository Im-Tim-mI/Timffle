/**
 *
 * This code provides a content script message listener that proxies messages
 * into/from the main world.
 *
 * On older Firefox, it also pierces the extension sandbox by copying our code into the main world
 *
 */

import {
    enableBrowserOnOutdatedChromium,
    getOptions,
    getExplicitOptions,
} from "./utils";
import { isMessage } from "./messages";
import { getProxySettings } from "./proxy-settings";
import {
    askSocketProxies,
    mergeSocketProxies,
    resolveSocketAccess,
} from "./socket-proxy";
import { startContentSocketBridge } from "./socket-bridge-content";

declare global {
    interface Navigator {
        // Only supported in Firefox, see https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Sharing_objects_with_page_scripts#accessing_page_script_objects_from_content_scripts
        wrappedJSObject?: Navigator;
    }
}

const pendingMessages: ({
    resolve(value: unknown): void;
    reject(reason?: unknown): void;
} | null)[] = [];

const ID = Math.floor(Math.random() * 100000000000);

/**
 * Send a message to the main world, where Ruffle runs.
 * @param {*} data - JSON-serializable data to send to main world.
 * @returns {Promise<*>} JSON-serializable response from main world.
 */
function sendMessageToPage(data: unknown): Promise<unknown> {
    const message = {
        to: "ruffle_page",
        index: pendingMessages.length,
        id: ID,
        data,
    };
    window.postMessage(message, "*");
    return new Promise((resolve, reject) => {
        pendingMessages.push({ resolve, reject });
    });
}

/**
 * Inject a raw script to the main world.
 * @param {string} src - Script to inject.
 */
function injectScriptRaw(src: string) {
    const script = document.createElement("script");
    script.textContent = src;
    (document.head || document.documentElement).append(script);
    script.remove();
}

/**
 * Inject a script by URL to the main world.
 * @param {string} url - Script URL to inject.
 */
function injectScriptURL(url: string): Promise<void> {
    const script = document.createElement("script");
    const promise = new Promise<void>((resolve, reject) => {
        script.addEventListener("load", function () {
            resolve();
            this.remove();
        });
        script.addEventListener("error", (e) => reject(e));
    });
    script.charset = "utf-8";
    script.src = url;
    (document.head || document.documentElement).append(script);
    return promise;
}

/**
 * Check whether the current page (or one of its ancestors) is configured
 * to opt-out from Ruffle.
 * @returns {boolean} Whether the current page opts-out or not.
 */
function checkPageOptout(): boolean {
    if (document.documentElement.hasAttribute("data-ruffle-optout")) {
        return true;
    }
    try {
        if (
            window.top &&
            window.top.document &&
            window.top.document.documentElement &&
            window.top.document.documentElement.hasAttribute(
                "data-ruffle-optout",
            )
        ) {
            // In case the opting-out page uses iframes.
            return true;
        }
    } catch (e) {
        const message = e instanceof Error ? e.message : String(e);
        console.warn(`Unable to check top-level optout: ${message}`);
    }
    return false;
}

/**
 * @returns {boolean} Whether the current page is an XML document or not.
 */
function isXMLDocument(): boolean {
    // Based on https://developer.mozilla.org/en-US/docs/Web/API/Document/xmlVersion
    return document.createElement("foo").tagName !== "FOO";
}

(async () => {
    enableBrowserOnOutdatedChromium();
    await browser.storage.sync.set({
        ["showReloadButton"]: false,
    });
    // Use this frame's origin, never a requested SWF URL or the top-level site.
    const origin = window.location.origin;
    const options = await getOptions(origin);
    const explicitOptions = await getExplicitOptions(origin);

    const pageOptout = checkPageOptout();
    const shouldLoad =
        !isXMLDocument() &&
        options.ruffleEnable &&
        (options.ignoreOptout || !pageOptout);

    browser.runtime.onMessage.addListener((message, _sender, sendResponse) => {
        if (shouldLoad) {
            sendMessageToPage(message).then((response) => {
                sendResponse({
                    loaded: true,
                    tabOptions: options,
                    origin,
                    optout: pageOptout,
                    data: response,
                });
            });
            return true;
        } else {
            sendResponse({
                loaded: false,
                tabOptions: options,
                origin,
                optout: pageOptout,
            });
            return false;
        }
    });

    if (!shouldLoad) {
        return;
    }

    // We must run the plugin polyfill before any flash detection scripts.
    // Unfortunately, this might still be too late for some websites (issue #969).
    // NOTE: The script code injected here is the compiled form of
    // plugin-polyfill.ts. It is injected by tools/inject_plugin_polyfill.ts
    // which just search-and-replaces for this particular string.
    // On browsers which support ExecutionWorld MAIN this will be done earlier.
    if (
        navigator.wrappedJSObject &&
        navigator.wrappedJSObject.plugins.namedItem("Shockwave Flash")
            ?.filename !== "ruffle.js"
    ) {
        injectScriptRaw("%PLUGIN_POLYFILL_SOURCE%");
        await injectScriptURL(browser.runtime.getURL("dist/ruffle.js"));
    }

    window.addEventListener("message", (event) => {
        // We only accept messages from ourselves.
        if (event.source !== window || !event.data) {
            return;
        }

        const { to, index, data, id } = event.data;
        if (to === "ruffle_content" && id === ID) {
            const request = index !== null ? pendingMessages[index] : null;
            if (request) {
                pendingMessages[index] = null;
                request.resolve(data);
            } else if (isMessage(data)) {
                switch (data.type) {
                    case "open_url_in_player":
                        browser.runtime.sendMessage({
                            type: "open_url_in_player",
                            url: data.url,
                        });
                        break;
                    default:
                    // Ignore unknown messages.
                }
            }
        }
    });

    // Sockets of allowed sites go to the native helper. The bridge is posted
    // before "load", so it is in place before Ruffle can open a socket.
    // A site that is neither allowed nor refused gets the helper URL too, so
    // that its first connection attempt reaches the background's question;
    // its page is only changed once a movie is about to load (see
    // socket-bridge-arm.ts).
    const proxySettings = await getProxySettings().catch(() => undefined);
    const allowed =
        resolveSocketAccess(proxySettings, origin)?.mode === "helper";
    const asked = askSocketProxies(proxySettings, origin);
    if (allowed || asked.length) {
        startContentSocketBridge((port) =>
            window.postMessage(
                {
                    to: "ruffle_page",
                    index: null,
                    id: ID,
                    data: {
                        type: "socket_bridge",
                        ...(allowed ? {} : { lazy: true }),
                    },
                },
                "*",
                [port],
            ),
        );
    }

    await sendMessageToPage({
        type: "load",
        config: {
            ...explicitOptions,
            ...(asked.length
                ? {
                      socketProxy: mergeSocketProxies(
                          explicitOptions.socketProxy,
                          asked,
                      ),
                  }
                : {}),
            autoplay: options.autostart ? "on" : "auto",
            unmuteOverlay: options.autostart ? "hidden" : "visible",
            splashScreen: !options.autostart,
        },
        publicPath: browser.runtime.getURL("/dist/"),
    });
})();
