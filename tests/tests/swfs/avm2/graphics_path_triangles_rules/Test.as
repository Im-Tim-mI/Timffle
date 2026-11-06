package {
import flash.display.*;
import flash.geom.Matrix;
import flash.geom.Rectangle;

// Graphics.drawPath / drawTriangles fill and stroke rules, sampled through BitmapData.draw +
// getPixel32 (no image comparison). Every expected value comes from the standalone Flash
// Player 32.0.0.465 (timffle/difftest/src/D55Graphics.hx, D56Graphics2.hx, D57Winding.hx);
// sample points are chosen away from anti-aliased edges and texel boundaries.
public class Test extends Sprite {
    private var bd:BitmapData;

    public function Test() {
        // quadrant bitmap: TL red, TR green, BL blue, BR white (20x20)
        bd = new BitmapData(20, 20, false, 0xFF0000);
        bd.fillRect(new Rectangle(10, 0, 10, 10), 0x00FF00);
        bd.fillRect(new Rectangle(0, 10, 10, 10), 0x0000FF);
        bd.fillRect(new Rectangle(10, 10, 10, 10), 0xFFFFFF);
        trace("===== drawTriangles uv/uvt");
        triangles();
        trace("===== drawTriangles errors");
        errors();
        trace("===== drawTriangles union");
        union();
        trace("===== drawPath");
        paths();
        trace("===== fill groups");
        groups();
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

    private static function hex(c:uint):String {
        var s:String = c.toString(16).toUpperCase();
        while (s.length < 8) s = "0" + s;
        return s;
    }

    private static function sample(label:String, s:DisplayObject, pts:Array):void {
        var out:BitmapData = new BitmapData(60, 60, true, 0x00000000);
        out.draw(s);
        var parts:Array = [];
        for each (var p:Array in pts) parts.push(p[0] + "," + p[1] + "=" + hex(out.getPixel32(p[0], p[1])));
        trace(label + " " + parts.join(" "));
    }

    private function quad():Vector.<Number> { return V(0, 0, 40, 0, 40, 40, 0, 40); }
    private function quadIdx():Vector.<int> { return I(0, 1, 2, 0, 2, 3); }

    private function triangles():void {
        var s:Shape = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 0, 1, 1, 0, 1));
        s.graphics.endFill();
        sample("t1 uv quad", s, [[5, 5], [35, 5], [5, 35], [35, 35], [15, 25], [25, 15]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 1, 0, 1, 1, 1, 1, 0, 1, 1));
        s.graphics.endFill();
        sample("t3 uvt t=1", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 0.5, 1, 0, 0.5, 1, 1, 0.5, 0, 1, 0.5));
        s.graphics.endFill();
        sample("t3b uvt t=0.5", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd, new Matrix(2, 0, 0, 2, 10, 10));
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 0, 1, 1, 0, 1));
        s.graphics.endFill();
        sample("t4 uv with fill matrix", s, [[5, 5], [35, 5], [5, 35], [35, 35]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd, new Matrix(2, 0, 0, 2, 0, 0));
        s.graphics.drawTriangles(quad(), quadIdx());
        s.graphics.endFill();
        sample("t5 bitmap no uv, matrix 2x", s, [[5, 5], [35, 5], [5, 35], [35, 35], [15, 15], [25, 25]]);

        // perspective: t=1 on the left, t=0.25 on the right (u/v not premultiplied)
        s = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 1, 0, 0.25, 1, 1, 0.25, 0, 1, 1));
        s.graphics.endFill();
        sample("u2 t right=0.25", s, [[25, 10], [37, 10], [20, 30], [38, 30]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 1, 0, 4, 1, 1, 4, 0, 1, 1));
        s.graphics.endFill();
        sample("u3 t right=4", s, [[3, 10], [25, 10], [4, 30], [25, 30]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd, null, false, false);
        s.graphics.drawTriangles(quad(), quadIdx(), V(-0.5, 0, 1.5, 0, 1.5, 1, -0.5, 1));
        s.graphics.endFill();
        sample("u5 uv -0.5..1.5 norepeat", s, [[5, 10], [35, 10]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd, null, true, false);
        s.graphics.drawTriangles(quad(), quadIdx(), V(-0.5, 0, 1.5, 0, 1.5, 1, -0.5, 1));
        s.graphics.endFill();
        sample("u5b uv -0.5..1.5 repeat", s, [[5, 10], [15, 10], [25, 10], [35, 10]]);

        s = new Shape();
        var m:Matrix = new Matrix();
        m.createGradientBox(40, 40);
        s.graphics.beginGradientFill("linear", [0xFF0000, 0x0000FF], [1, 1], [0, 255], m);
        s.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1, 0, 1, 1, 0, 1));
        s.graphics.endFill();
        sample("u6 gradient+uv draws nothing", s, [[5, 10], [35, 10]]);

        s = new Shape();
        s.graphics.beginBitmapFill(bd);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40), null, V(0, 0, 1, 0, 1, 1));
        s.graphics.endFill();
        sample("e3 uv no indices", s, [[30, 10], [16, 5], [35, 30]]);
    }

    private function errors():void {
        for each (var len:int in [0, 1, 2, 7, 8, 9, 12, 13, 16]) {
            var u:Vector.<Number> = new Vector.<Number>();
            for (var i:int = 0; i < len; i++) u.push(0.5);
            var sh:Shape = new Shape();
            sh.graphics.beginBitmapFill(bd);
            try {
                sh.graphics.drawTriangles(quad(), quadIdx(), u);
                trace("e1 uvt len " + len + " ok");
            } catch (e:Error) {
                trace("e1 uvt len " + len + " THREW #" + e.errorID);
            }
        }
        sh = new Shape();
        sh.graphics.beginFill(0xFF0000);
        try {
            sh.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1));
            trace("e2 solid uvt len 3 ok");
        } catch (e:Error) {
            trace("e2 solid uvt len 3 THREW #" + e.errorID);
        }
        sh = new Shape();
        try {
            sh.graphics.drawTriangles(quad(), quadIdx(), V(0, 0, 1));
            trace("e2b nofill uvt len 3 ok");
        } catch (e:Error) {
            trace("e2b nofill uvt len 3 THREW #" + e.errorID);
        }
    }

    private function union():void {
        var s:Shape = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40, 0, 0, 40, 40, 0, 40));
        s.graphics.endFill();
        sample("t7 cw+ccw", s, [[30, 10], [10, 30], [20, 20]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40, 0, 0, 0, 40, 40, 40));
        s.graphics.endFill();
        sample("t8 cw+cw", s, [[30, 10], [10, 30], [20, 20]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40, 10, 10, 30, 30, 30, 10));
        s.graphics.endFill();
        sample("t8b cw + inner ccw", s, [[25, 15], [35, 5], [20, 12]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40, 10, 10, 30, 10, 30, 30));
        s.graphics.endFill();
        sample("t8c cw + inner cw", s, [[25, 15], [35, 5], [20, 12]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(0, 0, 30, 30);
        s.graphics.drawRect(10, 10, 30, 30);
        s.graphics.drawTriangles(V(20, 20, 50, 20, 50, 50));
        s.graphics.drawRect(5, 5, 30, 30);
        s.graphics.endFill();
        sample("t9 mixed", s, [[15, 15], [25, 25], [40, 30], [7, 7], [32, 32], [2, 2], [45, 40]]);

        s = new Shape();
        s.graphics.lineStyle(4, 0x0000FF);
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(10, 10, 50, 10, 50, 50));
        s.graphics.endFill();
        sample("t10 stroke", s, [[30, 10], [50, 30], [30, 30], [40, 20], [10, 10]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(10, 10, 50, 10, 50, 50));
        s.graphics.lineTo(10, 50);
        s.graphics.lineTo(10, 30);
        s.graphics.endFill();
        sample("t11 lineTo after", s, [[12, 45], [30, 40], [30, 15], [12, 20]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawTriangles(V(0, 0, 40, 0, 40, 40));
        s.graphics.drawTriangles(V(0, 0, 40, 40, 40, 0));
        s.graphics.endFill();
        sample("i tri cw + tri ccw calls", s, [[30, 10], [20, 15]]);
    }

    private function paths():void {
        var cmds:Vector.<int> = I(1, 2, 2);
        var data:Vector.<Number> = V(0, 0, 40, 0, 40, 40);
        var s:Shape = new Shape();
        s.graphics.lineStyle(4, 0x0000FF);
        s.graphics.drawPath(cmds, data);
        sample("p1 drawPath stroke open", s, [[20, 0], [40, 20], [20, 20], [10, 10]]);

        s = new Shape();
        s.graphics.lineStyle(4, 0x0000FF);
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawPath(cmds, data);
        s.graphics.endFill();
        sample("p1b drawPath stroke+fill open", s, [[20, 0], [40, 20], [30, 10]]);

        s = new Shape();
        s.graphics.lineStyle(4, 0x0000FF);
        s.graphics.beginFill(0xFF0000);
        s.graphics.moveTo(0, 0); s.graphics.lineTo(40, 0); s.graphics.lineTo(40, 40);
        s.graphics.endFill();
        sample("p1c lineTo stroke+fill open", s, [[20, 0], [40, 20], [20, 20], [30, 10], [10, 10]]);

        s = new Shape();
        s.graphics.lineStyle(4, 0x0000FF);
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawPath(I(1, 2, 2, 1, 2, 2), V(0, 0, 20, 0, 20, 20, 30, 30, 50, 30, 50, 50));
        s.graphics.endFill();
        sample("p1d two subpaths", s, [[15, 5], [45, 35], [10, 0], [40, 30]]);

        for each (var w:String in ["evenOdd", "nonZero"]) {
            s = new Shape();
            s.graphics.beginFill(0xFF0000);
            s.graphics.drawPath(I(1, 2, 2, 2, 2, 1, 2, 2, 2, 2),
                V(0, 0, 30, 0, 30, 30, 0, 30, 0, 0, 10, 10, 40, 10, 40, 40, 10, 40, 10, 10), w);
            s.graphics.endFill();
            sample("p2 " + w, s, [[5, 5], [20, 20], [35, 35]]);
        }

        s = new Shape();
        s.graphics.lineStyle(8, 0x0000FF, 1, false, "normal", "none", "miter", 10);
        s.graphics.drawPath(I(1, 2, 2, 2, 2), V(10, 10, 40, 10, 40, 40, 10, 40, 10, 10));
        sample("w6 drawPath stroke explicit close corner", s, [[7, 7], [8, 8], [12, 12], [43, 43]]);
        s = new Shape();
        s.graphics.lineStyle(8, 0x0000FF, 1, false, "normal", "none", "miter", 10);
        s.graphics.moveTo(10, 10); s.graphics.lineTo(40, 10); s.graphics.lineTo(40, 40); s.graphics.lineTo(10, 40); s.graphics.lineTo(10, 10);
        sample("w6b lineTo stroke explicit close corner", s, [[7, 7], [8, 8], [12, 12], [43, 43]]);
    }

    private static function sq(g:Graphics, x:Number, y:Number, ccw:Boolean = false):void {
        g.moveTo(x, y);
        if (ccw) { g.lineTo(x, y + 30); g.lineTo(x + 30, y + 30); g.lineTo(x + 30, y); }
        else { g.lineTo(x + 30, y); g.lineTo(x + 30, y + 30); g.lineTo(x, y + 30); }
        g.lineTo(x, y);
    }

    private static function pathSq(g:Graphics, x:Number, y:Number, w:String, ccw:Boolean = false):void {
        var d:Vector.<Number> = ccw ? V(x, y, x, y + 30, x + 30, y + 30, x + 30, y, x, y)
                                    : V(x, y, x + 30, y, x + 30, y + 30, x, y + 30, x, y);
        g.drawPath(I(1, 2, 2, 2, 2), d, w);
    }

    private static function tri(g:Graphics, x:Number, y:Number):void {
        g.drawTriangles(V(x, y, x + 10, y, x + 10, y + 10));
    }

    private function groups():void {
        var pts:Array = [[20, 20], [5, 5], [35, 35]];
        var s:Shape = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(0, 0, 30, 30); s.graphics.drawRect(10, 10, 30, 30);
        s.graphics.endFill();
        sample("a drawRect x2", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0); sq(s.graphics, 10, 10); tri(s.graphics, 45, 0);
        s.graphics.endFill();
        sample("b lineTo x2 then tri", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        tri(s.graphics, 45, 0); sq(s.graphics, 0, 0); sq(s.graphics, 10, 10);
        s.graphics.endFill();
        sample("c tri then lineTo x2", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0); tri(s.graphics, 45, 0); sq(s.graphics, 10, 10);
        s.graphics.endFill();
        sample("c2 sq tri sq", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 0, 0, "evenOdd"); pathSq(s.graphics, 10, 10, "evenOdd");
        s.graphics.endFill();
        sample("d path eo x2", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 0, 0, "nonZero"); pathSq(s.graphics, 10, 10, "nonZero");
        s.graphics.endFill();
        sample("d2 path nz x2 cw", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 0, 0, "nonZero"); pathSq(s.graphics, 10, 10, "nonZero", true);
        s.graphics.endFill();
        sample("w4 nonZero cw + nonZero ccw", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 0, 0, "nonZero"); pathSq(s.graphics, 10, 10, "evenOdd");
        s.graphics.endFill();
        sample("e path nz then eo", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0); pathSq(s.graphics, 10, 10, "nonZero", true);
        s.graphics.endFill();
        sample("f sq then path nz ccw", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0); sq(s.graphics, 10, 10, true);
        s.graphics.endFill();
        sample("f2 sq cw + sq ccw", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0);
        s.graphics.drawTriangles(V(10, 10, 50, 10, 50, 50));
        s.graphics.endFill();
        sample("g sq then tri overlap", s, [[20, 15], [5, 5]]);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        s.graphics.drawRect(0, 0, 30, 30); s.graphics.drawRect(10, 10, 30, 30);
        pathSq(s.graphics, 45, 45, "evenOdd");
        s.graphics.endFill();
        sample("h rect x2 then path eo", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0); pathSq(s.graphics, 10, 10, "nonZero");
        s.graphics.endFill();
        sample("j sq then path nz cw", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 0, 0, "evenOdd"); sq(s.graphics, 10, 10);
        s.graphics.endFill();
        sample("k path eo then sq", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 0, 0);
        s.graphics.beginFill(0xFF0000);
        sq(s.graphics, 10, 10);
        s.graphics.endFill();
        sample("l two beginFill", s, pts);

        s = new Shape();
        s.graphics.beginFill(0xFF0000);
        pathSq(s.graphics, 50, 0, "nonZero");
        sq(s.graphics, 0, 0); sq(s.graphics, 10, 10);
        s.graphics.endFill();
        sample("w1 nonZero then lineTo overlap", s, [[5, 5], [20, 20], [35, 35], [54, 4]]);
    }
}
}
