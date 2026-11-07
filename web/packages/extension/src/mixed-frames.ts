/**
 * Timffle: on an HTTPS page, Chrome blocks every `<iframe>`/`<frame>` whose
 * address is plain HTTP ("mixed content") and shows nothing in its place.
 * Old Flash game websites often moved to HTTPS but still embed their
 * navigation bars and menus over HTTP. Such a frame is asked for again over
 * HTTPS: it was blocked anyway, so a server without HTTPS loses nothing.
 */

/**
 * The HTTPS address to load instead of `src`, or `null` when the frame is
 * fine as it is (not an HTTPS page, or not a plain-HTTP frame).
 */
export function upgradedFrameUrl(
    pageUrl: string,
    src: string | null,
): string | null {
    if (!src) {
        return null;
    }
    let page: URL;
    let frame: URL;
    try {
        page = new URL(pageUrl);
        frame = new URL(src, page);
    } catch {
        return null;
    }
    if (page.protocol !== "https:" || frame.protocol !== "http:") {
        return null;
    }
    frame.protocol = "https:";
    // An explicit :80 was the HTTP port; HTTPS uses its own default.
    if (frame.port === "80") {
        frame.port = "";
    }
    return frame.href;
}

function isFrame(node: Node): node is HTMLIFrameElement | HTMLFrameElement {
    return (
        node instanceof HTMLIFrameElement || node instanceof HTMLFrameElement
    );
}

function upgrade(frame: HTMLIFrameElement | HTMLFrameElement): void {
    const next = upgradedFrameUrl(
        document.location.href,
        frame.getAttribute("src"),
    );
    if (next) {
        frame.setAttribute("src", next);
    }
}

/**
 * Upgrades the plain-HTTP frames of this document, now and whenever one is
 * added or its address changes. Does nothing on a page that is not HTTPS.
 */
export function upgradeInsecureFrames(): void {
    if (document.location.protocol !== "https:") {
        return;
    }
    const scan = (root: ParentNode) => {
        for (const frame of Array.from(root.querySelectorAll("iframe,frame"))) {
            if (isFrame(frame)) {
                upgrade(frame);
            }
        }
    };
    scan(document);
    new MutationObserver((records) => {
        for (const record of records) {
            if (record.type === "attributes") {
                if (isFrame(record.target)) {
                    upgrade(record.target);
                }
                continue;
            }
            for (const node of Array.from(record.addedNodes)) {
                if (isFrame(node)) {
                    upgrade(node);
                } else if (node instanceof Element) {
                    scan(node);
                }
            }
        }
    }).observe(document, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ["src"],
    });
}
