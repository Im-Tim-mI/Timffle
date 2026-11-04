package {
import flash.accessibility.AccessibilityImplementation;
import flash.display.*;
import flash.events.Event;
import flash.events.MouseEvent;
import flash.events.ShaderEvent;
import flash.events.TransformGestureEvent;
import flash.geom.Rectangle;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.text.TextField;
import flash.text.TextFieldType;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// InteractiveObject soft-keyboard members + accessibilityImplementation, MovieClip.trackAsMenu
// (properties and the press-on-A / release-on-B click rule), Shader.precisionHint, ShaderJob
// (sync / async start, progress, cancel, complete event, error cases), Sprite.startTouchDrag /
// stopTouchDrag on a machine without a touch screen and TransformGestureEvent.GESTURE_DIRECTIONAL_TAP.
// Every expected value comes from the standalone Flash Player 32.0.0.465
// (timffle/difftest/src/D58Misc.hx with drive_drag.py, D59ShaderQueue.hx), except
// GESTURE_DIRECTIONAL_TAP (AIR-only constant, undefined in the Flash Player projector).
public class Test extends Sprite {
    private var frame:int = 0;
    private var mcA:MovieClip;
    private var mcB:MovieClip;
    private var downs:int = 0;
    private var ups:int = 0;
    private var pbj:ByteArray;

    public function Test() {
        stage.addEventListener(Event.ENTER_FRAME, function(e:Event):void { frame++; });
        step("gesture", gesture);
        step("interactive", interactive);
        step("trackAsMenuProps", trackAsMenuProps);
        step("precision", precision);
        step("touchDrag", touchDrag);
        step("dragPhase", dragPhase);
        var loader:URLLoader = new URLLoader();
        loader.dataFormat = URLLoaderDataFormat.BINARY;
        loader.addEventListener(Event.COMPLETE, function(e:Event):void {
            pbj = loader.data as ByteArray;
            trace("# pbj loaded bytes=" + pbj.length);
            step("shaderJobs", shaderJobs);
        });
        loader.load(new URLRequest("simple_shader.pbj"));
    }

    private static function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private static function r(x:Rectangle):String {
        return x == null ? "null" : "(" + x.x + "," + x.y + "," + x.width + "," + x.height + ")";
    }

    private static function hexp(bd:BitmapData):String {
        return bd.getPixel32(0, 0).toString(16).toUpperCase();
    }

    private function gesture():void {
        trace("GESTURE_DIRECTIONAL_TAP=" + TransformGestureEvent["GESTURE_DIRECTIONAL_TAP"] + " GESTURE_PAN=" + TransformGestureEvent.GESTURE_PAN);
    }

    private function interactive():void {
        var sp:Sprite = new Sprite();
        sp.graphics.beginFill(0x0000FF);
        sp.graphics.drawRect(0, 0, 10, 10);
        addChild(sp);
        var st:Stage = stage;
        trace("needsSoftKeyboard default=" + sp.needsSoftKeyboard);
        step("set needsSoftKeyboard", function():void {
            sp.needsSoftKeyboard = true;
            trace("needsSoftKeyboard after set=" + sp.needsSoftKeyboard);
        });
        step("requestSoftKeyboard unfocused", function():void {
            trace("focus before=" + st.focus + " requestSoftKeyboard()=" + sp.requestSoftKeyboard() + " focus after=" + getQualifiedClassName(st.focus) + " same=" + (st.focus == sp));
        });
        sp.needsSoftKeyboard = false;
        step("requestSoftKeyboard needs=false", function():void {
            st.focus = null;
            trace("needs=false requestSoftKeyboard()=" + sp.requestSoftKeyboard() + " focus after=" + st.focus);
        });
        var tf:TextField = new TextField();
        tf.type = TextFieldType.INPUT;
        tf.text = "x";
        addChild(tf);
        step("requestSoftKeyboard textfield", function():void {
            tf.needsSoftKeyboard = true;
            trace("tf requestSoftKeyboard()=" + tf.requestSoftKeyboard() + " focus=" + getQualifiedClassName(st.focus));
        });
        st.focus = null;
        trace("softKeyboardInputAreaOfInterest default=" + r(sp.softKeyboardInputAreaOfInterest));
        step("set area", function():void {
            var rc:Rectangle = new Rectangle(1, 2, 3, 4);
            sp.softKeyboardInputAreaOfInterest = rc;
            var back:Rectangle = sp.softKeyboardInputAreaOfInterest;
            trace("area after set=" + r(back) + " same=" + (back == rc) + " same twice=" + (sp.softKeyboardInputAreaOfInterest == back));
            rc.x = 99;
            trace("area after mutating original=" + r(sp.softKeyboardInputAreaOfInterest));
            back.width = 77;
            trace("area after mutating returned=" + r(sp.softKeyboardInputAreaOfInterest));
            sp.softKeyboardInputAreaOfInterest = null;
            trace("area after null=" + r(sp.softKeyboardInputAreaOfInterest));
        });
        trace("accessibilityImplementation default=" + sp.accessibilityImplementation);
        step("set accImpl", function():void {
            var ai:AccessibilityImplementation = new AccessibilityImplementation();
            sp.accessibilityImplementation = ai;
            trace("accImpl after set same=" + (sp.accessibilityImplementation == ai) + " stub=" + sp.accessibilityImplementation.stub);
            sp.accessibilityImplementation = null;
            trace("accImpl after null=" + sp.accessibilityImplementation);
        });
        removeChild(sp);
        removeChild(tf);
    }

    private function trackAsMenuProps():void {
        var mc:MovieClip = new MovieClip();
        trace("trackAsMenu default=" + mc.trackAsMenu);
        step("set trackAsMenu", function():void {
            mc.trackAsMenu = true;
            trace("trackAsMenu after set=" + mc.trackAsMenu + " other=" + new MovieClip().trackAsMenu);
            mc.trackAsMenu = false;
            trace("trackAsMenu after reset=" + mc.trackAsMenu);
        });
        var sb:SimpleButton = new SimpleButton();
        trace("SimpleButton trackAsMenu default=" + sb.trackAsMenu);
    }

    private function precision():void {
        var sh:Shader = new Shader();
        trace("precisionHint default=" + sh.precisionHint);
        step("set fast", function():void {
            sh.precisionHint = ShaderPrecision.FAST;
            trace("after fast=" + sh.precisionHint);
        });
        step("set bogus", function():void {
            sh.precisionHint = "bogus";
            trace("after bogus=" + sh.precisionHint);
        });
        step("set FULL upper", function():void {
            sh.precisionHint = "FULL";
            trace("after FULL=" + sh.precisionHint);
        });
        step("set null", function():void {
            sh.precisionHint = null;
            trace("after null=" + sh.precisionHint);
        });
        step("set empty", function():void {
            sh.precisionHint = "";
            trace("after empty=" + sh.precisionHint);
        });
        trace("precisionHint still=" + sh.precisionHint);
    }

    private function touchDrag():void {
        var sp:Sprite = new Sprite();
        sp.graphics.beginFill(0xFF0000);
        sp.graphics.drawRect(0, 0, 10, 10);
        addChild(sp);
        step("startTouchDrag(0)", function():void {
            sp.startTouchDrag(0);
            trace("startTouchDrag(0) ok x=" + sp.x);
        });
        step("startTouchDrag(1,true,rect)", function():void {
            sp.startTouchDrag(1, true, new Rectangle(0, 0, 10, 10));
            trace("startTouchDrag(1,true,rect) ok x=" + sp.x);
        });
        step("startTouchDrag(-1)", function():void { sp.startTouchDrag(-1); });
        step("stopTouchDrag(0)", function():void { sp.stopTouchDrag(0); });
        step("stopTouchDrag(5)", function():void { sp.stopTouchDrag(5); });
        step("stopTouchDrag(-1)", function():void { sp.stopTouchDrag(-1); });
        step("startTouchDrag then startDrag", function():void {
            sp.startTouchDrag(0);
            sp.startDrag();
            sp.stopDrag();
            sp.stopTouchDrag(0);
            trace("mixed ok");
        });
        removeChild(sp);
    }

    private function makeShader():Shader {
        var bytes:ByteArray = new ByteArray();
        bytes.writeBytes(pbj);
        var sh:Shader = new Shader(bytes);
        sh.data.radius.value = [100];
        sh.data.otherParam.value = [0];
        return sh;
    }

    private function shaderJobs():void {
        var job0:ShaderJob = new ShaderJob();
        trace("ShaderJob() shader=" + job0.shader + " target=" + job0.target + " w=" + job0.width + " h=" + job0.height + " progress=" + job0.progress);
        step("start no shader", function():void { job0.start(true); });
        step("start no shader async", function():void { job0.start(); });
        var sh:Shader = makeShader();
        var job1:ShaderJob = new ShaderJob(sh);
        step("start null target", function():void { job1.start(true); });
        job1.target = "str";
        step("start string target", function():void { job1.start(true); });
        job1.target = new Sprite();
        step("start sprite target", function():void { job1.start(true); });
        var bd:BitmapData = new BitmapData(4, 4, true, 0xFF0000FF);
        job1.target = bd;
        step("start sync bitmap", function():void {
            job1.start(true);
            trace("sync bitmap pixel=" + hexp(bd) + " progress=" + job1.progress);
        });
        step("start sync again", function():void {
            job1.start(true);
            trace("sync again progress=" + job1.progress);
        });
        var ba:ByteArray = new ByteArray();
        ba.writeByte(1);
        var job2:ShaderJob = new ShaderJob(sh, ba, 2, 3);
        step("start sync bytearray", function():void {
            job2.start(true);
            ba.position = 0;
            trace("sync bytearray length=" + ba.length + " first floats=" + ba.readFloat() + "," + ba.readFloat() + "," + ba.readFloat() + "," + ba.readFloat() + " progress=" + job2.progress);
        });
        var vec:Vector.<Number> = new Vector.<Number>();
        var job3:ShaderJob = new ShaderJob(sh, vec, 2, 2);
        step("start sync vector", function():void {
            job3.start(true);
            trace("sync vector length=" + vec.length + " v0..3=" + vec[0] + "," + vec[1] + "," + vec[2] + "," + vec[3] + " progress=" + job3.progress);
        });
        var job4:ShaderJob = new ShaderJob(sh, ba, 0, 0);
        step("start sync bytearray 0x0", function():void { job4.start(true); });
        var job5:ShaderJob = new ShaderJob(sh, vec, 3, 0);
        step("start sync vector 3x0", function():void { job5.start(true); });
        var fixedVec:Vector.<Number> = new Vector.<Number>(2, true);
        var jobFx:ShaderJob = new ShaderJob(sh, fixedVec, 1, 1);
        step("sync fixed vector", function():void { jobFx.start(true); });

        // asynchronous
        var bd2:BitmapData = new BitmapData(4, 4, true, 0xFF0000FF);
        var jobA:ShaderJob = new ShaderJob(sh, bd2);
        var startFrame:int = frame;
        var doneA:Boolean = false;
        jobA.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent):void {
            doneA = true;
            trace("jobA complete frame+" + (frame - startFrame) + " bubbles=" + e.bubbles + " cancelable=" + e.cancelable + " target same=" + (e.target == jobA) + " bitmapData same=" + (e.bitmapData == bd2) + " byteArray=" + e.byteArray + " vector=" + e.vector + " pixel=" + hexp(bd2) + " progress=" + jobA.progress + " type=" + e.type);
        });
        step("start async bitmap", function():void {
            jobA.start();
            trace("async right after start pixel=" + hexp(bd2) + " progress=" + jobA.progress);
        });
        step("start async twice", function():void { jobA.start(); });
        step("start sync while async pending", function():void { jobA.start(true); });
        var bd3:BitmapData = new BitmapData(4, 4, true, 0xFF0000FF);
        var jobC:ShaderJob = new ShaderJob(sh, bd3);
        jobC.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent):void {
            trace("jobC complete (must not happen) pixel=" + hexp(bd3));
        });
        step("start async then cancel", function():void {
            jobC.start();
            jobC.cancel();
            jobC.cancel();
            trace("after cancel progress=" + jobC.progress + " pixel=" + hexp(bd3));
        });
        step("restart after cancel", function():void { jobC.start(true); });
        step("cancel finished then start", function():void {
            job1.cancel();
            trace("progress after cancel of finished=" + job1.progress);
            job1.start(true);
        });
        // changes to the shader after start() do not reach the queued job
        var bd4:BitmapData = new BitmapData(4, 4, true, 0xFF0000FF);
        var sh2:Shader = makeShader();
        var jobG:ShaderJob = new ShaderJob(sh2, bd4);
        jobG.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent):void {
            trace("jobG complete frame+" + (frame - startFrame) + " pixel=" + hexp(bd4) + " (radius changed after start)");
        });
        step("start async then change parameter", function():void {
            jobG.start();
            sh2.data.radius.value = [200];
            trace("G started; radius now 200");
        });
        trace("# async jobs started; doneA=" + doneA + " progressA=" + jobA.progress);
        addEventListener(Event.ENTER_FRAME, function(e:Event):void {
            if (frame == startFrame + 1) {
                trace("# next frame: doneA=" + doneA + " progressA=" + jobA.progress + " G progress=" + jobG.progress);
            }
        });
    }

    private function box(color:uint, x:Number, name:String):MovieClip {
        var mc:MovieClip = new MovieClip();
        mc.graphics.beginFill(color);
        mc.graphics.drawRect(0, 0, 190, 300);
        mc.x = x;
        mc.name = name;
        mc.buttonMode = true;
        addChild(mc);
        var types:Array = [MouseEvent.MOUSE_DOWN, MouseEvent.MOUSE_UP, MouseEvent.CLICK, MouseEvent.RELEASE_OUTSIDE];
        for each (var t:String in types) {
            mc.addEventListener(t, function(e:MouseEvent):void {
                trace("  " + mc.name + " " + e.type + " target=" + DisplayObject(e.target).name + " buttonDown=" + e.buttonDown + " trackAsMenu A=" + mcA.trackAsMenu + " B=" + mcB.trackAsMenu);
            });
        }
        return mc;
    }

    private function dragPhase():void {
        mcA = box(0xFF8888, 0, "A");
        mcB = box(0x8888FF, 210, "B");
        mcB.trackAsMenu = true;
        stage.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent):void {
            downs++;
            trace("# mouseDown " + downs + " at " + e.stageX + "," + e.stageY + " target=" + DisplayObject(e.target).name);
        });
        stage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent):void {
            ups++;
            trace("# mouseUp " + ups + " at " + e.stageX + "," + e.stageY + " target=" + DisplayObject(e.target).name);
            if (ups == 2) {
                mcA.trackAsMenu = true;
                mcB.trackAsMenu = false;
                trace("# flags swapped: A=true B=false; drag 3 is A -> B");
            }
        });
        trace("# waiting for drags (1: A->B with B.trackAsMenu; 2: B->A; 3: A->B with A.trackAsMenu)");
    }
}
}
