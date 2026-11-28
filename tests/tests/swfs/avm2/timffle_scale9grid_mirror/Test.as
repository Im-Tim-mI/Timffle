// Timffle: 9-slice rendering of mirrored objects. A 100x50 sprite with a 10px
// blue frame, a red centre and a yellow mark in the top-left corner of the
// frame, scale9Grid = the centre. Flipped copies (scaleX/scaleY = -1, which
// Flash reports as rotation 180 with scale 1) must render whole and flipped;
// flipped *and* scaled copies keep a 10px frame with the mark in the flipped
// corner. The pixels are read back from a BitmapData.draw of the parent.
package {
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.geom.Matrix;
    import flash.geom.Rectangle;

    public class Test extends Sprite {
        private function piece():Sprite {
            var s:Sprite = new Sprite();
            s.graphics.beginFill(0x0000FF);
            s.graphics.drawRect(0, 0, 100, 50);
            s.graphics.endFill();
            s.graphics.beginFill(0xFF0000);
            s.graphics.drawRect(10, 10, 80, 30);
            s.graphics.endFill();
            s.graphics.beginFill(0xFFFF00);
            s.graphics.drawRect(2, 2, 6, 6);
            s.graphics.endFill();
            s.scale9Grid = new Rectangle(10, 10, 80, 30);
            return s;
        }

        private function check(name:String, s:Sprite, w:int, h:int, points:Array):void {
            var parent:Sprite = new Sprite();
            parent.addChild(s);
            addChild(parent);
            var bd:BitmapData = new BitmapData(w, h, false, 0x00FF00);
            bd.draw(parent);
            trace(name + ": scaleX=" + s.scaleX + " scaleY=" + s.scaleY + " rotation=" + s.rotation);
            for each (var pt:Array in points) {
                trace(name + " " + pt[0] + "," + pt[1] + ": " + bd.getPixel(pt[0], pt[1]).toString(16));
            }
            // Writing the reported values back must leave the matrix alone.
            s.scaleX = s.scaleX;
            s.scaleY = s.scaleY;
            s.rotation = s.rotation;
            trace(name + " roundtrip: " + s.transform.matrix);
            removeChild(parent);
        }

        public function Test() {
            var s:Sprite;

            // Unscaled, flipped horizontally: drawn whole, mark top-right.
            s = piece();
            s.scaleX = -1;
            s.x = 100;
            check("flipX", s, 100, 50, [[5, 25], [50, 25], [95, 25], [50, 5], [50, 45], [5, 5], [95, 5], [95, 45]]);

            // Unscaled, flipped vertically: mark bottom-left.
            s = piece();
            s.scaleY = -1;
            s.y = 50;
            check("flipY", s, 100, 50, [[5, 25], [50, 25], [50, 5], [50, 45], [5, 5], [5, 45], [95, 45]]);

            // Unscaled, flipped both ways: mark bottom-right.
            s = piece();
            s.scaleX = -1;
            s.scaleY = -1;
            s.x = 100;
            s.y = 50;
            check("flipXY", s, 100, 50, [[5, 25], [50, 25], [5, 5], [95, 5], [5, 45], [95, 45]]);

            // Flipped horizontally and scaled 3x2: 10px frame on every side,
            // mark in the top-right corner, corners unscaled.
            s = piece();
            s.scaleX = -3;
            s.scaleY = 2;
            s.x = 300;
            check("flipX-scaled", s, 300, 100,
                [[5, 50], [15, 50], [150, 50], [285, 50], [295, 50],
                 [150, 5], [150, 15], [150, 85], [150, 95],
                 [5, 5], [295, 5], [5, 95], [295, 95], [290, 10], [280, 5]]);

            // Flipped vertically and scaled 3x2: mark in the bottom-left corner.
            s = piece();
            s.scaleX = 3;
            s.scaleY = -2;
            s.y = 100;
            check("flipY-scaled", s, 300, 100,
                [[5, 50], [15, 50], [285, 50], [295, 50],
                 [150, 5], [150, 15], [150, 85], [150, 95],
                 [5, 5], [295, 5], [5, 95], [295, 95], [10, 90], [5, 80]]);

            // Flipped both ways and scaled 3x2: mark in the bottom-right corner.
            s = piece();
            s.scaleX = -3;
            s.scaleY = -2;
            s.x = 300;
            s.y = 100;
            check("flipXY-scaled", s, 300, 100,
                [[5, 50], [150, 50], [295, 50], [150, 5], [150, 95],
                 [5, 5], [295, 5], [5, 95], [295, 95]]);

            // Control: the same piece scaled 3x2 without a flip is 9-sliced
            // (10px frame, unscaled mark).
            s = piece();
            s.scaleX = 3;
            s.scaleY = 2;
            check("scaled", s, 300, 100,
                [[5, 50], [15, 50], [150, 50], [285, 50], [295, 50],
                 [150, 5], [150, 15], [150, 85], [150, 95],
                 [5, 5], [10, 10], [20, 5], [295, 95]]);

            // The flips set through transform.matrix (what symbol instances
            // and most code do); a = -1, d = -1 is reported as rotation 180.
            s = piece();
            s.transform.matrix = new Matrix(-3, 0, 0, 2, 300, 0);
            check("matrix-flipX-scaled", s, 300, 100,
                [[5, 50], [15, 50], [150, 50], [285, 50], [295, 50],
                 [150, 5], [150, 15], [5, 5], [295, 5], [290, 10], [280, 5]]);

            s = piece();
            s.transform.matrix = new Matrix(3, 0, 0, -2, 0, 100);
            check("matrix-flipY-scaled", s, 300, 100,
                [[5, 50], [15, 50], [150, 50], [295, 50], [150, 15], [150, 85],
                 [5, 5], [295, 5], [5, 95], [295, 95], [10, 90], [5, 80]]);

            s = piece();
            s.transform.matrix = new Matrix(-1, 0, 0, -1, 100, 50);
            check("matrix-rot180", s, 100, 50, [[5, 25], [50, 25], [5, 5], [95, 5], [5, 45], [95, 45]]);

            s = piece();
            s.transform.matrix = new Matrix(-3, 0, 0, -2, 300, 100);
            check("matrix-rot180-scaled", s, 300, 100,
                [[5, 50], [15, 50], [150, 50], [295, 50], [150, 15],
                 [5, 5], [295, 5], [5, 95], [295, 95], [290, 90], [280, 95]]);
        }
    }
}
