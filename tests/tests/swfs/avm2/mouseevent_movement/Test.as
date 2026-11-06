package {
import flash.display.Sprite;
import flash.display.Stage;
import flash.display.StageDisplayState;
import flash.display.StageScaleMode;
import flash.events.FullScreenEvent;
import flash.events.KeyboardEvent;
import flash.events.MouseEvent;

// Timffle: MouseEvent.movementX/movementY. Every value here was measured in the standalone
// Flash Player 32.0.0.465 (Wine, Xvfb, XTest input) with timffle/difftest/src/D66Movement.hx
// (golden: timffle/difftest/expected-interactive/d66movement.txt, same line format):
// constructed events and clones read 0, the setters coerce to Number, an unlocked mouse reports 0
// for every event; with Stage.mouseLock every mouseMove targets the stage with localX/Y 0 and
// movementX/Y = the raw screen-pixel motion, stage.mouseX/Y = that motion in stage units, and
// down/up/click/wheel read movement 0 and mouse 0; locking sends mouseOut/rollOut (localX/Y 0) to
// the object under the pointer at once. asc's 550x400 stage is shown in 1408x1024 (scale 2.56, as
// the probe's 400x300 stage in its 1024x768 full screen), so input positions are 2.56 x stage ones.
// mouseDown #1: plain click; #2: full screen; #3: mouseLock = true; a key press: mouseLock = false
// (the probe unlocks from a timer).
public class Test extends Sprite {
    private var downs:int = 0;
    private var cloned:Boolean = false;

    private static function n(v:Number):String {
        if (isNaN(v)) return "NaN";
        if (!isFinite(v)) return v > 0 ? "Infinity" : "-Infinity";
        var r:Number = Math.round(v * 1000) / 1000;
        return String(r == 0 ? 0 : r);
    }

    private static function mv(e:MouseEvent):String {
        return "movement=(" + n(e.movementX) + "," + n(e.movementY) + ")";
    }

    private function logEvent(where:String, e:MouseEvent):void {
        var name:String = e.target == stage ? "stage" : e.target.name;
        trace(where + " " + e.type + " target=" + name + " stage=(" + n(e.stageX) + "," + n(e.stageY) + ") local=("
            + n(e.localX) + "," + n(e.localY) + ") " + mv(e) + " delta=" + e.delta + " buttonDown=" + e.buttonDown
            + " lock=" + stage.mouseLock + " mouse=(" + n(stage.mouseX) + "," + n(stage.mouseY) + ")");
        if (!cloned && e.type == MouseEvent.MOUSE_MOVE && (e.movementX != 0 || e.movementY != 0)) {
            cloned = true;
            trace("clone of a dispatched mouseMove: " + mv(MouseEvent(e.clone())));
        }
    }

    public function Test() {
        var e:MouseEvent = new MouseEvent(MouseEvent.MOUSE_MOVE);
        trace("new MouseEvent: " + mv(e));
        var e2:MouseEvent = new MouseEvent(MouseEvent.MOUSE_MOVE, true, false, 10, 20, null, false, false, false, false, 3);
        trace("new MouseEvent(all args): " + mv(e2) + " stage=(" + n(e2.stageX) + "," + n(e2.stageY) + ")");
        e.movementX = 3.5;
        e.movementY = -7.25;
        trace("after set: " + mv(e));
        trace("clone: " + mv(MouseEvent(e.clone())));
        trace("toString: " + e.toString());
        var d:Object = e;
        d.movementX = "12";
        trace("set string \"12\": " + mv(e));
        d.movementX = null;
        trace("set null: " + mv(e));
        d.movementX = undefined;
        trace("set undefined: " + mv(e));
        d.movementY = Number.POSITIVE_INFINITY;
        trace("set Infinity: " + mv(e));
        var s:Sprite = new Sprite();
        s.addEventListener(MouseEvent.MOUSE_MOVE, function(ev:MouseEvent):void { trace("dispatchEvent listener: " + mv(ev)); });
        var e3:MouseEvent = new MouseEvent(MouseEvent.MOUSE_MOVE);
        e3.movementX = 4;
        e3.movementY = 5;
        s.dispatchEvent(e3);

        stage.scaleMode = StageScaleMode.SHOW_ALL;
        var bg:Sprite = new Sprite();
        bg.name = "bg";
        bg.graphics.beginFill(0xC0C0C0);
        bg.graphics.drawRect(0, 0, 400, 300);
        addChild(bg);
        var box:Sprite = new Sprite();
        box.name = "box";
        box.graphics.beginFill(0x3060C0);
        box.graphics.drawRect(0, 0, 100, 100);
        box.x = 120;
        box.y = 120;
        box.scaleX = 2;
        addChild(box);
        box.addEventListener(MouseEvent.ROLL_OVER, function(e:MouseEvent):void { logEvent("box", e); });
        box.addEventListener(MouseEvent.ROLL_OUT, function(e:MouseEvent):void { logEvent("box", e); });
        for each (var t:String in [MouseEvent.MOUSE_MOVE, MouseEvent.MOUSE_OVER, MouseEvent.MOUSE_OUT,
                MouseEvent.MOUSE_UP, MouseEvent.CLICK, MouseEvent.MOUSE_WHEEL]) {
            stage.addEventListener(t, function(e:MouseEvent):void { logEvent("stage", e); });
        }
        stage.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent):void {
            logEvent("stage", e);
            downs++;
            if (downs == 2) {
                stage.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
            } else if (downs == 3) {
                stage.mouseLock = true;
                trace("mouseLock=true -> " + stage.mouseLock);
            }
        });
        stage.addEventListener(KeyboardEvent.KEY_DOWN, function(e:KeyboardEvent):void {
            stage.mouseLock = false;
            trace("mouseLock=false -> " + stage.mouseLock + " mouse=(" + n(stage.mouseX) + "," + n(stage.mouseY) + ")");
        });
        stage.addEventListener(FullScreenEvent.FULL_SCREEN, function(e:FullScreenEvent):void {
            trace("fullScreen=" + e.fullScreen + " state=" + stage.displayState);
        });
        trace("ready");
    }
}
}
