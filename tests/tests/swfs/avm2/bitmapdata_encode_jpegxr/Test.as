package {
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.geom.Rectangle;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLRequestMethod;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// BitmapData.encode with JPEGXREncoderOptions: the file layout, the option checks and their
// order, and decoding the result again with Loader.loadBytes (lossless = every pixel back;
// lossy opaque = the very pixels Flash decodes, because the files are the same as Flash's).
// output.txt is the standalone Flash Player 32.0.0.465 run of this very SWF (served over HTTP
// by the difftest server, which is the only case where the lines are also POSTed); the 4:2:0 and
// 4:2:2 lines were added and re-recorded the same way. File lengths
// are not printed: Flash appends one or two zero bytes after the codestream.
public class Test extends Sprite {
    private static var lines:Array = [];
    private var queue:Array = [];

    private static function log(s:String):void {
        trace(s);
        lines.push(s);
    }

    private static function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            log(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private static function hex(b:ByteArray, from:int, to:int):String {
        var s:String = "";
        for (var i:int = from; i < to && i < b.length; i++) {
            var v:int = b[i];
            s += (v < 16 ? "0" : "") + v.toString(16);
        }
        return s;
    }

    private static function gradient(w:int, h:int, transparent:Boolean):BitmapData {
        var bd:BitmapData = new BitmapData(w, h, transparent, 0);
        for (var y:int = 0; y < h; y++) {
            for (var x:int = 0; x < w; x++) {
                var r:int = int(x * 255 / Math.max(1, w - 1));
                var g:int = int(y * 255 / Math.max(1, h - 1));
                var b:int = (x * 37 + y * 91) & 255;
                var a:int = transparent ? (((x + y) & 1) == 0 ? 255 : ((x * 13 + y * 7) & 255)) : 255;
                bd.setPixel32(x, y, (a << 24) | (r << 16) | (g << 8) | b);
            }
        }
        return bd;
    }

    private static function noise(w:int, h:int, transparent:Boolean):BitmapData {
        var bd:BitmapData = new BitmapData(w, h, transparent, 0);
        var s:uint = 12345;
        for (var y:int = 0; y < h; y++) {
            for (var x:int = 0; x < w; x++) {
                s = uint(s * 69069 + 1);
                var c:uint = s >>> 8;
                var a:uint = transparent ? ((s >>> 24) | 1) : 255;
                bd.setPixel32(x, y, (a << 24) | (c & 0xffffff));
            }
        }
        return bd;
    }

    public function Test() {
        var g8o:BitmapData = gradient(8, 8, false);
        var g8t:BitmapData = gradient(8, 8, true);
        var n37o:BitmapData = noise(37, 21, false);
        var n40t:BitmapData = noise(40, 18, true);
        var one:BitmapData = new BitmapData(1, 1, true, 0x80ff4020);

        step("defaults", function():void {
            var o:JPEGXREncoderOptions = new JPEGXREncoderOptions();
            log("defaults q=" + o.quantization + " cs=" + o.colorSpace + " trim=" + o.trimFlexBits);
            var out:ByteArray = g8o.encode(g8o.rect, o);
            log("defaults pos==len " + (out.position == out.length) + " endian=" + out.endian);
        });
        header("g8o q0", g8o, 0, "auto", 0);
        header("g8o q20", g8o, 20, "auto", 0);
        header("g8o q20 trim4", g8o, 20, "auto", 4);
        header("g8t q0", g8t, 0, "auto", 0);
        header("g8t q20", g8t, 20, "auto", 0);
        header("one q100", one, 100, "4:4:4", 15);
        header("g8o q20 420", g8o, 20, "4:2:0", 0);
        header("g8o q0 422", g8o, 0, "4:2:2", 0);
        header("g8t q0 420", g8t, 0, "4:2:0", 0);
        header("g8t q50 422", g8t, 50, "4:2:2", 0);

        errors(g8o);

        step("given ByteArray", function():void {
            var ba:ByteArray = new ByteArray();
            ba.writeByte(9);
            ba.writeByte(9);
            ba.writeByte(9);
            ba.position = 1;
            var out:ByteArray = g8o.encode(g8o.rect, new JPEGXREncoderOptions(20), ba);
            log("given same=" + (out == ba) + " pos==len " + (ba.position == ba.length) + " head=" + hex(ba, 0, 6));
        });
        step("sizes", function():void {
            var a:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(0));
            var b:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(20));
            var c:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(80));
            log("sizes q0>q20>q80 " + (a.length > b.length && b.length > c.length));
        });
        step("sizes cs", function():void {
            var f:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(20, "4:4:4"));
            var h:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(20, "4:2:2"));
            var q:ByteArray = n37o.encode(n37o.rect, new JPEGXREncoderOptions(20, "4:2:0"));
            log("sizes 444>422>420 " + (f.length > h.length && h.length > q.length));
        });

        roundTrip("g8o q0", g8o, g8o.rect, 0, "auto", 0);
        roundTrip("g8t q0", g8t, g8t.rect, 0, "auto", 0);
        roundTrip("n37o q0", n37o, n37o.rect, 0, "4:4:4", 0);
        roundTrip("n40t q0", n40t, n40t.rect, 0, "auto", 0);
        roundTrip("one q0", one, one.rect, 0, "auto", 0);
        roundTrip("n40t sub q0", n40t, new Rectangle(3, 5, 17, 9), 0, "auto", 0);
        roundTrip("g8o q20", g8o, g8o.rect, 20, "auto", 0);
        roundTrip("g8t q20", g8t, g8t.rect, 20, "auto", 0);
        roundTrip("n37o q20", n37o, n37o.rect, 20, "auto", 0);
        roundTrip("n40t q50", n40t, n40t.rect, 50, "auto", 0);
        roundTrip("n37o q20 trim6", n37o, n37o.rect, 20, "auto", 6);
        roundTrip("n40t q20 trim6", n40t, n40t.rect, 20, "auto", 6);
        roundTrip("g8o q0 420", g8o, g8o.rect, 0, "4:2:0", 0);
        roundTrip("n37o q0 420", n37o, n37o.rect, 0, "4:2:0", 0);
        roundTrip("n37o q20 422", n37o, n37o.rect, 20, "4:2:2", 0);
        roundTrip("n37o q50 420", n37o, n37o.rect, 50, "4:2:0", 0);
        roundTrip("n37o sub q0 422", n37o, new Rectangle(5, 3, 19, 11), 0, "4:2:2", 0);
        roundTrip("g8t q0 422", g8t, g8t.rect, 0, "4:2:2", 0);
        roundTrip("n40t q20 420", n40t, n40t.rect, 20, "4:2:0", 0);
        next();
    }

    private static function header(name:String, bd:BitmapData, q:uint, cs:String, trim:uint):void {
        step(name, function():void {
            var out:ByteArray = bd.encode(bd.rect, new JPEGXREncoderOptions(q, cs, trim));
            // container (without ImageByteCount) and the codestream headers
            log(name + " container=" + hex(out, 0, 66) + "|" + hex(out, 70, 90));
            log(name + " codestream=" + hex(out, 90, 90 + 40));
        });
    }

    private static function errors(bd:BitmapData):void {
        var cases:Array = [
            ["q100", bd.rect, 100, "auto", 0],
            ["q101", bd.rect, 101, "auto", 0],
            ["q4294967295", bd.rect, 4294967295, "auto", 0],
            ["cs null", bd.rect, 20, null, 0],
            ["cs x", bd.rect, 20, "x", 0],
            ["cs AUTO", bd.rect, 20, "AUTO", 0],
            ["cs 4:2:0", bd.rect, 20, "4:2:0", 0],
            ["cs 4:2:2", bd.rect, 20, "4:2:2", 0],
            ["cs 4:4:4", bd.rect, 20, "4:4:4", 0],
            ["trim15", bd.rect, 20, "auto", 15],
            ["trim16", bd.rect, 20, "auto", 16],
            ["q200 trim20", bd.rect, 200, "auto", 20],
            ["q200 cs x", bd.rect, 200, "x", 0],
            ["cs x trim20", bd.rect, 20, "x", 20],
            ["empty rect q200", new Rectangle(0, 0, 0, 0), 200, "x", 20],
            ["outside rect", new Rectangle(20, 20, 4, 4), 20, "auto", 0]
        ];
        for each (var c:Array in cases) {
            step(c[0], function():void {
                var o:JPEGXREncoderOptions = new JPEGXREncoderOptions(c[2], "auto", c[4]);
                o.colorSpace = c[3];
                var out:ByteArray = bd.encode(c[1], o);
                log(c[0] + " ok " + hex(out, 0, 4));
            });
        }
        step("disposed q200", function():void {
            var d:BitmapData = new BitmapData(2, 2);
            d.dispose();
            d.encode(new Rectangle(0, 0, 2, 2), new JPEGXREncoderOptions(200));
        });
    }

    private function roundTrip(name:String, bd:BitmapData, rect:Rectangle, q:uint, cs:String, trim:uint):void {
        queue.push(function():void {
            var out:ByteArray;
            step(name + " encode", function():void {
                out = bd.encode(rect, new JPEGXREncoderOptions(q, cs, trim));
            });
            if (out == null) {
                next();
                return;
            }
            var ld:Loader = new Loader();
            ld.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void {
                var info:LoaderInfo = ld.contentLoaderInfo;
                var bmp:BitmapData = Bitmap(ld.content).bitmapData;
                var r:Rectangle = rect.intersection(bd.rect);
                var differ:int = 0;
                var se:Number = 0;
                var sum:uint = 0;
                for (var y:int = 0; y < bmp.height; y++) {
                    for (var x:int = 0; x < bmp.width; x++) {
                        var a:uint = bd.getPixel32(r.x + x, r.y + y);
                        var b:uint = bmp.getPixel32(x, y);
                        if (a != b) differ++;
                        sum = uint(sum * 31 + b);
                        for (var sh:int = 0; sh < 32; sh += 8) {
                            var d:int = int((a >>> sh) & 255) - int((b >>> sh) & 255);
                            se += d * d;
                        }
                    }
                }
                var line:String = name + " loaded " + info.contentType + " " + bmp.width + "x" + bmp.height +
                    " transparent=" + bmp.transparent;
                // 4:2:0 and 4:2:2 subsample the chroma even with quantization 0
                if (q == 0 && trim == 0 && (cs == "auto" || cs == "4:4:4")) {
                    line += " differing=" + differ;
                } else {
                    var psnr:Number = 10 * Math.log(255 * 255 / Math.max(se / (bmp.width * bmp.height * 4), 1e-9)) / Math.LN10;
                    line += " psnr>=" + (psnr >= 30 ? 30 : psnr >= 20 ? 20 : psnr >= 10 ? 10 : 0);
                    // Flash's decoder rounds lossy alpha differently from jxrlib's in some
                    // pixels (one level), so the exact pixels are only compared when opaque.
                    if (!bd.transparent) {
                        line += " checksum=" + sum.toString(16);
                    }
                }
                log(line);
                next();
            });
            ld.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
                log(name + " IO_ERROR");
                next();
            });
            out.position = 0;
            ld.loadBytes(out);
        });
    }

    private function next():void {
        if (queue.length > 0) {
            queue.shift()();
            return;
        }
        log("done");
        var url:String = loaderInfo.url;
        if (url.indexOf("http://127.0.0.1:") == 0) {
            var req:URLRequest = new URLRequest(url.substr(0, url.indexOf("/t/")) + "/report?runner=flash&test=bitmapdata_encode_jpegxr");
            req.method = URLRequestMethod.POST;
            req.contentType = "text/plain";
            req.data = lines.join("\n");
            new URLLoader().load(req);
        }
    }
}
}
