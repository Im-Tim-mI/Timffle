package flash.external {
    [Ruffle(Abstract)]
    public final class ExternalInterface {
        public static native function get available():Boolean;

        public static native function addCallback(functionName:String, closure:Function):void;

        public static native function call(functionName:String, ...arguments):*;

        public static native function get objectID():String;

        // Timffle: when true, an exception thrown by an ActionScript callback
        // is rethrown in the page's JavaScript and a JavaScript exception
        // thrown by `call()` is rethrown here as an `Error` carrying its
        // message; when false (the default) callbacks return null and `call()`
        // returns undefined on an exception, as Flash does.
        public static native function get marshallExceptions():Boolean;
        public static native function set marshallExceptions(value:Boolean):void;
    }
}
