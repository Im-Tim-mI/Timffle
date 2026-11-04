/** Probe (no golden): Stage.fullScreenSourceRect clamping and the full-screen-only members
 *  (mouseLock, stageWidth/Height with a source rect) in the standalone Flash Player 32
 *  projector. Build with -swf-version 32. Steps are chained with timers so that one abort
 *  does not hide the rest (see TESTING.md). */
class D43StageFull {
	static var stage:Dynamic;
	static var steps:Array<Void->Void> = [];
	static var i = 0;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function rect(x:Float, y:Float, w:Float, h:Float) {
		step("rect", function() {
			stage.fullScreenSourceRect = new flash.geom.Rectangle(x, y, w, h);
			H.log("set (" + x + "," + y + "," + w + "," + h + ") -> " + Std.string(stage.fullScreenSourceRect));
		});
	}

	static function state() {
		H.log("displayState=" + stage.displayState + " stage=" + stage.stageWidth + "x" + stage.stageHeight
			+ " scaleMode=" + stage.scaleMode + " align=" + stage.align + " mouseLock=" + stage.mouseLock
			+ " rect=" + Std.string(stage.fullScreenSourceRect));
	}

	static function next() {
		if (i < steps.length) {
			var f = steps[i++];
			haxe.Timer.delay(function() { step("step" + i, f); next(); }, 300);
		} else
			H.done();
	}

	static function main() {
		H.init("d43stagefull");
		stage = flash.Lib.current.stage;
		state();
		rect(0, 0, 100, 100);
		rect(0, 0, 400, 300);
		rect(0, 0, 1000, 1000);
		rect(0, 0, 2000, 50);
		rect(10, 10, 0, 0);
		rect(0, 0, 302, 74);
		rect(0, 0, 301, 73);
		rect(0, 0, 303, 75);
		rect(-100, -100, 50, 1000);
		rect(0.4, 0.5, 0.6, 1.5);
		step("rect NaN", function() { stage.fullScreenSourceRect = new flash.geom.Rectangle(Math.NaN, 1, 2, 3); H.log("NaN -> " + Std.string(stage.fullScreenSourceRect)); });
		step("rect 1e9", function() { stage.fullScreenSourceRect = new flash.geom.Rectangle(1e9, -1e9, 1e9, 1e9); H.log("1e9 -> " + Std.string(stage.fullScreenSourceRect)); });
		stage.fullScreenSourceRect = null;
		steps.push(function() { stage.fullScreenSourceRect = new flash.geom.Rectangle(0, 0, 200, 150); stage.displayState = "fullScreen"; H.log("entered fullScreen"); });
		steps.push(function() state());
		steps.push(function() { stage.mouseLock = true; H.log("mouseLock=true in fullScreen -> " + stage.mouseLock); });
		steps.push(function() { stage.mouseLock = false; H.log("mouseLock=false in fullScreen -> " + stage.mouseLock); });
		steps.push(function() { stage.fullScreenSourceRect = new flash.geom.Rectangle(0, 0, 400, 300); H.log("rect changed while full -> " + Std.string(stage.fullScreenSourceRect)); });
		steps.push(function() state());
		steps.push(function() { stage.fullScreenSourceRect = null; H.log("rect null while full"); });
		steps.push(function() state());
		steps.push(function() { stage.displayState = "normal"; H.log("back to normal"); });
		steps.push(function() state());
		steps.push(function() { stage.displayState = "fullScreenInteractive"; H.log("set fullScreenInteractive"); });
		steps.push(function() state());
		steps.push(function() { stage.mouseLock = true; H.log("mouseLock=true in " + stage.displayState + " -> " + stage.mouseLock); });
		steps.push(function() { stage.displayState = "normal"; H.log("back to normal; mouseLock=" + stage.mouseLock); });
		steps.push(function() state());
		next();
	}
}
