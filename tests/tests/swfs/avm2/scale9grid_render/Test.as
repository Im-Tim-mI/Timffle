// Timffle: 9-slice rendering. A 100x50 sprite with a 10px blue frame and a red
// centre, scale9Grid = the centre, scaled 3x2 inside a parent and drawn into a
// BitmapData: the frame must stay 10px wide on every side.
package {
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.geom.Rectangle;

    public class Test extends Sprite {
        public function Test() {
            var s:Sprite = new Sprite();
            s.graphics.beginFill(0x0000FF);
            s.graphics.drawRect(0, 0, 100, 50);
            s.graphics.endFill();
            s.graphics.beginFill(0xFF0000);
            s.graphics.drawRect(10, 10, 80, 30);
            s.graphics.endFill();
            s.scale9Grid = new Rectangle(10, 10, 80, 30);
            s.scaleX = 3;
            s.scaleY = 2;

            var parent:Sprite = new Sprite();
            parent.addChild(s);
            addChild(parent);

            var bd:BitmapData = new BitmapData(300, 100, false, 0x00FF00);
            bd.draw(parent);
            var points:Array = [
                [5, 50], [15, 50], [150, 50], [285, 50], [295, 50],
                [150, 5], [150, 15], [150, 85], [150, 95],
                [5, 5], [295, 95]
            ];
            for each (var pt:Array in points) {
                trace(pt[0] + "," + pt[1] + ": " + bd.getPixel(pt[0], pt[1]).toString(16));
            }

            // Without the grid the frame scales with the object.
            s.scale9Grid = null;
            bd.fillRect(bd.rect, 0x00FF00);
            bd.draw(parent);
            trace("no grid 15,50: " + bd.getPixel(15, 50).toString(16));
            trace("no grid 150,15: " + bd.getPixel(150, 15).toString(16));
        }
    }
}
