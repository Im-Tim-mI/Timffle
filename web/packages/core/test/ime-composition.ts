import { strict as assert } from "assert";
import { JSDOM } from "jsdom";

// Timffle: input-method (IME) composition on the hidden "virtual keyboard"
// input. Typing Chinese with Bopomofo/Zhuyin on macOS used to produce
// doubled symbols ("ㄅㄅ") and never reach the candidate list, because the
// `input` events fired during the composition were replayed as key presses
// and the input was cleared, which killed the composition.
//
// Same harness as inner-player-lifecycle.ts: a jsdom window is installed as
// the global scope before the module is imported, and the wasm module is
// replaced by a fake builder through the `createBuilder` seam.

const GLOBALS = [
    "window",
    "document",
    "navigator",
    "Node",
    "Element",
    "HTMLElement",
    "HTMLInputElement",
    "HTMLScriptElement",
    "DocumentFragment",
    "MutationObserver",
    "Event",
    "CustomEvent",
    "KeyboardEvent",
    "CompositionEvent",
    "InputEvent",
    "AbortController",
] as const;

interface ImeCall {
    kind: "preedit" | "commit";
    text: string;
    cursor?: number;
}

interface FakeHandle {
    imeCalls: ImeCall[];
    destroy(): void;
}

function fakeHandle(): FakeHandle {
    const state: { imeCalls: ImeCall[] } = { imeCalls: [] };
    const methods: Record<string, unknown> = {
        destroy: () => {},
        play: () => {},
        is_playing: () => true,
        has_focus: () => true,
        renderer_debug_info: () => "",
        renderer_name: () => "fake",
        audio_context: () => ({ state: "running", resume() {} }),
        constructor: { is_wasm_simd_used: () => false },
        ime_preedit: (text: string, cursor?: number) => {
            state.imeCalls.push({ kind: "preedit", text, cursor });
        },
        ime_commit: (text: string) => {
            state.imeCalls.push({ kind: "commit", text });
        },
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
                return undefined;
            }
            return () => undefined;
        },
    }) as unknown as FakeHandle;
}

describe("InnerPlayer IME composition", function () {
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

    async function makePlayer() {
        const element = dom.window.document.createElement("div");
        dom.window.document.body.appendChild(element);
        const handles: FakeHandle[] = [];
        const player = new InnerPlayer(
            element,
            () => "",
            () => {},
        );
        player.createBuilder = async () => {
            const builder = new Proxy(
                {},
                {
                    get(_target, prop) {
                        if (prop === "build") {
                            return async () => {
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
        await player.load({ data: new Uint8Array([0x46, 0x57, 0x53]) });
        const input = element.shadowRoot!.getElementById(
            "virtual-keyboard",
        ) as HTMLInputElement;
        assert.ok(input, "hidden input exists");
        const typed: string[] = [];
        element.addEventListener("keydown", (event) => {
            typed.push((event as KeyboardEvent).key);
        });
        return { element, player, handle: handles[0]!, input, typed };
    }

    function composition(input: HTMLInputElement, type: string, data: string) {
        input.dispatchEvent(
            new dom.window.CompositionEvent(type, { data, bubbles: true }),
        );
    }

    function inputEvent(
        input: HTMLInputElement,
        isComposing: boolean,
        inputType: string,
    ) {
        input.dispatchEvent(
            new dom.window.InputEvent("input", {
                isComposing,
                inputType,
                bubbles: true,
            }),
        );
    }

    it("mirrors a Bopomofo composition as preedit and commits the chosen character", async function () {
        const { handle, input, typed } = await makePlayer();

        // ㄅ: the browser puts the preedit into the input and fires
        // compositionstart/compositionupdate, then an input event.
        composition(input, "compositionstart", "");
        input.value = "ㄅ";
        composition(input, "compositionupdate", "ㄅ");
        inputEvent(input, true, "insertCompositionText");

        // ㄅㄚ
        input.value = "ㄅㄚ";
        composition(input, "compositionupdate", "ㄅㄚ");
        inputEvent(input, true, "insertCompositionText");

        // The user picks 巴 from the candidate list.
        input.value = "巴";
        composition(input, "compositionupdate", "巴");
        inputEvent(input, true, "insertCompositionText");
        composition(input, "compositionend", "巴");
        // Firefox fires the final input event after compositionend.
        inputEvent(input, false, "insertCompositionText");

        assert.deepEqual(handle.imeCalls, [
            { kind: "preedit", text: "ㄅ", cursor: 3 },
            { kind: "preedit", text: "ㄅㄚ", cursor: 6 },
            { kind: "preedit", text: "巴", cursor: 3 },
            { kind: "commit", text: "巴" },
        ]);
        // Nothing was replayed as key presses (that was the "ㄅㄅ" bug)...
        assert.deepEqual(typed, []);
        // ...and the input is empty again for the next composition.
        assert.equal(input.value, "");
    });

    it("drops a cancelled composition", async function () {
        const { handle, input, typed } = await makePlayer();
        composition(input, "compositionstart", "");
        input.value = "ㄅ";
        composition(input, "compositionupdate", "ㄅ");
        // Escape: the browser ends the composition with empty data.
        input.value = "";
        composition(input, "compositionend", "");
        assert.deepEqual(handle.imeCalls, [
            { kind: "preedit", text: "ㄅ", cursor: 3 },
            { kind: "commit", text: "" },
        ]);
        assert.deepEqual(typed, []);
    });

    it("still types plain text from a virtual keyboard outside a composition", async function () {
        const { handle, input, typed } = await makePlayer();
        input.value = "ab";
        inputEvent(input, false, "insertText");
        assert.deepEqual(typed, ["a", "b"]);
        assert.equal(input.value, "");
        assert.deepEqual(handle.imeCalls, []);
    });

    it("moves the hidden input over the focused text field and follows the purpose", async function () {
        const { player, input } = await makePlayer();
        player.imeReady(false, 10.4, 20.6, 200.2, 24.7);
        assert.equal(input.type, "text");
        assert.equal(input.style.left, "10px");
        assert.equal(input.style.top, "21px");
        assert.equal(input.style.width, "200px");
        assert.equal(input.style.height, "25px");
        assert.equal(input.style.lineHeight, "25px");

        player.imeSetPurpose(true);
        assert.equal(input.type, "password");
        player.imeSetCursorArea(0, 0, 50, 300);
        assert.equal(input.style.height, "300px");
        assert.equal(input.style.fontSize, "48px");
        // Garbage coordinates never touch the layout.
        player.imeSetCursorArea(NaN, 0, 50, 10);
        assert.equal(input.style.height, "300px");

        input.value = "ㄅ";
        composition(input, "compositionstart", "");
        player.imeNotReady();
        assert.equal(input.value, "");
        // A stray input event after the field lost the focus is plain typing again.
        input.value = "x";
        inputEvent(input, false, "insertText");
        assert.equal(input.value, "");
    });
});
