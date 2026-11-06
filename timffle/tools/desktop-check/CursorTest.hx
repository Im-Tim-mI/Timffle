import flash.display.BitmapData;
import flash.display.Sprite;
import flash.geom.Point;
import flash.ui.Mouse;
import flash.ui.MouseCursorData;

class CursorTest {
    static function main() {
        var s = new Sprite();
        s.graphics.beginFill(0x808080);
        s.graphics.drawRect(0, 0, 400, 300);
        flash.Lib.current.addChild(s);
        // 16x16 cursor: left half red, right half opaque blue, hot spot (2,3)
        var bd = new BitmapData(16, 16, true, 0xFFFF0000);
        bd.fillRect(new flash.geom.Rectangle(8, 0, 8, 16), 0xFF0000FF);
        var v = new flash.Vector<BitmapData>();
        v.push(bd);
        var d = new MouseCursorData();
        d.data = v;
        d.hotSpot = new Point(2, 3);
        Mouse.registerCursor("timffle_test", d);
        Mouse.cursor = "timffle_test";
        trace("supportsNativeCursor=" + Mouse.supportsNativeCursor + " cursor=" + Mouse.cursor);
    }
}
