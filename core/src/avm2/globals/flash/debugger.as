package flash.debugger {
    // Timffle: `enterDebugger()` is a breakpoint for the debugger version of Flash
    // Player; the release player (and this one, which has no AS3 debugger) returns at
    // once. Measured on the standalone Flash Player 32.0.0.465: returns void, any
    // argument is ArgumentError #1063 (timffle/difftest/src/D50ClipAcc.hx).
    public function enterDebugger():void {
    }
}
