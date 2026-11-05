package {
import flash.display.*;
import flash.events.Event;
import flash.filters.ShaderFilter;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// BitmapData.applyFilter with a ShaderFilter over a sourceRect that is not the whole source:
// the region is copied to a temporary bitmap of the rect's size, the shader runs over it
// and the result lands at destPoint (simple_shader.pbj writes a constant FF640000 pixel).
// Needs a GPU renderer (imgtests); the edge behaviour is not Flash-verified (see
// timffle/docs/CHANGES-FROM-RUFFLE.md).
public class Test extends Sprite {
    private var pbj:ByteArray;

    public function Test() {
        var self:Test = this;
        var loader:URLLoader = new URLLoader();
        loader.dataFormat = URLLoaderDataFormat.BINARY;
        loader.addEventListener(Event.COMPLETE, function(e:Event):void {
            pbj = loader.data as ByteArray;
            trace("# pbj loaded bytes=" + pbj.length);
            step("filters", self.runFilters);
        });
        loader.load(new URLRequest("simple_shader.pbj"));
    }

    private static function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private static function hex(v:uint):String {
        var s:String = v.toString(16).toUpperCase();
        while (s.length < 8) s = "0" + s;
        return s;
    }

    private static function px(bd:BitmapData, x:int, y:int):String {
        return x + "," + y + "=" + hex(bd.getPixel32(x, y));
    }

    private function makeShader():Shader {
        var bytes:ByteArray = new ByteArray();
        bytes.writeBytes(pbj);
        var sh:Shader = new Shader(bytes);
        sh.data.radius.value = [100];
        sh.data.otherParam.value = [0];
        return sh;
    }

    private function runFilters():void {
        var filter:ShaderFilter = new ShaderFilter(makeShader());
        var src:BitmapData = new BitmapData(8, 8, true, 0xFF0000FF);

        // whole source
        var dst:BitmapData = new BitmapData(8, 8, true, 0xFF00FF00);
        dst.applyFilter(src, src.rect, new Point(0, 0), filter);
        trace("whole " + px(dst, 0, 0) + " " + px(dst, 7, 7));

        // sub-rect to a dest point
        dst = new BitmapData(8, 8, true, 0xFF00FF00);
        dst.applyFilter(src, new Rectangle(2, 2, 4, 4), new Point(1, 1), filter);
        trace("sub " + px(dst, 0, 0) + " " + px(dst, 1, 1) + " " + px(dst, 4, 4) + " " + px(dst, 5, 5) + " " + px(dst, 7, 7));

        // sub-rect reaching outside the source is clamped
        dst = new BitmapData(8, 8, true, 0xFF00FF00);
        dst.applyFilter(src, new Rectangle(6, 6, 4, 4), new Point(0, 0), filter);
        trace("clamped " + px(dst, 0, 0) + " " + px(dst, 1, 1) + " " + px(dst, 2, 2));

        // empty rect: nothing
        dst = new BitmapData(8, 8, true, 0xFF00FF00);
        dst.applyFilter(src, new Rectangle(2, 2, 0, 0), new Point(0, 0), filter);
        trace("empty " + px(dst, 0, 0) + " " + px(dst, 2, 2));

        // generateFilterRect still covers the whole bitmap
        var r:Rectangle = src.generateFilterRect(new Rectangle(2, 2, 4, 4), filter);
        trace("generateFilterRect " + r);
    }
}
}
