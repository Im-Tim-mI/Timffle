package flash.system {
    import flash.concurrent.Condition;
    import flash.concurrent.Mutex;
    import flash.events.EventDispatcher;
    import flash.utils.ByteArray;

    // Timffle: this player runs every SWF on one thread, like Flash Player on
    // a platform without concurrency (`Worker.isSupported` false — the mobile
    // browser plugins, AIR for iOS before 3.9). What such a player still has
    // is the primordial worker: `Worker.current` (`isPrimordial` true,
    // `state` "running"), its shared-property table and its message channels.
    //
    // Shared properties are really stored. Values go through an AMF3 copy
    // (`ByteArray.writeObject`/`readObject`), which is how Flash copies them
    // between workers, except the five types Flash shares by reference
    // (Worker, MessageChannel, shareable ByteArray, Mutex, Condition); null
    // or undefined removes the key and an absent key reads null, as
    // documented. `start()` on the primordial worker, which is already
    // running, is `Error #1511: Worker is already started.`; `terminate()`
    // is `Error #3732: Worker.terminate is only available for background
    // workers.` (both from the AS3 runtime-error list). `addEventListener`/
    // `removeEventListener` are the inherited ones — Flash re-declares them
    // on Worker only to document them.
    [API("682")]
    [Ruffle(Abstract)]
    public final class Worker extends EventDispatcher {
        private static var _current:Worker;
        private static var _sharedProperties:Object = {};

        public static function get isSupported():Boolean {
            return false;
        }

        public static function get current():Worker {
            if (!_current) {
                _current = instantiateInternal();
            }

            return _current;
        }

        public function get isPrimordial():Boolean {
            return this == _current;
        }

        public function get state():String {
            return WorkerState.RUNNING;
        }

        override public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false):void {
            super.addEventListener(type, listener, useCapture, priority, useWeakReference);
        }

        override public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false):void {
            super.removeEventListener(type, listener, useCapture);
        }

        public function createMessageChannel(receiver:Worker):MessageChannel {
            if (receiver == null) {
                throw new TypeError("Error #2007: Parameter receiver must be non-null.", 2007);
            }
            var channel:MessageChannel = instantiateMessageChannel();
            channel.init(this, receiver);
            return channel;
        }

        public function setSharedProperty(key:String, value:*):void {
            if (key == null) {
                throw new TypeError("Error #2007: Parameter key must be non-null.", 2007);
            }
            if (value === null || value === undefined) {
                delete _sharedProperties[key];
                return;
            }
            _sharedProperties[key] = copyForTransfer(value);
        }

        public function getSharedProperty(key:String):* {
            if (key == null) {
                throw new TypeError("Error #2007: Parameter key must be non-null.", 2007);
            }
            if (key in _sharedProperties) {
                return _sharedProperties[key];
            }
            return null;
        }

        public function start():void {
            throw new Error("Error #1511: Worker is already started.", 1511);
        }

        public function terminate():Boolean {
            throw new Error("Error #3732: Worker.terminate is only available for background workers.", 3732);
        }

        // The copy Flash makes of a value handed to another worker: the five
        // shareable types by reference, everything else through AMF3.
        internal static function copyForTransfer(value:*):* {
            if (value is Worker || value is MessageChannel || value is Mutex || value is Condition) {
                return value;
            }
            if (value is ByteArray && ByteArray(value).shareable) {
                return value;
            }
            var bytes:ByteArray = new ByteArray();
            bytes.writeObject(value);
            bytes.position = 0;
            return bytes.readObject();
        }

        private static native function instantiateInternal():Worker;
        private static native function instantiateMessageChannel():MessageChannel;
    }
}
