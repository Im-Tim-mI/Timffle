/**
 * The extension's own window for two things a web page can cause: the
 * question "this website wants to use sockets" and the notice "install the
 * socket helper first" (the page needed a TCP connection and the helper is not
 * there). It runs in a window of its own, so a web page can neither cover it
 * nor click it.
 */
import { enableBrowserOnOutdatedChromium, setPageLanguage } from "./utils";
import { fillRich, localizePage, text } from "./i18n";
import {
    PROMPT_ANSWER_REQUEST,
    PROMPT_GET_REQUEST,
    PROMPT_PORT_NAME,
    PROMPT_CHOICES,
} from "./socket-prompt";
import type { PromptChoice, PromptView } from "./socket-prompt";
import { isHelperPromptView } from "./helper-prompt";
import type { HelperPromptView } from "./helper-prompt";
import { bindHelperDownload, installStep } from "./helper-download";
import { queryHelper } from "./helper-status";
import {
    HELPER_WAIT_MAX_POLL_MS,
    showHelperReady,
    waitForHelper,
} from "./helper-wait";
import { HELPER_CONTINUE_REQUEST } from "./socket-bridge-protocol";
import { createInputGuard } from "./prompt-guard";
import type { InputGuard, PressKind } from "./prompt-guard";
import { lanHostOf } from "./socket-lan";

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
 *
 * The moment is for a window that has just appeared. `refocusMs` is how long
 * input is ignored when the window gets the focus back after it has been in
 * front for that long once: the question keeps the whole moment (its answers
 * decide what a website may do), the install window does not make a visitor
 * who has just come back from the install page click twice. Escape closes
 * the question at once (that refuses); `escapeWaits` makes it wait for the
 * moment too, for a window that is shown once per page and must not be lost
 * to a key meant for the game.
 */
function guardInput({
    refocusMs = IGNORE_INPUT_MS,
    escapeWaits = false,
}: { refocusMs?: number; escapeWaits?: boolean } = {}): {
    guard: InputGuard;
    watch: (el: HTMLElement) => void;
} {
    const guard = createInputGuard(IGNORE_INPUT_MS);
    let waiting: ReturnType<typeof setTimeout> | undefined;
    /** The window has been in front, with the visitor able to see it, for the whole moment once. */
    let seen = false;
    const arm = () => {
        const wait = seen ? refocusMs : IGNORE_INPUT_MS;
        guard.arm(Date.now() - (IGNORE_INPUT_MS - wait));
        document.body.dataset["wait"] = "1";
        clearTimeout(waiting);
        waiting = setTimeout(() => {
            seen = true;
            delete document.body.dataset["wait"];
        }, wait);
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
        // A key that was held down for the game keeps repeating into the
        // window that has just taken the focus; a repeat is not a press.
        if (
            event.key === "Escape" &&
            !event.repeat &&
            (!escapeWaits || guard.ready(Date.now()))
        ) {
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
                // Enter clicks on this press, Space when the key is let go. A
                // repeat is the same press: it began before, perhaps in the game.
                if (
                    !event.repeat &&
                    (event.key === "Enter" || event.key === " ")
                ) {
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

/**
 * "Install the socket helper first": what is wrong, a button that downloads
 * the installer and how to run it, the way to the others. Then the window
 * waits for the helper and offers to continue: the background reloads the
 * game page and closes the window.
 */
async function runHelperNotice(id: string, view: HelperPromptView) {
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
    // This window asks nothing: its title bar and the task switcher say what it is.
    document.title = text("timffle_helper_prompt_title");
    const download = document.getElementById("helper-download")!;
    const label = document.getElementById("helper-for")!;
    const more = document.getElementById("helper-more")!;
    const step = document.getElementById("helper-step")!;
    const wait = document.getElementById("helper-wait")!;
    const close = document.getElementById("helper-close")!;
    const proceed = document.getElementById(
        "helper-continue",
    ) as HTMLButtonElement;
    // Not offered before it is known what it would download.
    download.hidden = true;
    show("helper");
    keepBackgroundAlive();
    const { guard, watch } = guardInput({ refocusMs: 0, escapeWaits: true });
    const counts = (control: HTMLElement, event: MouseEvent) =>
        guard.accepts(
            "action",
            control.id,
            { isTrusted: event.isTrusted, detail: event.detail },
            Date.now(),
        );
    for (const control of [download, more, close, proceed]) {
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
    let continuing = false;
    proceed.addEventListener("click", (event) => {
        if (continuing || proceed.disabled || !counts(proceed, event)) {
            return;
        }
        continuing = true;
        // Only the id of this window: the background knows the game's tab,
        // reloads it if it still shows that game, and closes this window.
        void browser.runtime
            .sendMessage({ type: HELPER_CONTINUE_REQUEST, id })
            .then(
                (reloaded: unknown) => reloaded === true,
                () => false,
            )
            .then((reloaded) => {
                if (!reloaded) {
                    // Nothing to continue: this window's request has ended.
                    show("expired");
                }
            });
    });
    // It looks by itself whether the helper is there now, and at once when
    // the visitor comes back to the window after running the installer.
    // Each look starts a helper process, so it looks only while the window is
    // shown and, while the helper stays missing, less and less often.
    // Once it is there, the line at the top says so instead of what was wrong.
    const waiting = waitForHelper({
        query: queryHelper,
        minVersion: view.minVersion,
        maxPollMs: HELPER_WAIT_MAX_POLL_MS,
        active: () => document.visibilityState === "visible",
        ready: (version) =>
            showHelperReady(
                { problem: message, wait },
                proceed,
                version,
                download,
            ),
    });
    window.addEventListener("focus", () => waiting.check());
    document.addEventListener("visibilitychange", () => {
        if (document.visibilityState === "visible") {
            waiting.check();
        }
    });
    window.addEventListener("pagehide", () => waiting.stop());
    close.focus();
    // The system is worked out before the button is offered, so it already knows what it will download.
    const installer = await bindHelperDownload({
        button: download,
        label,
        accepts: (event) => counts(download, event),
        // The wait line says already what comes after the download.
        started: () => {},
    });
    // A system without an installer (or one the browser did not describe) is sent to the page that lists them all.
    download.hidden = installer === undefined;
    if (installer !== undefined) {
        fillRich(step, installStep(installer));
        step.hidden = false;
    }
}

/** "This website wants to use sockets": four ways to answer. */
function runQuestion(id: string, view: PromptView) {
    showOrigin(view, {
        origin: "prompt-origin",
        embedded: "prompt-embedded",
        embeddedOrigin: "prompt-embedded-origin",
    });
    // A website served from an address on the local network may also connect
    // back to that address: the usual text says the local network is out of reach.
    const lan = lanHostOf(view.origin);
    if (lan !== undefined) {
        document.getElementById("prompt-what")!.textContent = text(
            "timffle_prompt_what_lan",
            lan,
        );
    }
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
        await runHelperNotice(id, view);
    } else {
        runQuestion(id, view);
    }
});
