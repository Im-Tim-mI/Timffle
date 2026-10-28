//! Timffle: a SWF loaded with `Loader` must not keep its movie library alive
//! after the content is unloaded and dropped (see `core/src/library.rs`).
//!
//! Runs `swfs/avm2/timffle_library_release` like a normal trace test, but
//! forces a complete garbage collection after every tick and records the
//! number of movie libraries after each one.

use ruffle_test_framework::environment::Environment;
use ruffle_test_framework::options::TestOptions;
use ruffle_test_framework::runner::TestStatus;
use ruffle_test_framework::test::Test;
use ruffle_test_framework::vfs::{PhysicalFS, VfsPath};
use std::thread::sleep;

const TEST_DIR: &str = "tests/swfs/avm2/timffle_library_release/";
/// How many times Test.hx loads the child SWF.
const LOADS: usize = 4;

pub fn library_release_avm2(environment: &impl Environment) -> Result<(), libtest_mimic::Failed> {
    let test = &Test::from_options(
        TestOptions {
            num_frames: Some(40),
            ..Default::default()
        },
        VfsPath::new(PhysicalFS::new(TEST_DIR)),
        "library_release_avm2".to_string(),
    )?;
    let mut runner = test.create_test_runner(environment)?;
    let count_libraries = |runner: &ruffle_test_framework::runner::TestRunner| {
        let mut player = runner.player().lock().unwrap();
        player.force_full_gc();
        player.mutate_with_update_context(|context| context.library.known_movies().count())
    };

    let mut counts = Vec::new();
    let run_result = loop {
        match runner.tick() {
            Ok(TestStatus::Continue) => {}
            Ok(TestStatus::Sleep(duration)) => sleep(duration),
            Ok(TestStatus::Finished) => break Ok(()),
            Err(e) => break Err(e),
        }
        counts.push(count_libraries(&runner));
    };
    let final_count = count_libraries(&runner);
    counts.push(final_count);
    {
        let mut player = runner.player().lock().unwrap();
        player.mutate_with_update_context(|context| {
            for movie in context.library.known_movies() {
                eprintln!(
                    "surviving library: url={} bytes={} chars={}",
                    movie.url(),
                    movie.uncompressed_len(),
                    context
                        .library
                        .library_for_movie(movie)
                        .map(|l| l.characters().len())
                        .unwrap_or(0)
                );
            }
        });
    }
    run_result?;

    let peak = counts.iter().copied().max().unwrap_or(0);
    eprintln!("movie libraries after each tick (full GC each time): {counts:?}");

    // While all copies are referenced, every one of them has its own library
    // (plus the root movie): the collector must not take a live library.
    if peak < 1 + LOADS {
        return Err(format!(
            "expected at least {} libraries while all copies were alive, peak was {peak}: {counts:?}",
            1 + LOADS
        )
        .into());
    }
    // Once the SWF has released every copy, only the root movie is left.
    if final_count != 1 {
        return Err(format!(
            "expected only the root movie's library after release, got {final_count}: {counts:?}"
        )
        .into());
    }
    Ok(())
}
