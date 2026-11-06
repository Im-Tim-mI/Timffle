package {
    import flash.display.*;
    import flash.text.engine.*;

    // Timffle: where Flash Player 32 puts flash.text.engine glyphs of an embedded CFF font
    // (DefineFont4 "Exo 2", the subset font of visual/definefont4) on the pixel grid, at stage
    // quality low. Every case draws "L" glyphs with BitmapData.draw and prints, per glyph,
    // the first and last ink column of the vertical stem (a row in the middle of the stem)
    // and the first ink row of the stem: straight edges only, so the numbers depend on
    // where the glyph lands, not on how curves are rasterized.
    // Flash: the TextLine's device origin rounds to a whole pixel (x.5 down), the pen offset
    // of each glyph from it to a whole pixel (renderingMode normal) or a quarter pixel (cff).
    // test.swf = this file compiled with asc plus the DefineFont4 tag (see LICENSE-fonts.txt).
    public class Test extends Sprite {
        private static const SIZE:Number = 46;
        private static const ADV:Number = 514 * SIZE / 1000; // advance of "L"

        public function Test() {
            stage.quality = StageQuality.LOW;
            var modes:Array = ["normal", "cff"];
            var i:int, j:int, l:TextLine, sp:Sprite;
            for (j = 0; j < 2; j++) {
                var m:String = modes[j];
                for (i = 0; i < 20; i++) {
                    l = line("L", m); l.x = 10 + i * 0.05; l.y = 50;
                    report(m + " x=" + l.x, l, 1, 10 + i * 0.05, 50, 1);
                }
                for (i = 0; i < 20; i++) {
                    l = line("L", m); l.x = 10; l.y = 50 + i * 0.05;
                    report(m + " y=" + l.y, l, 1, 10, 50 + i * 0.05, 1);
                }
                // A parent at a fractional position: its origin and the line's offset in it
                // round separately.
                var px:Array = [10, 10.3, 10.45, 10.6];
                var lx:Array = [0.25, 0.3, 0.45, 0.55, 0.6];
                for (var a:int = 0; a < px.length; a++) for (var b:int = 0; b < lx.length; b++) {
                    sp = new Sprite(); l = line("L", m); l.x = lx[b]; l.y = 50; sp.addChild(l); sp.x = px[a];
                    report(m + " parent x=" + px[a] + " line x=" + lx[b], sp, 1, px[a] + lx[b], 50, 1);
                    sp = new Sprite(); l = line("L", m); l.x = 10; l.y = lx[b]; sp.addChild(l); sp.y = 40 + px[a];
                    report(m + " parent y=" + (40 + px[a]) + " line y=" + lx[b], sp, 1, 10, 40 + px[a] + lx[b], 1);
                }
                // Lines of several glyphs only for "normal": in "cff" the stems also depend
                // on Flash's CFF rasterizer (hinting, stem coverage), which Timffle lacks.
                if (m != "normal") continue;
                var xs:Array = [10, 10.3, 10.5, 10.7];
                for (i = 0; i < xs.length; i++) {
                    l = line("LLLLLLLLLLLLLLLLLLLL", m); l.x = xs[i]; l.y = 50;
                    report(m + " line x=" + xs[i], l, 20, xs[i], 50, 1);
                }
                sp = new Sprite(); l = line("LLLLLLLLLL", m); l.x = 5.3; l.y = 40; sp.addChild(l); sp.scaleX = sp.scaleY = 2;
                report(m + " line x=5.3 in parent scale 2", sp, 10, 10.6, 80, 2);
            }
        }

        private static function line(text:String, mode:String):TextLine {
            var fd:FontDescription = new FontDescription("Exo 2", FontWeight.NORMAL, FontPosture.NORMAL,
                FontLookup.EMBEDDED_CFF, mode);
            return new TextBlock(new TextElement(text, new ElementFormat(fd, SIZE))).createTextLine(null, 3000);
        }

        // ox/oy: device origin of the line; scale: device pixels per line pixel.
        private static function report(tag:String, o:DisplayObject, count:int, ox:Number, oy:Number, scale:Number):void {
            var holder:Sprite = new Sprite();
            holder.addChild(o);
            var w:int = int(ox + count * ADV * scale + 20);
            var bd:BitmapData = new BitmapData(w, int(oy + 10), false, 0xFFFFFF);
            bd.draw(holder);
            var row:int = int(oy - 10 * scale);
            var out:Array = [];
            for (var n:int = 0; n < count; n++) {
                var x0:int = int(ox + n * ADV * scale);
                var left:int = -1, right:int = -1;
                for (var x:int = x0; x < x0 + int(12 * scale); x++) {
                    if ((bd.getPixel(x, row) & 0xFF) < 128) {
                        if (left < 0) left = x;
                        right = x;
                    } else if (left >= 0) {
                        break;
                    }
                }
                var top:int = -1;
                // (the first ink row only at scale 1: scaled cap heights end within
                // 0.02 px of a pixel centre, where Flash's rasterizer differs)
                for (var y:int = 0; y < row && left >= 0 && scale == 1; y++) {
                    if ((bd.getPixel(left + 1, y) & 0xFF) < 128) { top = y; break; }
                }
                out.push(left + "-" + right + "/" + top);
            }
            trace(tag + ": " + out.join(" "));
        }
    }
}
