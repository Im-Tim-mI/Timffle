import { strict as assert } from "assert";
import { JSDOM } from "jsdom";

// InnerPlayer touches `window`/`document` at import time (shadow template)
// and in its constructor, so a jsdom window is installed as the global scope
// before the module is imported. The wasm module is replaced by a fake builder
// through the `createBuilder` seam.

const GLOBALS = [
    "window",
    "document",
    "navigator",
    "Node",
    "Element",
    "HTMLElement",
    "HTMLScriptElement",
    "DocumentFragment",
    "MutationObserver",
    "Event",
    "CustomEvent",
    "AbortController",
] as const;

interface FakeHandle {
    destroyed: boolean;
    played: number;
    visibilityChecks: number;
    destroy(): void;
}

interface Deferred<T> {
    promise: Promise<T>;
    resolve(value: T): void;
}

function deferred<T>(): Deferred<T> {
    let resolve!: (value: T) => void;
    const promise = new Promise<T>((r) => (resolve = r));
    return { promise, resolve };
}

function fakeHandle(): FakeHandle {
    const state = { destroyed: false, played: 0, visibilityChecks: 0 };
    const methods: Record<string, unknown> = {
        destroy: () => {
            state.destroyed = true;
        },
        play: () => {
            state.played++;
        },
        // Only the visibilitychange handler asks this in these tests.
        is_playing: () => {
            state.visibilityChecks++;
            return state.played > 0;
        },
        renderer_debug_info: () => "",
        renderer_name: () => "fake",
        // "running" skips the 200 ms autoplay probe.
        audio_context: () => ({ state: "running", resume() {} }),
        constructor: { is_wasm_simd_used: () => false },
    };
    return new Proxy(state, {
        get(target, prop) {
            if (typeof prop === "string" && prop in methods) {
                return methods[prop];
            }
            if (prop in target) {
                return target[prop as keyof typeof target];
            }
            if (prop === "then") {
                return undefined; // not a thenable
            }
            return () => undefined;
        },
    }) as unknown as FakeHandle;
}

