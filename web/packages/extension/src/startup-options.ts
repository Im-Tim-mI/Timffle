/**
 * What the content script does with the stored options before it tells the
 * page to load: pure, so it can be tested without the player (utils.ts needs
 * a document to be imported).
 */
import type { Options } from "./common";

/**
 * The options that are explicitly different from `defaults`; a copy, the
 * given object is not changed. `responseHeadersUnsupported` is specific to the
 * extension's own pages and is always left out.
 *
 * In the future we should just not store options we don't want to set.
 */
export function explicitOptionsFrom(
    options: Options,
    defaults: Required<Options>,
): Options {
    const explicit: Options = { ...options };
    for (const key in defaults) {
        // @ts-expect-error: Element implicitly has an any type
        if (key in explicit && defaults[key] === explicit[key]) {
            // @ts-expect-error: Element implicitly has an any type
            // eslint-disable-next-line @typescript-eslint/no-dynamic-delete
            delete explicit[key];
        }
    }
    if ("responseHeadersUnsupported" in explicit) {
        delete explicit["responseHeadersUnsupported"];
    }
    return explicit;
}

/**
 * The background sets `showReloadButton` after a permission grant; the next
 * page load clears it. It is written only when it is set (storage.sync allows
 * about 120 writes a minute, shared by every frame of every tab) and not
 * awaited, so a quota error can neither delay nor stop this frame's Flash
 * content. The returned options read as if the write had already happened, as
 * they did when the flag was cleared before the options were read.
 */
export function clearReloadFlag(
    options: Options,
    sync: { set(items: Record<string, unknown>): Promise<unknown> } = browser
        .storage.sync,
): Options {
    if (!options.showReloadButton) {
        return options;
    }
    try {
        void Promise.resolve(sync.set({ showReloadButton: false })).catch(
            () => {},
        );
    } catch {
        /* Storage is unavailable: the flag stays until a later load. */
    }
    return { ...options, showReloadButton: false };
}
