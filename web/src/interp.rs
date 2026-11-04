//! Timffle: adaptive frame interpolation ("smooth motion") control and frame statistics.
//!
//! The core draws extra pictures between movie frames when `Player::frame_interpolation` is on
//! (see `ruffle_core::display_object::interp`). This module decides, on every animation frame,
//! whether such a picture is wanted now (so the picture rate follows a target), moves the target
//! up and down in the automatic modes, and keeps the numbers the fps overlay shows.
//!
//! Modes (the extension's 補幀 menu):
//! - `Off`: no extra pictures; the movie's own frame rate.
//! - `Auto`: target moves between 144 / 120 / 60 / 30 / off, one step at a time, evaluated once a
//!   second: down fast (2 bad periods), up slowly (10 good periods), no step up within 15 s of a
//!   step down, a tier that fails within 5 s of being reached is locked for 60 s, and "off" retries
//!   30 every 30 s.
//! - `Unlimited`: same rules, but the target moves by ±10 % with no tier list; floor = the movie's
//!   frame rate.
//! - `Target(fps)`: fixed; never moved. The overlay says when it is not reached.
//!
//! Every mode: the effective target never exceeds the display's refresh rate (estimated from
//! requestAnimationFrame intervals), and no extra pictures are drawn when the target is at or
//! below the movie's own frame rate.
//!
//! A "dropped frame" is an animation-frame interval longer than 1.5 refresh intervals. The
//! "interpolation cost" is the time `Player::render` took for the extra pictures.

use std::collections::VecDeque;

const TIERS: [f64; 4] = [144.0, 120.0, 60.0, 30.0];
const TIER_OFF: usize = TIERS.len();
const PERIOD_MS: f64 = 1000.0;
const BAD_PERIODS_TO_STEP_DOWN: u32 = 2;
const GOOD_PERIODS_TO_STEP_UP: u32 = 10;
const NO_UP_AFTER_DOWN_MS: f64 = 15_000.0;
const QUICK_FAIL_MS: f64 = 5_000.0;
const LOCK_MS: f64 = 60_000.0;
const OFF_RETRY_MS: f64 = 30_000.0;
const BELOW_TARGET_HINT_MS: f64 = 30_000.0;
const STATS_WINDOW_MS: f64 = 500.0;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum InterpMode {
    Off,
    Auto,
    Unlimited,
    Target(f64),
}

impl InterpMode {
    /// Parses the config value: `off`/`false`, `auto`/`true`, `unlimited`, or a number of fps.
    pub fn parse(value: &str) -> Self {
        match value.trim().to_ascii_lowercase().as_str() {
            "off" | "false" | "0" | "" => Self::Off,
            "auto" | "true" | "on" => Self::Auto,
            "unlimited" | "max" => Self::Unlimited,
            other => match other.trim_end_matches("fps").trim().parse::<f64>() {
                Ok(fps) if fps.is_finite() && fps >= 1.0 => Self::Target(fps.clamp(1.0, 1000.0)),
                _ => Self::Auto,
            },
        }
    }

    pub fn is_off(self) -> bool {
        matches!(self, Self::Off)
    }

    fn name(self) -> &'static str {
        match self {
            Self::Off => "off",
            Self::Auto => "auto",
            Self::Unlimited => "unlimited",
            Self::Target(_) => "fixed",
        }
    }
}

#[derive(Default)]
struct Period {
    rafs: u32,
    dropped: u32,
    interp_renders: u32,
    interp_ms: f64,
}

pub struct InterpControl {
    mode: InterpMode,
    /// Animation-frame intervals of the last ~2 s, for the refresh-rate estimate.
    raf_deltas: VecDeque<f64>,
    refresh_hz: f64,
    /// Automatic mode: index into `TIERS`, or `TIER_OFF`.
    tier: usize,
    /// Unlimited mode: the current target.
    unlimited_target: f64,
    period_start: f64,
    period: Period,
    bad_periods: u32,
    good_periods: u32,
    last_step_down: f64,
    last_step_up: f64,
    locked_tier: Option<(usize, f64)>,
    off_since: f64,
    /// When the next extra picture is due (a phase accumulator, so the average rate follows the
    /// target instead of rounding up to the next animation frame).
    next_interp_due: f64,
    started: bool,
    /// Animation-frame intervals still to ignore for the display-rate estimate (see `set_mode`).
    hold_samples: u32,
    // Overlay numbers.
    win_start: f64,
    win_renders: u64,
    renders_at_win_start: u64,
    fps: f64,
    drop_pct: f64,
    interp_ms: f64,
    below_target_since: Option<f64>,
    paused_by_load: bool,
}

