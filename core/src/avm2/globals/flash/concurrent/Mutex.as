package flash.concurrent {
    // Timffle: a real mutex for the one worker this player has (see
    // flash/system/Worker.as). A mutex needs a worker to own it, and the
    // primordial worker is one, so `isSupported` is true — Flash Player
    // reports it true wherever `new Mutex()` succeeds — and the lock works as
    // documented: `lock()` takes ownership (or deepens it: the mutex is
    // released only after as many `unlock()` calls as there were `lock()`
    // calls), `tryLock()` always succeeds because no other worker can hold
    // or wait for the mutex, and `unlock()` without a matching `lock()` is
    // `Error #1514: unlock() with no preceding matching lock().`, the
    // runtime error for "the current worker doesn't own the mutex".
    [API("684")]
    public final class Mutex {
        private var _lockCount:int = 0;

        public static function get isSupported():Boolean {
            return true;
        }

        public function Mutex() {
        }

        public function lock():void {
            this._lockCount++;
        }

        public function tryLock():Boolean {
            this._lockCount++;
            return true;
        }

        public function unlock():void {
            if (this._lockCount == 0) {
                throw new Error("Error #1514: unlock() with no preceding matching lock().", 1514);
            }
            this._lockCount--;
        }

        // For Condition: whether the (only) worker owns this mutex, and the
        // release/re-acquire around a wait.
        internal function get isOwned():Boolean {
            return this._lockCount > 0;
        }

        internal function release():int {
            var depth:int = this._lockCount;
            this._lockCount = 0;
            return depth;
        }

        internal function reacquire(depth:int):void {
            this._lockCount = depth;
        }
    }
}
