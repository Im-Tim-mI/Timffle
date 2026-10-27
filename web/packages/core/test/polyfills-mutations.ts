import { strict as assert } from "assert";
import { JSDOM } from "jsdom";

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
] as const;

// The callback as it was before it was made allocation-free.
function oldDetection(mutationsList: MutationRecord[]): boolean {
    return mutationsList.some((mutation) =>
        Array.from(mutation.addedNodes).some(
            (node) =>
                ["EMBED", "OBJECT"].includes(node.nodeName) ||
                (node instanceof Element &&
                    (node as Element).querySelector("embed, object") !== null),
        ),
    );
}

describe("mutationsAddEmbedOrObject", function () {
    let dom: JSDOM;
    const saved = new Map<string, PropertyDescriptor | undefined>();
    let detect: (records: ArrayLike<MutationRecord>) => boolean;

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
            ({ mutationsAddEmbedOrObject: detect } =
                await import("../src/polyfills"));
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

    /** Runs `mutate` on a fresh container and returns the records it made. */
    function recordsOf(mutate: (root: HTMLElement) => void): MutationRecord[] {
        const doc = dom.window.document;
        const root = doc.createElement("div");
        root.innerHTML = "<p id=old>text<object id=gone></object></p>";
        doc.body.appendChild(root);
        const observer = new dom.window.MutationObserver(() => {});
        observer.observe(root, {
            childList: true,
            subtree: true,
            attributes: true,
            characterData: true,
        });
        mutate(root);
        const records = observer.takeRecords();
        observer.disconnect();
        root.remove();
        return records;
    }

    const CASES: [string, boolean, (root: HTMLElement) => void][] = [
        ["no mutations", false, () => {}],
        [
            "text node",
            false,
            (r) => r.appendChild(dom.window.document.createTextNode("hi")),
        ],
        [
            "comment",
            false,
            (r) => r.appendChild(dom.window.document.createComment("embed")),
        ],
        ["attribute only", false, (r) => r.setAttribute("data-x", "1")],
        ["removal only", false, (r) => r.querySelector("#gone")!.remove()],
        [
            "plain div",
            false,
            (r) =>
                r.insertAdjacentHTML("beforeend", "<div><span></span></div>"),
        ],
        [
            "embed",
            true,
            (r) => r.appendChild(dom.window.document.createElement("embed")),
        ],
        [
            "object",
            true,
            (r) => r.appendChild(dom.window.document.createElement("object")),
        ],
        [
            "nested object",
            true,
            (r) => {
                const div = dom.window.document.createElement("div");
                div.innerHTML =
                    "<section><object data=a.swf></object></section>";
                r.appendChild(div);
            },
        ],
        [
            "fragment with embed after text",
            true,
            (r) => {
                const frag = dom.window.document.createDocumentFragment();
                frag.append("before", dom.window.document.createElement("b"));
                const embed = dom.window.document.createElement("embed");
                frag.append(embed);
                r.appendChild(frag);
            },
        ],
        [
            "embed in a later record",
            true,
            (r) => {
                r.setAttribute("data-y", "2");
                r.appendChild(dom.window.document.createTextNode("x"));
                r.querySelector("#gone")!.remove();
                r.appendChild(dom.window.document.createElement("embed"));
            },
        ],
        [
            "uppercase-named custom element is not an embed",
            false,
            (r) =>
                r.appendChild(dom.window.document.createElement("embed-like")),
        ],
        [
            "SVG foreignObject is not an object",
            false,
            (r) =>
                r.insertAdjacentHTML(
                    "beforeend",
                    "<svg><foreignObject><p></p></foreignObject></svg>",
                ),
        ],
    ];

    for (const [name, expected, mutate] of CASES) {
        it(`matches the old detection: ${name}`, function () {
            const records = recordsOf(mutate);
            assert.equal(oldDetection(records), expected);
            assert.equal(detect(records), expected);
        });
    }
});
