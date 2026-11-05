package {
    import flash.display.Loader;
    import flash.display.MovieClip;
    import flash.events.Event;
    import flash.events.TextEvent;
    import flash.utils.ByteArray;

    /**
     * The content loaded by LTMain (compiled with asc.jar, so the constructor has `this`; see
     * build.sh). Reports its constructor, `added`/`addedToStage`, its frame-1 script and its first
     * two enterFrame/frameConstructed/exitFrame events through `loaderInfo.sharedEvents`, so the
     * loading movie logs them in order (CONFIG::harness is accepted but unused).
     *   CONFIG::grandchild  this is the grandchild (prefix "grand")
     *   CONFIG::grand       the constructor loadBytes a grandchild (GrandBytes.HEX)
     *   Pad.DATA            a 300 KB string in the big variant, never read
     */
    public class Child extends MovieClip {
        private var seen:Object = {};
        private var grandLoader:Loader;

        public function Child() {
            var me:Child = this;
            say("constructor " + where() + " pad=" + Pad.DATA.length);
            addEventListener(Event.ADDED, function(e:Event):void {
                say("added target=" + (e.target == me ? "self" : "other") + " " + where());
            });
            addEventListener(Event.ADDED_TO_STAGE, function(e:Event):void {
                say("addedToStage " + where());
            });
            addEventListener(Event.ENTER_FRAME, frameEvent);
            addEventListener(Event.FRAME_CONSTRUCTED, frameEvent);
            addEventListener(Event.EXIT_FRAME, frameEvent);
            addFrameScript(0, function():void {
                frameEvent(new Event("frameScript1"));
            });
            CONFIG::grand {
                grandLoader = new Loader();
                var info:* = grandLoader.contentLoaderInfo;
                info.sharedEvents.addEventListener("lt", function(e:TextEvent):void {
                    say("| " + e.text);
                });
                info.addEventListener(Event.INIT, function(e:Event):void {
                    say("grandchild loader: init content=" + (grandLoader.content == null ? "null" : "set"));
                });
                info.addEventListener(Event.COMPLETE, function(e:Event):void {
                    say("grandchild loader: complete");
                });
                var bytes:ByteArray = new ByteArray();
                var hex:String = GrandBytes.HEX;
                for (var i:int = 0; i < hex.length; i += 2) {
                    bytes.writeByte(parseInt(hex.substr(i, 2), 16));
                }
                grandLoader.loadBytes(bytes);
                say("constructor: loadBytes(grandchild) called, content=" + (grandLoader.content == null ? "null" : "set"));
                addChild(grandLoader);
            }
        }

        private function frameEvent(e:Event):void {
            var k:int = seen[e.type] == undefined ? 0 : seen[e.type];
            seen[e.type] = k + 1;
            if (k < 2) {
                say(e.type + " #" + (k + 1) + " " + where());
            }
        }

        private function where():String {
            return "parent=" + (parent == null ? "null" : "set") + " stage=" + (stage == null ? "null" : "set");
        }

        private function say(s:String):void {
            var who:String = CONFIG::grandchild ? "grand" : "child";
            // Always through sharedEvents: the loading movie prints the line, so the order and
            // the frame number are the same in the difftest and the trace (regression test) builds.
            loaderInfo.sharedEvents.dispatchEvent(new TextEvent("lt", false, false, who + " " + s));
        }
    }
}
