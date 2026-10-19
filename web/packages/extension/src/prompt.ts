/**
 * The extension's own window for two things a web page can cause: the
 * question "this website wants to use sockets" and the notice "install the
 * socket helper first" (the page needed a TCP connection and the helper is not
 * there). It runs in a window of its own, so a web page can neither cover it
 * nor click it.
 */
import { enableBrowserOnOutdatedChromium, setPageLanguage } from "./utils";
import { localizePage, text } from "./i18n";
import {
    PROMPT_ANSWER_REQUEST,
    PROMPT_GET_REQUEST,
    PROMPT_PORT_NAME,
    PROMPT_CHOICES,
} from "./socket-prompt";
import type { PromptChoice, PromptView } from "./socket-prompt";
import { isHelperPromptView } from "./helper-prompt";
import type { HelperPromptView } from "./helper-prompt";
import { bindHelperDownload } from "./helper-download";
import { createInputGuard } from "./prompt-guard";
import type { InputGuard, PressKind } from "./prompt-guard";

/**
 * Clicks and keys in this long after the window appeared (or got focus) are
 * ignored: the window can pop up while the visitor is clicking or typing in
 * the game, and that input is not an answer. See prompt-guard.ts for the rest
 * of what has to be true before input counts.
 */
const IGNORE_INPUT_MS = 700;
const KEEP_ALIVE_MS = 10000;

type WindowView = PromptView | HelperPromptView;

function isWindowView(value: unknown): value is WindowView {
    return (
        typeof value === "object" &&
        value !== null &&
        typeof (value as PromptView).origin === "string"
    );
}

/** The window may load a moment before the background knows it, so ask a few times. */
async function fetchView(id: string): Promise<WindowView | undefined> {
    for (let attempt = 0; attempt < 8; attempt++) {
        try {
            const reply: unknown = await browser.runtime.sendMessage({
                type: PROMPT_GET_REQUEST,
                id,
            });
            if (isWindowView(reply)) {
                return reply;
            }
        } catch {
            /* The background is starting; try again. */
        }
        await new Promise((resolve) => setTimeout(resolve, 150));
    }
    return undefined;
}

function show(id: "prompt" | "helper" | "expired") {
    for (const name of ["prompt", "helper", "expired"]) {
        document.getElementById(name)!.hidden = name !== id;
    }
}

/**
 * Keeps the background alive while the window is open: it holds the pages'
 * connection attempts, and a stopped service worker drops them (and forgets
 * that this window is open).
 */
function keepBackgroundAlive() {
    try {
        const port = browser.runtime.connect({ name: PROMPT_PORT_NAME });
        setInterval(() => {
            try {
                port.postMessage({ type: "ping" });
            } catch {
                /* The background is gone; the next click says so. */
            }
        }, KEEP_ALIVE_MS);
    } catch {
        /* Without the port the window still works while the worker is awake. */
    }
}

/**
 * The input guard of this window. The controls stay focusable (the safe one
 * has the focus) but do nothing for a moment, and while the window has no
 * focus; the dimming tells the visitor why. `watch` makes a control report
 * its pointer and key presses to the guard.
 */
function guardInput(): { guard: InputGuard; watch: (el: HTMLElement) => void } {
    const guard = createInputGuard(IGNORE_INPUT_MS);
    let waiting: ReturnType<typeof setTimeout> | undefined;
    const arm = () => {
        guard.arm(Date.now());
        document.body.dataset["wait"] = "1";
        clearTimeout(waiting);
        waiting = setTimeout(() => {
            delete document.body.dataset["wait"];
        }, IGNORE_INPUT_MS);
    };
    const disarm = () => {
        guard.disarm();
        document.body.dataset["wait"] = "1";
        clearTimeout(waiting);
    };
    if (document.hasFocus()) {
        arm();
    } else {
        disarm();
    }
    window.addEventListener("focus", arm);
    window.addEventListener("blur", disarm);
    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
            // Closing the window refuses (the question) or does nothing (the helper notice).
            window.close();
        }
    });
    return {
        guard,
        watch(control) {
            const key = control.id;
            control.addEventListener("pointermove", () => {
                guard.pointerMoved(key, Date.now());
            });
            control.addEventListener("pointerdown", (event) => {
                const kind: PressKind =
                    event.pointerType === "touch"
                        ? "touch"
                        : event.pointerType === "pen"
                          ? "pen"
                          : "mouse";
                guard.pressed(key, kind, Date.now());
            });
            control.addEventListener("keydown", (event) => {
                // Enter clicks on this press, Space when the key is let go.
                if (event.key === "Enter" || event.key === " ") {
                    guard.pressed(key, "key", Date.now());
                }
            });
        },
    };
}

