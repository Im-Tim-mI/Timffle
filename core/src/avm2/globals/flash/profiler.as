package flash.profiler {
    // Timffle: `profile()` and `showRedrawRegions()` are hooks for the debugger
    // version of Flash Player (the Flex profiler agent and the "Show Redraw
    // Regions" overlay). The release player accepts both calls and does
    // nothing — `Capabilities.isDebugger` is false here — so this player does
    // the same: no error, no output.
    public function profile(on:Boolean):void {
    }

    public function showRedrawRegions(on:Boolean, color:uint = 0xFF0000):void {
    }
}
