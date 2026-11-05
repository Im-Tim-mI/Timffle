import flash.display.Sprite;
import flash.display.StageDisplayState;
import flash.display.StageScaleMode;
import flash.events.Event;
import flash.events.FullScreenEvent;
import flash.events.MouseEvent;

/** MouseEvent.movementX/movementY in Flash Player 32 (standalone, driven by drive_movement.py):
 *  constructed events, clone(), every mouse event type windowed, in full screen, and with
 *  Stage.mouseLock (relative moves sent by XTest). Build with -swf-version 32 (mouseLock is FP 11.2+).
 *  Phases follow the mouseDown count: 1st = windowed click, 2nd = enter FULL_SCREEN_INTERACTIVE,
 *  3rd = mouseLock = true; 3 s after the lock, mouseLock = false; the report follows 3 s later. */
class D66Movement {
	static var st:flash.display.Stage;
	static var downs = 0;
	static var cloned = false;

	static function n(v:Float):String {
		if (Math.isNaN(v))
			return "NaN";
		if (!Math.isFinite(v))
			return v > 0 ? "Infinity" : "-Infinity";
		var r = Math.round(v * 1000) / 1000;
		return Std.string(r == 0 ? 0 : r);
	}

	static function mv(e:Dynamic):String
		return "movement=(" + n(e.movementX) + "," + n(e.movementY) + ")";

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function logEvent(where:String, e:MouseEvent) {
		var t:Dynamic = e.target;
		var name:String = t == st ? "stage" : t.name;
		H.log(where + " " + e.type + " target=" + name + " stage=(" + n(e.stageX) + "," + n(e.stageY) + ") local=(" + n(e.localX) + ","
			+ n(e.localY) + ") " + mv(e) + " delta=" + e.delta + " buttonDown=" + e.buttonDown + " lock=" + st.mouseLock + " mouse=("
			+ n(st.mouseX) + "," + n(st.mouseY) + ")");
		if (!cloned && e.type == MouseEvent.MOUSE_MOVE && (e.movementX != 0 || e.movementY != 0)) {
			cloned = true;
			var c:MouseEvent = cast e.clone();
			H.log("clone of a dispatched mouseMove: " + mv(c));
		}
	}

	static function main() {
		H.init("d66movement", 90000);
		st = flash.Lib.current.stage;
		st.scaleMode = StageScaleMode.SHOW_ALL;

		step("constructed", function() {
			var e = new MouseEvent(MouseEvent.MOUSE_MOVE);
			H.log("new MouseEvent: " + mv(e));
			var e2 = new MouseEvent(MouseEvent.MOUSE_MOVE, true, false, 10, 20, null, false, false, false, false, 3);
			H.log("new MouseEvent(all args): " + mv(e2) + " stage=(" + n(e2.stageX) + "," + n(e2.stageY) + ")");
			e.movementX = 3.5;
			e.movementY = -7.25;
			H.log("after set: " + mv(e));
			var c:Dynamic = e.clone();
			H.log("clone: " + mv(c));
			H.log("toString: " + e.toString());
			var d:Dynamic = e;
			d.movementX = "12";
			H.log("set string \"12\": " + mv(e));
			d.movementX = null;
			H.log("set null: " + mv(e));
			d.movementX = untyped __global__["undefined"];
			H.log("set undefined: " + mv(e));
			d.movementY = Math.POSITIVE_INFINITY;
			H.log("set Infinity: " + mv(e));
			// a hand-dispatched event keeps what the script set
			var s = new Sprite();
			s.addEventListener(MouseEvent.MOUSE_MOVE, function(ev:MouseEvent) H.log("dispatchEvent listener: " + mv(ev)));
			var e3 = new MouseEvent(MouseEvent.MOUSE_MOVE);
			e3.movementX = 4;
			e3.movementY = 5;
			s.dispatchEvent(e3);
		});

		var bg = new Sprite();
		bg.name = "bg";
		bg.graphics.beginFill(0xC0C0C0);
		bg.graphics.drawRect(0, 0, 400, 300);
		flash.Lib.current.addChild(bg);
		var box = new Sprite();
		box.name = "box";
		box.graphics.beginFill(0x3060C0);
		box.graphics.drawRect(0, 0, 100, 100);
		box.x = 120;
		box.y = 120;
		box.scaleX = 2;
		flash.Lib.current.addChild(box);
		box.addEventListener(MouseEvent.ROLL_OVER, function(e:MouseEvent) logEvent("box", e));
		box.addEventListener(MouseEvent.ROLL_OUT, function(e:MouseEvent) logEvent("box", e));

		for (t in [MouseEvent.MOUSE_MOVE, MouseEvent.MOUSE_OVER, MouseEvent.MOUSE_OUT, MouseEvent.MOUSE_UP, MouseEvent.CLICK,
			MouseEvent.MOUSE_WHEEL, MouseEvent.DOUBLE_CLICK]) {
			st.addEventListener(t, function(e:MouseEvent) logEvent("stage", e));
		}
		st.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
			logEvent("stage", e);
			downs++;
			if (downs == 2) {
				step("fullscreen", function() st.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE);
			} else if (downs == 3) {
				step("lock", function() {
					st.mouseLock = true;
					H.log("mouseLock=true -> " + st.mouseLock);
				});
				haxe.Timer.delay(function() {
					step("unlock", function() {
						st.mouseLock = false;
						H.log("mouseLock=false -> " + st.mouseLock + " mouse=(" + n(st.mouseX) + "," + n(st.mouseY) + ")");
					});
					haxe.Timer.delay(function() H.done(), 3000);
				}, 3000);
			}
		});
		st.addEventListener(FullScreenEvent.FULL_SCREEN, function(e:FullScreenEvent) {
			H.log("fullScreen=" + e.fullScreen + " state=" + st.displayState + " stage=" + st.stageWidth + "x" + st.stageHeight
				+ " fullScreenSize=" + st.fullScreenWidth + "x" + st.fullScreenHeight);
		});
		H.log("ready");
	}
}