pub struct RenderDecision {
    /// Whether an extra (interpolated) picture is wanted on this animation frame.
    pub interpolate: bool,
}

impl InterpControl {
    pub fn new(mode: InterpMode) -> Self {
        Self {
            mode,
            raf_deltas: VecDeque::with_capacity(128),
            refresh_hz: 60.0,
            tier: usize::MAX,
            unlimited_target: 0.0,
            period_start: 0.0,
            period: Period::default(),
            bad_periods: 0,
            good_periods: 0,
            last_step_down: f64::NEG_INFINITY,
            last_step_up: f64::NEG_INFINITY,
            locked_tier: None,
            off_since: f64::NEG_INFINITY,
            next_interp_due: f64::NEG_INFINITY,
            started: false,
            hold_samples: 0,
            win_start: 0.0,
            win_renders: 0,
            renders_at_win_start: 0,
            fps: 0.0,
            drop_pct: 0.0,
            interp_ms: 0.0,
            below_target_since: None,
            paused_by_load: false,
        }
    }

    pub fn set_mode(&mut self, mode: InterpMode) {
        if self.mode != mode {
            self.mode = mode;
            self.started = false;
            self.tier = usize::MAX;
            self.unlimited_target = 0.0;
            self.bad_periods = 0;
            self.good_periods = 0;
            self.locked_tier = None;
            self.below_target_since = None;
            self.paused_by_load = false;
            self.next_interp_due = f64::NEG_INFINITY;
            // While nothing was drawn the animation frames may have slowed down (a hidden or
            // idle page); measure the display again from scratch.
            self.raf_deltas.clear();
            self.refresh_hz = 60.0;
            // The browser slows the animation frames of a page that draws nothing new; only
            // once extra pictures are drawn again does the loop reach the display rate.
            // Measure after that, not during the first two seconds.
            self.hold_samples = 120;
        }
    }

    fn refresh_interval(&self) -> f64 {
        1000.0 / self.refresh_hz.max(1.0)
    }

    /// The highest tier at or below the display's refresh rate.
    fn start_tier(&self) -> usize {
        TIERS
            .iter()
            .position(|&t| t <= self.refresh_hz + 1.0)
            .unwrap_or(TIERS.len() - 1)
    }

    /// The target the mode asks for right now (before the display cap); 0 = none.
    fn requested_target(&self) -> f64 {
        match self.mode {
            InterpMode::Off => 0.0,
            InterpMode::Auto => {
                if self.tier >= TIER_OFF {
                    0.0
                } else {
                    TIERS[self.tier]
                }
            }
            InterpMode::Unlimited => self.unlimited_target,
            InterpMode::Target(fps) => fps,
        }
    }

    /// The target after the display cap.
    pub fn effective_target(&self) -> f64 {
        self.requested_target().min(self.refresh_hz)
    }

