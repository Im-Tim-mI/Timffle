//! Timffle: memory accounting for `flash.system.System.totalMemory`,
//! `totalMemberNumber`, `freeMemory` and `privateMemory`.
//!
//! Flash Player reports its own heap: `totalMemory` is what the player has
//! in use, `freeMemory` what it has allocated but not used, and
//! `privateMemory` the whole process (all three in 4 KiB pages, Flash
//! 32.0.0.465: `free + total <= private`). Ruffle has no player heap of its
//! own, so the numbers come from the process instead: [`CountingAllocator`]
//! wraps the global allocator of a front end (desktop, web, tests) and
//! counts the bytes currently allocated by Rust, and
//! [`process_private_bytes`] asks the platform for the process size (the
//! wasm linear memory on the web, the resident set on Linux). A front end
//! that installs no counting allocator still gets a non-zero `totalMemory`:
//! the process size is used for both.

use std::alloc::{GlobalAlloc, Layout};
use std::sync::atomic::{AtomicUsize, Ordering};

/// Flash reports every memory figure as a whole number of 4 KiB pages.
const PAGE: usize = 4096;

static ALLOCATED: AtomicUsize = AtomicUsize::new(0);

/// A global allocator wrapper that keeps a running count of the bytes
/// currently allocated. Install it in a binary with
/// `#[global_allocator] static GLOBAL: CountingAllocator<std::alloc::System> = CountingAllocator(std::alloc::System);`.
pub struct CountingAllocator<A: GlobalAlloc>(pub A);

// SAFETY: every call is forwarded unchanged to the wrapped allocator; the
// counter is bookkeeping only.
unsafe impl<A: GlobalAlloc> GlobalAlloc for CountingAllocator<A> {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { self.0.alloc(layout) };
        if !ptr.is_null() {
            ALLOCATED.fetch_add(layout.size(), Ordering::Relaxed);
        }
        ptr
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        let ptr = unsafe { self.0.alloc_zeroed(layout) };
        if !ptr.is_null() {
            ALLOCATED.fetch_add(layout.size(), Ordering::Relaxed);
        }
        ptr
    }

    unsafe fn dealloc(&self, ptr: *mut u8, layout: Layout) {
        unsafe { self.0.dealloc(ptr, layout) };
        ALLOCATED.fetch_sub(layout.size(), Ordering::Relaxed);
    }

    unsafe fn realloc(&self, ptr: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        let new_ptr = unsafe { self.0.realloc(ptr, layout, new_size) };
        if !new_ptr.is_null() {
            let old = layout.size();
            if new_size >= old {
                ALLOCATED.fetch_add(new_size - old, Ordering::Relaxed);
            } else {
                ALLOCATED.fetch_sub(old - new_size, Ordering::Relaxed);
            }
        }
        new_ptr
    }
}

/// Bytes currently allocated through a [`CountingAllocator`]; 0 when none
/// is installed.
pub fn allocated_bytes() -> usize {
    ALLOCATED.load(Ordering::Relaxed)
}

/// The size of this process as the platform reports it: the wasm linear
/// memory on the web, the resident set size on Linux, 0 where unknown.
pub fn process_private_bytes() -> usize {
    #[cfg(target_arch = "wasm32")]
    {
        core::arch::wasm32::memory_size(0) * 65536
    }
    #[cfg(all(not(target_arch = "wasm32"), target_os = "linux"))]
    {
        // /proc/self/statm: size resident shared text lib data dt (pages)
        std::fs::read_to_string("/proc/self/statm")
            .ok()
            .and_then(|s| s.split_whitespace().nth(1)?.parse::<usize>().ok())
            .map(|pages| pages * page_size())
            .unwrap_or(0)
    }
    #[cfg(all(not(target_arch = "wasm32"), not(target_os = "linux")))]
    {
        0
    }
}

#[cfg(all(not(target_arch = "wasm32"), target_os = "linux"))]
fn page_size() -> usize {
    // Linux reports statm in system pages; 4 KiB everywhere Timffle runs
    // (x86-64, and the common AArch64 configurations).
    4096
}

/// The three figures `flash.system.System` reports, in bytes, each a whole
/// number of 4 KiB pages: (`totalMemory`, `freeMemory`, `privateMemory`).
pub fn flash_memory_figures() -> (usize, usize, usize) {
    let round = |b: usize| b.div_ceil(PAGE) * PAGE;
    let private = round(process_private_bytes());
    let counted = allocated_bytes();
    let total = if counted > 0 { round(counted) } else { private };
    let private = private.max(total);
    let free = private - total;
    (total, free, private)
}
