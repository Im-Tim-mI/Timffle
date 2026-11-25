// Timffle: a page that ships its own copy of Ruffle is still played by the
// extension.
//
// Every Ruffle build since 2020 puts a `PublicAPI` object into
// `window.RufflePlayer` and, when something is already there, takes it over
// only if it is an instance of *its own* `PublicAPI` class. The extension's
// class and the page's class are never the same object, so whichever script
// runs last wins the slot and runs its polyfill, and the other copy is
// ignored. On the sites that bundle Ruffle that is usually a copy that is
// years old. Timffle always keeps the slot: the page's config is honoured,
// its copy of Ruffle is told not to initialise, and no switch is offered.
import type { Config } from "ruffle-core";
import { mergeSocketProxies } from "./socket-proxy";

/** What any version of Ruffle leaves in `window.RufflePlayer`. */
export interface RuffleSlot {
    config?: object;
    sources?: Record<string, unknown>;
    invoked?: boolean;
    newestName?: string | null;
    superseded?: () => void;
}

export interface KeepOptions {
    /** The extension's own socket mappings (fallback after the page's). */
    socketProxy?: readonly Config.SocketProxy[] | undefined;
    /** The extension's local-player opener; a page value never replaces it. */
    openInNewTab?: Config.BaseLoadOptions["openInNewTab"];
    /** The name the extension registered its source under. */
    sourceName?: string;
}

/**
 * Merges a page-provided config into the extension's: page values win, except
 * `publicPath` (the extension loads its own wasm; the core ignores a page
 * value in the extension anyway), `socketProxy` (the page's exact mappings
 * first, the extension's as fallback) and `openInNewTab` (always ours).
 * Returns `false` when there was nothing to merge.
 */
export function absorbPageConfig(
    ours: RuffleSlot,
    page: unknown,
    options: KeepOptions = {},
): boolean {
    if (!page || typeof page !== "object" || page === ours.config) {
        return false;
    }
    const pageConfig = { ...(page as Config.BaseLoadOptions) };
    delete pageConfig.publicPath;
    delete pageConfig.openInNewTab;
    const merged: Config.BaseLoadOptions = {
        ...(ours.config as Config.BaseLoadOptions),
        ...pageConfig,
    };
    if (pageConfig.socketProxy?.length || options.socketProxy?.length) {
        merged.socketProxy = mergeSocketProxies(
            pageConfig.socketProxy,
            options.socketProxy,
        );
    }
    if (options.openInNewTab) {
        merged.openInNewTab = options.openInNewTab;
    }
    ours.config = merged;
    return true;
}

/**
 * Keeps the page's own Ruffle from initialising: `init()` returns at once
 * when `invoked` is set (every version), so it never polyfills the page's
 * embeds with its own player. Its plugin polyfill may already have run; that
 * is harmless, it only fakes `navigator.plugins`.
 */
export function silencePageRuffle(foreign: RuffleSlot): void {
    foreign.invoked = true;
}

/**
 * Makes the extension's public API the one that stays in
 * `window.RufflePlayer`, in both orders the scripts can run in:
 *
 * - The extension installed first (the usual case: it is injected at
 *   `document_start`). The page's `ruffle.js` later assigns its own API over
 *   the slot; the slot is an accessor now, so the assignment reaches us
 *   instead: we merge the page config it carries, silence it and keep ours.
 *   A plain config object assigned by the page is merged the same way.
 * - The page's Ruffle ran first. `installRuffle` has then built our API on
 *   top of it, copying its sources, `invoked` and `newestName`, and the
 *   page's API may have called our `superseded()`. Only our source is kept,
 *   and our `init` is re-armed so our polyfill still runs.
 *
 * `ours.superseded` is replaced: a page Ruffle that is newer than our
 * `PublicAPI` would call it to stop our init, which is exactly what must
 * not happen.
 */
export function keepTimffleInSlot(
    win: { RufflePlayer?: unknown },
    ours: RuffleSlot,
    options: KeepOptions = {},
): void {
    const sourceName = options.sourceName ?? "extension";
    if (ours.sources) {
        const own = ours.sources[sourceName];
        for (const name of Object.keys(ours.sources)) {
            Reflect.deleteProperty(ours.sources, name);
        }
        if (own !== undefined) {
            ours.sources[sourceName] = own;
        }
    }
    // Re-arm: `init` sets `newestName`; it has not run while that is null.
    ours.invoked = false;
    ours.newestName = null;
    ours.superseded = () => {
        /* Timffle is never superseded by the page's copy. */
    };

    let silenced = false;
    Object.defineProperty(win, "RufflePlayer", {
        configurable: true,
        enumerable: true,
        get: () => ours,
        set: (value: unknown) => {
            if (value === ours || value === null || value === undefined) {
                return;
            }
            if (typeof value !== "object") {
                return;
            }
            const foreign = value as RuffleSlot;
            if ("sources" in foreign || "invoked" in foreign) {
                // The page's Ruffle public API.
                absorbPageConfig(ours, foreign.config, options);
                silencePageRuffle(foreign);
                silenced = true;
            } else {
                // `window.RufflePlayer = { config: {...} }` or a bare config.
                absorbPageConfig(
                    ours,
                    "config" in foreign ? foreign.config : foreign,
                    options,
                );
            }
            if (ours.newestName === null) {
                ours.invoked = false;
            }
        },
    });
    void silenced;
}
