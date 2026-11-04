/**
 * Timffle: the floating fps box (the extension's "Show frame rate" switch).
 *
 * Two lines: the pictures drawn per second (big) and, small, the movie's own
 * frame rate with the display's refresh rate (`SWF 24 · 60 Hz`). It sits in a
 * corner of the player, can be dragged to any of the four corners (remembered
 * in localStorage), updates every 0.5 s, is translucent and lets every click
 * through except on its drag handle. A double click on the handle shows a
 * debug line (late animation frames in the last second).
 */

interface FrameStats {
    /** Pictures drawn per second (the core's render counter over 0.5 s windows). */
    fps: number;
    /** The movie's own frame rate. */
    sourceFps: number;
    /** The display's refresh rate, estimated from the animation-frame intervals. */
    refreshHz: number;
    /** Animation frames that arrived late in the last second, in percent. */
    dropPct: number;
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
        this.debug.textContent = `late ${stats.dropPct.toFixed(1)}%`;
    }

    static describe(s: FrameStats): string {
        return `SWF ${s.sourceFps.toFixed(0)} · ${s.refreshHz.toFixed(0)} Hz`;
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
