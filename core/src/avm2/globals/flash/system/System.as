package flash.system {
    // Timffle: every member is real (system.rs). Values that depend on the
    // host were measured on the standalone Flash Player 32.0.0.465
    // (timffle/difftest/src/D44System.hx, D46SystemExit.hx):
    //   - `ime` is one IME instance per player, `vmVersion` is "2.1 sec cyclone";
    //   - `pause()`/`resume()` are debugger hooks: the release player keeps
    //     running (frames advanced while "paused"), so they do nothing here;
    //   - `processCPUUsage` is an AIR feature; Flash Player reports 0;
    //   - the memory figures are whole 4 KiB pages with free + total <= private;
    //   - `exit()` raises #2018 in a browser, #2017 outside the local-trusted
    //     sandbox, and quits the standalone player (UiBackend::exit) otherwise.
    [Ruffle(Abstract)]
    public final class System {
        public static function gc():void {}

        public static native function pauseForGCIfCollectionImminent(imminence:Number = 0.75):void;

        public static native function setClipboard(string:String):void;

        public static native function disposeXML(node:XML):void;

        public static native function exit(code:uint):void;

        public static native function pause():void;
        public static native function resume():void;

        public static native function get ime():IME;
        public static native function get processCPUUsage():Number;
        public static native function get useCodePage():Boolean;
        public static native function set useCodePage(value:Boolean):void;
        public static native function get vmVersion():String;

        public static native function get freeMemory():Number;
        public static native function get privateMemory():Number;
        public static native function get totalMemoryNumber():Number;

        public static function get totalMemory():uint {
            return totalMemoryNumber as uint;
        }
    }
}
