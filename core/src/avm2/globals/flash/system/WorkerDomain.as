package flash.system {
    import flash.utils.ByteArray;
    import flash.system.Worker;

    // Timffle: the one worker domain of a player without concurrency (see
    // Worker.as): `isSupported` false, `createWorker()` returns null — the
    // documented answer when "the current context doesn't support
    // concurrency" (after the null check on `swf`, `TypeError #2007`) — and
    // `listWorkers()` lists the running workers, which is the primordial
    // worker alone.
    [API("680")] // the docs say 682, that's wrong
    [Ruffle(Abstract)]
    public final class WorkerDomain {
        public static function get isSupported():Boolean {
            return false;
        }

        private static var _current:WorkerDomain;

        public static function get current():WorkerDomain {
            if (!_current) {
                _current = instantiateInternal();
            }

            return _current;
        }

        public function createWorker(swf:ByteArray, giveAppPrivileges:Boolean = false):Worker {
            if (swf == null) {
                throw new TypeError("Error #2007: Parameter swf must be non-null.", 2007);
            }
            return null;
        }

        public function listWorkers():Vector.<Worker> {
            var workers:Vector.<Worker> = new Vector.<Worker>();
            workers.push(Worker.current);
            return workers;
        }

        private static native function instantiateInternal():WorkerDomain;
    }
}
