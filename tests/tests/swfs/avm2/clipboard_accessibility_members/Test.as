package {
import flash.accessibility.Accessibility;
import flash.debugger.enterDebugger;
import flash.desktop.Clipboard;
import flash.desktop.ClipboardFormats;
import flash.desktop.ClipboardTransferMode;
import flash.display.Sprite;
import flash.events.Event;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// flash.desktop.Clipboard, flash.accessibility.Accessibility and flash.debugger.enterDebugger
// in Flash Player (not AIR). The lines outside the paste event are what the standalone Flash
// Player 32.0.0.465 printed (timffle/difftest/src/D50ClipAcc.hx); the paste part follows the
// AS3 reference (getData is allowed only inside an Event.PASTE handler, standard formats come
// back as copies, application-defined formats follow the transfer mode, handlers run on read).
// The test driver copies "from-os" to the host clipboard (another program's copy) and then
// sends the paste text control.
public class Test extends Sprite {
    private var clip:Clipboard;
    private var tf:TextField;
    private var custom:Object = {a: 1};
    private var custom2:Object = {b: 2};
    private var pasted:Boolean = false;

    public function Test() {
        step("new Clipboard()", function():void { trace(new Clipboard()); });
        clip = Clipboard.generalClipboard;
        trace("generalClipboard " + getQualifiedClassName(clip) + " same=" + (Clipboard.generalClipboard == clip));

        step("Accessibility.active", function():void { trace(Accessibility.active); });
        step("Accessibility.updateProperties()", function():void { Accessibility.updateProperties(); trace("returned"); });
        step("Accessibility.sendEvent(this, 0, 0x8005)", function():void { Accessibility.sendEvent(Test(stage.getChildAt(0)), 0, 0x8005); trace("returned"); });
        step("Accessibility.sendEvent(null, 0, 0)", function():void { Accessibility.sendEvent(null, 0, 0); trace("returned"); });
        step("enterDebugger()", function():void { enterDebugger(); trace("returned"); });

        clipboardCalls();

        tf = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.width = 200;
        tf.height = 50;
        addChild(tf);
        stage.focus = tf;
        tf.addEventListener(Event.PASTE, onPaste);
        stage.addEventListener(Event.PASTE, function(e:Event):void {
            trace("stage paste phase=" + e.eventPhase + " target=" + getQualifiedClassName(e.target));
        });
        addEventListener(Event.ENTER_FRAME, function(e:Event):void {
            if (pasted) {
                trace("--- after paste: tf.text=" + tf.text);
                step("getData(TEXT) after paste", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT)); });
                step("hasFormat(TEXT) after paste", function():void { trace(clip.hasFormat(ClipboardFormats.TEXT_FORMAT)); });
                pasted = false;
            }
        });
    }

    private function onPaste(e:Event):void {
        if (pasted) return;
        pasted = true;
        trace("--- paste event type=" + e.type + " bubbles=" + e.bubbles + " cancelable=" + e.cancelable + " target=" + getQualifiedClassName(e.target) + " current=" + getQualifiedClassName(e.currentTarget) + " tf.text=" + tf.text);
        step("formats in paste", formats);
        step("getData(TEXT)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT)); });
        step("getData(TEXT, cloneOnly)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT, ClipboardTransferMode.CLONE_ONLY)); });
        step("getData(TEXT, bogus)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT, "bogus")); });
        step("getData(null)", function():void { trace(clip.getData(null)); });
        step("getData(HTML)", function():void { trace(clip.getData(ClipboardFormats.HTML_FORMAT)); });
        step("getData(RTF)", function():void {
            var ba:ByteArray = clip.getData(ClipboardFormats.RICH_TEXT_FORMAT) as ByteArray;
            trace(getQualifiedClassName(ba) + " " + ba.length + " " + ba.readUTFBytes(ba.length));
        });
        step("getData(bogus)", function():void { trace(clip.getData("bogus")); });
        step("getData(custom)", function():void {
            var v:Object = clip.getData("custom");
            trace("same=" + (v === custom) + " a=" + v.a);
        });
        step("getData(custom, originalOnly)", function():void { trace(clip.getData("custom", ClipboardTransferMode.ORIGINAL_ONLY) === custom); });
        step("getData(custom, clonePreferred)", function():void {
            var v:Object = clip.getData("custom", ClipboardTransferMode.CLONE_PREFERRED);
            trace("same=" + (v === custom) + " a=" + v.a);
        });
        step("getData(custom, cloneOnly)", function():void {
            var v:Object = clip.getData("custom", ClipboardTransferMode.CLONE_ONLY);
            trace("same=" + (v === custom) + " a=" + v.a);
        });
        step("getData(custom2 not serializable, clonePreferred)", function():void { trace(clip.getData("custom2", ClipboardTransferMode.CLONE_PREFERRED) === custom2); });
        step("getData(custom2 not serializable, cloneOnly)", function():void { trace(clip.getData("custom2", ClipboardTransferMode.CLONE_ONLY)); });
        step("getData(custom3 handler)", function():void { trace(clip.getData("custom3")); });
        step("getData(custom3 handler, cloneOnly)", function():void { trace(clip.getData("custom3", ClipboardTransferMode.CLONE_ONLY)); });
        step("setData(TEXT) in paste", function():void { trace(clip.setData(ClipboardFormats.TEXT_FORMAT, "written in paste")); });
        step("getData(TEXT) after write", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT)); });
    }

    private function handler(format:String):Object {
        trace("handler called for " + format);
        return "from-handler-" + format;
    }

    private function formats():void {
        var f:Array = clip.formats;
        trace("formats len=" + f.length + " [" + f.join(",") + "] same=" + (clip.formats == f));
    }

    private function clipboardCalls():void {
        step("formats", formats);
        step("hasFormat(TEXT)", function():void { trace(clip.hasFormat(ClipboardFormats.TEXT_FORMAT)); });
        step("hasFormat(bogus)", function():void { trace(clip.hasFormat("bogus")); });
        step("hasFormat(null)", function():void { trace(clip.hasFormat(null)); });
        step("getData(TEXT)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT)); });
        step("getData(TEXT, cloneOnly)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT, ClipboardTransferMode.CLONE_ONLY)); });
        step("getData(TEXT, bogus)", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT, "bogus")); });
        step("getData(null)", function():void { trace(clip.getData(null)); });
        step("getData(bogus)", function():void { trace(clip.getData("bogus")); });
        step("clearData(TEXT)", function():void { clip.clearData(ClipboardFormats.TEXT_FORMAT); trace("returned"); });
        step("clearData(null)", function():void { clip.clearData(null); trace("returned"); });
        step("clear()", function():void { clip.clear(); trace("returned"); });
        step("setData(TEXT, hello)", function():void { trace(clip.setData(ClipboardFormats.TEXT_FORMAT, "hello")); });
        step("setData(TEXT, 123)", function():void { trace(clip.setData(ClipboardFormats.TEXT_FORMAT, 123)); });
        step("setData(TEXT, null)", function():void { trace(clip.setData(ClipboardFormats.TEXT_FORMAT, null)); });
        step("setData(null, x)", function():void { trace(clip.setData(null, "x")); });
        step("setData(HTML)", function():void { trace(clip.setData(ClipboardFormats.HTML_FORMAT, "<b>x</b>")); });
        step("setData(URL)", function():void { trace(clip.setData(ClipboardFormats.URL_FORMAT, "http://example.com/")); });
        step("setData(RTF)", function():void {
            var ba:ByteArray = new ByteArray();
            ba.writeUTFBytes("{\\rtf1 x}");
            trace(clip.setData(ClipboardFormats.RICH_TEXT_FORMAT, ba));
        });
        step("setData(BITMAP)", function():void { trace(clip.setData(ClipboardFormats.BITMAP_FORMAT, new Sprite())); });
        step("setData(FILE_LIST)", function():void { trace(clip.setData(ClipboardFormats.FILE_LIST_FORMAT, [])); });
        step("setData(FILE_PROMISE_LIST)", function():void { trace(clip.setData(ClipboardFormats.FILE_PROMISE_LIST_FORMAT, [])); });
        step("setData(custom)", function():void { trace(clip.setData("custom", custom)); });
        step("setData(custom2, false)", function():void { trace(clip.setData("custom2", custom2, false)); });
        step("formats after sets", formats);
        step("hasFormat(TEXT) after", function():void { trace(clip.hasFormat(ClipboardFormats.TEXT_FORMAT)); });
        step("hasFormat(custom) after", function():void { trace(clip.hasFormat("custom")); });
        step("getData(TEXT) after", function():void { trace(clip.getData(ClipboardFormats.TEXT_FORMAT)); });
        step("getData(custom) after", function():void { trace(clip.getData("custom")); });
        step("setDataHandler(TEXT, fn)", function():void { trace(clip.setDataHandler(ClipboardFormats.TEXT_FORMAT, handler)); });
        step("setDataHandler(custom3, fn)", function():void { trace(clip.setDataHandler("custom3", handler)); });
        step("setDataHandler(custom4, null)", function():void { trace(clip.setDataHandler("custom4", null)); });
        step("setDataHandler(null, fn)", function():void { trace(clip.setDataHandler(null, handler)); });
        step("setDataHandler(URL, fn)", function():void { trace(clip.setDataHandler(ClipboardFormats.URL_FORMAT, handler)); });
        step("formats after handlers", formats);
        step("clearData(TEXT) after", function():void { clip.clearData(ClipboardFormats.TEXT_FORMAT); trace("returned"); });
        step("formats after clearData", formats);
        step("clear() after", function():void { clip.clear(); trace("returned"); });
        step("formats after clear", formats);
        step("setData(TEXT, pasteme)", function():void { trace(clip.setData(ClipboardFormats.TEXT_FORMAT, "pasteme")); });
        step("setData(HTML) 2", function():void { trace(clip.setData(ClipboardFormats.HTML_FORMAT, "<i>y</i>")); });
        step("setData(RTF) 2", function():void {
            var ba:ByteArray = new ByteArray();
            ba.writeUTFBytes("{\\rtf1 y}");
            trace(clip.setData(ClipboardFormats.RICH_TEXT_FORMAT, ba));
        });
        step("setData(custom) 2", function():void { trace(clip.setData("custom", custom)); });
        step("setData(custom2, false) 2", function():void { trace(clip.setData("custom2", custom2, false)); });
        step("setDataHandler(custom3, fn) 2", function():void { trace(clip.setDataHandler("custom3", handler)); });
        step("formats end", formats);
    }

    private function step(label:String, f:Function):void {
        trace("// " + label);
        try {
            f();
        } catch (e:Error) {
            trace(getQualifiedClassName(e) + " #" + e.errorID);
        }
    }
}
}
