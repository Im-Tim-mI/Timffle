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

// BitmapData.applyFilter with a ShaderFilter, whole source and sub-rectangles.
// tintype.pbj (one image input `src`, from the pixelbender_effect_tintype test) maps
// each source pixel to a tinted grey; the sources are red gradients, so every output
// pixel shows which source pixel it came from.
// simple_shader.pbj has no image input. output.txt was recorded with Flash Player 32
// (Wine) and needs a GPU renderer here (imgtests).
public class Test extends Sprite {
    private var tintype:ByteArray;
    private var simple:ByteArray;

    public function Test() {
        var self:Test = this;
        load("tintype.pbj", function(b:ByteArray):void {
            tintype = b;
            load("simple_shader.pbj", function(b2:ByteArray):void {
                simple = b2;
                trace("# pbj loaded bytes=" + tintype.length + " " + simple.length);
                self.runFilters();
            });
        });
    }

    private static function load(url:String, done:Function):void {
        var loader:URLLoader = new URLLoader();
        loader.dataFormat = URLLoaderDataFormat.BINARY;
        loader.addEventListener(Event.COMPLETE, function(e:Event):void {
            done(loader.data as ByteArray);
        });
        loader.load(new URLRequest(url));
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

    private static function row(bd:BitmapData, y:int):String {
        var out:Array = [];
        for (var x:int = 0; x < bd.width; x++) {
            out.push(hex(bd.getPixel32(x, y)));
        }
        return out.join(" ");
    }

    // Column gradient (red = 20 + 29 * x) or row gradient (red = 20 + 29 * y): after the tint
    // every column (row) has its own grey, so each output pixel shows its source pixel.
    private static function source(rows:Boolean):BitmapData {
        var src:BitmapData = new BitmapData(8, 8, true, 0);
        for (var y:int = 0; y < 8; y++) {
            for (var x:int = 0; x < 8; x++) {
                src.setPixel32(x, y, 0xFF000000 | ((20 + 29 * (rows ? y : x)) << 16));
            }
        }
        return src;
    }

    // One line per row: the red byte of each pixel, "--" where the destination kept its green.
    private static function dump(label:String, bd:BitmapData):void {
        for (var y:int = 0; y < bd.height; y++) {
            var out:Array = [];
            for (var x:int = 0; x < bd.width; x++) {
                var p:uint = bd.getPixel32(x, y);
                if (p == 0xFF00FF00) {
                    out.push("--");
                } else {
                    var r:String = ((p >> 16) & 0xFF).toString(16).toUpperCase();
                    out.push(r.length < 2 ? "0" + r : r);
                }
            }
            trace(label + " " + y + ": " + out.join(" "));
        }
    }

    private function tint():ShaderFilter {
        var bytes:ByteArray = new ByteArray();
        bytes.writeBytes(tintype);
        return new ShaderFilter(new Shader(bytes));
    }

    private function apply(label:String, rect:Rectangle, pt:Point):void {
        for each (var rows:Boolean in [false, true]) {
            var name:String = label + (rows ? " (rows)" : " (columns)");
            step(name, function():void {
                var dst:BitmapData = new BitmapData(8, 8, true, 0xFF00FF00);
                dst.applyFilter(source(rows), rect, pt, tint());
                dump(name, dst);
            });
        }
    }

    // Source and destination of different widths (2 rows high): row 0 of the result.
    private function applySized(srcW:int, dstW:int, rx:int, w:int, px:int):void {
        var label:String = "src " + srcW + " dst " + dstW + " rect x=" + rx + " w=" + w + " at " + px;
        step(label, function():void {
            var src:BitmapData = new BitmapData(srcW, 2, true, 0);
            for (var x:int = 0; x < srcW; x++) {
                src.setPixel32(x, 0, 0xFF000000 | ((20 + int(200 / srcW) * x) << 16));
                src.setPixel32(x, 1, 0xFF000000 | ((20 + int(200 / srcW) * x) << 16));
            }
            var dst:BitmapData = new BitmapData(dstW, 2, true, 0xFF00FF00);
            dst.applyFilter(src, new Rectangle(rx, 0, w, 2), new Point(px, 0), tint());
            var out:Array = [];
            for (x = 0; x < dstW; x++) {
                var p:uint = dst.getPixel32(x, 0);
                if (p == 0xFF00FF00) {
                    out.push("--");
                } else {
                    var r:String = ((p >> 16) & 0xFF).toString(16).toUpperCase();
                    out.push(r.length < 2 ? "0" + r : r);
                }
            }
            trace(label + ": " + out.join(" "));
        });
    }

    private function runFilters():void {
        apply("whole", new Rectangle(0, 0, 8, 8), new Point(0, 0));
        apply("sub 2,2,4,4 at 1,1", new Rectangle(2, 2, 4, 4), new Point(1, 1));
        apply("sub 2,2,4,4 at 0,0", new Rectangle(2, 2, 4, 4), new Point(0, 0));
        apply("sub 0,0,4,4 at 2,2", new Rectangle(0, 0, 4, 4), new Point(2, 2));
        apply("sub 4,0,2,8 at 1,0", new Rectangle(4, 0, 2, 8), new Point(1, 0));
        apply("clamped 6,6,4,4 at 0,0", new Rectangle(6, 6, 4, 4), new Point(0, 0));
        apply("whole at 5,5", new Rectangle(0, 0, 8, 8), new Point(5, 5));
        apply("empty 2,2,0,0", new Rectangle(2, 2, 0, 0), new Point(0, 0));
        for each (var c:Array in [[8, 12, 0, 8, 0], [8, 12, 2, 4, 1], [8, 12, 0, 4, 6], [8, 12, 1, 2, 3],
                [12, 8, 0, 12, 0], [12, 8, 2, 4, 1], [12, 8, 4, 4, 0], [12, 8, 0, 4, 3], [12, 12, 3, 2, 1]]) {
            applySized(c[0], c[1], c[2], c[3], c[4]);
        }
        step("generateFilterRect", function():void {
            trace("generateFilterRect " + source(false).generateFilterRect(new Rectangle(2, 2, 4, 4), tint()));
        });
        step("shader without an image input", function():void {
            var bytes:ByteArray = new ByteArray();
            bytes.writeBytes(simple);
            var dst:BitmapData = new BitmapData(8, 8, true, 0xFF00FF00);
            dst.applyFilter(source(false), new Rectangle(0, 0, 8, 8), new Point(0, 0), new ShaderFilter(new Shader(bytes)));
            dump("shader without an image input", dst);
        });
    }
}
}