    /// Called at the start of every animation frame with the frame timestamp and the time since
    /// the previous one (both ms).
    pub fn on_animation_frame(&mut self, ts: f64, dt: f64) {
        if self.hold_samples > 0 && dt > 0.0 {
            self.hold_samples -= 1;
            // Draw at the assumed 60 Hz meanwhile so the loop can speed up.
            if !self.started {
                self.started = true;
                self.period_start = ts;
                self.win_start = ts;
                match self.mode {
                    InterpMode::Auto => self.tier = self.start_tier(),
                    InterpMode::Unlimited => self.unlimited_target = self.refresh_hz,
                    _ => {}
                }
            }
            return;
        }
        if dt > 0.0 && dt < 1000.0 {
            if self.raf_deltas.len() >= 120 {
                self.raf_deltas.pop_front();
            }
            self.raf_deltas.push_back(dt);
            if self.raf_deltas.len() >= 20 {
                let mut sorted: Vec<f64> = self.raf_deltas.iter().copied().collect();
                sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let median = sorted[sorted.len() / 2];
                if median > 0.5 {
                    // Snap to the usual refresh rates so 16.7 ms reads as 60 Hz.
                    let hz = 1000.0 / median;
                    self.refresh_hz = [30.0, 48.0, 50.0, 60.0, 75.0, 90.0, 100.0, 120.0, 144.0, 165.0, 240.0]
                        .iter()
                        .copied()
                        .find(|&r| (hz - r).abs() <= r * 0.06)
                        .unwrap_or(hz);
                }
            }
            self.period.rafs += 1;
            if dt > self.refresh_interval() * 1.5 {
                self.period.dropped += 1;
            }
        }
        if !self.started && self.raf_deltas.len() >= 20 {
            self.started = true;
            self.period_start = ts;
            self.win_start = ts;
            match self.mode {
                InterpMode::Auto => self.tier = self.start_tier(),
                InterpMode::Unlimited => self.unlimited_target = self.refresh_hz,
                _ => {}
            }
        }
    }

    /// Whether an extra picture is wanted now. `source_fps` is the movie's frame rate.
    pub fn decide(&self, ts: f64, source_fps: f64, background: bool) -> RenderDecision {
        if background || self.mode.is_off() || !self.started {
            return RenderDecision { interpolate: false };
        }
        let target = self.effective_target();
        if target <= source_fps + 0.5 || target <= 0.0 {
            return RenderDecision { interpolate: false };
        }
        RenderDecision {
            interpolate: ts >= self.next_interp_due - 1.0,
        }
    }

    /// Records a picture drawn on this animation frame; `interp_cost_ms` is set for extra pictures.
    pub fn note_render(&mut self, ts: f64, interp_cost_ms: Option<f64>) {
        self.win_renders += 1;
        let target = self.effective_target();
        if !self.started || target <= 0.0 {
            // No target yet (the refresh rate is still being measured, or the automatic mode
            // is off): the next extra picture is due as soon as there is a target. Accumulating
            // here would push the due time a second further out on every movie frame.
            self.next_interp_due = ts;
        } else {
            // Every picture, a movie frame or an extra one, counts towards the target rate.
            let interval = 1000.0 / target;
            // Keep the phase while on time; never schedule more than one interval behind.
            self.next_interp_due = (self.next_interp_due + interval).max(ts - interval + 0.5);
        }
        if let Some(cost) = interp_cost_ms {
            self.period.interp_renders += 1;
            self.period.interp_ms += cost;
        }
    }

    /// Once per animation frame, after drawing: updates the overlay numbers (every 0.5 s) and the
    /// automatic modes (every 1 s). `renders_total` is the core's picture counter.
    pub fn after_frame(&mut self, ts: f64, source_fps: f64, background: bool, renders_total: u64) {
        if !self.started {
            return;
        }
        if ts - self.win_start >= STATS_WINDOW_MS {
            let n = renders_total.saturating_sub(self.renders_at_win_start) as f64;
            self.fps = n * 1000.0 / (ts - self.win_start);
            self.renders_at_win_start = renders_total;
            self.win_start = ts;
            let target = self.effective_target();
            if target > source_fps + 0.5 && self.fps < target * 0.9 {
                self.below_target_since.get_or_insert(ts);
            } else {
                self.below_target_since = None;
            }
        }
        if background {
            // Nothing is drawn; do not judge the device by it.
            self.period = Period::default();
            self.period_start = ts;
            return;
        }
        if ts - self.period_start < PERIOD_MS {
            return;
        }
        let p = std::mem::take(&mut self.period);
        self.period_start = ts;
        self.drop_pct = if p.rafs > 0 {
            100.0 * p.dropped as f64 / p.rafs as f64
        } else {
            0.0
        };
        self.interp_ms = if p.interp_renders > 0 {
            p.interp_ms / p.interp_renders as f64
        } else {
            0.0
        };
        let target = self.effective_target();
        let interval = if target > 0.0 { 1000.0 / target } else { self.refresh_interval() };
        let judged = p.interp_renders > 0 || target <= 0.0;
        if !judged {
            return;
        }
        let bad = self.drop_pct > 5.0 || self.interp_ms > interval * 0.8;
        let good = self.drop_pct < 1.0 && self.interp_ms < interval * 0.5;
        if bad {
            self.bad_periods += 1;
            self.good_periods = 0;
        } else if good {
            self.good_periods += 1;
            self.bad_periods = 0;
        } else {
            self.bad_periods = 0;
            self.good_periods = 0;
        }
        match self.mode {
            InterpMode::Auto => self.adjust_auto(ts, bad),
            InterpMode::Unlimited => self.adjust_unlimited(ts, source_fps),
            _ => {}
        }
    }

