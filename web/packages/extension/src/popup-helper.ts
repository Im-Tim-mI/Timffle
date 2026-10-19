/**
 * The popup's notice that the socket helper is not installed (or is not the
 * one this extension needs), with the button that opens the install page.
 * Nothing is shown while the helper works, while it is not needed (sockets
 * off, Timffle off, or a custom WebSocket proxy), or in a browser that has no
 * native messaging.
 */
import {
    helperVerdict,
    needsInstaller,
    noticeMessage,
    queryHelper,
} from "./helper-status";
import { getProxySettings } from "./proxy-settings";
import type { ProxySettings } from "./socket-proxy";

/** Whether sockets would go through the helper at all: only then is a missing helper a problem. */
export function usesHelper(
    settings: ProxySettings,
    playerEnabled: boolean,
): boolean {
    return playerEnabled && settings.enabled && settings.mode === "helper";
}

export interface HelperNoticeOptions {
    /** Opens the install page. */
    install: () => void;
}

/**
 * Fills #helper-notice when the helper has to be installed. The check starts
 * the helper for a moment, so the notice appears when the answer arrives and
 * the rest of the popup does not wait for it.
 */
export async function bindHelperNotice({
    install,
}: HelperNoticeOptions): Promise<void> {
    const notice = document.getElementById("helper-notice");
    const message = document.getElementById("helper-notice-text");
    const button = document.getElementById("helper-notice-button");
    // A web page can frame the popup; it has nothing to offer there.
    if (!notice || !message || !button || window.top !== window) {
        return;
    }
    // Browsers without native messaging (Firefox) have no helper to install.
    if (typeof browser.runtime.connectNative !== "function") {
        return;
    }
    try {
        const [settings, player] = await Promise.all([
            getProxySettings(),
            browser.storage.sync.get({ ruffleEnable: true }),
        ]);
        if (!usesHelper(settings, player["ruffleEnable"] !== false)) {
            return;
        }
        const verdict = helperVerdict(await queryHelper());
        const shown = needsInstaller(verdict)
            ? noticeMessage(verdict)
            : undefined;
        if (shown === undefined) {
            return;
        }
        message.textContent = shown;
        button.addEventListener("click", (event) => {
            if (event.isTrusted) {
                install();
            }
        });
        notice.classList.remove("hidden");
    } catch {
        /* Settings or the background cannot be read: no notice rather than a wrong one. */
    }
}
