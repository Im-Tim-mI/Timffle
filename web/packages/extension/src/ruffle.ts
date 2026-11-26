import { Setup, setCurrentScriptURL, type Config } from "ruffle-core";
import { Message } from "./messages";
import { mergeSocketProxies } from "./socket-proxy";
import { installSocketBridge } from "./socket-bridge-page";
import { armSocketBridge } from "./socket-bridge-arm";
import { keepTimffleInSlot, type RuffleSlot } from "./page-ruffle";

/**
 *
 * This script runs in the MAIN ExecutionWorld for the following reasons:
 *
 * 1. On Chrome, you are explicitly banned from registering custom elements.
 * 2. On Firefox, you can register custom elements but they can't expose any
 *    useful API surface, and can't even see their own methods.
 *
 */

// Current message ID to be included in openInNewTab
let currentMessageId: string | null = null;

// The bridge of a website that is only asked about: installed when Ruffle first
// reads its socket proxy list (see socket-bridge-arm.ts), not before.
let askedBridgePort: MessagePort | undefined;

// Timffle: Ruffle's navigator calls `window.__timffleCrossDomain(origin)` when
// the browser refused a cross-origin request; the answer (from the host's
// crossdomain.xml, judged by the background) says whether to try again.
const crossDomainAnswers = new Map<number, (allowed: boolean) => void>();
const crossDomainOrigins = new Map<string, Promise<boolean>>();
let crossDomainSeq = 0;
function askCrossDomain(origin: unknown): Promise<boolean> {
    if (typeof origin !== "string" || currentMessageId === null) {
        return Promise.resolve(false);
    }
    // One question per host; a refusal is asked again (the host may have been down).
    const known = crossDomainOrigins.get(origin);
    if (known) {
        return known;
    }
    const pending = askCrossDomainOnce(origin);
    crossDomainOrigins.set(origin, pending);
    pending.then((allowed) => {
        if (!allowed) {
            crossDomainOrigins.delete(origin);
        }
    });
    return pending;
}
function askCrossDomainOnce(origin: string): Promise<boolean> {
    const seq = ++crossDomainSeq;
    return new Promise((resolve) => {
        crossDomainAnswers.set(seq, resolve);
        setTimeout(() => {
            if (crossDomainAnswers.delete(seq)) {
                resolve(false);
            }
        }, 30000);
        window.postMessage(
            {
                to: "ruffle_content",
                index: null,
                id: currentMessageId,
                data: { type: "cross_domain", origin, seq },
            },
            "*",
        );
    });
}
Object.defineProperty(window, "__timffleCrossDomain", {
    value: askCrossDomain,
    writable: false,
    configurable: false,
    enumerable: false,
});

function handleMessage(message: Message) {
    switch (message.type) {
        case "load": {
            const publicPath = new URL(".", message.publicPath);
            if (!publicPath.protocol.includes("extension")) {
                // Ignore messages from a non-extension URL.
                return null;
            }
            if (window.RufflePlayer === undefined) {
                window.RufflePlayer = {};
            }
            if (window.RufflePlayer.config === undefined) {
                window.RufflePlayer.config = {};
            }
            const pageConfig = window.RufflePlayer
                .config as Config.BaseLoadOptions;
            window.RufflePlayer.config = {
                ...message.config,
                ...pageConfig,
                // Site-provided exact mappings take priority, but must not
                // discard an explicitly enabled extension fallback.
                ...(message.config.socketProxy?.length
                    ? {
                          socketProxy: mergeSocketProxies(
                              pageConfig.socketProxy,
                              message.config.socketProxy,
                          ),
                      }
                    : {}),
                openInNewTab,
            };
            if (askedBridgePort) {
                armSocketBridge(window.RufflePlayer.config, () => {
                    // Once: a second install would close the port it is given.
                    const port = askedBridgePort;
                    askedBridgePort = undefined;
                    if (port) {
                        installSocketBridge(port);
                    }
                });
            }
            setCurrentScriptURL(publicPath);
            Setup.installRuffle("extension");
            // Timffle: the page may ship its own (usually old) Ruffle; the
            // extension plays the page regardless, see page-ruffle.ts.
            keepTimffleInSlot(window, window.RufflePlayer as RuffleSlot, {
                socketProxy: message.config.socketProxy,
                openInNewTab,
                sourceName: "extension",
            });
            return {};
        }
        case "settings": {
            // Timffle: apply to every player on the page and to players made later.
            if (window.RufflePlayer?.config) {
                const cfg = window.RufflePlayer
                    .config as Config.BaseLoadOptions;
                cfg.showFps = message.showFps;
            }
            for (const el of document.querySelectorAll(
                "ruffle-embed, ruffle-object, ruffle-player",
            )) {
                const player = el as unknown as { showFps?: boolean };
                try {
                    player.showFps = message.showFps;
                } catch {
                    // A player that is not ready yet.
                }
            }
            return {};
        }
        case "ping":
            // Ping back.
            return {};
        default:
            // Ignore unknown messages.
            return null;
    }
}

function openInNewTab(swf: URL): void {
    const message = {
        to: "ruffle_content",
        index: null,
        id: currentMessageId,
        data: {
            type: "open_url_in_player",
            url: swf.toString(),
        },
    };
    window.postMessage(message, "*");
}

window.addEventListener("message", (event) => {
    // We only accept messages from ourselves.
    if (event.source !== window || !event.data) {
        return;
    }

    const { to, index, data, id } = event.data;
    if (to === "ruffle_page") {
        if (data?.type === "cross_domain_result") {
            const answer = crossDomainAnswers.get(data.seq);
            crossDomainAnswers.delete(data.seq);
            answer?.(data.allowed === true);
            return;
        }
        if (data?.type === "socket_bridge") {
            const port = event.ports[0];
            if (port) {
                if (data.lazy === true) {
                    askedBridgePort = port;
                } else {
                    installSocketBridge(port);
                }
            }
            return;
        }
        currentMessageId = id;
        const response = handleMessage(data);
        if (response) {
            const message = {
                to: "ruffle_content",
                index,
                id,
                data: response,
            };
            window.postMessage(message, "*");
        }
    }
});
