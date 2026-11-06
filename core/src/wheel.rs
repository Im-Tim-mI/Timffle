//! Timffle: turns the wheel input that browsers and windowing systems report
//! into Flash Player's whole-line `MouseEvent.delta`.
//!
//! Flash Player reports one `mouseWheel` event per wheel notch with `delta` =
//! the system's lines per notch (3 by default on Windows; a TextField scrolls
//! that many lines), always a whole number. Frontends see two very different
//! kinds of input:
//!
//! - **Wheel notches** (an ordinary mouse wheel): a few large, discrete steps.
//!   Each notch becomes [`LINES_PER_NOTCH`] lines, like Flash.
//! - **Smooth scrolling** (trackpads, Magic Mouse, high-resolution wheels,
//!   touchpads): a stream of small pixel amounts, ~60 per second, with
//!   momentum after the finger lifts. Converting each one on its own either
//!   rounds them all to 0 or makes every tiny movement a full Flash event, so
//!   the pixels are accumulated and an event goes out only once they add up
//!   to a whole line ([`PIXELS_PER_LINE`]).
//!
//! Browsers report both as pixels (`deltaMode` 0) in Chromium and Safari.
//! [`WheelAccumulator::classify_pixels`] tells them apart with the legacy
//! `wheelDeltaY`: Chromium and Safari set it to 120 per notch for a wheel
//! (measured: Chrome 155 on Linux sends `deltaY` 120 / `wheelDeltaY` -120 per
//! notch and 240 / -240 for two notches merged), while smooth scrolling gives
//! arbitrary values. Once a gesture is smooth it stays smooth until it pauses,
//! so a smooth delta that happens to be a multiple of 120 is not mistaken for
//! a notch.

use crate::events::MouseWheelDelta;

/// Lines per wheel notch (Flash Player on Windows with the default setting).
pub const LINES_PER_NOTCH: f64 = 3.0;

/// Pixels of smooth scrolling per Flash line. Chromium on macOS counts 40 px
/// per line, and on Linux a notch is 120 px = 3 lines, so smooth scrolling
/// moves Flash content about as far as a wheel moving the same distance.
pub const PIXELS_PER_LINE: f64 = 40.0;

/// A pause longer than this ends a gesture: the unfinished line is dropped and
/// the next input is classified afresh.
pub const GESTURE_GAP_MS: f64 = 300.0;

/// One piece of wheel input, positive = away from the user (scroll up), the
/// sign Flash uses for `MouseEvent.delta`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum WheelInput {
    /// Wheel notches (winit `LineDelta`, or a browser notch).
    Notches(f64),
    /// Lines already scaled by the system (Firefox `DOM_DELTA_LINE`, which is
    /// 3 per notch on Windows and Linux).
    Lines(f64),
    /// Smooth-scrolling pixels.
    Pixels(f64),
}

/// Per-player wheel state. Feed every wheel event to [`Self::push`]; it
/// returns the Flash event to send, if any.
#[derive(Debug, Default)]
pub struct WheelAccumulator {
    /// Fraction of a line not yet sent.
    pending: f64,
    /// Time of the last input, in milliseconds.
    last_time: Option<f64>,
    /// The current gesture was recognised as smooth scrolling.
    smooth_gesture: bool,
    /// Whether the last event sent in this gesture was handled by the movie.
    last_handled: bool,
}

impl WheelAccumulator {
    pub fn new() -> Self {
        Self::default()
    }

    fn in_gesture(&self, time_ms: f64) -> bool {
        self.last_time
            .is_some_and(|last| time_ms >= last && time_ms - last <= GESTURE_GAP_MS)
    }

    /// Classifies a browser pixel delta (`deltaMode` 0). `pixels` is positive
    /// for scrolling up (`-deltaY`); `legacy_wheel_delta` is `wheelDeltaY`
    /// when the browser has it.
    pub fn classify_pixels(
        &mut self,
        pixels: f64,
        legacy_wheel_delta: Option<f64>,
        time_ms: f64,
    ) -> WheelInput {
        let smooth_continues = self.smooth_gesture && self.in_gesture(time_ms);
        let notches = legacy_wheel_delta
            .filter(|legacy| {
                *legacy != 0.0
                    && legacy.fract() == 0.0
                    && legacy % 120.0 == 0.0
                    && legacy.signum() == pixels.signum()
            })
            .map(|legacy| legacy / 120.0);
        match notches {
            Some(notches) if !smooth_continues => WheelInput::Notches(notches),
            _ => {
                if pixels != 0.0 {
                    self.smooth_gesture = true;
                }
                WheelInput::Pixels(pixels)
            }
        }
    }

