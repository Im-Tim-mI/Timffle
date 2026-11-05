package {
import flash.display.BitmapData;
import flash.display.Sprite;
import flash.geom.Point;
import flash.net.ObjectEncoding;
import flash.net.URLRequest;
import flash.ui.ContextMenu;
import flash.ui.ContextMenuItem;
import flash.ui.Keyboard;
import flash.ui.KeyboardType;
import flash.ui.Mouse;
import flash.ui.MouseCursorData;
import flash.ui.Multitouch;
import flash.ui.MultitouchInputMode;
import flash.utils.ByteArray;
import flash.utils.Endian;
import flash.utils.getQualifiedClassName;

// flash.ui / flash.utils members Ruffle used to stub or lack: ContextMenu.clone/link/isSupported,
// Keyboard.capsLock/numLock/hasVirtualKeyboard/physicalKeyboardType, Mouse.supportsCursor,
// MouseCursorData, Multitouch statics, ByteArray.atomicCompareAndSwapIntAt/Length, shareable and
// writeObject with a repeated object. Expected values follow the Adobe reference for a desktop
// player without touch input (see the doc comments on each class).
public class Test extends Sprite {
    public function Test() {
        trace("// ContextMenu");
        trace("isSupported", ContextMenu.isSupported);
        var menu:ContextMenu = new ContextMenu();
        trace("link default", menu.link);
        menu.link = new URLRequest("http://example.com/");
        trace("link url", menu.link.url);
        menu.customItems.push(new ContextMenuItem("One", true, false, true));
        menu.customItems.push(new ContextMenuItem("Two"));
        menu.builtInItems.zoom = false;
        menu.clipboardItems.paste = false;
        menu.clipboardMenu = true;
        var copy:ContextMenu = menu.clone() as ContextMenu;
        trace("clone class", getQualifiedClassName(copy));
        trace("clone is new", copy !== menu, copy.customItems !== menu.customItems);
        trace("clone items", copy.customItems.length, copy.customItems[0] !== menu.customItems[0]);
        trace("clone item 0", copy.customItems[0].caption, copy.customItems[0].separatorBefore, copy.customItems[0].enabled, copy.customItems[0].visible);
        trace("clone item 1", copy.customItems[1].caption);
        trace("clone builtIn", copy.builtInItems !== menu.builtInItems, copy.builtInItems.zoom, copy.builtInItems.play);
        trace("clone clipboard", copy.clipboardItems !== menu.clipboardItems, copy.clipboardItems.paste, copy.clipboardItems.copy);
        trace("clone clipboardMenu", copy.clipboardMenu);
        trace("clone link", copy.link === menu.link);
        copy.customItems[0].caption = "Changed";
        trace("original untouched", menu.customItems[0].caption);

        trace("// Keyboard");
        trace("capsLock", Keyboard.capsLock);
        trace("numLock", Keyboard.numLock);
        trace("hasVirtualKeyboard", Keyboard.hasVirtualKeyboard);
        trace("physicalKeyboardType", Keyboard.physicalKeyboardType, Keyboard.physicalKeyboardType == KeyboardType.ALPHANUMERIC);

        trace("// Mouse / MouseCursorData");
        trace("supportsCursor", Mouse.supportsCursor);
        var data:MouseCursorData = new MouseCursorData();
        trace("defaults", data.data, data.frameRate, data.hotSpot);
        var frames:Vector.<BitmapData> = new Vector.<BitmapData>();
        frames.push(new BitmapData(16, 16, true, 0xFF00FF00));
        data.data = frames;
        data.frameRate = 12;
        data.hotSpot = new Point(3, 4);
        trace("stored", data.data === frames, data.data.length, data.frameRate, data.hotSpot);

        trace("// Multitouch");
        trace("inputMode", Multitouch.inputMode);
        Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;
        trace("inputMode set", Multitouch.inputMode);
        try {
            Multitouch.inputMode = "bogus";
            trace("inputMode bogus accepted");
        } catch (e:Error) {
            trace("inputMode bogus THREW", getQualifiedClassName(e), e.errorID);
        }
        Multitouch.inputMode = MultitouchInputMode.GESTURE;
        trace("mapTouchToMouse", Multitouch.mapTouchToMouse);
        Multitouch.mapTouchToMouse = false;
        trace("mapTouchToMouse set", Multitouch.mapTouchToMouse);
        trace("maxTouchPoints", Multitouch.maxTouchPoints);
        trace("supportedGestures", Multitouch.supportedGestures);
        trace("supportsGestureEvents", Multitouch.supportsGestureEvents);
        trace("supportsTouchEvents", Multitouch.supportsTouchEvents);

        trace("// ByteArray");
        var ba:ByteArray = new ByteArray();
        trace("shareable default", ba.shareable);
        ba.shareable = true;
        trace("shareable set", ba.shareable);
        ba.shareable = false;
        trace("shareable reset", ba.shareable);

        ba.endian = Endian.LITTLE_ENDIAN;
        ba.writeInt(10);
        ba.writeInt(20);
        ba.writeInt(30);
        trace("cas mismatch", ba.atomicCompareAndSwapIntAt(4, 99, 7), readIntAt(ba, 4));
        trace("cas match", ba.atomicCompareAndSwapIntAt(4, 20, 7), readIntAt(ba, 4));
        trace("cas 0", ba.atomicCompareAndSwapIntAt(0, 10, -1), readIntAt(ba, 0));
        trace("length after cas", ba.length, ba.position);
        try {
            ba.atomicCompareAndSwapIntAt(2, 0, 0);
            trace("unaligned accepted");
        } catch (e:Error) {
            trace("unaligned THREW", getQualifiedClassName(e), e.errorID);
        }
        try {
            ba.atomicCompareAndSwapIntAt(-4, 0, 0);
            trace("negative accepted");
        } catch (e:Error) {
            trace("negative THREW", getQualifiedClassName(e), e.errorID);
        }
        try {
            ba.atomicCompareAndSwapIntAt(12, 0, 0);
            trace("past end accepted");
        } catch (e:Error) {
            trace("past end THREW", getQualifiedClassName(e), e.errorID);
        }
        try {
            ba.atomicCompareAndSwapIntAt(10, 0, 0);
            trace("straddling accepted");
        } catch (e:Error) {
            trace("straddling THREW", getQualifiedClassName(e), e.errorID);
        }
        trace("cas length mismatch", ba.atomicCompareAndSwapLength(5, 100), ba.length);
        trace("cas length match", ba.atomicCompareAndSwapLength(12, 16), ba.length);
        trace("cas length shrink", ba.atomicCompareAndSwapLength(16, 4), ba.length);
        trace("cas length same", ba.atomicCompareAndSwapLength(4, 4), ba.length);

        trace("// writeObject with a repeated object");
        var shared:Object = {a: 1};
        var holder:Object = {x: shared, y: shared, list: [shared, shared]};
        var amf3:ByteArray = new ByteArray();
        amf3.objectEncoding = ObjectEncoding.AMF3;
        amf3.writeObject(holder);
        amf3.position = 0;
        var back:Object = amf3.readObject();
        trace("amf3 bytes", amf3.length);
        trace("amf3 identity", back.x === back.y, back.list[0] === back.x, back.list[1] === back.x, back.x.a);
        var amf0:ByteArray = new ByteArray();
        amf0.objectEncoding = ObjectEncoding.AMF0;
        amf0.writeObject(holder);
        amf0.position = 0;
        var back0:Object = amf0.readObject();
        trace("amf0 bytes", amf0.length);
        trace("amf0 identity", back0.x === back0.y, back0.list[0] === back0.x, back0.list[1] === back0.x, back0.x.a);
    }

    private static function readIntAt(ba:ByteArray, pos:uint):int {
        var old:uint = ba.position;
        ba.position = pos;
        var v:int = ba.readInt();
        ba.position = old;
        return v;
    }
}
}
