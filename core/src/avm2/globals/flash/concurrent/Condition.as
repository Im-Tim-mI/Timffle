package flash.concurrent {
    import flash.errors.ScriptTimeoutError;
    import flash.utils.getTimer;

    // Timffle: a condition variable for the one worker this player has (see
    // Mutex.as). `isSupported` follows `Mutex.isSupported`, as documented.
    // The ownership rules are enforced with the runtime errors Flash uses:
    // `notify()`/`notifyAll()`/`wait()` while the worker does not own the
    // mutex are `Error #1516`/`#1517`/`#1518`, a `timeout` below 0 other
    // than -1 is `ArgumentError #1515`, and a null mutex is `ArgumentError
    // #2007` (Flash Player 32, measured). `notify()`/`notifyAll()` have nobody
    // to wake. `wait(timeout)` really pauses the worker for `timeout`
    // milliseconds — the mutex released meanwhile and re-acquired after —
    // and returns true (the timeout elapsed: no other worker can notify).
    // `wait()` without a timeout, or with one past the 15-second script
    // limit, would pause forever; Flash Player 32 freezes until the script
    // limit and then throws `ScriptTimeoutError #1502` with the mutex left
    // released (measured); this player throws the same error, mutex released,
    // at once instead of freezing the page first.
    [API("684")]
    public final class Condition {
        private var _mutex:Mutex;

        public static function get isSupported():Boolean {
            return Mutex.isSupported;
        }

        public function Condition(mutex:Mutex) {
            if (mutex == null) {
                throw new ArgumentError("Error #2007: Parameter mutex must be non-null.", 2007);
            }
            this._mutex = mutex;
        }

        public function get mutex():Mutex {
            return this._mutex;
        }

        public function notify():void {
            if (!this._mutex.isOwned) {
                throw new Error("Error #1516: Condition cannot notify if associated mutex is not owned.", 1516);
            }
        }

        public function notifyAll():void {
            if (!this._mutex.isOwned) {
                throw new Error("Error #1517: Condition cannot notifyAll if associated mutex is not owned.", 1517);
            }
        }

        public function wait(timeout:Number = -1):Boolean {
            if (!this._mutex.isOwned) {
                throw new Error("Error #1518: Condition cannot wait if associated mutex is not owned.", 1518);
            }
            if (timeout < 0 && timeout != -1) {
                throw new ArgumentError("Error #1515: Invalid condition timeout value: " + timeout + ".", 1515);
            }
            if (timeout == -1 || timeout >= 15000) {
                this._mutex.release();
                throw new ScriptTimeoutError("Error #1502: A script has executed for longer than the default timeout period of 15 seconds.", 1502);
            }
            var depth:int = this._mutex.release();
            var end:int = getTimer() + Math.ceil(timeout);
            while (getTimer() < end) {
            }
            this._mutex.reacquire(depth);
            return true;
        }
    }
}
