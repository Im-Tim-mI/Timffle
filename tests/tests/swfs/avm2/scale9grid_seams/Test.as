// Timffle: 9-slice seams at fractional scales. A white panel with a 9-slice grid
// (laid out like Mole's 毛毛樹 dialog: scaled 1.0004 x 1.0003 by its own matrix)
// sits on green and is drawn at the fractional scales phones use. Between the
// grid's regions no green may show through (Flash draws the panel seamless).
package {
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.geom.Matrix;
    import flash.geom.Point;
    import flash.geom.Rectangle;

    public class Test extends Sprite {
        public function Test() {
            var panel:Sprite = new Sprite();
            panel.graphics.beginFill(0xFFFFFF);
            panel.graphics.drawRect(0, 0, 257, 339);
            panel.graphics.endFill();
            panel.scale9Grid = new Rectangle(63, 83, 128, 170);
            panel.scaleX = 1.0004;
            panel.scaleY = 1.0003;
            panel.x = 1.5;
            panel.y = 1.5;

            var holder:Sprite = new Sprite();
            holder.addChild(panel);
            holder.x = 20;
            holder.y = 10;

            var bg:Sprite = new Sprite();
            bg.graphics.beginFill(0x00FF00);
            bg.graphics.drawRect(0, 0, 300, 360);
            bg.graphics.endFill();
            bg.addChild(holder);
            addChild(bg);

            // A panel stretched well past its grid, too.
            var wide:Sprite = new Sprite();
            wide.graphics.beginFill(0xFFFFFF);
            wide.graphics.drawRect(0, 0, 60, 60);
            wide.graphics.endFill();
            wide.scale9Grid = new Rectangle(17.3, 21.7, 25.1, 18.9);
            wide.scaleX = 2.37;
            wide.scaleY = 1.91;
            wide.x = 120.35;
            wide.y = 230.65;
            bg.addChild(wide);

            // The phone scales that were reported, plus a sweep of the whole
            // range: whether two regions' edges round to the same pixel depends
            // on the exact scale, so a few scales prove little.
            var scales:Array = [2.142857, 2.625, 1.5, 0.8, 3.0, 0.5007, 0.5042, 0.5196];
            for (var i:int = 0; i < 60; i++) {
                scales.push(Math.round((0.5 + i * 0.0583 + i * i * 0.00037) * 10000) / 10000);
            }
            var bad:int = 0;
            for each (var scale:Number in scales) {
                var w:int = Math.ceil(300 * scale);
                var h:int = Math.ceil(360 * scale);
                var bd:BitmapData = new BitmapData(w, h, false, 0x00FF00);
                bd.draw(bg, new Matrix(scale, 0, 0, scale, 0, 0));
                // Every pixel well inside each panel must be pure white.
                for each (var r:Rectangle in [
                    new Rectangle(23 * scale, 13 * scale, 250 * scale, 332 * scale),
                    new Rectangle(123 * scale, 233 * scale, 136 * scale, 108 * scale)]) {
                    var x0:int = Math.ceil(r.left), y0:int = Math.ceil(r.top);
                    var inner:BitmapData = new BitmapData(Math.floor(r.right) - x0, Math.floor(r.bottom) - y0, false, 0xFFFFFF);
                    inner.copyPixels(bd, new Rectangle(x0, y0, inner.width, inner.height), new Point());
                    var stain:Rectangle = inner.getColorBoundsRect(0xFFFFFF, 0xFFFFFF, false);
                    if (stain.width > 0 || stain.height > 0) {
                        bad++;
                        trace("scale " + scale + ": non-white inside the panel at " + (x0 + stain.x) + "," + (y0 + stain.y)
                            + " size " + stain.width + "x" + stain.height
                            + " colour " + bd.getPixel(x0 + stain.x, y0 + stain.y).toString(16));
                    }
                }
            }
            trace(scales.length + " scales, " + bad + " panels with seams");
        }
    }
}
