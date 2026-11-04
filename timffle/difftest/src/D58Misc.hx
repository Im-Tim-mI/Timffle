/** Probe (no golden): small display members in Flash Player 32 — InteractiveObject soft-keyboard
 *  members + accessibilityImplementation, MovieClip.trackAsMenu (incl. a press-on-A/release-on-B
 *  drag sent by timffle/difftest/drive_drag.py), Shader.precisionHint, ShaderJob (sync/async
 *  start, progress, cancel, complete event timing, error cases), Sprite.startTouchDrag/stopTouchDrag
 *  on a machine without a touch screen, TransformGestureEvent.GESTURE_DIRECTIONAL_TAP.
 *  Build with -swf-version 32; run with drive_drag.py (3 drags) — without input it still reports
 *  the phase-1 lines after the watchdog. */
import flash.Lib;
import flash.display.*;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.events.ShaderEvent;
import flash.geom.Rectangle;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.utils.ByteArray;

@:file("../../../tests/tests/swfs/avm2/pixelbender_shaderdata/simple_shader.pbj")
class SimplePbj extends ByteArray {}

@:file("../../../tests/tests/swfs/avm2/pixelbender_shaderdata/shader.pbj")
class InputPbj extends ByteArray {}

class D58Misc {
	static var qn:Dynamic;
	static var frame = 0;
	static var mcA:MovieClip;
	static var mcB:MovieClip;
	static var downs = 0;
	static var ups = 0;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function r(x:Rectangle):String {
		return x == null ? "null" : "(" + x.x + "," + x.y + "," + x.width + "," + x.height + ")";
	}

	static function interactive() {
		var sp = new Sprite();
		sp.graphics.beginFill(0x0000FF);
		sp.graphics.drawRect(0, 0, 10, 10);
		Lib.current.addChild(sp);
		var st = Lib.current.stage;
		H.log("needsSoftKeyboard default=" + sp.needsSoftKeyboard);
		step("set needsSoftKeyboard", function() {
			sp.needsSoftKeyboard = true;
			H.log("needsSoftKeyboard after set=" + sp.needsSoftKeyboard);
		});
		step("requestSoftKeyboard unfocused", function() {
			H.log("focus before=" + qn(st.focus) + " requestSoftKeyboard()=" + sp.requestSoftKeyboard() + " focus after=" + qn(st.focus) + " same=" + (st.focus == sp));
		});
		sp.needsSoftKeyboard = false;
		step("requestSoftKeyboard needs=false", function() {
			st.focus = null;
			H.log("needs=false requestSoftKeyboard()=" + sp.requestSoftKeyboard() + " focus after=" + qn(st.focus));
		});
		var tf = new TextField();
		tf.type = TextFieldType.INPUT;
		tf.text = "x";
		Lib.current.addChild(tf);
		step("requestSoftKeyboard textfield", function() {
			tf.needsSoftKeyboard = true;
			H.log("tf requestSoftKeyboard()=" + tf.requestSoftKeyboard() + " focus=" + qn(st.focus));
		});
		st.focus = null;
		H.log("softKeyboardInputAreaOfInterest default=" + r(sp.softKeyboardInputAreaOfInterest));
		step("set area", function() {
			var rc = new Rectangle(1, 2, 3, 4);
			sp.softKeyboardInputAreaOfInterest = rc;
			var back = sp.softKeyboardInputAreaOfInterest;
			H.log("area after set=" + r(back) + " same=" + (back == rc) + " same twice=" + (sp.softKeyboardInputAreaOfInterest == back));
			rc.x = 99;
			H.log("area after mutating original=" + r(sp.softKeyboardInputAreaOfInterest));
			back.width = 77;
			H.log("area after mutating returned=" + r(sp.softKeyboardInputAreaOfInterest));
			sp.softKeyboardInputAreaOfInterest = null;
			H.log("area after null=" + r(sp.softKeyboardInputAreaOfInterest));
		});
		H.log("accessibilityImplementation default=" + sp.accessibilityImplementation);
		step("set accImpl", function() {
			var ai = new flash.accessibility.AccessibilityImplementation();
			sp.accessibilityImplementation = ai;
			H.log("accImpl after set same=" + (sp.accessibilityImplementation == ai) + " stub=" + sp.accessibilityImplementation.stub);
			sp.accessibilityImplementation = null;
			H.log("accImpl after null=" + sp.accessibilityImplementation);
		});
		Lib.current.removeChild(sp);
		Lib.current.removeChild(tf);
	}

