/**
 * Timffle: which Flash Player the page and the movies are told about.
 *
 * A page is first told about Flash Player 32 (the last global release). Some
 * websites refuse 32 (the global Flash Player stopped running in 2021) and
 * take their Flash content out of the page again; such a page is loaded once
 * more with Flash Player 34 (the last regional release). The choice lasts for
 * the tab's session of that origin (`sessionStorage`), so the page and every
 * script bundle of it (plugin polyfill, player) agree on it synchronously.
 */

export interface FlashIdentity {
    /** Major version, also used as the player version of the movies. */
    readonly major: number;
    /** `navigator.plugins["Shockwave Flash"].description`. */
    readonly description: string;
    /** `navigator.plugins["Shockwave Flash"].filename`, the same everywhere. */
    readonly filename: string;
}

export const FLASH_IDENTITY_FIRST: FlashIdentity = {
    major: 32,
    description: "Shockwave Flash 32.0 r0",
    filename: "pepflashplayer.dll",
};

export const FLASH_IDENTITY_FALLBACK: FlashIdentity = {
    major: 34,
    description: "Shockwave Flash 34.0 r0",
    filename: "pepflashplayer.dll",
};

const STORAGE_KEY = "timffle.flashVersion";

/** Flash content taken out this soon after it was put in is a refusal (ms). */
const REFUSAL_WINDOW_MS = 2000;
/** How long the page may take to put other Flash content in (ms). */
const REFUSAL_SETTLE_MS = 500;
/** Flash content that stays this long means the page accepted it (ms). */
const ACCEPTED_AFTER_MS = 5000;

/**
 * @returns The `sessionStorage` of this page, or null when it is unavailable.
 */
function storage(): Storage | null {
    try {
        return window.sessionStorage;
    } catch {
        return null;
    }
}

/**
 * @returns The identity this page is told about.
 */
export function currentFlashIdentity(): FlashIdentity {
    try {
        if (storage()?.getItem(STORAGE_KEY) === "34") {
            return FLASH_IDENTITY_FALLBACK;
        }
    } catch {
        // Storage refused: keep the first identity.
    }
    return FLASH_IDENTITY_FIRST;
}

/**
 * The version string movies see (`$version`, `Capabilities.version`).
 *
 * @param major Major version.
 * @returns For example `WIN 32,0,0,465`.
 */
export function flashVersionString(major: number): string {
    return `WIN ${major},0,0,465`;
}

let pluginVersionRead = false;

/**
 * Called when the page reads the plugin's version (its description).
 */
export function notePluginVersionRead(): void {
    pluginVersionRead = true;
}

/**
 * @param element An element.
 * @returns Whether it is Flash content with a movie: a native embed/object of
 * a SWF, or a Ruffle player element made from one. An empty Flash object (a
 * detection probe) does not count.
 */
function isFlashMovieElement(element: Element): boolean {
    const tag = element.tagName.toUpperCase();
    if (
        tag !== "EMBED" &&
        tag !== "OBJECT" &&
        tag !== "RUFFLE-EMBED" &&
        tag !== "RUFFLE-OBJECT"
    ) {
        return false;
    }
    const url =
        element.getAttribute("src") ||
        element.getAttribute("data") ||
        element.querySelector("param[name='movie' i]")?.getAttribute("value") ||
        "";
    return /\.swf(?:[?#]|$)/i.test(url);
}

/**
 * @param node A node.
 * @returns The Flash movie elements it is or contains.
 */
function flashMovies(node: Node): Element[] {
    if (!(node instanceof Element)) {
        return [];
    }
    const found = isFlashMovieElement(node) ? [node] : [];
    for (const element of node.querySelectorAll(
        "embed, object, ruffle-embed, ruffle-object",
    )) {
        if (isFlashMovieElement(element)) {
            found.push(element);
        }
    }
    return found;
}

/**
 * Whether a refusal seen now should load the page again: the page read the
 * plugin's version, took Flash content out right after putting it in, no
 * Flash content is left, nobody touched the page and it still has the first
 * identity.
 *
 * @param state What was seen.
 * @param state.versionRead The page read the plugin's version.
 * @param state.removedAfterMs How long the Flash content was in the page (ms).
 * @param state.flashLeft Flash content is still in the page.
 * @param state.userActive The user has interacted with the page.
 * @param state.major The page's current identity.
 * @returns Whether to switch to the fallback identity and reload.
 */
export function shouldRetryWithFallback(state: {
    versionRead: boolean;
    removedAfterMs: number;
    flashLeft: boolean;
    userActive: boolean;
    major: number;
}): boolean {
    return (
        state.versionRead &&
        state.removedAfterMs <= REFUSAL_WINDOW_MS &&
        !state.flashLeft &&
        !state.userActive &&
        state.major === FLASH_IDENTITY_FIRST.major
    );
}

let watching = false;

/**
 * Watch for the page taking its Flash content out again right after putting
 * it in (a website refusing this Flash Player version). Then remember the
 * fallback identity for this origin and load the page once more. Stops once
 * Flash content stayed in the page for a while.
 */
export function watchFlashRefusal(): void {
    if (
        watching ||
        typeof MutationObserver === "undefined" ||
        currentFlashIdentity().major !== FLASH_IDENTITY_FIRST.major
    ) {
        return;
    }
    watching = true;
    const addedAt = new WeakMap<Element, number>();
    let refusedAfterMs: number | null = null;
    let pending = false;
    const observer = new MutationObserver((records) => {
        const now = performance.now();
        // Records are in order, so content added and removed in the same
        // task is seen as added first.
        for (const record of records) {
            for (const node of record.addedNodes) {
                for (const movie of flashMovies(node)) {
                    if (!addedAt.has(movie)) {
                        addedAt.set(movie, now);
                        setTimeout(() => {
                            if (movie.isConnected) {
                                observer.disconnect();
                            }
                        }, ACCEPTED_AFTER_MS);
                    }
                }
            }
            for (const node of record.removedNodes) {
                for (const movie of flashMovies(node)) {
                    const at = addedAt.get(movie);
                    if (at !== undefined) {
                        const after = now - at;
                        refusedAfterMs =
                            refusedAfterMs === null
                                ? after
                                : Math.min(refusedAfterMs, after);
                    }
                }
            }
        }
        if (refusedAfterMs === null || pending) {
            return;
        }
        pending = true;
        setTimeout(() => {
            pending = false;
            const removedAfterMs = refusedAfterMs ?? Infinity;
            refusedAfterMs = null;
            const retry = shouldRetryWithFallback({
                versionRead: pluginVersionRead,
                removedAfterMs,
                flashLeft: flashMovies(document.documentElement).length > 0,
                userActive: !!navigator.userActivation?.hasBeenActive,
                major: currentFlashIdentity().major,
            });
            if (!retry) {
                return;
            }
            try {
                storage()?.setItem(STORAGE_KEY, "34");
            } catch {
                // Handled below.
            }
            // Reload only when the choice sticks, else it would loop.
            if (
                currentFlashIdentity().major !== FLASH_IDENTITY_FALLBACK.major
            ) {
                return;
            }
            observer.disconnect();
            console.info(
                "Timffle: this page refused Flash Player 32; loading it again as Flash Player 34.",
            );
            window.location.reload();
        }, REFUSAL_SETTLE_MS);
    });
    observer.observe(document, { childList: true, subtree: true });
}
