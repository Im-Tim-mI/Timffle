/**
 * The question window: "this website wants to use sockets". It runs in a
 * window of its own, so a web page can neither cover it nor click it.
 */
import { enableBrowserOnOutdatedChromium, setPageLanguage } from "./utils";
import {
    PROMPT_ANSWER_REQUEST,
    PROMPT_GET_REQUEST,
    PROMPT_PORT_NAME,
    PROMPT_CHOICES,
} from "./socket-prompt";
import type { PromptChoice, PromptView } from "./socket-prompt";

/**
 * Clicks and keys in this long after the window appeared (or got focus) are
 * ignored: the question can pop up while the visitor is clicking or typing in
 * the game, and that input is not an answer.
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
        const embedded = document.getElementById("prompt-embedded")!;
        embedded.textContent = `出現在這個頁面中 / Embedded in a page of: ${view.embeddedIn}`;
        embedded.hidden = false;
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
    let armedAt = 0;
    let answering = false;
    let waiting: ReturnType<typeof setTimeout> | undefined;
    // The buttons stay focusable (the safe one has the focus) but do nothing
    // for a moment; the dimming tells the visitor why.
    const arm = () => {
        armedAt = Date.now() + IGNORE_INPUT_MS;
        document.body.dataset["wait"] = "1";
        clearTimeout(waiting);
        waiting = setTimeout(() => {
            delete document.body.dataset["wait"];
        }, IGNORE_INPUT_MS);
    };
    arm();
    window.addEventListener("focus", arm);
    document.addEventListener("keydown", (event) => {
        if (event.key === "Escape") {
            // Closing the window refuses for this visit.
            window.close();
        }
    });

    for (const button of buttons) {
        button.addEventListener("click", async (event) => {
            const choice = button.dataset["choice"] as PromptChoice | undefined;
            if (
                !event.isTrusted ||
                answering ||
                Date.now() < armedAt ||
                !choice ||
                !PROMPT_CHOICES.includes(choice)
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
