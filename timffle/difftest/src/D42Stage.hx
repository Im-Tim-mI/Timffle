/** Probe (no golden): the flash.display.Stage members Ruffle still stubs, read by name so the
 *  undocumented ones (displayContextInfo, constructor) are reachable without Haxe externs.
 *  Build with -swf-version 32 (mouseLock, allowsFullScreenInteractive need FP 11.2+) and run in
 *  the standalone Flash Player 32 projector (windowed, not full screen). */
class D42Stage {
	static var stage:Dynamic;

	// catch flash.errors.Error only: Haxe's catch(e:Dynamic) wrapper aborts in the release player
	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + e.name + " #" + e.errorID + " " + e.message);
		}
	}

	static function main() {
		H.init("d42stage");
		stage = flash.Lib.current.stage;
		var qn:Dynamic = untyped __global__["flash.utils.getQualifiedClassName"];
		for (n in ["allowsFullScreen", "allowsFullScreenInteractive", "colorCorrection",
				"colorCorrectionSupport", "constructor", "displayContextInfo", "fullScreenHeight",
				"fullScreenWidth", "fullScreenSourceRect", "mouseLock", "softKeyboardRect",
				"stageVideos", "wmodeGPU", "displayState", "stageWidth", "stageHeight"]) {
			step(n, function() {
				var v:Dynamic = Reflect.field(stage, n);
				H.log(n + " (" + qn(v) + ") = " + Std.string(v));
			});
		}
		step("stageVideos.length", function() H.log("stageVideos.length = " + stage.stageVideos.length));
		step("stageVideos same object", function() H.log("stageVideos same = " + (stage.stageVideos == stage.stageVideos)));
		step("stageVideos fixed", function() H.log("stageVideos fixed = " + stage.stageVideos.fixed));
		step("stageVideos push", function() { var v = stage.stageVideos; v.push(null); H.log("stageVideos push ok, same vector length " + v.length + ", fresh length " + stage.stageVideos.length); });
		step("stageVideos[0] same", function() H.log("stageVideos[0] same = " + (stage.stageVideos[0] == stage.stageVideos[0])));
		step("new StageVideo", function() { var c:Dynamic = untyped __global__["flash.media.StageVideo"]; var o = Type.createInstance(c, []); H.log("new StageVideo ok: " + Std.string(o)); });
		step("isFocusInaccessible", function() H.log("isFocusInaccessible() = " + stage.isFocusInaccessible()));
		step("focus=null then isFocusInaccessible", function() { stage.focus = null; H.log("after focus=null: " + stage.isFocusInaccessible()); });
		step("softKeyboardRect same", function() H.log("softKeyboardRect same = " + (stage.softKeyboardRect == stage.softKeyboardRect)));

		for (v in ["on", "off", "default", "ON", "bogus", ""]) {
			step("colorCorrection=" + v, function() {
				stage.colorCorrection = v;
				H.log("colorCorrection=" + v + " -> " + stage.colorCorrection);
			});
		}
		step("colorCorrection=null", function() { stage.colorCorrection = null; H.log("colorCorrection=null -> " + stage.colorCorrection); });
		step("colorCorrection=on again", function() { stage.colorCorrection = "on"; H.log("colorCorrection=on -> " + stage.colorCorrection); });

		step("mouseLock=true (windowed)", function() { stage.mouseLock = true; H.log("mouseLock=true -> " + stage.mouseLock); });
		step("mouseLock=false", function() { stage.mouseLock = false; H.log("mouseLock=false -> " + stage.mouseLock); });

		step("fullScreenSourceRect=rect", function() {
			var r = new flash.geom.Rectangle(1, 2, 3, 4);
			stage.fullScreenSourceRect = r;
			var g:Dynamic = stage.fullScreenSourceRect;
			H.log("fullScreenSourceRect=rect -> " + Std.string(g) + " same=" + (g == r));
			g.x = 99;
			H.log("after mutating returned rect: " + Std.string(stage.fullScreenSourceRect));
			r.y = 77;
			H.log("after mutating set rect: " + Std.string(stage.fullScreenSourceRect));
		});
		step("fullScreenSourceRect=frac rect", function() {
			stage.fullScreenSourceRect = new flash.geom.Rectangle(1.5, -6.7, 2.2, 0);
			H.log("fullScreenSourceRect=frac -> " + Std.string(stage.fullScreenSourceRect));
		});
		step("fullScreenSourceRect=null", function() { stage.fullScreenSourceRect = null; H.log("fullScreenSourceRect=null -> " + Std.string(stage.fullScreenSourceRect)); });

		step("constructor=1", function() { stage.constructor = 1; H.log("constructor=1 -> " + Std.string(stage.constructor)); });
		step("constructor=obj", function() { var o = {}; stage.constructor = o; H.log("constructor=obj -> " + Std.string(stage.constructor)); });
		step("displayContextInfo set", function() { Reflect.setField(stage, "displayContextInfo", "x"); H.log("displayContextInfo set ok -> " + Std.string(stage.displayContextInfo)); });
		step("wmodeGPU set", function() { Reflect.setField(stage, "wmodeGPU", true); H.log("wmodeGPU set ok"); });
		step("colorCorrectionSupport set", function() { Reflect.setField(stage, "colorCorrectionSupport", "defaultOn"); H.log("colorCorrectionSupport set ok"); });
		step("final", function() H.log("displayState=" + stage.displayState + " mouseLock=" + stage.mouseLock + " colorCorrection=" + stage.colorCorrection));
		H.done();
	}
}
