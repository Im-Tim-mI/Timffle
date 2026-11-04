package {
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.filters.*;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.net.URLRequest;
import flash.text.TextField;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// BitmapData.generateFilterRect / encode, DisplayObjectContainer.getObjectsUnderPoint /
// areInaccessibleObjectsUnderPoint, AVLoader.load and AVM1Movie.call / addCallback in Flash
// Player (not AIR). Every expected value comes from the standalone Flash Player 32.0.0.465
// (timffle/difftest/src/D51DisplayMisc.hx, D52DisplayEdge.hx, D53BlurRect.hx, D54BlurRect2.hx),
// except the PNG/JPEG byte lengths, which depend on the encoder and are not printed.
public class Test extends Sprite {
    private var png:ByteArray;
    private var jpeg:ByteArray;

    public function Test() {
        filterRects();
        encode();
        underPoint();
        step("AVLoader.load", function():void {
            var l:AVLoader = new AVLoader();
            trace("AVLoader is Loader " + (l is Loader) + " cli=" + (l.contentLoaderInfo != null));
            l.load(new URLRequest("assetA.swf"));
            trace("returned");
        });
        loadPng();
    }

    private static function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private static function r(x:Rectangle):String {
        return x == null ? "null" : "(" + x.x + "," + x.y + "," + x.width + "," + x.height + ")";
    }

    private static function hex(b:ByteArray, from:uint, n:uint):String {
        var s:String = "";
        var p:uint = b.position;
        b.position = from;
        for (var i:uint = 0; i < n && b.bytesAvailable > 0; i++) {
            var v:uint = b.readUnsignedByte();
            s += (v < 16 ? "0" : "") + v.toString(16);
        }
        b.position = p;
        return s;
    }

    private function filterRects():void {
        var bd:BitmapData = new BitmapData(100, 100, true, 0xFF00FF00);
        var src:Rectangle = new Rectangle(10, 20, 30, 40);
        var fs:Array = [
            ["blur4x4p1", new BlurFilter(4, 4, 1)],
            ["blur4x4p3", new BlurFilter(4, 4, 3)],
            ["blur5.5x2.3p2", new BlurFilter(5.5, 2.3, 2)],
            ["blur0x0p1", new BlurFilter(0, 0, 1)],
            ["blur255x255p15", new BlurFilter(255, 255, 15)],
            ["blur10p0", new BlurFilter(10, 10, 0)],
            ["blur10p16", new BlurFilter(10, 10, 16)],
            ["blur-4p1", new BlurFilter(-4, -4, 1)],
            ["blur4x0p1", new BlurFilter(4, 0, 1)],
            ["blur2.5p1", new BlurFilter(2.5, 2.25, 1)],
            ["blur5p2", new BlurFilter(5, 25, 2)],
            ["blur15p3", new BlurFilter(15, 0, 3)],
            ["blur3p5", new BlurFilter(3, 1.5, 5)],
            ["blur2.5p8", new BlurFilter(2.5, 13, 8)],
            ["blur0.75p12", new BlurFilter(0.75, 0, 12)],
            ["blur1.5p15", new BlurFilter(1.5, 3, 15)],
            ["glow6x6p2", new GlowFilter(0xFF0000, 1, 6, 6, 2, 2)],
            ["glowInner6x6p2", new GlowFilter(0xFF0000, 1, 6, 6, 2, 2, true)],
            ["shadow d4 a45 b4p1", new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1)],
            ["shadow d4 a225 b4p1", new DropShadowFilter(4, 225, 0, 1, 4, 4, 1, 1)],
            ["shadow d10 a0 b0p1", new DropShadowFilter(10, 0, 0, 1, 0, 0, 1, 1)],
            ["shadow d4 a90 b0", new DropShadowFilter(4, 90, 0, 1, 0, 0, 1, 1)],
            ["shadow d2.5 a0 b0", new DropShadowFilter(2.5, 0, 0, 1, 0, 0, 1, 1)],
            ["shadow d-4 a0 b0", new DropShadowFilter(-4, 0, 0, 1, 0, 0, 1, 1)],
            ["shadow d4 a30 b0", new DropShadowFilter(4, 30, 0, 1, 0, 0, 1, 1)],
            ["shadowInner d4 a45 b4p1", new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1, true)],
            ["shadowHide d4 a45 b4p1", new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1, false, false, true)],
            ["shadow d4 a0 b2 q2", new DropShadowFilter(4, 0, 0, 1, 2, 2, 2, 1)],
            ["bevel d4 a45 b4p1", new BevelFilter(4, 45, 0xFFFFFF, 1, 0, 1, 4, 4, 1, 1)],
            ["bevel d4 a45 b4p1 inner", new BevelFilter(4, 45, 0xFFFFFF, 1, 0, 1, 4, 4, 1, 1, "inner")],
            ["bevel d2.5 a0 b0", new BevelFilter(2.5, 0, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)],
            ["bevel d4 a30 b0", new BevelFilter(4, 30, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)],
            ["gglow b4p1 d4", new GradientGlowFilter(4, 45, [0, 0xFF0000], [0, 1], [0, 255], 4, 4, 1, 1)],
            ["gbevel b4p1 d4", new GradientBevelFilter(4, 45, [0, 0xFF0000], [0, 1], [0, 255], 4, 4, 1, 1)],
            ["colormatrix", new ColorMatrixFilter()],
            ["convolution3x3", new ConvolutionFilter(3, 3, [0, 0, 0, 0, 1, 0, 0, 0, 0])],
            ["convolution5x7", new ConvolutionFilter(5, 7)],
            ["convolution4x4", new ConvolutionFilter(4, 4)],
            ["convolution1.5x2.5", new ConvolutionFilter(1.5, 2.5)],
            ["dmap color 10x10", new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, 10, 10, "color")],
            ["dmap wrap -10x-10", new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, -10, -10, "wrap")]
        ];
        for each (var e:Array in fs) {
            trace("gfr " + e[0] + " " + r(bd.generateFilterRect(src, e[1])));
        }
        trace("gfr outside " + r(bd.generateFilterRect(new Rectangle(-20, -20, 500, 500), new BlurFilter(4, 4, 1))));
        trace("gfr empty " + r(bd.generateFilterRect(new Rectangle(10, 10, 0, 0), new BlurFilter(4, 4, 1))));
        trace("gfr negsize " + r(bd.generateFilterRect(new Rectangle(10, 10, -5, -5), new BlurFilter(4, 4, 1))));
        trace("gfr frac " + r(bd.generateFilterRect(new Rectangle(10.4, 10.6, 30.3, 30.7), new BlurFilter(4, 4, 1))));
        trace("gfr frac2 " + r(bd.generateFilterRect(new Rectangle(10.5, 11.5, 30.5, 30.5), new ColorMatrixFilter())));
        trace("gfr frac4 " + r(bd.generateFilterRect(new Rectangle(0.4, 0.6, 99.3, 99.7), new ColorMatrixFilter())));
        trace("gfr clampleft " + r(bd.generateFilterRect(new Rectangle(-5, -5, 20, 20), new ColorMatrixFilter())));
        trace("gfr fullyout " + r(bd.generateFilterRect(new Rectangle(200, 200, 20, 20), new ColorMatrixFilter())));
        trace("gfr fullyout blur " + r(bd.generateFilterRect(new Rectangle(200, 200, 20, 20), new BlurFilter(4, 4, 1))));
        trace("gfr negout " + r(bd.generateFilterRect(new Rectangle(-50, -50, 20, 20), new ColorMatrixFilter())));
        trace("gfr shader " + r(bd.generateFilterRect(src, new ShaderFilter())));
        step("gfr nullrect", function():void { trace(r(bd.generateFilterRect(null, new BlurFilter(4, 4, 1)))); });
        step("gfr nullfilter", function():void { trace(r(bd.generateFilterRect(src, null))); });
        var res:Rectangle = bd.generateFilterRect(src, new ColorMatrixFilter());
        trace("gfr returns new rect " + (res != src));
        bd.dispose();
        step("gfr disposed", function():void { trace(r(bd.generateFilterRect(src, new BlurFilter(4, 4, 1)))); });
    }

    private function encode():void {
        var bd:BitmapData = new BitmapData(8, 6, true, 0x80FF0000);
        bd.setPixel32(1, 1, 0xFF00FF00);
        var full:Rectangle = bd.rect;
        var opaque:BitmapData = new BitmapData(8, 6, false, 0xFF0000FF);
        var cases:Array = [
            ["png", bd, full, new PNGEncoderOptions()],
            ["png fast", bd, full, new PNGEncoderOptions(true)],
            ["png opaque", opaque, full, new PNGEncoderOptions()],
            ["png sub", bd, new Rectangle(2, 1, 3, 2), new PNGEncoderOptions()],
            ["png outside", bd, new Rectangle(-2, -2, 20, 20), new PNGEncoderOptions()],
            ["jpeg80", bd, full, new JPEGEncoderOptions()],
            ["jpeg0", bd, full, new JPEGEncoderOptions(0)],
            ["jpeg100", opaque, new Rectangle(1, 1, 5, 3), new JPEGEncoderOptions(100)]
        ];
        for each (var e:Array in cases) {
            step("encode " + e[0], function():void {
                var out:ByteArray = e[1].encode(e[2], e[3]);
                var desc:String = "encode " + e[0] + " pos=len " + (out.position == out.length) + " endian=" + out.endian;
                if (hex(out, 0, 8) == "89504e470d0a1a0a") {
                    out.position = 16;
                    desc += " PNG " + out.readUnsignedInt() + "x" + out.readUnsignedInt() + " depth=" + out.readUnsignedByte() + " colorType=" + out.readUnsignedByte();
                } else if (hex(out, 0, 2) == "ffd8") {
                    desc += " JPEG app0=" + hex(out, 2, 2) + " " + hex(out, 6, 4);
                } else {
                    desc += " ??? " + hex(out, 0, 8);
                }
                trace(desc);
            });
        }
        step("encode jpeg200", function():void { trace(bd.encode(full, new JPEGEncoderOptions(200))); });
        step("encode disjoint", function():void { trace(bd.encode(new Rectangle(50, 50, 4, 4), new PNGEncoderOptions())); });
        step("encode empty", function():void { trace(bd.encode(new Rectangle(1, 1, 0, 0), new PNGEncoderOptions())); });
        step("encode nullrect", function():void { trace(bd.encode(null, new PNGEncoderOptions())); });
        step("encode obj compressor", function():void { trace(bd.encode(full, {quality: 50})); });
        step("encode null compressor", function():void { trace(bd.encode(full, null)); });
        step("encode string compressor", function():void { trace(bd.encode(full, "png")); });
        step("encode into prefilled", function():void {
            var ba:ByteArray = new ByteArray();
            ba.writeUTFBytes("hello world!");
            ba.position = 5;
            var out:ByteArray = bd.encode(full, new PNGEncoderOptions(), ba);
            trace("encode prefilled same=" + (out == ba) + " pos=len " + (ba.position == ba.length) + " head=" + hex(ba, 0, 13));
        });
        png = bd.encode(full, new PNGEncoderOptions());
        jpeg = opaque.encode(full, new JPEGEncoderOptions(90));
        bd.dispose();
        step("encode disposed", function():void { trace(bd.encode(new Rectangle(0, 0, 1, 1), new PNGEncoderOptions())); });
    }

    private static function names(a:Array):String {
        if (a == null) {
            return "null";
        }
        var out:Array = [];
        for each (var o:DisplayObject in a) {
            out.push(o.name);
        }
        return "[" + out.join(",") + "] len=" + a.length;
    }

    private static function box(name:String, x:Number, y:Number, w:Number, h:Number, alpha:Number = 1):Sprite {
        var s:Sprite = new Sprite();
        s.name = name;
        s.graphics.beginFill(0xFF0000, alpha);
        s.graphics.drawRect(0, 0, w, h);
        s.graphics.endFill();
        s.x = x;
        s.y = y;
        return s;
    }

    private function underPoint():void {
        var cont:Sprite = new Sprite();
        cont.name = "cont";
        addChild(cont);
        var a:Sprite = box("a", 0, 0, 50, 50);
        var b:Sprite = box("b", 25, 25, 50, 50);
        b.addChild(box("inner", 10, 10, 10, 10));
        var shape:Shape = new Shape();
        shape.name = "shape";
        shape.graphics.beginFill(0x00FF00);
        shape.graphics.drawRect(0, 0, 100, 100);
        shape.x = 200;
        var tf:TextField = new TextField();
        tf.name = "tf";
        tf.x = 200;
        tf.y = 200;
        tf.width = 50;
        tf.height = 20;
        tf.text = "hi";
        var bmp:Bitmap = new Bitmap(new BitmapData(20, 20, true, 0x00000000));
        bmp.name = "bmp";
        bmp.x = 300;
        var empty:Sprite = new Sprite();
        empty.name = "empty";
        var hidden:Sprite = box("hidden", 0, 100, 20, 20);
        hidden.visible = false;
        var nomouse:Sprite = box("nomouse", 100, 100, 20, 20);
        nomouse.mouseEnabled = false;
        var nmc:Sprite = box("nmc", 100, 150, 20, 20);
        nmc.mouseChildren = false;
        nmc.addChild(box("nmcchild", 0, 0, 10, 10));
        var alpha0:Sprite = box("alpha0", 150, 100, 20, 20, 0);
        var alphaprop:Sprite = box("alphaprop", 150, 150, 20, 20);
        alphaprop.alpha = 0;
        var maskSp:Sprite = box("mask", 0, 200, 10, 10);
        var masked:Sprite = box("masked", 0, 200, 50, 50);
        masked.mask = maskSp;
        var masked2:Sprite = box("masked2", 60, 200, 50, 50);
        masked2.mask = box("mask2", 0, 0, 1, 1);
        var line:Sprite = new Sprite();
        line.name = "line";
        line.graphics.lineStyle(4, 0);
        line.graphics.moveTo(0, 0);
        line.graphics.lineTo(40, 0);
        line.x = 300;
        line.y = 100;
        var btn:SimpleButton = new SimpleButton();
        btn.name = "btn";
        btn.upState = box("up", 0, 0, 20, 20);
        btn.overState = box("over", 0, 0, 20, 20);
        btn.downState = box("down", 0, 0, 20, 20);
        btn.hitTestState = box("hit", 0, 0, 40, 40);
        btn.x = 300;
        btn.y = 200;
        var btn2:SimpleButton = new SimpleButton();
        btn2.name = "btn2";
        btn2.upState = box("up2", 0, 0, 40, 40);
        btn2.hitTestState = box("hit2", 0, 0, 10, 10);
        btn2.x = 350;
        btn2.y = 200;
        var scaled:Sprite = box("scaled", 200, 300, 10, 10);
        scaled.scaleX = 4;
        scaled.scaleY = 4;
        var rotated:Sprite = box("rotated", 300, 300, 40, 40);
        rotated.rotation = 45;
        var nested:Sprite = new Sprite();
        nested.name = "nested";
        nested.x = 100;
        nested.y = 300;
        nested.addChild(box("n1", 0, 0, 20, 20));
        nested.addChild(box("n2", 0, 0, 20, 20));
        nested.addChild(box("n3", 10, 10, 20, 20));
        var scrolled:Sprite = box("scrolled", 200, 400, 50, 50);
        scrolled.scrollRect = new Rectangle(0, 0, 10, 10);
        var mc:MovieClip = new MovieClip();
        mc.name = "mc";
        mc.graphics.beginFill(0xFF);
        mc.graphics.drawRect(0, 0, 20, 20);
        mc.x = 300;
        mc.y = 400;
        for each (var c:DisplayObject in [a, b, shape, tf, bmp, empty, hidden, nomouse, nmc, alpha0, alphaprop, maskSp, masked, masked2, line, btn, btn2, scaled, rotated, nested, scrolled, mc]) {
            cont.addChild(c);
        }
        var p:Function = function(label:String, c:DisplayObjectContainer, x:Number, y:Number):void {
            step(label, function():void { trace(label + " (" + x + "," + y + ") " + names(c.getObjectsUnderPoint(new Point(x, y)))); });
        };
        p("overlap", cont, 30, 30);
        p("overlap root", this, 30, 30);
        p("overlap stage", stage, 30, 30);
        p("only a", cont, 5, 5);
        p("inner", cont, 40, 40);
        p("inner from b", b, 15, 15);
        p("inner from b global", b, 40, 40);
        p("shape", cont, 250, 50);
        p("tf", cont, 210, 210);
        p("bmp transparent", cont, 310, 10);
        p("empty region", cont, 150, 50);
        p("hidden", cont, 10, 110);
        p("nomouse", cont, 110, 110);
        p("nmc", cont, 105, 155);
        p("alpha0 fill", cont, 160, 110);
        p("alphaprop", cont, 160, 160);
        p("masked in", cont, 5, 205);
        p("masked out", cont, 30, 230);
        p("masked2 out", cont, 70, 210);
        p("line", cont, 320, 100);
        p("line 3 off", cont, 320, 103);
        p("btn up", cont, 310, 210);
        p("btn hit only", cont, 330, 230);
        p("btn2 up only", cont, 380, 230);
        p("btn2 hit", cont, 355, 205);
        p("scaled", cont, 230, 330);
        p("rotated inside", cont, 300, 320);
        p("rotated corner", cont, 325, 302);
        p("nested", cont, 115, 315);
        p("scrolled in", cont, 205, 405);
        p("scrolled out", cont, 230, 430);
        p("mc", cont, 310, 410);
        p("far", cont, 1000, 1000);
        step("null point", function():void { trace(names(cont.getObjectsUnderPoint(null))); });
        step("inacc", function():void { trace("inacc " + cont.areInaccessibleObjectsUnderPoint(new Point(30, 30)) + " " + cont.areInaccessibleObjectsUnderPoint(new Point(1000, 1000)) + " stage " + stage.areInaccessibleObjectsUnderPoint(new Point(30, 30))); });
        step("inacc null", function():void { trace(cont.areInaccessibleObjectsUnderPoint(null)); });
        var self:Sprite = box("self", 400, 400, 30, 30);
        addChild(self);
        self.addChild(box("selfchild", 0, 0, 10, 10));
        p("self from self", self, 5, 5);
        p("self from self global", self, 405, 405);
        p("self from root", this, 405, 405);
        p("self from root 420", this, 420, 420);
        var off:Sprite = new Sprite();
        off.name = "off";
        off.addChild(box("offchild", 0, 0, 20, 20));
        p("off stage", off, 5, 5);
    }

    private function loadPng():void {
        var l:Loader = new Loader();
        l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void {
            var bmp:Bitmap = l.content as Bitmap;
            trace("png decoded " + getQualifiedClassName(l.content) + " " + bmp.bitmapData.width + "x" + bmp.bitmapData.height + " transparent=" + bmp.bitmapData.transparent + " (0,0)=" + bmp.bitmapData.getPixel32(0, 0).toString(16) + " (1,1)=" + bmp.bitmapData.getPixel32(1, 1).toString(16));
            loadJpeg();
        });
        l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
            trace("png decode failed " + e.text);
            loadJpeg();
        });
        l.loadBytes(png);
    }

    private function loadJpeg():void {
        var l:Loader = new Loader();
        l.contentLoaderInfo.addEventListener(Event.COMPLETE, function(e:Event):void {
            var bmp:Bitmap = l.content as Bitmap;
            var px:uint = bmp.bitmapData.getPixel(3, 3);
            trace("jpeg decoded " + getQualifiedClassName(l.content) + " " + bmp.bitmapData.width + "x" + bmp.bitmapData.height + " blue-ish=" + ((px & 0xFF) > 0xE0 && (px >> 16) < 0x20));
            loadAvm1();
        });
        l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
            trace("jpeg decode failed " + e.text);
            loadAvm1();
        });
        l.loadBytes(jpeg);
    }

    private function loadAvm1():void {
        // A minimal SWF 8 movie (one ShowFrame): FWS header, 400x300 twips rect, 12 fps, 1 frame.
        var bytes:ByteArray = new ByteArray();
        for each (var v:uint in [0x46, 0x57, 0x53, 0x08, 0x19, 0x00, 0x00, 0x00, 0x78, 0x00, 0x03, 0xE8, 0x00, 0x00, 0x0B, 0xB8, 0x00, 0x00, 0x0C, 0x01, 0x00, 0x40, 0x00, 0x00, 0x00]) {
            bytes.writeByte(v);
        }
        var l:Loader = new Loader();
        l.contentLoaderInfo.addEventListener(Event.INIT, function(e:Event):void {
            var c:* = l.content;
            trace("AVM1 content " + getQualifiedClassName(c) + " avm=" + l.contentLoaderInfo.actionScriptVersion + " swfv=" + l.contentLoaderInfo.swfVersion);
            step("AVM1Movie.addCallback", function():void { trace("addCallback = " + c.addCallback("f", function(a:*):* { return a; })); });
            step("AVM1Movie.addCallback null", function():void { trace("addCallback null = " + c.addCallback(null, null)); });
            step("AVM1Movie.call", function():void { trace("call = " + c.call("g", 1, 2)); });
            step("AVM1Movie.call null", function():void { trace("call null = " + c.call(null)); });
            trace("done");
        });
        l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
            trace("AVM1 load failed " + e.text);
        });
        l.loadBytes(bytes);
        addChild(l);
    }
}
}
