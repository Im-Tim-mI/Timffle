package flash.net {
    import flash.events.EventDispatcher;

    // Timffle: keeps track of every NetStream (Flash Player 32: `listStreams()` returns a new,
    // non-fixed Vector each time with all NetStreams still alive, also those created before the
    // monitor and closed or disposed ones; every monitor gets `netStreamCreate` synchronously
    // from the NetStream constructor).
    [API("672")]
    public class NetMonitor extends EventDispatcher {
        public function NetMonitor() {
            this.register();
        }

        private native function register():void;

        public native function listStreams():Vector.<NetStream>;
    }
}
