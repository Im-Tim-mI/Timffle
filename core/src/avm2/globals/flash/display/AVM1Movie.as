package flash.display {
    import flash.errors.IllegalOperationError;

    [Ruffle(Abstract)]
    public class AVM1Movie extends DisplayObject {
        // Timffle: `call()` and `addCallback()` are the AIR-only bridge to the
        // loaded AVM1 movie. Flash Player 32 throws `IllegalOperationError
        // #2014` for every argument (measured with
        // timffle/difftest/src/D51DisplayMisc.hx): Flash without the feature.
        public function call(functionName:String, ...rest):* {
            Error.throwError(IllegalOperationError, 2014);
            return null;
        }

        public function addCallback(name:String, fn:Function):void {
            Error.throwError(IllegalOperationError, 2014);
        }
    }
}