	static function trackAsMenuProps() {
		var mc = new MovieClip();
		H.log("trackAsMenu default=" + mc.trackAsMenu);
		step("set trackAsMenu", function() {
			mc.trackAsMenu = true;
			H.log("trackAsMenu after set=" + mc.trackAsMenu + " other=" + new MovieClip().trackAsMenu);
			mc.trackAsMenu = false;
			H.log("trackAsMenu after reset=" + mc.trackAsMenu);
		});
		var sb = new SimpleButton();
		H.log("SimpleButton trackAsMenu default=" + sb.trackAsMenu);
	}

	static function precision() {
		var sh = new Shader();
		H.log("precisionHint default=" + sh.precisionHint);
		step("set fast", function() {
			sh.precisionHint = ShaderPrecision.FAST;
			H.log("after fast=" + sh.precisionHint);
		});
		step("set bogus", function() {
			sh.precisionHint = cast "bogus";
			H.log("after bogus=" + sh.precisionHint);
		});
		step("set FULL upper", function() {
			sh.precisionHint = cast "FULL";
			H.log("after FULL=" + sh.precisionHint);
		});
		step("set null", function() {
			sh.precisionHint = null;
			H.log("after null=" + sh.precisionHint);
		});
		step("set empty", function() {
			sh.precisionHint = cast "";
			H.log("after empty=" + sh.precisionHint);
		});
		var sh2 = new Shader(new SimplePbj());
		H.log("precisionHint with bytecode=" + sh2.precisionHint);
	}

	static function makeShader():Shader {
		var sh = new Shader(new SimplePbj());
		untyped sh.data.radius.value = [100];
		untyped sh.data.otherParam.value = [0];
		return sh;
	}

	static function hexp(bd:BitmapData):String {
		return StringTools.hex(bd.getPixel32(0, 0), 8);
	}

