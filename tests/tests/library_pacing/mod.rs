//! Timffle: when a game reloads SWFs again and again, the collector must
//! release the dead copies' libraries before many of them pile up, without
//! anyone forcing a collection (see `decoded_tag_estimate` in
//! `core/common/src/tag_utils.rs`).
//!
//! Runs `swfs/avm2/timffle_library_pacing` like a normal trace test, ticking
//! the player normally (one paced collector step per frame), and records the
//! number of movie libraries and of completed collection cycles after each
//! tick.

use ruffle_test_framework::environment::Environment;
use ruffle_test_framework::options::TestOptions;
use ruffle_test_framework::runner::TestStatus;
use ruffle_test_framework::test::Test;
use ruffle_test_framework::vfs::{PhysicalFS, VfsPath};
use std::thread::sleep;

const TEST_DIR: &str = "tests/swfs/avm2/timffle_library_pacing/";
/// How many times Test.hx loads the child SWF (one copy at a time).
const LOADS: usize = 12;
/// The most libraries (root + dead copies not yet collected + the live copy)
/// allowed at any tick. Each child is 8 KB of SWF but holds a 4 MiB bitmap
/// once decoded; with the decoded size reported to the collector a cycle
/// completes every two or three loads.
const MAX_LIBRARIES: usize = 1 + LOADS / 2;

pub fn library_pacing_avm2(environment: &impl Environment) -> Result<(), libtest_mimic::Failed> {
    let test = &Test::from_options(
        TestOptions {
            num_frames: Some(60),
            ..Default::default()
        },
        VfsPath::new(PhysicalFS::new(TEST_DIR)),
        "library_pacing_avm2".to_string(),
    )?;
    let mut runner = test.create_test_runner(environment)?;
    let observe = |runner: &ruffle_test_framework::runner::TestRunner| {
        let mut player = runner.player().lock().unwrap();
        let cycles = player.gc_cycles();
        let libraries =
            player.mutate_with_update_context(|context| context.library.known_movies().count());
        (libraries, cycles)
    };

    let mut libraries = Vec::new();
    let mut cycles = Vec::new();
    let run_result = loop {
        match runner.tick() {
            Ok(TestStatus::Continue) => {}
            Ok(TestStatus::Sleep(duration)) => sleep(duration),
            Ok(TestStatus::Finished) => break Ok(()),
            Err(e) => break Err(e),
        }
        let (l, c) = observe(&runner);
        libraries.push(l);
        cycles.push(c);
    };
    run_result?;

    let peak = libraries.iter().copied().max().unwrap_or(0);
    let total_cycles = cycles.last().copied().unwrap_or(0);
    eprintln!("movie libraries after each tick (no forced GC): {libraries:?}");
    eprintln!("completed collection cycles after each tick: {cycles:?}");
    eprintln!(
        "peak libraries {peak}, cycles {total_cycles} over {} ticks",
        libraries.len()
    );

    if peak > MAX_LIBRARIES {
        return Err(format!(
            "dead libraries piled up: peak {peak} > {MAX_LIBRARIES} (root + {LOADS} loads): {libraries:?}, cycles {cycles:?}"
        )
        .into());
    }
    Ok(())
}
