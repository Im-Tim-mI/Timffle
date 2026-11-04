/** Probe (no golden): flash.display.AVLoader.load, AVM1Movie.call/addCallback,
 *  BitmapData.generateFilterRect/encode, DisplayObjectContainer.getObjectsUnderPoint and
 *  areInaccessibleObjectsUnderPoint in Flash Player 32 (not AIR). Build with -swf-version 32 and run
 *  in the standalone projector served over HTTP (loads /asset/assetA.swf and /asset/avm1a.swf). */
import flash.Lib;
import flash.display.*;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.filters.*;
import flash.geom.Matrix;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.net.URLRequest;
import flash.utils.ByteArray;

class D51DisplayMisc {
	static var qn:Dynamic;
	static var pending = 0;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function r(x:Rectangle):String {
		return x == null ? "null" : "(" + x.x + "," + x.y + "," + x.width + "," + x.height + ")";
	}

	static function hex(b:ByteArray, n:Int):String {
		var s = "";
		var p = b.position;
		b.position = 0;
		for (i in 0...n) {
			if (b.bytesAvailable == 0) break;
			var v = b.readUnsignedByte();
			s += (v < 16 ? "0" : "") + StringTools.hex(v).toLowerCase();
		}
		b.position = p;
		return s;
	}

	static function filterRects() {
		var bd = new BitmapData(100, 100, true, 0xFF00FF00);
		var src = new Rectangle(10, 20, 30, 40);
		var fs:Array<{n:String, f:BitmapFilter}> = [
			{n: "blur4x4p1", f: new BlurFilter(4, 4, 1)},
			{n: "blur4x4p3", f: new BlurFilter(4, 4, 3)},
			{n: "blur5.5x2.3p2", f: new BlurFilter(5.5, 2.3, 2)},
			{n: "blur0x0p1", f: new BlurFilter(0, 0, 1)},
			{n: "blur1x1p1", f: new BlurFilter(1, 1, 1)},
			{n: "blur255x255p15", f: new BlurFilter(255, 255, 15)},
			{n: "glow6x6p2", f: new GlowFilter(0xFF0000, 1, 6, 6, 2, 2)},
			{n: "glowInner6x6p2", f: new GlowFilter(0xFF0000, 1, 6, 6, 2, 2, true)},
			{n: "shadow d4 a45 b4p1", f: new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1)},
			{n: "shadow d4 a225 b4p1", f: new DropShadowFilter(4, 225, 0, 1, 4, 4, 1, 1)},
			{n: "shadow d10 a0 b0p1", f: new DropShadowFilter(10, 0, 0, 1, 0, 0, 1, 1)},
			{n: "shadowInner d4 a45 b4p1", f: new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1, true)},
			{n: "shadowHide d4 a45 b4p1", f: new DropShadowFilter(4, 45, 0, 1, 4, 4, 1, 1, false, false, true)},
			{n: "bevel d4 a45 b4p1", f: new BevelFilter(4, 45, 0xFFFFFF, 1, 0, 1, 4, 4, 1, 1)},
			{n: "bevel d4 a45 b4p1 inner", f: new BevelFilter(4, 45, 0xFFFFFF, 1, 0, 1, 4, 4, 1, 1, BitmapFilterType.INNER)},
			{n: "gglow b4p1 d4", f: new GradientGlowFilter(4, 45, [0, 0xFF0000], [0, 1], [0, 255], 4, 4, 1, 1)},
			{n: "gbevel b4p1 d4", f: new GradientBevelFilter(4, 45, [0, 0xFF0000], [0, 1], [0, 255], 4, 4, 1, 1)},
			{n: "colormatrix", f: new ColorMatrixFilter()},
			{n: "convolution3x3", f: new ConvolutionFilter(3, 3, [0, 0, 0, 0, 1, 0, 0, 0, 0])},
			{n: "convolution5x7", f: new ConvolutionFilter(5, 7)},
			{n: "dmap color 10x10", f: new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, 10, 10, DisplacementMapFilterMode.COLOR)},
			{n: "dmap wrap 10x10", f: new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, 10, 10, DisplacementMapFilterMode.WRAP)},
			{n: "dmap clamp 7x3", f: new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, 7, 3, DisplacementMapFilterMode.CLAMP)},
			{n: "dmap ignore 10x10", f: new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, 10, 10, DisplacementMapFilterMode.IGNORE)},
			{n: "dmap color -10x-10", f: new DisplacementMapFilter(new BitmapData(4, 4), new Point(0, 0), 0, 0, -10, -10, DisplacementMapFilterMode.COLOR)},
		];
		for (e in fs)
			step("gfr " + e.n, function() H.log("gfr " + e.n + " " + r(bd.generateFilterRect(src, e.f))));
		step("gfr outside", function() H.log("gfr outside " + r(bd.generateFilterRect(new Rectangle(-20, -20, 500, 500), new BlurFilter(4, 4, 1)))));
		step("gfr empty", function() H.log("gfr empty " + r(bd.generateFilterRect(new Rectangle(10, 10, 0, 0), new BlurFilter(4, 4, 1)))));
		step("gfr negsize", function() H.log("gfr negsize " + r(bd.generateFilterRect(new Rectangle(10, 10, -5, -5), new BlurFilter(4, 4, 1)))));
		step("gfr frac", function() H.log("gfr frac " + r(bd.generateFilterRect(new Rectangle(10.4, 10.6, 30.3, 30.7), new BlurFilter(4, 4, 1)))));
		step("gfr nullrect", function() H.log("gfr nullrect " + r(bd.generateFilterRect(null, new BlurFilter(4, 4, 1)))));
		step("gfr nullfilter", function() H.log("gfr nullfilter " + r(bd.generateFilterRect(src, null))));
		var res = bd.generateFilterRect(src, new ColorMatrixFilter());
		H.log("gfr returns new rect " + (res != src));
		bd.dispose();
		step("gfr disposed", function() H.log("gfr disposed " + r(bd.generateFilterRect(src, new BlurFilter(4, 4, 1)))));
	}

	static function encode() {
		var bd = new BitmapData(8, 6, true, 0x80FF0000);
		bd.setPixel32(1, 1, 0xFF00FF00);
		var full = bd.rect;
		var opaque = new BitmapData(8, 6, false, 0xFF0000FF);
		var cases:Array<{n:String, bd:BitmapData, rect:Rectangle, c:Dynamic}> = [
			{n: "png", bd: bd, rect: full, c: new PNGEncoderOptions()},
			{n: "png fast", bd: bd, rect: full, c: new PNGEncoderOptions(true)},
			{n: "png opaque", bd: opaque, rect: full, c: new PNGEncoderOptions()},
			{n: "jpeg80", bd: bd, rect: full, c: new JPEGEncoderOptions()},
			{n: "jpeg10", bd: bd, rect: full, c: new JPEGEncoderOptions(10)},
			{n: "jpeg100", bd: bd, rect: full, c: new JPEGEncoderOptions(100)},
			{n: "jpeg0", bd: bd, rect: full, c: new JPEGEncoderOptions(0)},
			{n: "jpeg200", bd: bd, rect: full, c: new JPEGEncoderOptions(200)},
			{n: "jpegxr", bd: bd, rect: full, c: new JPEGXREncoderOptions()},
			{n: "png sub", bd: bd, rect: new Rectangle(2, 1, 3, 2), c: new PNGEncoderOptions()},
			{n: "png sub frac", bd: bd, rect: new Rectangle(2.6, 1.4, 3.5, 2.5), c: new PNGEncoderOptions()},
			{n: "png outside", bd: bd, rect: new Rectangle(-2, -2, 20, 20), c: new PNGEncoderOptions()},
			{n: "png disjoint", bd: bd, rect: new Rectangle(50, 50, 4, 4), c: new PNGEncoderOptions()},
			{n: "png empty", bd: bd, rect: new Rectangle(1, 1, 0, 0), c: new PNGEncoderOptions()},
			{n: "png nullrect", bd: bd, rect: null, c: new PNGEncoderOptions()},
			{n: "obj compressor", bd: bd, rect: full, c: {quality: 50}},
			{n: "null compressor", bd: bd, rect: full, c: null},
			{n: "string compressor", bd: bd, rect: full, c: "png"},
		];
		for (e in cases)
			step("encode " + e.n, function() {
				var out:ByteArray = e.bd.encode(e.rect, e.c);
				if (out == null)
					H.log("encode " + e.n + " = null");
				else
					H.log("encode " + e.n + " len=" + out.length + " pos=" + out.position + " head=" + hex(out, 12) + " endian=" + out.endian);
			});
		step("encode into prefilled", function() {
			var ba = new ByteArray();
			ba.writeUTFBytes("hello world!");
			ba.position = 5;
			var out:ByteArray = bd.encode(full, new PNGEncoderOptions(), ba);
			H.log("encode prefilled same=" + (out == ba) + " len=" + ba.length + " pos=" + ba.position + " head=" + hex(ba, 16));
		});
		step("encode into empty given", function() {
			var ba = new ByteArray();
			var out:ByteArray = bd.encode(full, new JPEGEncoderOptions(), ba);
			H.log("encode given same=" + (out == ba) + " len=" + ba.length + " pos=" + ba.position);
		});
		step("encode png 1x1", function() {
			var one = new BitmapData(1, 1, true, 0x12345678);
			var out = one.encode(one.rect, new PNGEncoderOptions());
			H.log("encode 1x1 len=" + out.length + " all=" + hex(out, out.length));
		});
		step("encode png 2x2 opaque", function() {
			var two = new BitmapData(2, 2, false, 0xFF112233);
			two.setPixel(1, 1, 0x445566);
			var out = two.encode(two.rect, new PNGEncoderOptions());
			H.log("encode 2x2 len=" + out.length + " all=" + hex(out, out.length));
		});
		step("encode jpeg 1x1", function() {
			var one = new BitmapData(1, 1, false, 0xFF808080);
			var out = one.encode(one.rect, new JPEGEncoderOptions(80));
			H.log("encode jpeg1x1 len=" + out.length + " head=" + hex(out, 40));
		});
		bd.dispose();
		step("encode disposed", function() {
			var out = bd.encode(new Rectangle(0, 0, 1, 1), new PNGEncoderOptions());
			H.log("encode disposed " + (out == null ? "null" : "len=" + out.length));
		});
	}

	static function names(a:Array<Dynamic>):String {
		if (a == null)
			return "null";
		var out = [];
		for (i in 0...a.length) {
			var o:Dynamic = a[i];
			out.push(o.name);
		}
		return "[" + out.join(",") + "] len=" + a.length;
	}

	static function box(name:String, x:Float, y:Float, w:Float, h:Float, alpha:Float = 1):Sprite {
		var s = new Sprite();
		s.name = name;
		s.graphics.beginFill(0xFF0000, alpha);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		s.x = x;
		s.y = y;
		return s;
	}

	static function underPoint() {
		var root = Lib.current;
		var cont = new Sprite();
		cont.name = "cont";
		root.addChild(cont);
		var a = box("a", 0, 0, 50, 50);
		var b = box("b", 25, 25, 50, 50);
		var inner = box("inner", 10, 10, 10, 10);
		b.addChild(inner);
		var shape = new Shape();
		shape.name = "shape";
		shape.graphics.beginFill(0x00FF00);
		shape.graphics.drawRect(0, 0, 100, 100);
		shape.x = 200;
		var tf = new flash.text.TextField();
		tf.name = "tf";
		tf.x = 200;
		tf.y = 200;
		tf.width = 50;
		tf.height = 20;
		tf.text = "hi";
		var bmp = new Bitmap(new BitmapData(20, 20, true, 0x00000000));
		bmp.name = "bmp";
		bmp.x = 300;
		bmp.y = 0;
		var empty = new Sprite();
		empty.name = "empty";
		var hidden = box("hidden", 0, 100, 20, 20);
		hidden.visible = false;
		var nomouse = box("nomouse", 100, 100, 20, 20);
		nomouse.mouseEnabled = false;
		var nomousechildren = box("nmc", 100, 150, 20, 20);
		nomousechildren.mouseChildren = false;
		nomousechildren.addChild(box("nmcchild", 0, 0, 10, 10));
		var transparent = box("alpha0", 150, 100, 20, 20, 0);
		var alphaprop = box("alphaprop", 150, 150, 20, 20);
		alphaprop.alpha = 0;
		var maskSp = box("mask", 0, 200, 10, 10);
		var masked = box("masked", 0, 200, 50, 50);
		masked.mask = maskSp;
		var maskedNotChild = box("masked2", 60, 200, 50, 50);
		var maskOut = box("mask2", 0, 0, 1, 1);
		maskedNotChild.mask = maskOut;
		var linesp = new Sprite();
		linesp.name = "line";
		linesp.graphics.lineStyle(4, 0);
		linesp.graphics.moveTo(0, 0);
		linesp.graphics.lineTo(40, 0);
		linesp.x = 300;
		linesp.y = 100;
		var hairsp = new Sprite();
		hairsp.name = "hair";
		hairsp.graphics.lineStyle(0, 0);
		hairsp.graphics.moveTo(0, 0);
		hairsp.graphics.lineTo(40, 0);
		hairsp.x = 300;
		hairsp.y = 120;
		var btn = new SimpleButton();
		btn.name = "btn";
		btn.upState = box("up", 0, 0, 20, 20);
		btn.overState = box("over", 0, 0, 20, 20);
		btn.downState = box("down", 0, 0, 20, 20);
		btn.hitTestState = box("hit", 0, 0, 40, 40);
		btn.x = 300;
		btn.y = 200;
		var btn2 = new SimpleButton();
		btn2.name = "btn2";
		btn2.upState = box("up2", 0, 0, 40, 40);
		btn2.hitTestState = box("hit2", 0, 0, 10, 10);
		btn2.x = 350;
		btn2.y = 200;
		var scaled = box("scaled", 0, 0, 10, 10);
		scaled.x = 200;
		scaled.y = 300;
		scaled.scaleX = 4;
		scaled.scaleY = 4;
		var rotated = box("rotated", 0, 0, 40, 40);
		rotated.x = 300;
		rotated.y = 300;
		rotated.rotation = 45;
		var nested = new Sprite();
		nested.name = "nested";
		nested.x = 100;
		nested.y = 300;
		nested.addChild(box("n1", 0, 0, 20, 20));
		nested.addChild(box("n2", 0, 0, 20, 20));
		nested.addChild(box("n3", 10, 10, 20, 20));
		var with3d = box("threed", 0, 0, 40, 40);
		with3d.x = 100;
		with3d.y = 400;
		with3d.z = 0;
		var scrolled = box("scrolled", 0, 0, 50, 50);
		scrolled.x = 200;
		scrolled.y = 400;
		scrolled.scrollRect = new Rectangle(0, 0, 10, 10);
		var mc = new MovieClip();
		mc.name = "mc";
		mc.graphics.beginFill(0xFF);
		mc.graphics.drawRect(0, 0, 20, 20);
		mc.x = 300;
		mc.y = 400;
		for (c in [a, b, shape, tf, bmp, empty, hidden, nomouse, nomousechildren, transparent, alphaprop, maskSp, masked, maskedNotChild, linesp, hairsp, btn, btn2, scaled, rotated, nested, with3d, scrolled, mc])
			cont.addChild(c);
		var p = function(label:String, c:DisplayObjectContainer, x:Float, y:Float) {
			step(label, function() H.log(label + " (" + x + "," + y + ") " + names(c.getObjectsUnderPoint(new Point(x, y)))));
		};
		p("overlap", cont, 30, 30);
		p("overlap root", root, 30, 30);
		p("overlap stage", Lib.current.stage, 30, 30);
		p("only a", cont, 5, 5);
		p("inner", cont, 40, 40);
		p("inner from b", b, 15, 15);
		p("inner from b local?", b, 40, 40);
		p("edge a right", cont, 50, 25);
		p("edge a left", cont, 0, 25);
		p("edge a 49.9", cont, 49.9, 25);
		p("edge a 50.5", cont, 50.5, 25);
		p("edge a -0.5", cont, -0.5, 25);
		p("edge a 0.05", cont, 0.05, 25);
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
		p("line 1.5 off", cont, 320, 101.5);
		p("line 3 off", cont, 320, 103);
		p("hair", cont, 320, 120);
		p("hair 0.5 off", cont, 320, 120.5);
		p("btn up", cont, 310, 210);
		p("btn hit only", cont, 330, 230);
		p("btn2 up only", cont, 380, 230);
		p("btn2 hit", cont, 355, 205);
		p("scaled", cont, 230, 330);
		p("rotated inside", cont, 300, 320);
		p("rotated corner", cont, 325, 302);
		p("nested", cont, 115, 315);
		p("threed", cont, 110, 410);
		p("scrolled in", cont, 205, 405);
		p("scrolled out", cont, 230, 430);
		p("mc", cont, 310, 410);
		p("far", cont, 1000, 1000);
		p("negative", cont, -100, -100);
		step("null point", function() H.log("null point " + names(cont.getObjectsUnderPoint(null))));
		step("inacc", function() H.log("inacc " + cont.areInaccessibleObjectsUnderPoint(new Point(30, 30)) + " " + cont.areInaccessibleObjectsUnderPoint(new Point(1000, 1000)) + " stage " + Lib.current.stage.areInaccessibleObjectsUnderPoint(new Point(30, 30))));
		step("inacc null", function() H.log("inacc null " + cont.areInaccessibleObjectsUnderPoint(null)));
		// container itself: is the container included when it has its own graphics?
		var self = box("self", 0, 0, 30, 30);
		self.x = 400;
		self.y = 400;
		root.addChild(self);
		self.addChild(box("selfchild", 0, 0, 10, 10));
		p("self from self", self, 5, 5);
		p("self from self local", self, 405, 405);
		p("self from root", root, 405, 405);
		p("self from root 420", root, 420, 420);
		// cont moved: coordinates are stage coords
		cont.x = 1000;
		p("moved", cont, 30, 30);
		p("moved stagecoords", cont, 1030, 30);
		cont.x = 0;
		// not on stage
		var off = new Sprite();
		off.name = "off";
		off.addChild(box("offchild", 0, 0, 20, 20));
		p("off stage", off, 5, 5);
		var offp = new Sprite();
		offp.name = "offp";
		offp.x = 100;
		offp.addChild(off);
		p("off stage parented", off, 105, 5);
		p("off stage parented local", off, 5, 5);
	}

	static function loaders() {
		pending = 2;
		var avl:Dynamic = untyped __global__["flash.display.AVLoader"];
		H.log("AVLoader class " + (avl == null ? "null" : Std.string(avl)));
		if (avl != null) {
			step("AVLoader", function() {
				var l:Loader = untyped __new__(avl);
				H.log("AVLoader is Loader " + Std.isOfType(l, Loader) + " cli=" + (l.contentLoaderInfo != null));
				for (t in ["open", "init", "complete", "unload", "httpStatus", "ioError", "securityError", "progress"])
					l.contentLoaderInfo.addEventListener(t, function(e:Event) {
						H.log("AVLoader event " + t + " content=" + (t == "init" || t == "complete" ? qn(l.content) : "-") + " type=" + l.contentLoaderInfo.contentType + " " + (Std.isOfType(e, IOErrorEvent) ? cast(e, IOErrorEvent).text : ""));
						if (t == "complete" || t == "ioError") {
							step("AVLoader unload", function() l.unload());
							if (--pending == 0) finish();
						}
					});
				l.load(new URLRequest(H.BASE + "/asset/assetA.swf?c=avl"));
				H.log("AVLoader load returned; cli.url=" + l.contentLoaderInfo.url + " bytesTotal=" + l.contentLoaderInfo.bytesTotal);
				Lib.current.addChild(l);
			});
			step("AVLoader loadBytes/unloadAndStop exist", function() {
				var l:Dynamic = untyped __new__(avl);
				H.log("AVLoader.load own " + Reflect.hasField(l, "load") + " " + Std.string(Type.getClass(l)));
			});
		} else {
			pending--;
		}
		step("AVM1Movie", function() {
			var l = new Loader();
			l.contentLoaderInfo.addEventListener(Event.INIT, function(e) {
				var c:Dynamic = l.content;
				H.log("AVM1 content " + qn(c) + " avm=" + l.contentLoaderInfo.actionScriptVersion + " swfv=" + l.contentLoaderInfo.swfVersion);
				step("AVM1Movie.addCallback", function() H.log("addCallback = " + c.addCallback("f", function(a) return a)));
				step("AVM1Movie.addCallback null", function() H.log("addCallback null = " + c.addCallback(null, null)));
				step("AVM1Movie.call", function() H.log("call = " + c.call("g", 1, 2)));
				step("AVM1Movie.call noargs", function() H.log("call noargs = " + c.call("g")));
				step("AVM1Movie.call null", function() H.log("call null = " + c.call(null)));
				step("AVM1Movie.addChild", function() c.addChild(new Sprite()));
				step("AVM1Movie.numChildren", function() H.log("numChildren " + c.numChildren));
				step("AVM1Movie.width", function() H.log("size " + c.width + "x" + c.height + " dispatch " + c.dispatchEvent(new Event("x"))));
				if (--pending == 0) finish();
			});
			l.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent) {
				H.log("AVM1 ioError " + e.text);
				if (--pending == 0) finish();
			});
			l.load(new URLRequest(H.BASE + "/asset/avm1a.swf?c=avm1"));
			Lib.current.addChild(l);
		});
	}

	static function finish() {
		H.done();
	}

	static function main() {
		H.init("d51displaymisc", 40000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		step("filterRects", filterRects);
		step("encode", encode);
		step("underPoint", underPoint);
		step("loaders", loaders);
	}
}
