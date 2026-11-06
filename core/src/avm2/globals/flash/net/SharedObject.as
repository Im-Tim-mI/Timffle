package flash.net {
    import flash.events.EventDispatcher;

    // Timffle: every member is real (shared_object.rs). Behaviour measured on
    // the standalone Flash Player 32.0.0.465 (timffle/difftest/src/D45SharedObject.hx):
    //   - `objectEncoding` accepts AMF0 (0) and AMF3 (3) only (#2008) and
    //     selects the format `flush()`/`size` use; `defaultObjectEncoding`
    //     stores any value and only matters for shared objects made later;
    //   - `client` defaults to the shared object itself and must be an object (#2004);
    //   - `connect()` needs a remote shared object on a server connection:
    //     a local one, a null or unconnected NetConnection raise #2139, and a
    //     connected NetConnection with a different URI first dispatches
    //     NetStatusEvent "SharedObject.UriMismatch". Ruffle has no RTMP
    //     server connection, so every `connect()` ends that way; `send()`,
    //     `setDirty()` (non-null name, #2007) and `close()` then have nothing
    //     to transmit, like Flash with a disconnected remote object;
    //   - `getRemote()` needs an RTMP-family remote path (else #2134); its
    //     objects are keyed by name, path and persistence, keep data in
    //     memory, `size` works, `flush()` raises #2130;
    //   - `deleteAll()`/`getDiskUsage()` are AIR-only: Flash Player raises
    //     #2014 (#2007 for a null URL); `preventBackup` is an AIR/iOS
    //     setting read back as null until assigned.
    [Ruffle(Abstract)]
    public class SharedObject extends EventDispatcher {
        public static native function getLocal(
            name:String,
            localPath:String = null,
            secure:Boolean = false
        ):SharedObject;

        public static native function getRemote(
            name:String,
            remotePath:String = null,
            persistence:Object = false,
            secure:Boolean = false
        ):SharedObject;

        public static native function deleteAll(url:String):int;
        public static native function getDiskUsage(url:String):int;

        public static native function get defaultObjectEncoding():uint;
        public static native function set defaultObjectEncoding(value:uint):void;
        public static native function get preventBackup():Boolean;
        public static native function set preventBackup(value:Boolean):void;

        public native function get size():uint;
        public native function get objectEncoding():uint;
        public native function set objectEncoding(value:uint):void;
        public native function get client():Object;
        public native function set client(value:Object):void;
        public native function set fps(value:Number):void;

        public native function flush(minDiskSpace:int = 0):String;
        public native function close():void;
        public native function clear():void;
        public native function connect(myConnection:NetConnection, params:String = null):void;
        public native function send(...args):void;
        public native function setDirty(propertyName:String):void;

        public function setProperty(propertyName:String, value:Object = null):void {
            this.data[propertyName] = value;
            this.setDirty(propertyName);
        }

        public native function get data():Object;
    }
}
