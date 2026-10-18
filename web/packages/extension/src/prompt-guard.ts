/**
 * When a click or key press in the question window counts as an answer.
 *
 * The question can pop up while the visitor is clicking or typing in the game,
 * and a page can guess where the buttons will land (the window opens centred
 * over its own). Input that was not clearly meant for the question must not
 * answer it, least of all with "allow":
 *
 *  - nothing counts for a moment after the window appeared or got focus, and
 *    not at all while it has no focus;
 *  - a press has to begin after that moment, not only end after it (a key held
 *    down when the window appeared and let go of a moment later is not a click);
 *  - "allow" needs a pointer: keyboard activation (Tab, Enter, Space) never
 *    allows, so keys typed into the game cannot, while "deny" works with any
 *    input;
 *  - with a mouse or pen the pointer must have moved over that button after
 *    the moment passed; a pointer that merely rests where the button appeared
 *    does not count.
 */
import type { PromptChoice } from "./socket-prompt";

/** How the press that led to a click began. */
export type PressKind = "mouse" | "pen" | "touch" | "key";

export interface ClickEvidence {
    /** `event.isTrusted`: made by the visitor's input, not by a script. */
    isTrusted: boolean;
    /** `MouseEvent.detail`: 0 for keyboard activation and script clicks. */
    detail: number;
}

export interface InputGuard {
    /** The window appeared or got focus: input is ignored for a moment. */
    arm(now: number): void;
    /** The window lost focus: nothing counts until it is armed again. */
    disarm(): void;
    /** Whether input counts at all right now. */
    ready(now: number): boolean;
    /** A pointer moved over a button. */
    pointerMoved(button: string, now: number): void;
    /** A press (pointer button, Enter or Space) began on a button. */
    pressed(button: string, kind: PressKind, now: number): void;
    /** Whether the click that has just happened on this button is a deliberate answer. */
    accepts(
        choice: PromptChoice,
        button: string,
        click: ClickEvidence,
        now: number,
    ): boolean;
}

export function isAllow(choice: PromptChoice): boolean {
    return choice === "allow-once" || choice === "allow-always";
}

export function createInputGuard(ignoreMs: number): InputGuard {
    /** Input counts from this time on; undefined while the window has no focus. */
    let armedFrom: number | undefined;
    const moved = new Map<string, number>();
    const presses = new Map<string, { at: number; kind: PressKind }>();
    return {
        arm(now) {
            armedFrom = now + ignoreMs;
            moved.clear();
            presses.clear();
        },
        disarm() {
            armedFrom = undefined;
            moved.clear();
            presses.clear();
        },
        ready: (now) => armedFrom !== undefined && now >= armedFrom,
        pointerMoved(button, now) {
            moved.set(button, now);
        },
        pressed(button, kind, now) {
            presses.set(button, { at: now, kind });
        },
        accepts(choice, button, click, now) {
            if (
                !click.isTrusted ||
                armedFrom === undefined ||
                now < armedFrom
            ) {
                return false;
            }
            // The press must have begun after the moment passed.
            const press = presses.get(button);
            presses.delete(button);
            if (!press || press.at < armedFrom) {
                return false;
            }
            if (!isAllow(choice)) {
                return true;
            }
            // "Allow" is a pointer click, never a key.
            if (press.kind === "key" || click.detail < 1) {
                return false;
            }
            if (press.kind === "touch") {
                return true;
            }
            const movedAt = moved.get(button);
            return movedAt !== undefined && movedAt >= armedFrom;
        },
    };
}
