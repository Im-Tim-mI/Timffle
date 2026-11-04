/** Probe (no golden): edge cases for BitmapData.generateFilterRect (blur/convolution/shadow rounding)
 *  and DisplayObjectContainer.getObjectsUnderPoint (edge pixels, stage clipping) in Flash Player 32. */
import flash.Lib;
import flash.display.*;
import flash.filters.*;
import flash.geom.Point;
import flash.geom.Rectangle;

class D52DisplayEdge {
	static function r(x:Rectangle):String {
		return x == null ? "null" : "(" + x.x + "," + x.y + "," + x.width + "," + x.height + ")";
	}

	static function names(a:Array<Dynamic>):String {
		if (a == null)
			return "null";
		var out = [];
		for (i in 0...a.length) {
			var o:Dynamic = a[i];
			out.push(o.name);
		}
		return "[" + out.join(",") + "]";
	}

	static function box(name:String, x:Float, y:Float, w:Float, h:Float):Sprite {
		var s = new Sprite();
		s.name = name;
		s.graphics.beginFill(0xFF0000);
		s.graphics.drawRect(0, 0, w, h);
		s.graphics.endFill();
		s.x = x;
		s.y = y;
		return s;
	}

	static function main() {
		H.init("d52displayedge", 20000);
		var bd = new BitmapData(100, 100, true, 0xFF00FF00);
		var src = new Rectangle(10, 20, 30, 40);
		var fs:Array<{n:String, f:BitmapFilter}> = [
			{n: "blur2p1", f: new BlurFilter(2, 2, 1)},
			{n: "blur6p1", f: new BlurFilter(6, 6, 1)},
			{n: "blur0.5p1", f: new BlurFilter(0.5, 0.5, 1)},
			{n: "blur3p1", f: new BlurFilter(3, 3, 1)},
			{n: "blur0p2", f: new BlurFilter(0, 0, 2)},
			{n: "blur1p2", f: new BlurFilter(1, 1, 2)},
			{n: "blur2p2", f: new BlurFilter(2, 2, 2)},
			{n: "blur4p2", f: new BlurFilter(4, 4, 2)},
			{n: "blur10p2", f: new BlurFilter(10, 10, 2)},
			{n: "blur10p3", f: new BlurFilter(10, 10, 3)},
			{n: "blur10p4", f: new BlurFilter(10, 10, 4)},
			{n: "blur10p5", f: new BlurFilter(10, 10, 5)},
			{n: "blur10p6", f: new BlurFilter(10, 10, 6)},
			{n: "blur10p7", f: new BlurFilter(10, 10, 7)},
			{n: "blur10p8", f: new BlurFilter(10, 10, 8)},
			{n: "blur10p9", f: new BlurFilter(10, 10, 9)},
			{n: "blur10p10", f: new BlurFilter(10, 10, 10)},
			{n: "blur10p11", f: new BlurFilter(10, 10, 11)},
			{n: "blur10p12", f: new BlurFilter(10, 10, 12)},
			{n: "blur10p13", f: new BlurFilter(10, 10, 13)},
			{n: "blur10p14", f: new BlurFilter(10, 10, 14)},
			{n: "blur10p15", f: new BlurFilter(10, 10, 15)},
			{n: "blur10p0", f: new BlurFilter(10, 10, 0)},
			{n: "blur10p16", f: new BlurFilter(10, 10, 16)},
			{n: "blur100p1", f: new BlurFilter(100, 100, 1)},
			{n: "blur4x0p1", f: new BlurFilter(4, 0, 1)},
			{n: "blur-4p1", f: new BlurFilter(-4, -4, 1)},
			{n: "conv1x1", f: new ConvolutionFilter(1, 1)},
			{n: "conv2x2", f: new ConvolutionFilter(2, 2)},
			{n: "conv4x4", f: new ConvolutionFilter(4, 4)},
			{n: "conv6x6", f: new ConvolutionFilter(6, 6)},
			{n: "conv0x0", f: new ConvolutionFilter(0, 0)},
			{n: "conv1.5x2.5", f: new ConvolutionFilter(1.5, 2.5)},
			{n: "shadow d4 a90 b0", f: new DropShadowFilter(4, 90, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d2.5 a0 b0", f: new DropShadowFilter(2.5, 0, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d2.4 a0 b0", f: new DropShadowFilter(2.4, 0, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d-4 a0 b0", f: new DropShadowFilter(-4, 0, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d4 a180 b0", f: new DropShadowFilter(4, 180, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d4 a30 b0", f: new DropShadowFilter(4, 30, 0, 1, 0, 0, 1, 1)},
			{n: "shadow d4 a0 b4p1 knockout", f: new DropShadowFilter(4, 0, 0, 1, 4, 4, 1, 1, false, true)},
			{n: "shadow d0 a0 b4p1", f: new DropShadowFilter(0, 0, 0, 1, 4, 4, 1, 1)},
			{n: "shadow d4 a0 b0 q2", f: new DropShadowFilter(4, 0, 0, 1, 0, 0, 2, 1)},
			{n: "shadow d4 a0 b2 q2", f: new DropShadowFilter(4, 0, 0, 1, 2, 2, 2, 1)},
			{n: "bevel d4 a0 b0", f: new BevelFilter(4, 0, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)},
			{n: "bevel d2.5 a0 b0", f: new BevelFilter(2.5, 0, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)},
			{n: "bevel d4 a30 b0", f: new BevelFilter(4, 30, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)},
			{n: "bevel d-4 a0 b0", f: new BevelFilter(-4, 0, 0xFFFFFF, 1, 0, 1, 0, 0, 1, 1)},
			{n: "glow b4p1", f: new GlowFilter(0xFF0000, 1, 4, 4, 1, 1)},
			{n: "glow b4p1 knockout", f: new GlowFilter(0xFF0000, 1, 4, 4, 1, 1, false, true)},
			{n: "gglow d4 a0 b0", f: new GradientGlowFilter(4, 0, [0, 0xFF0000], [0, 1], [0, 255], 0, 0, 1, 1)},
			{n: "gbevel d4 a0 b0", f: new GradientBevelFilter(4, 0, [0, 0xFF0000], [0, 1], [0, 255], 0, 0, 1, 1)},
		];
		for (e in fs)
			H.attempt("gfr " + e.n, function() H.log("gfr " + e.n + " " + r(bd.generateFilterRect(src, e.f))));
		H.attempt("gfr frac2", function() H.log("gfr frac2 " + r(bd.generateFilterRect(new Rectangle(10.5, 11.5, 30.5, 30.5), new ColorMatrixFilter()))));
		H.attempt("gfr frac3", function() H.log("gfr frac3 " + r(bd.generateFilterRect(new Rectangle(10.5, 12.5, 29.5, 29.5), new ColorMatrixFilter()))));
		H.attempt("gfr frac4", function() H.log("gfr frac4 " + r(bd.generateFilterRect(new Rectangle(0.4, 0.6, 99.3, 99.7), new ColorMatrixFilter()))));
		H.attempt("gfr clampleft", function() H.log("gfr clampleft " + r(bd.generateFilterRect(new Rectangle(-5, -5, 20, 20), new ColorMatrixFilter()))));
		H.attempt("gfr fullyout", function() H.log("gfr fullyout " + r(bd.generateFilterRect(new Rectangle(200, 200, 20, 20), new ColorMatrixFilter()))));
		H.attempt("gfr fullyout blur", function() H.log("gfr fullyout blur " + r(bd.generateFilterRect(new Rectangle(200, 200, 20, 20), new BlurFilter(4, 4, 1)))));
		H.attempt("gfr negout", function() H.log("gfr negout " + r(bd.generateFilterRect(new Rectangle(-50, -50, 20, 20), new ColorMatrixFilter()))));
		H.attempt("gfr neg blur", function() H.log("gfr neg blur " + r(bd.generateFilterRect(new Rectangle(10, 10, -5, 0), new ColorMatrixFilter()))));
		H.attempt("gfr neg2 blur", function() H.log("gfr neg2 blur " + r(bd.generateFilterRect(new Rectangle(10, 10, -5, -5), new ColorMatrixFilter()))));
		H.attempt("gfr shader", function() H.log("gfr shader " + r(bd.generateFilterRect(src, new ShaderFilter()))));

		var root = Lib.current;
		var cont = new Sprite();
		cont.name = "cont";
		root.addChild(cont);
		var a = box("a", 0, 0, 50, 50);
		cont.addChild(a);
		var h = box("h", 100.5, 0, 50, 50);
		cont.addChild(h);
		var xs = [-1.0, -0.5, -0.1, 0, 0.04, 0.05, 0.06, 0.1, 0.5, 0.9, 0.95, 1, 1.1, 49, 49.5, 49.9, 49.95, 50, 50.04, 50.05, 50.06, 50.1, 50.5, 50.9, 50.95, 51, 51.5];
		for (x in xs)
			H.log("x " + x + " " + names(cont.getObjectsUnderPoint(new Point(x, 25))));
		for (y in xs)
			H.log("y " + y + " " + names(cont.getObjectsUnderPoint(new Point(25, y))));
		for (x in [100, 100.4, 100.5, 100.6, 101, 101.5, 150, 150.4, 150.5, 150.6, 151, 151.5])
			H.log("hx " + x + " " + names(cont.getObjectsUnderPoint(new Point(x, 25))));
		H.log("hittestpoint a 0 " + a.hitTestPoint(0, 25, true) + " 50 " + a.hitTestPoint(50, 25, true) + " 0.05 " + a.hitTestPoint(0.05, 25, true) + " 50.5 " + a.hitTestPoint(50.5, 25, true) + " -0.5 " + a.hitTestPoint(-0.5, 25, true));
		cont.scaleX = 2;
		for (x in [-1, 0, 0.5, 1, 1.5, 2, 99, 99.5, 100, 100.5, 101, 102])
			H.log("sx " + x + " " + names(cont.getObjectsUnderPoint(new Point(x, 25))));
		cont.scaleX = 1;
		cont.x = 200;
		H.log("moved200 " + names(cont.getObjectsUnderPoint(new Point(230, 30))) + " " + names(cont.getObjectsUnderPoint(new Point(30, 30))));
		cont.x = 380;
		H.log("moved380 on " + names(cont.getObjectsUnderPoint(new Point(390, 30))) + " off " + names(cont.getObjectsUnderPoint(new Point(410, 30))) + " edge399 " + names(cont.getObjectsUnderPoint(new Point(399, 30))) + " edge400 " + names(cont.getObjectsUnderPoint(new Point(400, 30))) + " edge401 " + names(cont.getObjectsUnderPoint(new Point(401, 30))));
		cont.x = 0;
		cont.y = 280;
		H.log("movedy280 on " + names(cont.getObjectsUnderPoint(new Point(25, 290))) + " off " + names(cont.getObjectsUnderPoint(new Point(25, 310))) + " edge299 " + names(cont.getObjectsUnderPoint(new Point(25, 299))) + " edge300 " + names(cont.getObjectsUnderPoint(new Point(25, 300))));
		cont.y = 0;
		cont.x = -20;
		H.log("movedneg " + names(cont.getObjectsUnderPoint(new Point(-10, 30))) + " in " + names(cont.getObjectsUnderPoint(new Point(10, 30))));
		cont.x = 0;
		Lib.current.stage.scaleMode = StageScaleMode.NO_SCALE;
		H.log("noscale " + names(cont.getObjectsUnderPoint(new Point(30, 30))) + " stage " + Lib.current.stage.stageWidth + "x" + Lib.current.stage.stageHeight);
		cont.x = 380;
		H.log("noscale moved380 off " + names(cont.getObjectsUnderPoint(new Point(410, 30))));
		cont.x = 0;
		// off-stage tree: which coordinate space?
		var offp = new Sprite();
		offp.name = "offp";
		offp.x = 100;
		var off = new Sprite();
		off.name = "off";
		off.x = 50;
		offp.addChild(off);
		off.addChild(box("offchild", 0, 0, 20, 20));
		H.log("offtree off(5,5) " + names(off.getObjectsUnderPoint(new Point(5, 5))) + " off(55,5) " + names(off.getObjectsUnderPoint(new Point(55, 5))) + " off(155,5) " + names(off.getObjectsUnderPoint(new Point(155, 5))) + " offp(5,5) " + names(offp.getObjectsUnderPoint(new Point(5, 5))) + " offp(55,5) " + names(offp.getObjectsUnderPoint(new Point(55, 5))) + " offp(155,5) " + names(offp.getObjectsUnderPoint(new Point(155, 5))));
		// mask that is itself a child inside a sub-container, and object with mask but mask invisible
		var m = box("m", 0, 0, 10, 10);
		m.visible = false;
		var mk = box("mk", 0, 0, 50, 50);
		mk.x = 200;
		mk.y = 100;
		m.x = 200;
		m.y = 100;
		mk.mask = m;
		cont.addChild(mk);
		cont.addChild(m);
		H.log("invisible mask in " + names(cont.getObjectsUnderPoint(new Point(205, 105))) + " out " + names(cont.getObjectsUnderPoint(new Point(230, 130))));
		// cacheAsBitmap and filters do not matter?
		var cb = box("cb", 200, 200, 20, 20);
		cb.cacheAsBitmap = true;
		cb.filters = [new BlurFilter(20, 20, 3)];
		cont.addChild(cb);
		H.log("cacheasbitmap in " + names(cont.getObjectsUnderPoint(new Point(205, 205))) + " blur area " + names(cont.getObjectsUnderPoint(new Point(195, 205))));
		// a child with scrollRect: is the hit limited to the scroll rect?
		var sr = box("sr", 300, 200, 50, 50);
		sr.scrollRect = new Rectangle(0, 0, 10, 10);
		cont.addChild(sr);
		H.log("scrollrect in " + names(cont.getObjectsUnderPoint(new Point(305, 205))) + " out " + names(cont.getObjectsUnderPoint(new Point(330, 230))) + " beyond " + names(cont.getObjectsUnderPoint(new Point(355, 205))));
		var srp = new Sprite();
		srp.name = "srp";
		srp.x = 300;
		srp.y = 260;
		srp.scrollRect = new Rectangle(0, 0, 10, 10);
		srp.addChild(box("srpchild", 0, 0, 50, 30));
		cont.addChild(srp);
		H.log("scrollrect parent in " + names(cont.getObjectsUnderPoint(new Point(305, 265))) + " out " + names(cont.getObjectsUnderPoint(new Point(330, 275))));
		H.done();
	}
}
