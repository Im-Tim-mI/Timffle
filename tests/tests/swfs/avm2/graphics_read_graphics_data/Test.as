package {
import flash.display.*;
import flash.geom.Matrix;
import flash.utils.getQualifiedClassName;

// Graphics.readGraphicsData: the structure Flash Player 32.0.0.465 reports, measured with
// the probes timffle/difftest/src/D55Graphics.hx (r*), D56Graphics2.hx (s*, c1, g*) and
// D57Winding.hx; the same describe() formatting is used (3 decimals). Which lines are
// Flash-derived and which are inferred is listed in timffle/docs/api100/pending/graphics2.md.
public class Test extends Sprite {
    public function Test() {
        readData();
        readData2();
    }

    private static function n(v:Number):String {
        var r:Number = Math.round(v * 1000) / 1000;
        return String(r);
    }

    private static function mat(m:Matrix):String {
        return m == null ? "null" : "[" + n(m.a) + "," + n(m.b) + "," + n(m.c) + "," + n(m.d) + "," + n(m.tx) + "," + n(m.ty) + "]";
    }

    private static function vec(v:*):String {
        if (v == null) return "null";
        var out:Array = [];
        for (var i:int = 0; i < v.length; i++) out.push(n(v[i]));
        return "[" + out.join(",") + "]";
    }

    private static function arr(a:Array):String {
        if (a == null) return "null";
        var out:Array = [];
        for (var i:int = 0; i < a.length; i++) out.push(String(a[i]));
        return "[" + out.join(",") + "]";
    }

    private static function hex(v:uint, digits:int):String {
        var s:String = v.toString(16).toUpperCase();
        while (s.length < digits) s = "0" + s;
        return s;
    }

    private static function fill(f:*):String {
        if (f == null) return "null";
        var c:String = getQualifiedClassName(f);
        if (c == "flash.display::GraphicsSolidFill")
            return "Solid(color=" + hex(f.color, 6) + " alpha=" + n(f.alpha) + ")";
        if (c == "flash.display::GraphicsGradientFill")
            return "Gradient(type=" + f.type + " colors=" + arr(f.colors) + " alphas=" + arr(f.alphas) + " ratios=" + arr(f.ratios)
                + " matrix=" + mat(f.matrix) + " spread=" + f.spreadMethod + " interp=" + f.interpolationMethod + " focal=" + n(f.focalPointRatio) + ")";
        if (c == "flash.display::GraphicsBitmapFill")
            return "Bitmap(" + (f.bitmapData == null ? "null" : f.bitmapData.width + "x" + f.bitmapData.height) + " matrix=" + mat(f.matrix)
                + " repeat=" + f.repeat + " smooth=" + f.smooth + ")";
        if (c == "flash.display::GraphicsShaderFill")
            return "Shader(matrix=" + mat(f.matrix) + ")";
        return c;
    }

    private static function describe(d:*):String {
        var c:String = getQualifiedClassName(d);
        if (c == "flash.display::GraphicsEndFill") return "EndFill";
        if (c == "flash.display::GraphicsPath")
            return "Path(cmds=" + vec(d.commands) + " data=" + vec(d.data) + " winding=" + d.winding + ")";
        if (c == "flash.display::GraphicsStroke")
            return "Stroke(thickness=" + n(d.thickness) + " hint=" + d.pixelHinting + " scale=" + d.scaleMode + " caps=" + d.caps
                + " joints=" + d.joints + " miter=" + n(d.miterLimit) + " fill=" + fill(d.fill) + ")";
        if (c == "flash.display::GraphicsTrianglePath")
            return "Triangles(v=" + vec(d.vertices) + " i=" + vec(d.indices) + " uvt=" + vec(d.uvtData) + " cull=" + d.culling + ")";
        return fill(d);
    }

    private static function dump(label:String, g:Graphics, recurse:Boolean = true):void {
        var v:Vector.<IGraphicsData> = g.readGraphicsData(recurse);
        trace(label + " n=" + v.length + " " + getQualifiedClassName(v));
        for (var i:int = 0; i < v.length; i++) trace("  " + i + ": " + describe(v[i]));
    }

    private static function V(...rest):Vector.<Number> {
        var v:Vector.<Number> = new Vector.<Number>();
        for each (var d:Number in rest) v.push(d);
        return v;
    }

    private static function I(...rest):Vector.<int> {
        var v:Vector.<int> = new Vector.<int>();
        for each (var d:int in rest) v.push(d);
        return v;
    }

    private function readData():void {
        // 1. fill only, unclosed path, shape translated
        var s:Shape = new Shape();
        s.x = 100; s.y = 20;
        s.graphics.beginFill(0xFF0000, 0.5);
        s.graphics.moveTo(10, 10);
        s.graphics.lineTo(50, 10);
        s.graphics.lineTo(50, 50);
        s.graphics.endFill();
        dump("r1 fill-unclosed x100y20", s.graphics);
        addChild(s);
        dump("r1b on stage", s.graphics);
        removeChild(s);

        // 2. stroke only
        s = new Shape();
        s.graphics.lineStyle(2, 0x00FF00, 0.75, true, "none", "square", "miter", 7);
        s.graphics.moveTo(0, 0);
        s.graphics.lineTo(20, 0);
        s.graphics.lineTo(20, 20);
        dump("r2 stroke-only", s.graphics);

        // 3. fill + stroke rect, then a second fill
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawRect(0, 0, 30, 20);
        s.graphics.endFill();
        s.graphics.beginFill(0x123456);
        s.graphics.drawRect(40, 0, 10, 10);
        s.graphics.endFill();
        dump("r3 rect-fill-stroke-x2", s.graphics);

        // 4. circle (curves) without stroke
        s = new Shape();
        s.graphics.beginFill(0xFFFFFF);
        s.graphics.drawCircle(50, 50, 20);
        s.graphics.endFill();
        dump("r4 circle", s.graphics);

        // 5. gradient fill with matrix
        s = new Shape();
        var m:Matrix = new Matrix();
        m.createGradientBox(100, 50, Math.PI / 4, 10, 20);
        s.graphics.beginGradientFill("linear", [0xFF0000, 0x00FF00, 0x0000FF], [1, 0.5, 0], [0, 128, 255], m, "reflect", "linearRGB", 0.3);
        s.graphics.drawRect(0, 0, 100, 50);
        s.graphics.endFill();
        dump("r5 gradient", s.graphics);
        s = new Shape();
        s.graphics.beginGradientFill("radial", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m, "pad", "rgb", 0.5);
        s.graphics.drawRect(0, 0, 100, 50);
        s.graphics.endFill();
        dump("r5b radial focal", s.graphics);

        // 6. bitmap fill with matrix, repeat=false smooth=true
        s = new Shape();
        var bd:BitmapData = new BitmapData(8, 4, false, 0xFF00FF);
        var bm:Matrix = new Matrix(2, 0, 0, 3, 5, 7);
        s.graphics.beginBitmapFill(bd, bm, false, true);
        s.graphics.drawRect(0, 0, 40, 40);
        s.graphics.endFill();
        dump("r6 bitmap", s.graphics);
        trace("r6 same bitmapData: " + (GraphicsBitmapFill(s.graphics.readGraphicsData()[0]).bitmapData == bd));

        // 7. drawPath nonZero + wide/cubic commands
        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawPath(I(1, 2, 2, 2, 6, 4, 5, 3), V(0, 0, 20, 0, 20, 20, 0, 20, 5, 5, 10, 10, 0, 0, -1, -1, 30, 30, -1, -1, 40, 40, 45, 45, 50, 40), "nonZero");
        s.graphics.endFill();
        dump("r7 drawPath nonZero cubic", s.graphics);

        // 8. recurse: sprite with child shape, scaled child
        var sp:Sprite = new Sprite();
        sp.graphics.beginFill(0x111111);
        sp.graphics.drawRect(0, 0, 10, 10);
        sp.graphics.endFill();
        var ch:Shape = new Shape();
        ch.x = 50; ch.scaleX = 2; ch.rotation = 90;
        ch.graphics.beginFill(0x222222);
        ch.graphics.drawRect(0, 0, 10, 10);
        ch.graphics.endFill();
        sp.addChild(ch);
        var ch2:Shape = new Shape();
        ch2.visible = false;
        ch2.graphics.beginFill(0x333333);
        ch2.graphics.drawRect(0, 0, 10, 10);
        ch2.graphics.endFill();
        sp.addChild(ch2);
        dump("r8 recurse=true", sp.graphics, true);
        dump("r8b recurse=false", sp.graphics, false);
        dump("r8c child", ch.graphics);

        // 9. triangles are reported as paths
        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 10, 0, 10, 10));
        s.graphics.endFill();
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawRect(0, 0, 5, 5);
        s.graphics.endFill();
        dump("r9 triangles", s.graphics);

        // 10. open fill (no endFill) + lineStyle change mid-path
        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.lineStyle(3, 0x0000FF);
        s.graphics.moveTo(0, 0);
        s.graphics.lineTo(10, 0);
        s.graphics.lineStyle(5, 0x00FF00);
        s.graphics.lineTo(10, 10);
        dump("r10 open fill, style change", s.graphics);
        s.graphics.endFill();
        dump("r10b after endFill", s.graphics);

        // 11. empty / cleared
        s = new Shape();
        dump("r11 empty", s.graphics);
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(0, 0, 5, 5);
        s.graphics.clear();
        dump("r11b cleared", s.graphics);

        // 12. two-point fill sub-path and lineTo without moveTo
        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.lineTo(10, 0);
        s.graphics.lineTo(10, 10);
        s.graphics.moveTo(20, 20);
        s.graphics.lineTo(30, 20);
        s.graphics.endFill();
        dump("r12 no moveTo + 2pt subpath", s.graphics);

        // 13. drawGraphicsData round trip
        s = new Shape();
        var gd:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
        gd.push(new GraphicsStroke(2, false, "normal", "round", "bevel", 2, new GraphicsSolidFill(0xABCDEF, 0.25)));
        gd.push(new GraphicsSolidFill(0x00FF00, 1));
        var p:GraphicsPath = new GraphicsPath();
        p.moveTo(0, 0); p.lineTo(20, 0); p.curveTo(20, 20, 0, 20);
        gd.push(p);
        gd.push(new GraphicsEndFill());
        s.graphics.drawGraphicsData(gd);
        dump("r13 drawGraphicsData", s.graphics);

        // 14. drawGraphicsData of the read-back data draws the same thing
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawRect(0, 0, 30, 20);
        s.graphics.endFill();
        var copy:Shape = new Shape();
        copy.graphics.drawGraphicsData(s.graphics.readGraphicsData());
        dump("r14 round trip", copy.graphics);
    }

    private function readData2():void {
        // s1: lineStyle BEFORE beginFill, manual closed path
        var s:Shape = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
        s.graphics.endFill();
        dump("s1 style-before-fill closed", s.graphics);
        // s2: lineStyle AFTER beginFill, same path
        s = new Shape();
        s.graphics.beginFill(0x00FF00);
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
        s.graphics.endFill();
        dump("s2 style-after-fill closed", s.graphics);
        // s3: lineStyle before beginFill, open path + endFill
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20);
        s.graphics.endFill();
        dump("s3 style-before-fill open", s.graphics);
        // s4: stroke only, closed manually, then drawRect stroke only
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0); s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20); s.graphics.lineTo(0, 0);
        s.graphics.drawRect(40, 0, 10, 10);
        dump("s4 stroke-only closed + rect", s.graphics);
        // s5: lineStyle before beginFill, drawRect, no endFill, then beginFill again
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawRect(0, 0, 30, 20);
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(40, 0, 10, 10);
        dump("s5 two fills no endFill", s.graphics);
        // s6: lineStyle before beginFill, moveTo first then beginFill
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.moveTo(5, 5);
        s.graphics.beginFill(0x00FF00);
        s.graphics.lineTo(30, 5); s.graphics.lineTo(30, 20);
        s.graphics.endFill();
        dump("s6 moveTo before beginFill", s.graphics);
        // s7: fill, then lineStyle() mid-path to stop stroking
        s = new Shape();
        s.graphics.beginFill(0x00FF00);
        s.graphics.lineStyle(2, 0x0000FF);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(30, 0);
        s.graphics.lineStyle();
        s.graphics.lineTo(30, 20); s.graphics.lineTo(0, 20);
        s.graphics.endFill();
        dump("s7 lineStyle() mid path", s.graphics);
        // s8: drawCircle with stroke before fill
        s = new Shape();
        s.graphics.lineStyle(1, 0x0000FF);
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawCircle(50, 50, 20);
        s.graphics.endFill();
        dump("s8 circle stroke+fill", s.graphics);
        // s9: drawEllipse + drawRoundRect fill only
        s = new Shape();
        s.graphics.beginFill(0x00FF00);
        s.graphics.drawEllipse(0, 0, 40, 20);
        s.graphics.drawRoundRect(0, 30, 40, 20, 10, 6);
        s.graphics.endFill();
        dump("s9 ellipse+roundrect", s.graphics);

        // c1: colour rounding for fills and strokes
        s = new Shape();
        s.graphics.lineStyle(1, 0xFF8040, 0.75);
        s.graphics.beginFill(0xFF8040, 0.75);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.lineStyle(1, 0x10CDAB, 0.3);
        s.graphics.beginFill(0x10CDAB, 0.3);
        s.graphics.drawRect(20, 0, 10, 10);
        s.graphics.lineStyle(1, 0xFFFFFF, 0.5);
        s.graphics.beginFill(0xFFFFFF, 0.5);
        s.graphics.drawRect(40, 0, 10, 10);
        s.graphics.lineStyle(1, 0x7F7F7F, 0.1);
        s.graphics.beginFill(0x7F7F7F, 0.1);
        s.graphics.drawRect(60, 0, 10, 10);
        s.graphics.lineStyle(1, 0x123456, 0);
        s.graphics.beginFill(0x123456, 0);
        s.graphics.drawRect(80, 0, 10, 10);
        s.graphics.endFill();
        dump("c1 colours", s.graphics);

        // g1: gradient/bitmap matrices
        s = new Shape();
        var m:Matrix = new Matrix(1, 2, 3, 4, 5, 6);
        s.graphics.beginGradientFill("linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.endFill();
        var bd:BitmapData = new BitmapData(8, 4, false, 0xFF00FF);
        s.graphics.beginBitmapFill(bd, m);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.endFill();
        m = new Matrix(0.5, 0, 0, 0.25, 1.5, -2.5);
        s.graphics.beginGradientFill("linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.endFill();
        s.graphics.beginBitmapFill(bd, null);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.endFill();
        dump("g1 matrices", s.graphics);
        // g2: line gradient / line bitmap style read back
        s = new Shape();
        s.graphics.lineStyle(3, 0, 1);
        s.graphics.lineGradientStyle("radial", [0xFF0000, 0x0000FF], [0.5, 1], [10, 200], m, "repeat", "linearRGB", -0.4);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(20, 0);
        s.graphics.lineBitmapStyle(bd, m, false, true);
        s.graphics.lineTo(20, 20);
        dump("g2 line styles", s.graphics);

        // mixed fill groups in one fill (D57): commands + drawPath groups
        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(0, 0, 10, 10);
        s.graphics.drawPath(I(1, 2, 2, 2), V(20, 0, 30, 0, 30, 10, 20, 10), "nonZero");
        s.graphics.drawPath(I(1, 2, 2, 2), V(40, 0, 50, 0, 50, 10, 40, 10), "nonZero");
        s.graphics.drawPath(I(1, 2, 2, 2), V(60, 0, 70, 0, 70, 10, 60, 10), "evenOdd");
        s.graphics.drawRect(80, 0, 10, 10);
        s.graphics.endFill();
        dump("w1 fill groups", s.graphics);
    }
}
}
