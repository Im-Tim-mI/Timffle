//! Timffle: frame-rate statistics for the fps overlay (the extension's "Show frame rate" switch).
//!
//! Counts the pictures the core draws (`Player::render_count`) over half-second windows,
//! estimates the display's refresh rate from the animation-frame intervals, and counts
//! animation frames that arrived late ("dropped": an interval longer than 1.5 refresh
//! intervals) over one-second periods. Nothing here changes what is drawn.

use std::collections::VecDeque;

const STATS_WINDOW_MS: f64 = 500.0;
const PERIOD_MS: f64 = 1000.0;
const USUAL_REFRESH_RATES: [f64; 11] = [
    30.0, 48.0, 50.0, 60.0, 75.0, 90.0, 100.0, 120.0, 144.0, 165.0, 240.0,
];

pub struct FrameStats {
    /// Animation-frame intervals of the last ~2 s, for the refresh-rate estimate.
    raf_deltas: VecDeque<f64>,
    refresh_hz: f64,
    period_start: f64,
    period_rafs: u32,
    period_dropped: u32,
    drop_pct: f64,
    win_start: f64,
    renders_at_win_start: u64,
    fps: f64,
    started: bool,
}

impl FrameStats {
    pub fn new() -> Self {
        Self {
            raf_deltas: VecDeque::with_capacity(120),
            refresh_hz: 60.0,
            period_start: 0.0,
            period_rafs: 0,
            period_dropped: 0,
            drop_pct: 0.0,
            win_start: 0.0,
            renders_at_win_start: 0,
            fps: 0.0,
            started: false,
        }
    }

    fn refresh_interval(&self) -> f64 {
        1000.0 / self.refresh_hz.max(1.0)
    }

    /// Called at the start of every animation frame with the frame timestamp and the time since
    /// the previous one (both ms).
    pub fn on_animation_frame(&mut self, ts: f64, dt: f64, renders_total: u64) {
        if !self.started {
            self.started = true;
            self.win_start = ts;
            self.period_start = ts;
            self.renders_at_win_start = renders_total;
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
                    self.refresh_hz = USUAL_REFRESH_RATES
                        .iter()
                        .copied()
                        .find(|&r| (hz - r).abs() <= r * 0.06)
                        .unwrap_or(hz);
                }
            }
            self.period_rafs += 1;
            if dt > self.refresh_interval() * 1.5 {
                self.period_dropped += 1;
            }
        }
    }

    /// Once per animation frame, after drawing. `renders_total` is the core's picture counter.
    pub fn after_frame(&mut self, ts: f64, background: bool, renders_total: u64) {
        if !self.started {
            return;
        }
        if ts - self.win_start >= STATS_WINDOW_MS {
            let n = renders_total.saturating_sub(self.renders_at_win_start) as f64;
            self.fps = n * 1000.0 / (ts - self.win_start);
            self.renders_at_win_start = renders_total;
            self.win_start = ts;
        }
        if background {
            // Nothing is drawn while the page is hidden; do not count it as dropped frames.
            self.period_rafs = 0;
            self.period_dropped = 0;
            self.period_start = ts;
            return;
        }
        if ts - self.period_start >= PERIOD_MS {
            self.drop_pct = if self.period_rafs > 0 {
                100.0 * self.period_dropped as f64 / self.period_rafs as f64
            } else {
                0.0
            };
            self.period_rafs = 0;
            self.period_dropped = 0;
            self.period_start = ts;
        }
    }

    /// The numbers the overlay shows, as JSON (`source_fps` is the movie's own frame rate).
    pub fn stats_json(&self, source_fps: f64) -> String {
        format!(
            "{{\"fps\":{:.1},\"sourceFps\":{:.2},\"refreshHz\":{:.0},\"dropPct\":{:.1}}}",
            self.fps, source_fps, self.refresh_hz, self.drop_pct
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn counts_pictures_per_second() {
        let mut s = FrameStats::new();
        let mut ts = 0.0;
        let mut renders = 0;
        s.on_animation_frame(ts, 0.0, renders);
        s.after_frame(ts, false, renders);
        // 60 Hz animation frames, a picture on every other one: 30 fps.
        for i in 1..=120 {
            ts += 1000.0 / 60.0;
            s.on_animation_frame(ts, 1000.0 / 60.0, renders);
            if i % 2 == 0 {
                renders += 1;
            }
            s.after_frame(ts, false, renders);
        }
        assert!((s.fps - 30.0).abs() < 1.5, "fps {}", s.fps);
        assert_eq!(s.refresh_hz, 60.0);
        assert_eq!(s.drop_pct, 0.0);
        assert_eq!(
            s.stats_json(24.0),
            format!(
                "{{\"fps\":{:.1},\"sourceFps\":24.00,\"refreshHz\":60,\"dropPct\":0.0}}",
                s.fps
            )
        );
    }

    #[test]
    fn counts_late_animation_frames() {
        let mut s = FrameStats::new();
        let mut ts = 0.0;
        s.on_animation_frame(ts, 0.0, 0);
        for i in 1..=100 {
            let dt = if i % 10 == 0 { 50.0 } else { 1000.0 / 60.0 };
            ts += dt;
            s.on_animation_frame(ts, dt, i);
            s.after_frame(ts, false, i);
        }
        assert_eq!(s.refresh_hz, 60.0);
        assert!(s.drop_pct > 5.0 && s.drop_pct < 15.0, "drop {}", s.drop_pct);
    }
}
