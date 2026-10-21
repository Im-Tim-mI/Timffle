/**
 * Waiting for the socket helper to be installed. The "install the helper
 * first" window and the install page look by themselves whether it is there
 * now, so that the visitor need not press anything after running the
 * installer. A look is the background's status request: the helper is started
 * for a moment and says hello (its version), and no TCP connection is opened.
 */
import { helperVerdict } from "./helper-status";
import { text } from "./i18n";
import { isRecord } from "./socket-bridge-protocol";
import type { HelperStatus } from "./socket-bridge-protocol";
import { versionAtLeast } from "./socket-lan";

/** How long the window waits between two looks. */
export const HELPER_WAIT_POLL_MS = 2000;
/** The same for the install page, which looks only while it is shown. */
export const HELPER_PAGE_REFRESH_MS = 3000;

/**
 * The helper's version when it is one to continue with: installed, of this
 * extension's protocol, and at least `minVersion` when that is given (an
 * older helper refuses what the window was opened for). Nothing otherwise,
 * also for an answer that is not a status at all.
 */
export function readyVersion(
    status: unknown,
    minVersion?: string,
): string | undefined {
    if (
        !isRecord(status) ||
        status["installed"] !== true ||
        (status["version"] !== undefined &&
            typeof status["version"] !== "string")
    ) {
        return undefined;
    }
    const verdict = helperVerdict(status as unknown as HelperStatus);
    if (
        verdict.kind !== "installed" ||
        (minVersion !== undefined &&
            !versionAtLeast(verdict.version, minVersion))
    ) {
        return undefined;
    }
    return verdict.version;
}

export interface HelperWaitOptions {
    /** One look: the background's status request. */
    query: () => Promise<HelperStatus>;
    /** The helper is there: called once, with its version, and the wait is over. */
    ready: (version: string) => void;
    /** Every other answer, as it comes; one that is not a status counts as no answer. */
    notYet?: (status: HelperStatus) => void;
    /** A helper older than this is not there yet. */
    minVersion?: string | undefined;
    /** How long to wait between two looks. */
    pollMs?: number;
    /** Whether a look that is due is made now; one that is not waits for the next turn. */
    active?: () => boolean;
    /** Replaceable for tests. */
    setTimer?: (callback: () => void, ms: number) => unknown;
    clearTimer?: (timer: unknown) => void;
}

export interface HelperWait {
    /** Looks at once (the visitor has come back), unless a look is under way or the wait is over. */
    check(): void;
    /** No more looks: the page is going away. */
    stop(): void;
}

/**
 * Looks every `pollMs` until the helper is there, one look at a time; the
 * first look is due `pollMs` after the start.
 */
export function waitForHelper({
    query,
    ready,
    notYet = () => {},
    minVersion,
    pollMs = HELPER_WAIT_POLL_MS,
    active = () => true,
    setTimer = (callback, ms) => setTimeout(callback, ms),
    clearTimer = (timer) =>
        clearTimeout(timer as ReturnType<typeof setTimeout>),
}: HelperWaitOptions): HelperWait {
    let over = false;
    let looking = false;
    let timer: unknown;

    const schedule = () => {
        clearTimer(timer);
        timer = setTimer(due, pollMs);
    };
    const look = async () => {
        looking = true;
        let status: unknown;
        try {
            status = await query();
        } catch {
            status = undefined;
        }
        looking = false;
        if (over) {
            return;
        }
        const version = readyVersion(status, minVersion);
        if (version !== undefined) {
            over = true;
            clearTimer(timer);
            ready(version);
            return;
        }
        notYet(
            isRecord(status)
                ? (status as unknown as HelperStatus)
                : { installed: false, error: "no_response" },
        );
        schedule();
    };
    function due() {
        if (over) {
            return;
        }
        if (active()) {
            void look();
        } else {
            schedule();
        }
    }

    schedule();
    return {
        check() {
            if (over || looking) {
                return;
            }
            // The look that was due is this one; the next is due after its answer.
            clearTimer(timer);
            void look();
        },
        stop() {
            over = true;
            clearTimer(timer);
        },
    };
}

/**
 * The window's wait line and its Continue button once the helper is there:
 * the line says so, with the version, and the button can be pressed. It is
 * marked like the question's recommended answer but takes no focus: the
 * visitor may be typing somewhere else. The installer button, if there is one,
 * stops being the highlighted one: what is left to do is "Continue".
 */
export function showHelperReady(
    line: HTMLElement,
    button: HTMLButtonElement,
    version: string,
    installer?: HTMLElement,
): void {
    line.textContent = text("timffle_helper_ready", [version]);
    line.dataset["state"] = "ready";
    button.disabled = false;
    button.dataset["ready"] = "true";
    button.classList.add("recommended");
    installer?.classList.remove("recommended");
}
