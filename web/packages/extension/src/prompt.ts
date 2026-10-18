/**
 * The question window: "this website wants to use sockets". It runs in a
 * window of its own, so a web page can neither cover it nor click it.
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
import { createInputGuard } from "./prompt-guard";
import type { PressKind } from "./prompt-guard";

/**
 * Clicks and keys in this long after the window appeared (or got focus) are
 * ignored: the question can pop up while the visitor is clicking or typing in
 * the game, and that input is not an answer. See prompt-guard.ts for the rest
 * of what has to be true before input counts.
 */
const IGNORE_INPUT_MS = 700;
const KEEP_ALIVE_MS = 10000;

function isPromptView(value: unknown): value is PromptView {
    return (
        typeof value === "object" &&
        value !== null &&
        typeof (value as PromptView).origin === "string"
    );
}

/** The window may load a moment before the background knows it, so ask a few times. */
async function fetchView(id: string): Promise<PromptView | undefined> {
    for (let attempt = 0; attempt < 8; attempt++) {
        try {
            const reply: unknown = await browser.runtime.sendMessage({
                type: PROMPT_GET_REQUEST,
                id,
            });
            if (isPromptView(reply)) {
                return reply;
            }
        } catch {
            /* The background is starting; try again. */
        }
        await new Promise((resolve) => setTimeout(resolve, 150));
    }
    return undefined;
}

function show(id: string) {
    for (const name of ["prompt", "expired"]) {
        document.getElementById(name)!.hidden = name !== id;
    }
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
    document.getElementById("prompt-origin")!.textContent = view.origin;
    if (view.embeddedIn !== undefined) {
        document.getElementById("prompt-embedded-origin")!.textContent =
            view.embeddedIn;
        document.getElementById("prompt-embedded")!.hidden = false;
    }
    show("prompt");

    // Keeps the background alive while the question is open: it holds the
    // pages' connection attempts, and a stopped service worker drops them.
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
        /* Without the port the question still works while the worker is awake. */
    }

    const buttons = Array.from(
        document.querySelectorAll<HTMLButtonElement>("button[data-choice]"),
    );
    const error = document.getElementById("prompt-error")!;
    const guard = createInputGuard(IGNORE_INPUT_MS);
    let answering = false;
    let waiting: ReturnType<typeof setTimeout> | undefined;
    // The buttons stay focusable (the safe one has the focus) but do nothing
    // for a moment, and while the window has no focus; the dimming tells the
    // visitor why.
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
            // Closing the window refuses for this visit.
            window.close();
        }
    });

    for (const button of buttons) {
        const key = button.id;
        button.addEventListener("pointermove", () => {
            guard.pointerMoved(key, Date.now());
        });
        button.addEventListener("pointerdown", (event) => {
            const kind: PressKind =
                event.pointerType === "touch"
                    ? "touch"
                    : event.pointerType === "pen"
                      ? "pen"
                      : "mouse";
            guard.pressed(key, kind, Date.now());
        });
        button.addEventListener("keydown", (event) => {
            // Enter clicks on this press, Space when the key is let go.
            if (event.key === "Enter" || event.key === " ") {
                guard.pressed(key, "key", Date.now());
            }
        });
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
});
