package flash.printing {
    import flash.display.Sprite;
    import flash.errors.IllegalOperationError;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;

    // Timffle: Flash Player 32 on a desktop, where the user cancels every print dialog.
    // `isSupported` and `Capabilities.hasPrinting` are true (as on a desktop without a
    // printer, measured), but this player has no printing, so `start()` returns false
    // without showing anything -- what Flash Player 32 answers when the dialog is
    // cancelled (measured under Wine). Measured rules of the job slot: only one PrintJob
    // may be in use at a time -- constructing another one while a job that was neither
    // sent nor failed to start is still alive throws IllegalOperationError #2141;
    // a failed `start()` and `send()` free the slot. The page members
    // (pageWidth/pageHeight/paperWidth/paperHeight) read 0 before and after a failed
    // `start()` (no error); `orientation` reads "0" before `start()` and null after a
    // failed `start()` or a `send()`.
    // `addPage()` throws Error #2057 and `send()` does nothing without a started job.
    // The `orientation` setter exists only in AIR (assigning is ReferenceError #1074 in
    // Flash Player, measured), so there is none here.
    public class PrintJob extends EventDispatcher {
        private var _orientation:String = "0";

        private var _startTried:Boolean = false;

        // The player-wide job slot (a weak reference: a job that is collected frees it).
        private static native function claimSlot(job:PrintJob):Boolean;
        private static native function releaseSlot(job:PrintJob):void;

        public function PrintJob() {
            super();
            if (!PrintJob.claimSlot(this)) {
                throw new IllegalOperationError("Error #2141: Only one PrintJob may be in use at a time.", 2141);
            }
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return true;
        }

        public function get orientation():String {
            return this._orientation;
        }

        public function get pageHeight():int {
            return 0;
        }

        public function get pageWidth():int {
            return 0;
        }

        public function get paperHeight():int {
            return 0;
        }

        public function get paperWidth():int {
            return 0;
        }

        public function start():Boolean {
            // As if the user cancelled the print dialog: the job does not start and
            // frees the slot.
            if (!this._startTried) {
                this._startTried = true;
                this._orientation = null;
                PrintJob.releaseSlot(this);
            }
            return false;
        }

        public function addPage(sprite:Sprite, printArea:Rectangle = null, options:PrintJobOptions = null, frameNum:int = 0):void {
            // start() was not successful, so no page can be added.
            throw new Error("Error #2057: The page could not be added to the print job.", 2057);
        }

        public function send():void {
            // Nothing was started: the documented "does not succeed" case, no exception;
            // the job is finished (orientation null, measured) and frees the slot.
            this._orientation = null;
            PrintJob.releaseSlot(this);
        }
    }
}
