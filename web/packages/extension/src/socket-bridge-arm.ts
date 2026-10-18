/**
 * Websites that are only asked about (not yet allowed) must not get a changed
 * `WebSocket` just because the extension is installed: most pages never run a
 * Flash movie, let alone one that opens a socket. So their bridge stays unused
 * until Ruffle reads its socket proxy list, which it does when a movie is about
 * to load - before the movie runs any code.
 */
export function armSocketBridge(config: object, install: () => void): boolean {
    const descriptor = Object.getOwnPropertyDescriptor(config, "socketProxy");
    if (!descriptor || !("value" in descriptor) || !descriptor.configurable) {
        return false;
    }
    let value: unknown = descriptor.value;
    let installed = false;
    Object.defineProperty(config, "socketProxy", {
        configurable: true,
        enumerable: true,
        get() {
            if (!installed) {
                installed = true;
                install();
            }
            return value;
        },
        set(next: unknown) {
            value = next;
        },
    });
    return true;
}
