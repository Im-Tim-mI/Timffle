package flash.display {
    import flash.errors.IllegalOperationError;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.events.UncaughtErrorEvents;
    import flash.system.ApplicationDomain;
    import flash.utils.ByteArray;

    [Ruffle(Abstract)]
    public class LoaderInfo extends EventDispatcher {
        public native function get actionScriptVersion():uint;
        public native function get applicationDomain():ApplicationDomain;
        public native function get bytesLoaded():uint;
        public native function get bytesTotal():uint;
        public native function get content():DisplayObject;
        public native function get contentType():String;
        public native function get frameRate():Number;
        public native function get height():int;
        public native function get isURLInaccessible():Boolean;
        public native function get parentAllowsChild():Boolean;
        public native function get swfVersion():uint;
        public native function get url():String;
        public native function get width():int;
        public native function get bytes():ByteArray;
        public native function get loader():Loader;
        public native function get loaderURL():String;
        public native function get parameters():Object;
        public native function get sharedEvents():EventDispatcher;
        public native function get sameDomain():Boolean;
        public native function get childAllowsParent():Boolean;

        [API("667")]
        public native function get uncaughtErrorEvents():UncaughtErrorEvents;

        override public function dispatchEvent(event:Event):Boolean {
            throw new IllegalOperationError("Error #2118: The LoaderInfo class does not implement this method.", 2118);
        }

        // Timffle: a release Flash Player only answers this in the local-trusted
        // sandbox (with null); elsewhere it throws a SecurityError (loader_info.rs).
        public static native function getLoaderInfoByDefinition(object:Object):LoaderInfo;

        // Playerglobals says all the *Bridge functions are AIR-only, but that
        // doesn't seem to be true. Timffle: stored on the LoaderInfo; only the
        // Loader's SWF may set the parent bridge, only the content the child one.
        public native function get parentSandboxBridge():Object;
        public native function set parentSandboxBridge(obj:Object):void;

        public native function get childSandboxBridge():Object;
        public native function set childSandboxBridge(obj:Object):void;
    }
}