function showOrigin(
    view: WindowView,
    ids: { origin: string; embedded: string; embeddedOrigin: string },
) {
    document.getElementById(ids.origin)!.textContent = view.origin;
    if (view.embeddedIn !== undefined) {
        document.getElementById(ids.embeddedOrigin)!.textContent =
            view.embeddedIn;
        document.getElementById(ids.embedded)!.hidden = false;
    }
}

/** "Install the socket helper first": what is wrong, a button that downloads the installer, the way to the others. */
async function runHelperNotice(view: HelperPromptView) {
    showOrigin(view, {
        origin: "helper-origin",
        embedded: "helper-embedded",
        embeddedOrigin: "helper-embedded-origin",
    });
    const message = document.getElementById("helper-text")!;
    message.textContent = text(
        view.helper === "incompatible"
            ? "timffle_helper_notice_incompatible"
            : "timffle_helper_notice_missing",
    );
    const download = document.getElementById("helper-download")!;
    const label = document.getElementById("helper-for")!;
    const more = document.getElementById("helper-more")!;
    const close = document.getElementById("helper-close")!;
    // Not offered before it is known what it would download.
    download.hidden = true;
    show("helper");
    keepBackgroundAlive();
    const { guard, watch } = guardInput();
    const counts = (control: HTMLElement, event: MouseEvent) =>
        guard.accepts(
            "action",
            control.id,
            { isTrusted: event.isTrusted, detail: event.detail },
            Date.now(),
        );
    for (const control of [download, more, close]) {
        watch(control);
    }
    close.addEventListener("click", (event) => {
        if (counts(close, event)) {
            window.close();
        }
    });
    more.addEventListener("click", (event) => {
        if (counts(more, event)) {
            // The page that lists every installer; it opens in a window with tabs.
            void browser.tabs.create({
                url: browser.runtime.getURL("/helper.html"),
            });
        }
    });
    close.focus();
    // The system is worked out before the button is offered, so it already knows what it will download.
    const installer = await bindHelperDownload({
        button: download,
        label,
        accepts: (event) => counts(download, event),
        started: () => {
            message.textContent = text("timffle_helper_download_started");
        },
    });
    // A system without an installer (or one the browser did not describe) is sent to the page that lists them all.
    download.hidden = installer === undefined;
}

/** "This website wants to use sockets": four ways to answer. */
function runQuestion(id: string, view: PromptView) {
    showOrigin(view, {
        origin: "prompt-origin",
        embedded: "prompt-embedded",
        embeddedOrigin: "prompt-embedded-origin",
    });
    show("prompt");
    keepBackgroundAlive();

    const buttons = Array.from(
        document.querySelectorAll<HTMLButtonElement>("button[data-choice]"),
    );
    const error = document.getElementById("prompt-error")!;
    const { guard, watch } = guardInput();
    let answering = false;

    for (const button of buttons) {
        const key = button.id;
        watch(button);
        button.addEventListener("click", async (event) => {
            const choice = button.dataset["choice"] as PromptChoice | undefined;
            if (
                answering ||
                !choice ||
                !PROMPT_CHOICES.includes(choice) ||
                !guard.accepts(
                    choice,
                    key,
                    { isTrusted: event.isTrusted, detail: event.detail },
                    Date.now(),
                )
            ) {
                return;
            }
            answering = true;
            for (const other of buttons) {
                other.disabled = true;
            }
            error.hidden = true;
            const accepted = await browser.runtime
                .sendMessage({
                    type: PROMPT_ANSWER_REQUEST,
                    id,
                    choice,
                })
                .then(
                    (reply: unknown) => reply === true,
                    () => false,
                );
            if (accepted) {
                window.close();
                return;
            }
            // Ended in the meantime (decided elsewhere, tab closed) or not stored.
            show("expired");
        });
    }
    buttons.find((button) => button.id === "deny-once")?.focus();
}

window.addEventListener("DOMContentLoaded", async () => {
    enableBrowserOnOutdatedChromium();
    setPageLanguage();
    localizePage();
    document.title = text("timffle_prompt_page_title");
    document
        .getElementById("close-window")!
        .addEventListener("click", () => window.close());
    // A web page can frame this page (extension pages are web accessible);
    // inside a frame it must not offer anything to click.
    if (window.top !== window) {
        document.body.replaceChildren();
        return;
    }
    const id = new URLSearchParams(window.location.search).get("id");
    const view = id ? await fetchView(id) : undefined;
    if (!id || !view) {
        show("expired");
        return;
    }
    if (isHelperPromptView(view)) {
        await runHelperNotice(view);
    } else {
        runQuestion(id, view);
    }
});
