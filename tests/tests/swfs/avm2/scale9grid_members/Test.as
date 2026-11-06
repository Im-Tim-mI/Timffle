// Timffle: DisplayObject.scale9Grid — get/set, copy semantics, twips rounding,
// ArgumentError #2004 for rectangles outside the object's bounds (or on an
// object without content), null clearing, and bounds that include children.
package {
    import flash.display.Shape;
    import flash.display.Sprite;
    import flash.geom.Rectangle;

    public class Test extends Sprite {
        public function Test() {
            var s:Sprite = new Sprite();
            trace("default: " + s.scale9Grid);

            try {
                s.scale9Grid = new Rectangle(1, 1, 2, 2);
                trace("set on empty: accepted " + s.scale9Grid);
            } catch (e:Error) {
                trace("set on empty: " + e.errorID + " " + (e is ArgumentError));
            }

            s.graphics.beginFill(0xFF0000);
            s.graphics.drawRect(0, 0, 100, 50);
            s.graphics.endFill();

            s.scale9Grid = new Rectangle(10, 10, 80, 30);
            trace("get: " + s.scale9Grid);
            var r:Rectangle = s.scale9Grid;
            r.x = 99;
            trace("copy: " + s.scale9Grid);

            s.scale9Grid = new Rectangle(10.123, 10.126, 20, 20);
            trace("rounded: " + s.scale9Grid);

            var bad:Array = [
                new Rectangle(-1, 0, 10, 10),
                new Rectangle(0, 0, 101, 10),
                new Rectangle(0, 0, 10, 51),
                new Rectangle(10, 10, -5, 5),
                new Rectangle(95, 45, 10, 10)
            ];
            for each (var b:Rectangle in bad) {
                try {
                    s.scale9Grid = b;
                    trace("bad accepted: " + b);
                } catch (e:Error) {
                    trace("bad " + b + ": " + e.errorID + " " + (e is ArgumentError));
                }
            }
            trace("still: " + s.scale9Grid);

            s.scale9Grid = new Rectangle(0, 0, 100, 50);
            trace("exact: " + s.scale9Grid);
            s.scale9Grid = new Rectangle(50, 25, 0, 0);
            trace("zero: " + s.scale9Grid);
            s.scale9Grid = null;
            trace("cleared: " + s.scale9Grid);

            s.scale9Grid = new Rectangle(10, 10, 80, 30);
            s.scaleX = 3;
            s.scaleY = 2;
            trace("scaled size: " + s.width + "x" + s.height);
            trace("scaled grid: " + s.scale9Grid);
            s.rotation = 45;
            trace("rotated grid kept: " + s.scale9Grid);

            var p:Sprite = new Sprite();
            var c:Shape = new Shape();
            c.graphics.beginFill(0);
            c.graphics.drawRect(20, 20, 10, 10);
            c.graphics.endFill();
            p.addChild(c);
            p.scale9Grid = new Rectangle(22, 22, 4, 4);
            trace("child bounds: " + p.scale9Grid);
            try {
                p.scale9Grid = new Rectangle(0, 0, 5, 5);
                trace("child bounds out: accepted");
            } catch (e:Error) {
                trace("child bounds out: " + e.errorID + " " + (e is ArgumentError));
            }

            try {
                stage.scale9Grid = new Rectangle(0, 0, 1, 1);
                trace("stage: accepted");
            } catch (e:Error) {
                trace("stage: " + e.errorID);
            }
            trace("stage get: " + stage.scale9Grid);
        }
    }
}
