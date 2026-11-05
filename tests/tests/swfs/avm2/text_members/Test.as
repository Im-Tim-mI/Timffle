package {
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.text.AntiAliasType;
    import flash.text.CSMSettings;
    import flash.text.Font;
    import flash.text.FontStyle;
    import flash.text.FontType;
    import flash.text.TextColorType;
    import flash.text.TextDisplayMode;
    import flash.text.TextField;
    import flash.text.TextFormat;
    import flash.text.TextInteractionMode;
    import flash.text.TextRenderer;

    // Timffle: TextField.getRawText/getXMLText/insertXMLText/getImageReference/
    // mouseWheelEnabled/isFontCompatible/textInteractionMode/useRichTextClipboard,
    // TextRenderer.antiAliasType/displayMode/maxLevel/setAdvancedAntiAliasingTable
    // and Font.enumerateFonts(true).
    [SWF(width="100", height="100")]
    public class Test extends Sprite {
        private var frame:int = 0;
        private var scroller:TextField;

        public function Test() {
            stage.scaleMode = "noScale";
            testTextField();
            testTextRenderer();
            testFonts();
            setupScroller();
            addEventListener(Event.ENTER_FRAME, onFrame);
        }

        private function errorOf(f:Function):String {
            try {
                f();
            } catch (e:Error) {
                return e.errorID + " " + e;
            }
            return "no error";
        }

        private function testTextField():void {
            var tf:TextField = new TextField();
            tf.multiline = true;
            trace("mouseWheelEnabled default: " + tf.mouseWheelEnabled);
            tf.mouseWheelEnabled = false;
            trace("mouseWheelEnabled after set: " + tf.mouseWheelEnabled);
            trace("useRichTextClipboard default: " + tf.useRichTextClipboard);
            tf.useRichTextClipboard = true;
            trace("useRichTextClipboard after set: " + tf.useRichTextClipboard);
            trace("textInteractionMode: " + tf.textInteractionMode + " normal=" + (tf.textInteractionMode == TextInteractionMode.NORMAL));

            tf.htmlText = "<p>Hello <b>bold</b> world</p>";
            trace("text: " + tf.text);
            trace("getRawText: " + tf.getRawText());
            trace("getXMLText(): " + tf.getXMLText());
            trace("getXMLText(6, 10): " + tf.getXMLText(6, 10));
            trace("getXMLText(-5, 99): " + tf.getXMLText(-5, 99));
            trace("getXMLText(3, 3): [" + tf.getXMLText(3, 3) + "]");

            tf.insertXMLText(6, 10, "<i>fancy</i>");
            trace("after insertXMLText text: " + tf.text);
            trace("after insertXMLText html: " + tf.htmlText);
            trace("format at 6: italic=" + tf.getTextFormat(6, 7).italic + " bold=" + tf.getTextFormat(6, 7).bold);
            trace("format at 0: italic=" + tf.getTextFormat(0, 1).italic + " bold=" + tf.getTextFormat(0, 1).bold);
            tf.insertXMLText(0, 0, "<u>Oh </u>");
            trace("after insertXMLText at 0: " + tf.text + " underline=" + tf.getTextFormat(0, 1).underline);
            tf.insertXMLText(100, 200, "<b>!</b>");
            trace("after insertXMLText past end: " + tf.text);

            var plain:TextField = new TextField();
            plain.text = "plain";
            trace("plain getXMLText: " + plain.getXMLText());
            trace("plain getRawText: " + plain.getRawText());

            tf.htmlText = "<p>pic <img src='missing.png' id='pic'/> here</p>";
            trace("getImageReference(pic): " + tf.getImageReference("pic"));
            trace("getImageReference(nope): " + tf.getImageReference("nope"));

            trace("isFontCompatible Arial regular: " + TextField.isFontCompatible("Arial", FontStyle.REGULAR));
            trace("isFontCompatible _sans bold: " + TextField.isFontCompatible("_sans", FontStyle.BOLD));
            trace("isFontCompatible bad style: " + errorOf(function():void { TextField.isFontCompatible("Arial", "weird"); }));
            trace("isFontCompatible null name: " + errorOf(function():void { TextField.isFontCompatible(null, FontStyle.REGULAR); }));
            trace("isFontCompatible null style: " + errorOf(function():void { TextField.isFontCompatible("Arial", null); }));
        }

        private function testTextRenderer():void {
            trace("TextRenderer.antiAliasType default: " + TextRenderer.antiAliasType);
            TextRenderer.antiAliasType = AntiAliasType.ADVANCED;
            trace("TextRenderer.antiAliasType set: " + TextRenderer.antiAliasType);
            trace("TextRenderer.antiAliasType bad: " + errorOf(function():void { TextRenderer.antiAliasType = "fancy"; }));
            trace("TextRenderer.antiAliasType null: " + errorOf(function():void { TextRenderer.antiAliasType = null; }));
            trace("TextRenderer.antiAliasType kept: " + TextRenderer.antiAliasType);

            trace("TextRenderer.displayMode default: " + TextRenderer.displayMode);
            TextRenderer.displayMode = TextDisplayMode.LCD;
            trace("TextRenderer.displayMode set: " + TextRenderer.displayMode);
            TextRenderer.displayMode = TextDisplayMode.CRT;
            trace("TextRenderer.displayMode set: " + TextRenderer.displayMode);
            trace("TextRenderer.displayMode bad: " + errorOf(function():void { TextRenderer.displayMode = "oled"; }));
            trace("TextRenderer.displayMode kept: " + TextRenderer.displayMode);

            trace("TextRenderer.maxLevel default: " + TextRenderer.maxLevel);
            TextRenderer.maxLevel = 7;
            trace("TextRenderer.maxLevel set: " + TextRenderer.maxLevel);
            TextRenderer.maxLevel = 3;
            trace("TextRenderer.maxLevel set: " + TextRenderer.maxLevel);
            trace("TextRenderer.maxLevel bad: " + errorOf(function():void { TextRenderer.maxLevel = 5; }));
            trace("TextRenderer.maxLevel kept: " + TextRenderer.maxLevel);

            var table:Array = [new CSMSettings(12, 0.5, -0.5), new CSMSettings(24, 0.2, -0.2)];
            trace("setAdvancedAntiAliasingTable ok: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.BOLD, TextColorType.DARK_COLOR, table);
            }));
            trace("setAdvancedAntiAliasingTable again: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.BOLD, TextColorType.DARK_COLOR, [new CSMSettings(10, 0.1, -0.1)]);
            }));
            trace("setAdvancedAntiAliasingTable empty: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.REGULAR, TextColorType.LIGHT_COLOR, []);
            }));
            trace("setAdvancedAntiAliasingTable bad style: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", "slanted", TextColorType.DARK_COLOR, table);
            }));
            trace("setAdvancedAntiAliasingTable bad color: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.BOLD, "red", table);
            }));
            trace("setAdvancedAntiAliasingTable bad entry: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.BOLD, TextColorType.DARK_COLOR, [1, 2]);
            }));
            trace("setAdvancedAntiAliasingTable null font: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable(null, FontStyle.BOLD, TextColorType.DARK_COLOR, table);
            }));
            trace("setAdvancedAntiAliasingTable null table: " + errorOf(function():void {
                TextRenderer.setAdvancedAntiAliasingTable("Arial", FontStyle.BOLD, TextColorType.DARK_COLOR, null);
            }));
        }

        private function testFonts():void {
            var embedded:Array = Font.enumerateFonts(false);
            var all:Array = Font.enumerateFonts(true);
            trace("enumerateFonts(false) is Array: " + (embedded is Array) + " length " + embedded.length);
            trace("enumerateFonts(true) is Array: " + (all is Array));
            trace("enumerateFonts(true) holds the embedded ones: " + (all.length >= embedded.length));
            var typesOk:Boolean = true;
            var sorted:Boolean = true;
            var previous:String = "";
            for each (var f:Font in all) {
                if (f.fontType != FontType.DEVICE && f.fontType != FontType.EMBEDDED) {
                    typesOk = false;
                }
                if (f.fontName.toLowerCase() < previous) {
                    sorted = false;
                }
                previous = f.fontName.toLowerCase();
                if (f.fontType == FontType.DEVICE && f.fontName == "") {
                    typesOk = false;
                }
            }
            trace("enumerateFonts(true) types ok: " + typesOk + " sorted: " + sorted);
            trace("enumerateFonts(true) has device fonts: " + (all.length > embedded.length));
        }

        private function setupScroller():void {
            scroller = new TextField();
            scroller.multiline = true;
            scroller.wordWrap = false;
            scroller.x = 0;
            scroller.y = 0;
            scroller.width = 100;
            scroller.height = 60;
            scroller.text = "";
            for (var i:int = 0; i < 40; i++) {
                scroller.appendText("line " + i + "\n");
            }
            scroller.scrollV = 1;
            scroller.mouseWheelEnabled = false;
            scroller.addEventListener(Event.SCROLL, function(e:Event):void {
                trace("scroll event: scrollV=" + scroller.scrollV);
            });
            addChild(scroller);
            trace("scroller maxScrollV>1: " + (scroller.maxScrollV > 1) + " scrollV=" + scroller.scrollV);
        }

        private function onFrame(e:Event):void {
            frame++;
            if (frame == 1) {
                // The first wheel event arrived while mouseWheelEnabled was false.
                trace("after wheel with mouseWheelEnabled=false: scrollV=" + scroller.scrollV);
                scroller.mouseWheelEnabled = true;
            } else if (frame == 2) {
                trace("after wheel with mouseWheelEnabled=true: scrollV>1=" + (scroller.scrollV > 1));
                removeEventListener(Event.ENTER_FRAME, onFrame);
            }
        }
    }
}
