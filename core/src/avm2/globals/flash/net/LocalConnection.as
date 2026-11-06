package flash.net {
    import flash.events.EventDispatcher;
    import flash.events.StatusEvent;
    import flash.utils.setTimeout;

    [Ruffle(InstanceAllocator)]
    public class LocalConnection extends EventDispatcher {
        public function LocalConnection() {
            super();
        }

        [API("667")]
        public static function get isSupported():Boolean {
            return true;
        }

        public var isPerUser:Boolean = false;

        public native function get domain():String;

        public native function close():void;

        public native function connect(connectionName:String):void;

        public native function send(connectionName:String, methodName:String, ...arguments):void;

        public native function get client():Object;
        public native function set client(client:Object):void;

        // Timffle: real allow lists; a send() from a domain the receiver did
        // not allow gets a status event with level "error" (local_connection.rs).
        public native function allowDomain(...domains):void;

        public native function allowInsecureDomain(...domains):void;
    }
}
