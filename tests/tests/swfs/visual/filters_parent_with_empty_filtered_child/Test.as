package {
    import flash.display.Sprite;
    import flash.filters.BlurFilter;
    import flash.filters.GlowFilter;

    // A parent's own filter must still be drawn when the parent holds an empty child that has a filter
    // (an empty clip's bounds must not grow into a huge rectangle). Left to right: no child, empty child
    // with a glow, empty child with a blur, empty child holding an empty child with a glow.
    // Expected image from Flash Player 32.
    public class Test extends Sprite {
        public function Test() {
            graphics.beginFill(0x336699);
            graphics.drawRect(0, 0, 320, 100);
            graphics.endFill();
            box(20, null, false);
            box(100, [new GlowFilter(0xFFFF00, 1, 15, 15, 2.9, 1)], false);
            box(180, [new BlurFilter(8, 8, 1)], false);
            box(260, [new GlowFilter(0xFFFF00, 1, 15, 15, 2.9, 1)], true);
        }

        private function box(x:Number, childFilters:Array, nested:Boolean):void {
            var host:Sprite = new Sprite();
            host.graphics.beginFill(0xFF0000);
            host.graphics.drawRect(0, 0, 40, 40);
            host.x = x;
            host.y = 30;
            addChild(host);
            if (childFilters != null) {
                var child:Sprite = new Sprite();
                if (nested) {
                    child.addChild(new Sprite());
                }
                child.filters = childFilters;
                host.addChild(child);
            }
            host.filters = [new GlowFilter(0xFFFF00, 1, 10, 10, 3, 1)];
        }
    }
}
