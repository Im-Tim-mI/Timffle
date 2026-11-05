package {
    import flash.display.DisplayObjectContainer;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.net.URLRequest;
    import flash.system.ApplicationDomain;
    import flash.system.LoaderContext;
    import flash.text.TextSnapshot;

    // Timffle: flash.text.TextSnapshot over the static text (DefineText) of a
    // loaded SWF (static.swf is tests/tests/swfs/avm2/static_text/test.swf,
    // whose frame 1 holds one StaticText).
    public class Test extends Sprite {
        public function Test() {
            var empty:TextSnapshot = textSnapshot;
            trace("sprite without static text: charCount=" + empty.charCount
                + " getText=[" + empty.getText(0, 10) + "]"
                + " findText=" + empty.findText(0, "a", false)
                + " getSelected=" + empty.getSelected(0, 1)
                + " getSelectedText=[" + empty.getSelectedText() + "]"
                + " runs=" + empty.getTextRunInfo(0, 10).length
                + " hit=" + empty.hitTestTextNearPos(0, 0));
            var fresh:TextSnapshot = new TextSnapshot();
            trace("new TextSnapshot(): charCount=" + fresh.charCount);

            var loader:Loader = new Loader();
            loader.contentLoaderInfo.addEventListener(Event.COMPLETE, onLoaded);
            loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, function(e:IOErrorEvent):void {
                trace("load failed: " + e.text);
            });
            addChild(loader);
            loader.load(new URLRequest("static.swf"), new LoaderContext(false, new ApplicationDomain()));
        }

        private function onLoaded(e:Event):void {
            var content:DisplayObjectContainer = e.target.content as DisplayObjectContainer;
            trace("loaded: " + content + " children=" + content.numChildren + " child0=" + content.getChildAt(0));
            var ts:TextSnapshot = content.textSnapshot;
            trace("textSnapshot: " + ts + " is TextSnapshot=" + (ts is TextSnapshot));
            trace("charCount: " + ts.charCount);
            var all:String = ts.getText(0, ts.charCount);
            trace("getText(0, charCount): [" + all + "]");
            trace("getText(0, 3): [" + ts.getText(0, 3) + "]");
            trace("getText(-4, 2): [" + ts.getText(-4, 2) + "]");
            trace("getText(2, 2): [" + ts.getText(2, 2) + "]");
            trace("getText(2, 1): [" + ts.getText(2, 1) + "]");
            trace("getText(1000, 2000): [" + ts.getText(1000, 2000) + "]");
            trace("getText with line endings: [" + ts.getText(0, ts.charCount, true) + "]");

            var needle:String = all.substr(1, 2);
            trace("findText(0, '" + needle + "', true): " + ts.findText(0, needle, true));
            trace("findText(2, '" + needle + "', true): " + ts.findText(2, needle, true));
            trace("findText(0, upper, false): " + ts.findText(0, needle.toUpperCase(), false));
            trace("findText(0, upper, true): " + ts.findText(0, needle.toUpperCase(), true));
            trace("findText(0, 'zzzz', false): " + ts.findText(0, "zzzz", false));
            trace("findText(0, '', false): " + ts.findText(0, "", false));

            trace("getSelected(0, charCount) before: " + ts.getSelected(0, ts.charCount));
            trace("getSelectedText before: [" + ts.getSelectedText() + "]");
            ts.setSelected(1, 3, true);
            trace("getSelected(1, 3): " + ts.getSelected(1, 3));
            trace("getSelected(0, 1): " + ts.getSelected(0, 1));
            trace("getSelected(2, 10): " + ts.getSelected(2, 10));
            trace("getSelected(3, 10): " + ts.getSelected(3, 10));
            trace("getSelectedText: [" + ts.getSelectedText() + "]");
            ts.setSelected(0, 1, true);
            trace("getSelectedText after adding 0..1: [" + ts.getSelectedText() + "]");
            ts.setSelected(1, 2, false);
            trace("getSelectedText after removing 1..2: [" + ts.getSelectedText() + "]");
            trace("getSelected(1, 2): " + ts.getSelected(1, 2));
            ts.setSelectColor(0xFF0000);
            ts.setSelectColor();
            // A new snapshot of the same container sees the same selection.
            var again:TextSnapshot = content.textSnapshot;
            trace("new snapshot getSelectedText: [" + again.getSelectedText() + "]");

            var runs:Array = ts.getTextRunInfo(0, 2);
            trace("getTextRunInfo(0, 2).length: " + runs.length);
            for (var i:int = 0; i < runs.length; i++) {
                var run:Object = runs[i];
                trace("run " + i + ": indexInRun=" + run.indexInRun + " selected=" + run.selected
                    + " font=" + run.font + " color=0x" + run.color.toString(16) + " height=" + run.height
                    + " matrix=[" + run.matrix_a + " " + run.matrix_b + " " + run.matrix_c + " " + run.matrix_d
                    + " " + run.matrix_tx + " " + run.matrix_ty + "]"
                    + " corners=(" + run.corner0x + "," + run.corner0y + ")(" + run.corner1x + "," + run.corner1y
                    + ")(" + run.corner2x + "," + run.corner2y + ")(" + run.corner3x + "," + run.corner3y + ")");
            }
            var keys:Array = [];
            for (var key:String in runs[0]) {
                keys.push(key);
            }
            keys.sort();
            trace("run keys: " + keys.join(","));
            trace("getTextRunInfo(5, 2).length: " + ts.getTextRunInfo(5, 2).length);
            trace("getTextRunInfo(1000, 2000).length: " + ts.getTextRunInfo(1000, 2000).length);

            var first:Object = runs[0];
            var cx:Number = (first.corner0x + first.corner2x) / 2;
            var cy:Number = (first.corner0y + first.corner2y) / 2;
            trace("hitTestTextNearPos(centre of 0): " + ts.hitTestTextNearPos(cx, cy));
            trace("hitTestTextNearPos(far, 0): " + ts.hitTestTextNearPos(cx + 5000, cy + 5000));
            trace("hitTestTextNearPos(far, 10): " + ts.hitTestTextNearPos(cx + 5000, cy + 5000, 10));
            trace("hitTestTextNearPos(far, huge): " + (ts.hitTestTextNearPos(cx + 5000, cy + 5000, 100000) >= 0));
            var second:Object = runs[1];
            var cx2:Number = (second.corner0x + second.corner2x) / 2;
            var cy2:Number = (second.corner0y + second.corner2y) / 2;
            trace("hitTestTextNearPos(just above 1, 0): " + ts.hitTestTextNearPos(cx2, second.corner0y - 1));
            trace("hitTestTextNearPos(just above 1, 5): " + ts.hitTestTextNearPos(cx2, second.corner0y - 1, 5));
        }
    }
}
