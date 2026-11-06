package {
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.geom.Point;
    import flash.ui.Mouse;
    import flash.ui.MouseCursorData;

    public class Test extends Sprite {
        private function cursorData(w:int, h:int, frames:int = 1):MouseCursorData {
            var data:MouseCursorData = new MouseCursorData();
            var v:Vector.<BitmapData> = new Vector.<BitmapData>();
            for (var i:int = 0; i < frames; i++) {
                v.push(new BitmapData(w, h, true, 0x80FF0000));
            }
            data.data = v;
            data.hotSpot = new Point(1, 2);
            data.frameRate = 10;
            return data;
        }

        private function attempt(label:String, f:Function):void {
            try {
                f();
                trace(label + ": ok");
            } catch (e:Error) {
                trace(label + ": " + e);
            }
        }

        public function Test() {
            // The test harness has no native cursor.
            trace("supportsNativeCursor: " + Mouse.supportsNativeCursor);
            trace("supportsCursor: " + Mouse.supportsCursor);

            var good:MouseCursorData = cursorData(32, 32, 2);
            attempt("register 32x32 two frames", function():void { Mouse.registerCursor("good", good); });
            attempt("register 1x1", function():void { Mouse.registerCursor("tiny", cursorData(1, 1)); });

            attempt("register null name", function():void { Mouse.registerCursor(null, good); });
            attempt("register null cursor", function():void { Mouse.registerCursor("x", null); });
            attempt("register no data", function():void { Mouse.registerCursor("nodata", new MouseCursorData()); });
            var empty:MouseCursorData = new MouseCursorData();
            empty.data = new Vector.<BitmapData>();
            attempt("register empty data", function():void { Mouse.registerCursor("empty", empty); });
            attempt("register 33x32", function():void { Mouse.registerCursor("wide", cursorData(33, 32)); });
            attempt("register 32x33", function():void { Mouse.registerCursor("tall", cursorData(32, 33)); });
            var disposed:MouseCursorData = cursorData(8, 8);
            disposed.data[0].dispose();
            attempt("register disposed frame", function():void { Mouse.registerCursor("disposed", disposed); });
            attempt("register null hotSpot", function():void {
                var d:MouseCursorData = cursorData(4, 4);
                d.hotSpot = null;
                Mouse.registerCursor("nohotspot", d);
            });
            for each (var builtin:String in ["auto", "arrow", "button", "hand", "ibeam"]) {
                attempt("register builtin " + builtin, function():void { Mouse.registerCursor(builtin, good); });
            }
            attempt("unregister null", function():void { Mouse.unregisterCursor(null); });
            attempt("unregister unknown", function():void { Mouse.unregisterCursor("unknown"); });

            // Names that failed to register are not selectable.
            for each (var failed:String in ["wide", "tall", "empty", "nodata", "disposed"]) {
                attempt("cursor = " + failed, function():void { Mouse.cursor = failed; });
            }

            // A registered name is selectable and reported; built-in names and auto
            // replace it; re-registering a shown name keeps it shown.
            Mouse.cursor = "good";
            trace("cursor after good: " + Mouse.cursor);
            Mouse.registerCursor("good", cursorData(16, 16));
            trace("cursor after re-register: " + Mouse.cursor);
            Mouse.cursor = "tiny";
            trace("cursor after tiny: " + Mouse.cursor);
            Mouse.cursor = "button";
            trace("cursor after button: " + Mouse.cursor);
            Mouse.cursor = "good";
            Mouse.cursor = "auto";
            trace("cursor after auto: " + Mouse.cursor);

            // Unregistering the shown cursor falls back to auto; unregistering another
            // one leaves the shown cursor alone.
            Mouse.cursor = "good";
            Mouse.unregisterCursor("tiny");
            trace("cursor after unregistering another: " + Mouse.cursor);
            Mouse.unregisterCursor("good");
            trace("cursor after unregistering shown: " + Mouse.cursor);
            attempt("cursor = good after unregister", function():void { Mouse.cursor = "good"; });

            Mouse.cursor = "ibeam";
            Mouse.registerCursor("good", good);
            Mouse.unregisterCursor("good");
            trace("cursor after unregistering unshown: " + Mouse.cursor);
        }
    }
}
