import { strict as assert } from "assert";
import { JSDOM } from "jsdom";

const GLOBALS = [
    "window",
    "document",
    "navigator",
    "Node",
    "Element",
    "HTMLElement",
    "DocumentFragment",
] as const;

describe("ruffleShadowTemplate", function () {
    let dom: JSDOM;
    const saved = new Map<string, PropertyDescriptor | undefined>();
    let templatesCreated = 0;

    before(function () {
        dom = new JSDOM("<!doctype html><html><body></body></html>");
        const g = globalThis as Record<string, unknown>;
        for (const key of GLOBALS) {
            saved.set(key, Object.getOwnPropertyDescriptor(g, key));
            Object.defineProperty(g, key, {
                value: (dom.window as unknown as Record<string, unknown>)[key],
                configurable: true,
                writable: true,
            });
        }
        const doc = dom.window.document;
        const createElement = doc.createElement.bind(doc);
        doc.createElement = ((
            name: string,
            options?: ElementCreationOptions,
        ) => {
            if (name === "template") {
                templatesCreated++;
            }
            return createElement(name, options);
        }) as typeof doc.createElement;
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

    it("is built on first use, not on import, and only once", async function () {
        const { error } = console;
        console.error = () => {}; // missing text bundles
        try {
            // A query string gives a fresh module instance even if another
            // test already loaded the module.
            const { ruffleShadowTemplate } =
                await import("../src/internal/ui/shadow-template.tsx?lazy-test");
            assert.equal(templatesCreated, 0);
            const first = ruffleShadowTemplate();
            assert.equal(templatesCreated, 1);
            assert.ok(first.content.getElementById("container"));
            assert.ok(first.content.getElementById("dynamic-styles"));
            assert.equal(first.content.children.length, 10);
            assert.equal(ruffleShadowTemplate(), first);
            assert.equal(templatesCreated, 1);
        } finally {
            console.error = error;
        }
    });
});
