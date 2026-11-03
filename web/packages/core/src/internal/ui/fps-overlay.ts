/**
 * Timffle: the floating fps box (the extension's "Show frame rate" switch).
 *
 * Two lines: the current picture rate (big) and the interpolation mode with
 * its target (small). It sits in a corner of the player, can be dragged to
 * any of the four corners (remembered in localStorage), updates every 0.5 s,
 * is translucent and lets every click through except on itself.
 *
 * The second line uses short language-neutral tokens:
 *   `AUTO · 120`        automatic mode at the 120 tier
 *   `AUTO · ⏸`          automatic mode paused by load
 *   `MAX · 88`          unlimited mode, current target 88
 *   `144 fps`           fixed target reached
 *   `144 ▼`             fixed target not reached for 30 s
 *   `144 ▶ 60 Hz`       target above the display's refresh rate
 *   `24 ≥ 30`           movie frame rate at or above the target: nothing added
 *   `OFF · 24`          interpolation off (movie frame rate)
 */

interface FrameStats {
    fps: number;
    sourceFps: number;
    mode: "off" | "auto" | "unlimited" | "fixed";
    target: number;
    effective: number;
    refreshHz: number;
    dropPct: number;
    interpMs: number;
    state:
        | "off"
        | "starting"
        | "paused"
        | "source_above"
        | "capped"
        | "below"
        | "ok";
    pausedByLoad: boolean;
}

type Corner = "tl" | "tr" | "bl" | "br";
const STORAGE_KEY = "timffle-fps-corner";
const UPDATE_MS = 500;

export class FpsOverlay {
    private readonly box: HTMLDivElement;
    private readonly big: HTMLDivElement;
    private readonly small: HTMLDivElement;
    private readonly debug: HTMLDivElement;
    private readonly handle: HTMLDivElement;
    private timer: ReturnType<typeof setInterval> | null = null;
    private source: (() => string | null) | null = null;
    private corner: Corner;
    private drag: { startX: number; startY: number; moved: boolean } | null =
        null;

    constructor(private readonly container: HTMLElement) {
        this.box = document.createElement("div");
        this.box.id = "fps-overlay";
        this.box.setAttribute("aria-live", "off");
        this.big = document.createElement("div");
        this.big.className = "fps-big";
        this.small = document.createElement("div");
        this.small.className = "fps-small";
        this.debug = document.createElement("div");
        this.debug.className = "fps-debug";
        // Only the handle takes pointer events, so the box never blocks the game.
        this.handle = document.createElement("div");
        this.handle.className = "fps-handle";
        this.handle.textContent = "⠿";
        this.handle.title = "drag";
        this.box.append(this.handle, this.big, this.small, this.debug);
        this.corner = this.loadCorner();
        this.applyCorner();
        this.handle.addEventListener("pointerdown", this.onPointerDown);
        this.handle.addEventListener("pointermove", this.onPointerMove);
        this.handle.addEventListener("pointerup", this.onPointerUp);
        this.handle.addEventListener("pointercancel", this.onPointerUp);
        this.handle.addEventListener("dblclick", () => {
            this.debug.classList.toggle("open");
        });
    }

    /** Shows the box and starts reading `source` (the player's `frame_stats`). */
    start(source: () => string | null): void {
        this.stop();
        this.source = source;
        if (!this.box.isConnected) {
            this.container.appendChild(this.box);
        }
        this.update();
        this.timer = setInterval(() => this.update(), UPDATE_MS);
    }

    stop(): void {
        if (this.timer !== null) {
            clearInterval(this.timer);
            this.timer = null;
        }
        this.source = null;
        this.box.remove();
    }

    private update(): void {
        let stats: FrameStats | null = null;
        try {
            const raw = this.source?.();
            stats = raw ? (JSON.parse(raw) as FrameStats) : null;
        } catch {
            stats = null;
        }
        if (!stats) {
            this.big.textContent = "–";
            this.small.textContent = "";
            return;
        }
        this.big.textContent = stats.fps.toFixed(0);
        this.small.textContent = FpsOverlay.describe(stats);
        this.debug.textContent = `drop ${stats.dropPct.toFixed(1)}% · ${stats.interpMs.toFixed(1)} ms · ${stats.refreshHz.toFixed(0)} Hz · src ${stats.sourceFps.toFixed(0)}`;
    }

    static describe(s: FrameStats): string {
        const src = s.sourceFps.toFixed(0);
        if (s.mode === "off" || s.state === "off") {
            return `OFF · ${src}`;
        }
        if (s.state === "starting") {
            return "…";
        }
        if (s.mode === "auto") {
            if (s.state === "paused") {
                return "AUTO · ⏸";
            }
            if (s.state === "source_above") {
                return `AUTO · ${src} ≥ ${s.target.toFixed(0)}`;
            }
            return `AUTO · ${s.effective.toFixed(0)}`;
        }
        if (s.mode === "unlimited") {
            return `MAX · ${s.effective.toFixed(0)}`;
        }
        // fixed
        const t = s.target.toFixed(0);
        switch (s.state) {
            case "capped":
                return `${t} ▶ ${s.refreshHz.toFixed(0)} Hz`;
            case "source_above":
                return `${src} ≥ ${t}`;
            case "below":
                return `${t} ▼`;
            default:
                return `${t} fps`;
        }
    }

    private loadCorner(): Corner {
        try {
            const v = localStorage.getItem(STORAGE_KEY);
            if (v === "tl" || v === "tr" || v === "bl" || v === "br") {
                return v;
            }
        } catch {
            // Storage may be unavailable; keep the default.
        }
        return "tr";
    }

    private applyCorner(): void {
        this.box.dataset["corner"] = this.corner;
        this.box.style.left = this.corner.endsWith("l") ? "8px" : "";
        this.box.style.right = this.corner.endsWith("r") ? "8px" : "";
        this.box.style.top = this.corner.startsWith("t") ? "8px" : "";
        this.box.style.bottom = this.corner.startsWith("b") ? "8px" : "";
        this.box.style.transform = "";
    }

    private onPointerDown = (e: PointerEvent): void => {
        if (e.button !== 0) {
            return;
        }
        this.drag = { startX: e.clientX, startY: e.clientY, moved: false };
        this.handle.setPointerCapture(e.pointerId);
        e.preventDefault();
        e.stopPropagation();
    };

    private onPointerMove = (e: PointerEvent): void => {
        if (!this.drag) {
            return;
        }
        const dx = e.clientX - this.drag.startX;
        const dy = e.clientY - this.drag.startY;
        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) {
            this.drag.moved = true;
        }
        this.box.style.transform = `translate(${dx}px, ${dy}px)`;
        e.stopPropagation();
    };

    private onPointerUp = (e: PointerEvent): void => {
        if (!this.drag) {
            return;
        }
        const moved = this.drag.moved;
        this.drag = null;
        try {
            this.handle.releasePointerCapture(e.pointerId);
        } catch {
            // Already released.
        }
        if (moved) {
            // Snap to the corner nearest to where the box was dropped.
            const rect = this.container.getBoundingClientRect();
            const box = this.box.getBoundingClientRect();
            const cx = box.left + box.width / 2 - rect.left;
            const cy = box.top + box.height / 2 - rect.top;
            const vertical = cy < rect.height / 2 ? "t" : "b";
            const horizontal = cx < rect.width / 2 ? "l" : "r";
            this.corner = `${vertical}${horizontal}` as Corner;
            try {
                localStorage.setItem(STORAGE_KEY, this.corner);
            } catch {
                // Storage may be unavailable.
            }
        }
        this.applyCorner();
        e.stopPropagation();
    };
}
