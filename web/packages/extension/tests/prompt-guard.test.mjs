import test from "node:test";
import assert from "node:assert/strict";
import { createInputGuard, isAllow } from "../src/prompt-guard.ts";

const MS = 700;
const pointer = { isTrusted: true, detail: 1 };
const keyboard = { isTrusted: true, detail: 0 };

/** The window appears at t = 0; `t` is when things happen after that. */
function window() {
    const guard = createInputGuard(MS);
    guard.arm(0);
    return guard;
}
/** A deliberate mouse click: the pointer arrives, presses and lets go. */
function mouseClick(guard, choice, button, t) {
    guard.pointerMoved(button, t - 30);
    guard.pressed(button, "mouse", t - 10);
    return guard.accepts(choice, button, pointer, t);
}

test("the choices that allow are exactly the two allow answers", () => {
    assert.deepEqual(
        ["allow-once", "allow-always", "deny-once", "deny-always"].map(isAllow),
        [true, true, false, false],
    );
});

test("nothing counts for a moment after the window appeared", () => {
    const guard = window();
    assert.equal(guard.ready(MS - 1), false);
    assert.equal(guard.ready(MS), true);
    assert.equal(mouseClick(guard, "allow-once", "a", MS - 1), false);
    // The same click a moment later counts.
    assert.equal(mouseClick(guard, "allow-once", "a", MS + 50), true);
});

test("a click made by a script never counts", () => {
    const guard = window();
    guard.pointerMoved("a", MS + 10);
    guard.pressed("a", "mouse", MS + 20);
    assert.equal(
        guard.accepts(
            "deny-once",
            "a",
            { isTrusted: false, detail: 1 },
            MS + 30,
        ),
        false,
    );
});

test("a press that began before the moment passed does not count when it ends after", () => {
    const guard = window();
    // A key held down while the window appeared, let go of a moment later.
    guard.pressed("deny", "key", 400);
    assert.equal(guard.accepts("deny-once", "deny", keyboard, MS + 200), false);
    // Likewise for the mouse button.
    guard.pointerMoved("allow", 500);
    guard.pressed("allow", "mouse", 600);
    assert.equal(
        guard.accepts("allow-once", "allow", pointer, MS + 200),
        false,
    );
    // A click without any press (script-like) does not count either.
    assert.equal(guard.accepts("deny-once", "deny", pointer, MS + 300), false);
});

test("keys can refuse but never allow", () => {
    const guard = window();
    for (const choice of ["deny-once", "deny-always"]) {
        guard.pressed("b", "key", MS + 10);
        assert.equal(guard.accepts(choice, "b", keyboard, MS + 20), true);
    }
    for (const choice of ["allow-once", "allow-always"]) {
        // Tab to the button, then Enter or Space: the keys of a game's login.
        guard.pointerMoved("b", MS + 5);
        guard.pressed("b", "key", MS + 10);
        assert.equal(guard.accepts(choice, "b", keyboard, MS + 20), false);
        // Not even with a click detail the browser would not give.
        guard.pressed("b", "key", MS + 10);
        assert.equal(guard.accepts(choice, "b", pointer, MS + 20), false);
    }
});

test("allowing needs the pointer to have moved over that very button after the moment passed", () => {
    const guard = window();
    // Resting where the button appeared (or moving before the moment passed) is not enough.
    guard.pointerMoved("allow", MS - 100);
    guard.pressed("allow", "mouse", MS + 10);
    assert.equal(
        guard.accepts("allow-always", "allow", pointer, MS + 20),
        false,
    );
    // Moving over a different button does not license this one.
    guard.pointerMoved("deny", MS + 30);
    guard.pressed("allow", "mouse", MS + 40);
    assert.equal(
        guard.accepts("allow-always", "allow", pointer, MS + 50),
        false,
    );
    // Moving over it does.
    guard.pointerMoved("allow", MS + 60);
    guard.pressed("allow", "mouse", MS + 70);
    assert.equal(
        guard.accepts("allow-always", "allow", pointer, MS + 80),
        true,
    );
    // Refusing does not need the pointer to move first.
    guard.pressed("deny", "mouse", MS + 90);
    assert.equal(guard.accepts("deny-once", "deny", pointer, MS + 100), true);
});

test("a tap on a touch screen has no hover and still counts", () => {
    const guard = window();
    guard.pressed("allow", "touch", MS + 10);
    assert.equal(guard.accepts("allow-once", "allow", pointer, MS + 20), true);
    // Before the moment it does not.
    guard.pressed("allow", "touch", MS - 50);
    assert.equal(guard.accepts("allow-once", "allow", pointer, MS - 40), false);
});

test("losing the focus disarms; getting it back starts the moment again", () => {
    const guard = window();
    assert.equal(mouseClick(guard, "allow-once", "a", MS + 100), true);
    guard.disarm();
    assert.equal(guard.ready(MS + 150), false);
    assert.equal(mouseClick(guard, "allow-once", "a", MS + 200), false);
    // The window is clicked to bring it back: that click is the focus, not an answer.
    guard.arm(MS + 300);
    assert.equal(mouseClick(guard, "deny-once", "a", MS + 400), false);
    assert.equal(mouseClick(guard, "deny-once", "a", MS + 300 + MS + 50), true);
});

test("an accepted press is used up: the same press cannot answer twice", () => {
    const guard = window();
    guard.pressed("a", "mouse", MS + 10);
    assert.equal(guard.accepts("deny-once", "a", pointer, MS + 20), true);
    assert.equal(guard.accepts("deny-once", "a", pointer, MS + 30), false);
});

test("the window never armed counts nothing", () => {
    const guard = createInputGuard(MS);
    assert.equal(guard.ready(10_000), false);
    guard.pressed("a", "mouse", 10_000);
    assert.equal(guard.accepts("deny-once", "a", pointer, 10_010), false);
});