	static function shaderJobs(next:Void->Void) {
		var job0 = new ShaderJob();
		H.log("ShaderJob() shader=" + job0.shader + " target=" + job0.target + " w=" + job0.width + " h=" + job0.height + " progress=" + job0.progress);
		step("start no shader", function() job0.start(true));
		step("start no shader async", function() job0.start());
		var pb = new SimplePbj();
		H.log("pbj bytes=" + pb.length);
		var sh = makeShader();
		H.log("data fields=" + Reflect.fields(sh.data).join(","));
		var job1 = new ShaderJob(sh);
		step("start null target", function() job1.start(true));
		job1.target = "str";
		step("start string target", function() job1.start(true));
		job1.target = new Sprite();
		step("start sprite target", function() job1.start(true));
		var bd = new BitmapData(4, 4, true, 0xFF0000FF);
		job1.target = bd;
		step("start sync bitmap", function() {
			job1.start(true);
			H.log("sync bitmap pixel=" + hexp(bd) + " progress=" + job1.progress);
		});
		step("start sync again", function() {
			job1.start(true);
			H.log("sync again progress=" + job1.progress);
		});
		var ba = new ByteArray();
		ba.writeByte(1);
		var job2 = new ShaderJob(sh, ba, 2, 3);
		step("start sync bytearray", function() {
			job2.start(true);
			ba.position = 0;
			H.log("sync bytearray length=" + ba.length + " pos=" + ba.position + " first floats=" + ba.readFloat() + "," + ba.readFloat() + "," + ba.readFloat() + "," + ba.readFloat() + " endian=" + ba.endian + " progress=" + job2.progress);
		});
		var vec = new flash.Vector<Float>();
		var job3 = new ShaderJob(sh, vec, 2, 2);
		step("start sync vector", function() {
			job3.start(true);
			H.log("sync vector length=" + vec.length + " v0..3=" + vec[0] + "," + vec[1] + "," + vec[2] + "," + vec[3] + " progress=" + job3.progress);
		});
		var job4 = new ShaderJob(sh, ba, 0, 0);
		step("start sync bytearray 0x0", function() {
			job4.start(true);
			H.log("0x0 bytearray length=" + ba.length);
		});
		var job5 = new ShaderJob(sh, vec, 3, 0);
		step("start sync vector 3x0", function() {
			job5.start(true);
			H.log("3x0 vector length=" + vec.length);
		});
		var shNoInput = new Shader(new InputPbj());
		H.log("input pbj fields=" + Reflect.fields(shNoInput.data).join(","));
		var job6 = new ShaderJob(shNoInput, new BitmapData(2, 2));
		step("start missing input", function() job6.start(true));
		step("start missing input async", function() job6.start());

		// async
		var bd2 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobA = new ShaderJob(sh, bd2);
		var startFrame = frame;
		var t0 = Lib.getTimer();
		var doneA = false;
		jobA.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			doneA = true;
			H.log("jobA complete frame+" + (frame - startFrame) + " bubbles=" + e.bubbles + " cancelable=" + e.cancelable + " target same=" + (e.target == jobA) + " bitmapData same=" + (e.bitmapData == bd2) + " byteArray=" + e.byteArray + " vector=" + e.vector + " pixel=" + hexp(bd2) + " progress=" + jobA.progress + " type=" + e.type);
		});
		step("start async bitmap", function() {
			jobA.start();
			H.log("async right after start pixel=" + hexp(bd2) + " progress=" + jobA.progress);
		});
		step("start async twice", function() {
			jobA.start();
			H.log("async start twice ok progress=" + jobA.progress);
		});
		step("start sync while async pending", function() {
			jobA.start(true);
			H.log("sync while pending pixel=" + hexp(bd2) + " progress=" + jobA.progress);
		});
		var bd3 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobC = new ShaderJob(sh, bd3);
		jobC.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobC complete (should NOT happen if cancel works) pixel=" + hexp(bd3));
		});
		step("start async then cancel", function() {
			jobC.start();
			jobC.cancel();
			jobC.cancel();
			H.log("after cancel progress=" + jobC.progress + " pixel=" + hexp(bd3));
		});
		var ba4 = new ByteArray();
		var jobD = new ShaderJob(sh, ba4, 1, 1);
		jobD.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobD complete frame+" + (frame - startFrame) + " byteArray same=" + (e.byteArray == ba4) + " bitmapData=" + e.bitmapData + " vector=" + e.vector + " length=" + ba4.length);
		});
		var vec5 = new flash.Vector<Float>();
		var jobE = new ShaderJob(sh, vec5, 1, 1);
		jobE.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobE complete frame+" + (frame - startFrame) + " vector same=" + (e.vector == vec5) + " length=" + vec5.length);
		});
		step("start async D then E", function() {
			jobE.start();
			jobD.start();
			H.log("D/E started; E before D");
		});
		var jobF = new ShaderJob(sh, new BitmapData(2, 2));
		jobF.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobF complete frame+" + (frame - startFrame) + " progress=" + jobF.progress);
		});
		step("start async then dispose target", function() {
			var t = cast(jobF.target, BitmapData);
			jobF.start();
			t.dispose();
			H.log("disposed target after start; progress=" + jobF.progress);
		});
		H.log("# async jobs started at frame " + startFrame + " t=" + t0);
		haxe.Timer.delay(function() {
			H.log("# 1000ms later: jobA done=" + doneA + " frames elapsed=" + (frame - startFrame) + " jobA progress=" + jobA.progress);
			next();
		}, 1000);
	}

	static function touchDrag() {
		var sp = new Sprite();
		sp.graphics.beginFill(0xFF0000);
		sp.graphics.drawRect(0, 0, 10, 10);
		Lib.current.addChild(sp);
		H.log("Multitouch supportsTouchEvents=" + flash.ui.Multitouch.supportsTouchEvents + " inputMode=" + flash.ui.Multitouch.inputMode + " maxTouchPoints=" + flash.ui.Multitouch.maxTouchPoints);
		step("startTouchDrag(0)", function() {
			sp.startTouchDrag(0);
			H.log("startTouchDrag(0) ok x=" + sp.x);
		});
		step("startTouchDrag(1,true,rect)", function() {
			sp.startTouchDrag(1, true, new Rectangle(0, 0, 10, 10));
			H.log("startTouchDrag(1,true,rect) ok x=" + sp.x);
		});
		step("startTouchDrag(-1)", function() sp.startTouchDrag(-1));
		step("stopTouchDrag(0)", function() sp.stopTouchDrag(0));
		step("stopTouchDrag(5)", function() sp.stopTouchDrag(5));
		step("stopTouchDrag(-1)", function() sp.stopTouchDrag(-1));
		step("startTouchDrag then startDrag", function() {
			sp.startTouchDrag(0);
			sp.startDrag();
			sp.stopDrag();
			sp.stopTouchDrag(0);
			H.log("mixed ok");
		});
		step("inputMode=TOUCH_POINT then startTouchDrag", function() {
			flash.ui.Multitouch.inputMode = flash.ui.MultitouchInputMode.TOUCH_POINT;
			H.log("inputMode now=" + flash.ui.Multitouch.inputMode);
			sp.startTouchDrag(0);
			sp.stopTouchDrag(0);
			H.log("touch_point mode ok");
			flash.ui.Multitouch.inputMode = flash.ui.MultitouchInputMode.NONE;
		});
		Lib.current.removeChild(sp);
	}

	static function gesture() {
		var cls:Dynamic = untyped __global__["flash.events.TransformGestureEvent"];
		H.log("GESTURE_DIRECTIONAL_TAP=" + Reflect.field(cls, "GESTURE_DIRECTIONAL_TAP") + " GESTURE_PAN=" + cls.GESTURE_PAN);
		var ge:Dynamic = untyped __global__["flash.events.GestureEvent"];
		H.log("GestureEvent.GESTURE_TWO_FINGER_TAP=" + Reflect.field(ge, "GESTURE_TWO_FINGER_TAP"));
	}

	static function box(color:Int, x:Float, name:String):MovieClip {
		var mc = new MovieClip();
		mc.graphics.beginFill(color);
		mc.graphics.drawRect(0, 0, 190, 300);
		mc.x = x;
		mc.name = name;
		mc.buttonMode = true;
		Lib.current.addChild(mc);
		for (t in [MouseEvent.MOUSE_DOWN, MouseEvent.MOUSE_UP, MouseEvent.CLICK, MouseEvent.RELEASE_OUTSIDE, MouseEvent.ROLL_OVER, MouseEvent.ROLL_OUT, MouseEvent.MOUSE_OVER, MouseEvent.MOUSE_OUT]) {
			mc.addEventListener(t, function(e:MouseEvent) {
				H.log("  " + name + " " + e.type + " target=" + cast(e.target, DisplayObject).name + " buttonDown=" + e.buttonDown + " trackAsMenu A=" + mcA.trackAsMenu + " B=" + mcB.trackAsMenu);
			});
		}
		return mc;
	}

	static function dragPhase() {
		mcA = box(0xFF8888, 0, "A");
		mcB = box(0x8888FF, 210, "B");
		mcB.trackAsMenu = true;
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
			downs++;
			H.log("# mouseDown " + downs + " at " + e.stageX + "," + e.stageY + " target=" + cast(e.target, DisplayObject).name);
		});
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent) {
			ups++;
			H.log("# mouseUp " + ups + " at " + e.stageX + "," + e.stageY + " target=" + cast(e.target, DisplayObject).name);
			if (ups == 1) {
				// drag 2 will be B -> A with the same flags
			} else if (ups == 2) {
				mcA.trackAsMenu = true;
				mcB.trackAsMenu = false;
				H.log("# flags swapped: A=true B=false; drag 3 is A -> B");
			} else if (ups == 3) {
				haxe.Timer.delay(H.done, 500);
			}
		});
		H.log("# waiting for drags (1: A->B with B.trackAsMenu; 2: B->A; 3: A->B with A.trackAsMenu)");
	}

	static function main() {
		H.init("d58misc", 60000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) frame++);
		step("gesture", gesture);
		step("interactive", interactive);
		step("trackAsMenuProps", trackAsMenuProps);
		step("precision", precision);
		step("touchDrag", touchDrag);
		step("shaderJobs", function() shaderJobs(function() {
			step("dragPhase", dragPhase);
		}));
	}
}