    /// Adds one input. Returns the whole lines to send to the movie now, or
    /// `None` while a smooth gesture has not yet added up to a line.
    pub fn push(&mut self, input: WheelInput, time_ms: f64) -> Option<MouseWheelDelta> {
        let lines = match input {
            WheelInput::Notches(notches) => notches * LINES_PER_NOTCH,
            WheelInput::Lines(lines) => lines,
            WheelInput::Pixels(pixels) => pixels / PIXELS_PER_LINE,
        };
        if !lines.is_finite() {
            return None;
        }

        let continues = self.in_gesture(time_ms);
        self.last_time = Some(time_ms);
        if !continues {
            self.pending = 0.0;
            self.last_handled = false;
            if !matches!(input, WheelInput::Pixels(_)) {
                self.smooth_gesture = false;
            }
        }
        if lines == 0.0 {
            return None;
        }
        // Reversing direction starts over instead of first undoing the
        // unsent fraction.
        if self.pending != 0.0 && self.pending.signum() != lines.signum() {
            self.pending = 0.0;
        }

        self.pending += lines;
        // The epsilon keeps ten 0.1-line steps from summing to 0.999….
        let whole = (self.pending + self.pending.signum() * 1e-9).trunc();
        if whole == 0.0 {
            return None;
        }
        self.pending -= whole;
        Some(MouseWheelDelta::Lines(whole))
    }

    /// Records whether the movie handled the event [`Self::push`] returned.
    pub fn set_handled(&mut self, handled: bool) {
        self.last_handled = handled;
    }

    /// For input that did not produce an event yet: whether the movie handled
    /// the previous event of the same gesture (so the page should not scroll
    /// either).
    pub fn gesture_handled(&self, time_ms: f64) -> bool {
        self.last_handled && self.in_gesture(time_ms)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn lines(delta: Option<MouseWheelDelta>) -> Option<f64> {
        delta.map(MouseWheelDelta::lines)
    }

    #[test]
    fn notches_are_three_lines() {
        let mut acc = WheelAccumulator::new();
        assert_eq!(lines(acc.push(WheelInput::Notches(1.0), 0.0)), Some(3.0));
        assert_eq!(lines(acc.push(WheelInput::Notches(-2.0), 50.0)), Some(-6.0));
        assert_eq!(lines(acc.push(WheelInput::Lines(3.0), 1000.0)), Some(3.0));
    }

    #[test]
    fn chrome_notch_is_detected_from_wheel_delta() {
        let mut acc = WheelAccumulator::new();
        // Linux Chrome: deltaY 120, wheelDeltaY -120 per notch (scroll down).
        let input = acc.classify_pixels(-120.0, Some(-120.0), 0.0);
        assert_eq!(input, WheelInput::Notches(-1.0));
        assert_eq!(lines(acc.push(input, 0.0)), Some(-3.0));
        // Windows Chrome: deltaY -100, wheelDeltaY 120 (scroll up).
        let input = acc.classify_pixels(100.0, Some(120.0), 2000.0);
        assert_eq!(input, WheelInput::Notches(1.0));
        // Two notches merged into one event.
        let input = acc.classify_pixels(-240.0, Some(-240.0), 4000.0);
        assert_eq!(input, WheelInput::Notches(-2.0));
    }

    #[test]
    fn trackpad_accumulates_to_whole_lines() {
        let mut acc = WheelAccumulator::new();
        let mut sent = 0.0;
        let mut events = 0;
        // 100 small deltas of 4 px at 60 Hz = 400 px = 10 lines.
        for i in 0..100 {
            let t = f64::from(i) * 16.0;
            let input = acc.classify_pixels(4.0, Some(12.0), t);
            if let Some(delta) = acc.push(input, t) {
                sent += delta.lines();
                events += 1;
            }
        }
        assert_eq!(sent, 10.0);
        assert_eq!(events, 10);
    }

    #[test]
    fn smooth_gesture_stays_smooth_on_multiple_of_120() {
        let mut acc = WheelAccumulator::new();
        let input = acc.classify_pixels(10.0, Some(30.0), 0.0);
        assert_eq!(input, WheelInput::Pixels(10.0));
        acc.push(input, 0.0);
        // macOS Chrome: wheelDeltaY = 3 × deltaY, so 40 px gives 120.
        let input = acc.classify_pixels(40.0, Some(120.0), 16.0);
        assert_eq!(input, WheelInput::Pixels(40.0));
        // After a pause a notch is a notch again.
        let input = acc.classify_pixels(40.0, Some(120.0), 1000.0);
        assert_eq!(input, WheelInput::Notches(1.0));
    }

    #[test]
    fn fraction_is_dropped_after_pause_and_on_reverse() {
        let mut acc = WheelAccumulator::new();
        assert_eq!(acc.push(WheelInput::Pixels(30.0), 0.0), None);
        // A pause drops the 30 px.
        assert_eq!(acc.push(WheelInput::Pixels(30.0), 1000.0), None);
        // Reversing drops them too.
        assert_eq!(acc.push(WheelInput::Pixels(-30.0), 1016.0), None);
        assert_eq!(
            lines(acc.push(WheelInput::Pixels(-30.0), 1032.0)),
            Some(-1.0)
        );
    }

    #[test]
    fn handled_state_lasts_for_the_gesture() {
        let mut acc = WheelAccumulator::new();
        assert!(acc.push(WheelInput::Pixels(50.0), 0.0).is_some());
        acc.set_handled(true);
        assert_eq!(acc.push(WheelInput::Pixels(10.0), 16.0), None);
        assert!(acc.gesture_handled(16.0));
        assert!(!acc.gesture_handled(2000.0));
    }
}
