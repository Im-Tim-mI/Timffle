/**
 * What the extension knows about the socket helper, and how it tells the user.
 * The settings page, the popup's notice and the install page all ask the
 * background (which starts the helper for a moment, `hello` only, no TCP) and
 * read the answer the same way.
 */
import { text } from "./i18n";
import { HELPER_STATUS_REQUEST } from "./socket-bridge-protocol";
import type { HelperStatus } from "./socket-bridge-protocol";

export async function queryHelper(): Promise<HelperStatus> {
    try {
        const status = (await browser.runtime.sendMessage({
            type: HELPER_STATUS_REQUEST,
        })) as HelperStatus | undefined;
        return status ?? { installed: false, error: "no_response" };
    } catch {
        return { installed: false, error: "no_response" };
    }
}

export type HelperVerdict =
    | { kind: "installed"; version: string }
    /** Chrome knows no such native messaging host: the installer was never run. */
    | { kind: "missing" }
    /** A helper answered, but not one this extension can work with. */
    | { kind: "incompatible" }
    /** Anything else: it did not start, did not answer in time, the bridge is busy... */
    | { kind: "unavailable" };

export function helperVerdict(status: HelperStatus): HelperVerdict {
    if (status.installed) {
        return { kind: "installed", version: status.version ?? "?" };
    }
    switch (status.error) {
        case "helper_missing":
            return { kind: "missing" };
        case "helper_incompatible":
            return { kind: "incompatible" };
        default:
            return { kind: "unavailable" };
    }
}

/** Running the installer is the fix: the case the popup's notice and the install page are about. */
export function needsInstaller(verdict: HelperVerdict): boolean {
    return verdict.kind === "missing" || verdict.kind === "incompatible";
}

/** The status line shown on the settings page and the install page. */
export function statusMessage(verdict: HelperVerdict): string {
    switch (verdict.kind) {
        case "installed":
            return text("timffle_helper_installed", [verdict.version]);
        case "missing":
            return text("timffle_helper_missing");
        case "incompatible":
            return text("timffle_helper_incompatible");
        case "unavailable":
            return text("timffle_helper_unavailable");
    }
}

/**
 * Writes the install page's status line for an answer. A line that says so
 * already is left alone: the page asks again by itself every few seconds, and
 * a screen reader reads the line out each time it is written.
 */
export function showStatus(line: HTMLElement, verdict: HelperVerdict): void {
    const message = statusMessage(verdict);
    const state = verdict.kind === "installed" ? "info" : "error";
    if (line.textContent !== message || line.dataset["state"] !== state) {
        line.textContent = message;
        line.dataset["state"] = state;
    }
}

/** The popup's notice for a helper that has to be installed; nothing for any other state. */
export function noticeMessage(verdict: HelperVerdict): string | undefined {
    switch (verdict.kind) {
        case "missing":
            return text("timffle_helper_notice_missing");
        case "incompatible":
            return text("timffle_helper_notice_incompatible");
        default:
            return undefined;
    }
}