describe("InnerPlayer load lifecycle", function () {
    let dom: JSDOM;
    const saved = new Map<string, PropertyDescriptor | undefined>();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    let InnerPlayer: any;

    before(async function () {
        dom = new JSDOM("<!doctype html><html><body></body></html>", {
            url: "https://example.com/",
        });
        const g = globalThis as Record<string, unknown>;
        for (const key of GLOBALS) {
            saved.set(key, Object.getOwnPropertyDescriptor(g, key));
            Object.defineProperty(g, key, {
                value: (dom.window as unknown as Record<string, unknown>)[key],
                configurable: true,
                writable: true,
            });
        }
        const { log, warn, error } = console;
        console.log = console.warn = console.error = () => {};
        try {
            ({ InnerPlayer } = await import("../src/internal/player/inner"));
        } finally {
            console.log = log;
            console.warn = warn;
            console.error = error;
        }
    });

    after(function () {
        const g = globalThis as Record<string, unknown>;
        for (const [key, descriptor] of saved) {
            if (descriptor) {
                Object.defineProperty(g, key, descriptor);
            } else {
                Reflect.deleteProperty(g, key);
            }
        }
        dom.window.close();
    });

    // Missing text bundles and the load log lines are noise here.
    let originalLog: typeof console.log;
    let originalWarn: typeof console.warn;
    let originalError: typeof console.error;
    beforeEach(function () {
        originalLog = console.log;
        originalWarn = console.warn;
        originalError = console.error;
        console.log = () => {};
        console.warn = () => {};
        console.error = (...args: unknown[]) => {
            if (!String(args[0]).startsWith("Unknown text key")) {
                originalError(...args);
            }
        };
    });
    afterEach(function () {
        console.log = originalLog;
        console.warn = originalWarn;
        console.error = originalError;
    });

    /**
     * Creates a player on a connected element whose builder resolves only
     * when the test says so.
     */
    function makePlayer() {
        const element = dom.window.document.createElement("div");
        dom.window.document.body.appendChild(element);
        const builderGate = deferred<null>();
        const buildGate = deferred<null>();
        const handles: FakeHandle[] = [];
        const player = new InnerPlayer(
            element,
            () => "",
            () => {},
        );
        player.createBuilder = async () => {
            await builderGate.promise;
            const builder = new Proxy(
                {},
                {
                    get(_target, prop) {
                        if (prop === "build") {
                            return async () => {
                                await buildGate.promise;
                                const handle = fakeHandle();
                                handles.push(handle);
                                return handle;
                            };
                        }
                        if (prop === "then") {
                            return undefined;
                        }
                        return () => undefined;
                    },
                },
            );
            return [builder, () => ({})];
        };
        return { element, player, builderGate, buildGate, handles };
    }

    const DATA = { data: new Uint8Array([0x46, 0x57, 0x53]) };

    it("keeps the instance when the element stays connected", async function () {
        const { player, builderGate, buildGate, handles } = makePlayer();
        builderGate.resolve(null);
        buildGate.resolve(null);
        await player.load(DATA);
        assert.equal(handles.length, 1);
        assert.equal(handles[0]!.destroyed, false);
        assert.equal(handles[0]!.played, 1);
        assert.equal(player.instance, handles[0]);
    });

    it("destroys an instance built after the element was removed", async function () {
        const { element, player, builderGate, buildGate, handles } =
            makePlayer();
        builderGate.resolve(null);
        const loading = player.load(DATA);
        await new Promise((r) => setTimeout(r, 0));
        element.remove();
        player.destroy(); // what disconnectedCallback does
        buildGate.resolve(null);
        await loading;
        assert.equal(handles.length, 1);
        assert.equal(handles[0]!.destroyed, true);
        assert.equal(handles[0]!.played, 0);
        assert.equal(player.instance, null);
    });

    it("never builds when the element is removed while Ruffle downloads", async function () {
        const { element, player, builderGate, buildGate, handles } =
            makePlayer();
        const loading = player.load(DATA);
        element.remove();
        player.destroy();
        builderGate.resolve(null);
        buildGate.resolve(null);
        await loading;
        assert.equal(handles.length, 0);
        assert.equal(player.instance, null);
    });

    it("keeps loading when the element is moved during the load", async function () {
        const { element, player, builderGate, buildGate, handles } =
            makePlayer();
        const loading = player.load(DATA);
        element.remove();
        player.destroy();
        dom.window.document.body.appendChild(element);
        builderGate.resolve(null);
        buildGate.resolve(null);
        await loading;
        assert.equal(handles.length, 1);
        assert.equal(handles[0]!.destroyed, false);
        assert.equal(player.instance, handles[0]);
    });

    it("drops the older of two overlapping loads", async function () {
        const { player, builderGate, buildGate, handles } = makePlayer();
        builderGate.resolve(null);
        const first = player.load(DATA);
        const second = player.load(DATA);
        buildGate.resolve(null);
        await Promise.all([first, second]);
        // Before, both loads built an instance and the first one kept running
        // unreferenced next to the second.
        const alive = handles.filter((h) => !h.destroyed);
        assert.equal(alive.length, 1);
        assert.equal(player.instance, alive[0]);
    });

    describe("document listeners", function () {
        function fire(target: EventTarget, type: string) {
            target.dispatchEvent(new dom.window.Event(type));
        }

        function listenerCounts(player: {
            localize: () => void;
            isTouch: boolean;
        }) {
            let localized = 0;
            player.localize = () => {
                localized++;
            };
            return () => {
                player.isTouch = true;
                fire(dom.window, "languagechange");
                // A pointerdown that is not touch/pen clears isTouch.
                fire(dom.window.document.documentElement, "pointerdown");
                return { localized, touchHandled: !player.isTouch };
            };
        }

        it("are active while the element is connected", async function () {
            const { player, builderGate, buildGate, handles } = makePlayer();
            builderGate.resolve(null);
            buildGate.resolve(null);
            await player.load(DATA);
            const probe = listenerCounts(player);
            assert.deepEqual(probe(), { localized: 1, touchHandled: true });
            fire(dom.window.document, "visibilitychange");
            assert.equal(handles[0]!.visibilityChecks, 1);
            // A reload (destroy + load on a connected element) keeps them.
            await player.load(DATA);
            assert.deepEqual(probe(), { localized: 2, touchHandled: true });
        });

        it("are removed on disconnect and added again on reconnect", async function () {
            const { element, player, builderGate, buildGate, handles } =
                makePlayer();
            builderGate.resolve(null);
            buildGate.resolve(null);
            await player.load(DATA);
            const probe = listenerCounts(player);
            element.remove();
            player.destroy(); // disconnectedCallback
            assert.deepEqual(probe(), { localized: 0, touchHandled: false });

            dom.window.document.body.appendChild(element);
            player.updateStyles(); // connectedCallback
            player.updateStyles(); // attributeChangedCallback: no duplicates
            assert.deepEqual(probe(), { localized: 1, touchHandled: true });

            await player.load(DATA);
            fire(dom.window.document, "visibilitychange");
            assert.equal(handles[1]!.visibilityChecks, 1);
            assert.equal(handles[0]!.visibilityChecks, 0);
        });
    });
});
