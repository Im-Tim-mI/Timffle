/**
 * Timffle's own texts (the socket pages and the question window) come from the
 * extension's message catalogs, `_locales/<language>/messages.json`, like the
 * rest of the extension. Their keys start with `timffle_`; the sources are in
 * `timffle/locales`.
 *
 * The pages carry no text of their own for these: an element marked
 * `data-i18n="key"` gets the message as its text, and an element marked
 * `data-i18n-rich="key"` gets a message with `<1>…</1>` spans, each of which
 * becomes a copy of the element's n-th child (a link, or bold text) holding
 * the spanned text. `data-i18n-alt="key"` sets an element's `alt`, and
 * `data-i18n-image="key"` sets an `<img>`'s picture to the file in `images/`
 * that the message names (a banner that exists in some languages only).
 * `data-i18n-languages="en zh"` keeps an element (which starts `hidden`) hidden
 * unless the browser's interface is in one of those languages.
 */

/** The primary language of the browser's interface: "en" for en-GB, "zh" for zh-TW. */
export function interfaceLanguage(): string {
    return browser.i18n.getUILanguage().split(/[-_]/u)[0]!.toLowerCase();
}

/** The message for `key`; the key itself when it is missing, so a gap shows instead of staying blank. */
export function text(key: string, substitutions?: string | string[]): string {
    return browser.i18n.getMessage(key, substitutions) || key;
}

export type RichPart = string | { slot: number; text: string };

/** Splits a message into plain text and the `<n>…</n>` spans it contains. */
export function splitRich(message: string): RichPart[] {
    const parts: RichPart[] = [];
    let end = 0;
    for (const match of message.matchAll(/<(\d)>([^<]*)<\/\1>/gu)) {
        if (match.index > end) {
            parts.push(message.slice(end, match.index));
        }
        parts.push({ slot: Number(match[1]), text: match[2]! });
        end = match.index + match[0].length;
    }
    if (end < message.length) {
        parts.push(message.slice(end));
    }
    return parts;
}

/**
 * Replaces the content of `node` with `message`. The n-th child element of
 * `node` (counting from 1) is the template for `<n>…</n>`; a span without a
 * template stays plain text.
 */
export function fillRich(node: Element, message: string): void {
    const templates = Array.from(node.children);
    node.replaceChildren(
        ...splitRich(message).map((part) => {
            if (typeof part === "string") {
                return document.createTextNode(part);
            }
            const template = templates[part.slot - 1];
            if (!template) {
                return document.createTextNode(part.text);
            }
            const copy = template.cloneNode(false) as Element;
            copy.textContent = part.text;
            return copy;
        }),
    );
}

/** Fills every marked element below `root` (the whole page by default). */
export function localizePage(root: ParentNode = document): void {
    for (const node of root.querySelectorAll<HTMLElement>("[data-i18n]")) {
        node.textContent = text(node.dataset["i18n"]!);
    }
    for (const node of root.querySelectorAll<HTMLElement>("[data-i18n-rich]")) {
        fillRich(node, text(node.dataset["i18nRich"]!));
    }
    for (const node of root.querySelectorAll<HTMLElement>("[data-i18n-alt]")) {
        node.setAttribute("alt", text(node.dataset["i18nAlt"]!));
    }
    for (const node of root.querySelectorAll<HTMLImageElement>(
        "[data-i18n-image]",
    )) {
        const file = text(node.dataset["i18nImage"]!);
        // Only a plain file name: a message must never point anywhere else.
        if (/^[\w-]+\.(?:png|svg|jpg|webp)$/u.test(file)) {
            node.src = `images/${file}`;
        }
    }
    for (const node of root.querySelectorAll<HTMLElement>(
        "[data-i18n-languages]",
    )) {
        node.hidden =
            !node.dataset["i18nLanguages"]!.split(" ").includes(
                interfaceLanguage(),
            );
    }
}