    fn adjust_auto(&mut self, ts: f64, bad: bool) {
        if self.tier >= TIER_OFF {
            self.paused_by_load = true;
            // Retry the lowest tier every 30 s.
            if ts - self.off_since >= OFF_RETRY_MS {
                self.tier = TIERS.len() - 1;
                self.last_step_up = ts;
                self.bad_periods = 0;
                self.good_periods = 0;
            }
            return;
        }
        if self.bad_periods >= BAD_PERIODS_TO_STEP_DOWN {
            // A tier that fails right after being reached is locked for a minute.
            if ts - self.last_step_up <= QUICK_FAIL_MS {
                self.locked_tier = Some((self.tier, ts + LOCK_MS));
            }
            self.tier += 1;
            if self.tier >= TIER_OFF {
                self.tier = TIER_OFF;
                self.off_since = ts;
                self.paused_by_load = true;
            }
            self.last_step_down = ts;
            self.bad_periods = 0;
            self.good_periods = 0;
            return;
        }
        if !bad {
            self.paused_by_load = false;
        }
        if self.good_periods >= GOOD_PERIODS_TO_STEP_UP
            && self.tier > 0
            && ts - self.last_step_down >= NO_UP_AFTER_DOWN_MS
        {
            let next = self.tier - 1;
            let locked = matches!(self.locked_tier, Some((t, until)) if t == next && ts < until);
            if !locked && TIERS[next] <= self.refresh_hz + 1.0 {
                self.tier = next;
                self.last_step_up = ts;
            }
            self.good_periods = 0;
        }
    }

    fn adjust_unlimited(&mut self, ts: f64, source_fps: f64) {
        let floor = source_fps.max(1.0);
        if self.bad_periods >= BAD_PERIODS_TO_STEP_DOWN {
            self.unlimited_target = (self.unlimited_target * 0.9).max(floor);
            self.last_step_down = ts;
            self.bad_periods = 0;
            self.good_periods = 0;
            self.paused_by_load = self.unlimited_target <= floor + 0.5;
        } else if self.good_periods >= GOOD_PERIODS_TO_STEP_UP
            && ts - self.last_step_down >= NO_UP_AFTER_DOWN_MS
        {
            self.unlimited_target = (self.unlimited_target * 1.1).min(self.refresh_hz);
            self.last_step_up = ts;
            self.good_periods = 0;
            self.paused_by_load = false;
        }
    }

