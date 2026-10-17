import { Setup, setCurrentScriptURL, type Config } from "ruffle-core";
import { Message } from "./messages";
import { mergeSocketProxies } from "./socket-proxy";
import { installSocketBridge } from "./socket-bridge-page";

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
            setCurrentScriptURL(publicPath);
            Setup.installRuffle("extension");
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
        if (data?.type === "socket_bridge") {
            const port = event.ports[0];
            if (port) {
                installSocketBridge(port);
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