    /// The numbers for the fps overlay, as JSON.
    pub fn stats_json(&self, ts: f64, source_fps: f64, core: [u32; 8]) -> String {
        let requested = self.requested_target();
        let effective = self.effective_target();
        let state = if self.mode.is_off() {
            "off"
        } else if !self.started {
            "starting"
        } else if matches!(self.mode, InterpMode::Auto) && self.tier >= TIER_OFF {
            "paused"
        } else if requested > 0.0 && requested <= source_fps + 0.5 {
            "source_above"
        } else if requested > self.refresh_hz + 1.0 {
            "capped"
        } else if matches!(self.below_target_since, Some(since) if ts - since >= BELOW_TARGET_HINT_MS)
        {
            "below"
        } else {
            "ok"
        };
        format!(
            "{{\"fps\":{:.1},\"sourceFps\":{:.2},\"mode\":\"{}\",\"target\":{:.0},\"effective\":{:.0},\"refreshHz\":{:.0},\"dropPct\":{:.1},\"interpMs\":{:.2},\"state\":\"{}\",\"pausedByLoad\":{},\"frames\":{},\"changedFrames\":{},\"visibleFrames\":{},\"changed\":{},\"moving\":{},\"visible\":{},\"halfPxFrames\":{},\"onePxFrames\":{}}}",
            self.fps,
            source_fps,
            self.mode.name(),
            requested,
            effective,
            self.refresh_hz,
            self.drop_pct,
            self.interp_ms,
            state,
            self.paused_by_load,
            core[0],
            core[1],
            core[2],
            core[3],
            core[4],
            core[5],
            core[6],
            core[7]
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn warm(c: &mut InterpControl, hz: f64) -> f64 {
        let mut ts = 0.0;
        for _ in 0..30 {
            ts += 1000.0 / hz;
            c.on_animation_frame(ts, 1000.0 / hz);
        }
        ts
    }

    #[test]
    fn parses_modes() {
        assert_eq!(InterpMode::parse("off"), InterpMode::Off);
        assert_eq!(InterpMode::parse("false"), InterpMode::Off);
        assert_eq!(InterpMode::parse("true"), InterpMode::Auto);
        assert_eq!(InterpMode::parse("Auto"), InterpMode::Auto);
        assert_eq!(InterpMode::parse("unlimited"), InterpMode::Unlimited);
        assert_eq!(InterpMode::parse("90"), InterpMode::Target(90.0));
        assert_eq!(InterpMode::parse("144 fps"), InterpMode::Target(144.0));
    }

    #[test]
    fn auto_starts_at_the_display_rate_and_steps_down_then_up() {
        let mut c = InterpControl::new(InterpMode::Auto);
        let mut ts = warm(&mut c, 60.0);
        assert_eq!(c.refresh_hz, 60.0);
        assert_eq!(c.effective_target(), 60.0);
        assert!(c.decide(ts, 24.0, false).interpolate);
        // Two bad seconds (every picture costs 15 ms of a 16.7 ms interval) -> 30.
        for _ in 0..2 {
            for _ in 0..60 {
                ts += 16.7;
                c.on_animation_frame(ts, 16.7);
                c.note_render(ts, Some(15.0));
                c.after_frame(ts, 24.0, false, 0);
            }
        }
        assert_eq!(c.effective_target(), 30.0);
        // No step up within 15 s, then 10 good seconds -> back to 60.
        let mut secs = 0;
        while c.effective_target() < 60.0 && secs < 40 {
            for _ in 0..60 {
                ts += 16.7;
                c.on_animation_frame(ts, 16.7);
                c.note_render(ts, Some(1.0));
                c.after_frame(ts, 24.0, false, 0);
            }
            secs += 1;
        }
        assert!(secs >= 15 && secs <= 30, "took {secs} s");
    }

    #[test]
    fn fixed_target_is_capped_by_the_display_and_skipped_below_the_source() {
        let mut c = InterpControl::new(InterpMode::Target(144.0));
        let ts = warm(&mut c, 60.0);
        assert_eq!(c.effective_target(), 60.0);
        assert!(c.stats_json(ts, 24.0, [0; 8]).contains("\"state\":\"capped\""));
        let mut c = InterpControl::new(InterpMode::Target(30.0));
        let ts = warm(&mut c, 60.0);
        assert!(!c.decide(ts, 60.0, false).interpolate);
        assert!(c.stats_json(ts, 60.0, [0; 8]).contains("source_above"));
    }

    #[test]
    fn movie_frames_drawn_before_the_start_do_not_delay_the_first_extra_picture() {
        for mode in [InterpMode::Auto, InterpMode::Unlimited] {
            let mut c = InterpControl::new(mode);
            // Movie frames drawn while the refresh rate is still being measured (no target yet).
            for i in 0..5 {
                c.note_render(i as f64 * 83.3, None);
            }
            let ts = warm(&mut c, 60.0);
            assert!(c.decide(ts, 12.0, false).interpolate, "{mode:?}");
        }
    }

    #[test]
    fn pictures_follow_the_target_rate() {
        let mut c = InterpControl::new(InterpMode::Target(30.0));
        let mut ts = warm(&mut c, 60.0);
        let mut drawn = 0;
        for _ in 0..60 {
            ts += 16.7;
            c.on_animation_frame(ts, 16.7);
            if c.decide(ts, 12.0, false).interpolate {
                c.note_render(ts, Some(1.0));
                drawn += 1;
            }
        }
        assert!((28..=32).contains(&drawn), "{drawn}");
    }
}
