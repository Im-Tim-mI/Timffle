package {
import flash.automation.ActionGenerator;
import flash.automation.AutomationAction;
import flash.automation.Configuration;
import flash.automation.StageCapture;
import flash.automation.StageCaptureEvent;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.GeolocationEvent;
import flash.printing.PrintJob;
import flash.printing.PrintJobOrientation;
import flash.sampler.*;
import flash.sensors.Accelerometer;
import flash.sensors.Geolocation;
import flash.ui.GameInput;
import flash.ui.GameInputControl;
import flash.ui.GameInputDevice;
import flash.utils.getQualifiedClassName;

// Flash-without-the-feature classes: game input devices, automation, printing, the sampler
// and the sensors, plus the GeolocationEvent data class. Expected values follow the Adobe
// reference and the AVM's behaviour in the release player (see the doc comment on each class).
public class Test extends Sprite {
    public var slot:int = 5;
    private var _acc:int = 7;
    public function get acc():int { return this._acc; }
    public function set acc(v:int):void { this._acc = v; }
    public function method():void {}

    public function Test() {
        trace("// GameInput");
        trace("isSupported", GameInput.isSupported, "numDevices", GameInput.numDevices);
        attempt("new GameInputDevice()", function():void { new GameInputDevice(); });
        attempt("new GameInputControl()", function():void { new GameInputControl(); });
        trace("MAX_BUFFER_SIZE", GameInputDevice.MAX_BUFFER_SIZE);

        trace("// automation");
        var gen:ActionGenerator = new ActionGenerator();
        gen.generateAction(new AutomationAction());
        gen.generateActions(new Vector.<AutomationAction>());
        trace("generate ok");
        attempt("generateAction(null)", function():void { gen.generateAction(null); });
        attempt("generateActions(null)", function():void { gen.generateActions(null); });
        trace("deviceConfiguration", "[" + Configuration.deviceConfiguration + "]");
        Configuration.deviceConfiguration = "tablet";
        trace("deviceConfiguration set", Configuration.deviceConfiguration);
        trace("testAutomationConfiguration", "[" + Configuration.testAutomationConfiguration + "]");
        var cap:StageCapture = new StageCapture();
        cap.addEventListener(StageCaptureEvent.CAPTURE, function(e:Event):void { trace("capture event!"); });
        trace("capture defaults", cap.capturePTS, cap.captureSource, cap.clipRect, cap.fileNameBase);
        cap.captureSource = StageCapture.SCREEN;
        cap.fileNameBase = "shot";
        trace("capture set", cap.captureSource, cap.fileNameBase);
        attempt("captureSource bogus", function():void { cap.captureSource = "bogus"; });
        cap.capture(StageCapture.CURRENT);
        cap.capture(StageCapture.NEXT);
        attempt("capture bogus", function():void { cap.capture("bogus"); });
        cap.cancel();
        trace("captureBitmapData", cap.captureBitmapData());

        trace("// PrintJob");
        trace("isSupported", PrintJob.isSupported);
        var job:PrintJob = new PrintJob();
        trace("orientation", job.orientation);
        // Read-only in Flash Player 32 (ReferenceError #1074, measured).
        attempt("orientation set", function():void { Object(job).orientation = PrintJobOrientation.LANDSCAPE; });
        trace("sizes", job.pageWidth, job.pageHeight, job.paperWidth, job.paperHeight);
        trace("start", job.start());
        attempt("addPage", function():void { job.addPage(new Sprite()); });
        job.send();
        trace("send returned");

        trace("// sampler");
        startSampling();
        pauseSampling();
        sampleInternalAllocs(true);
        setSamplerCallback(function():void {});
        trace("getSampleCount", getSampleCount());
        trace("getSamples", getSamples());
        var n:int = 0;
        for each (var s:* in getSamples()) { n++; }
        trace("samples iterated", n);
        stopSampling();
        clearSamples();
        trace("getSize", getSize(this), getSize("x"));
        trace("getInvocationCount", getInvocationCount(this, new QName("method")));
        trace("getGetterInvocationCount", getGetterInvocationCount(this, new QName("acc")));
        trace("getSetterInvocationCount", getSetterInvocationCount(this, new QName("acc")));
        trace("getMasterString", getMasterString("hello"), getMasterString("hello world".substr(0, 5)));
        trace("isGetterSetter acc", isGetterSetter(this, new QName("acc")));
        trace("isGetterSetter slot", isGetterSetter(this, new QName("slot")));
        trace("isGetterSetter method", isGetterSetter(this, new QName("method")));
        trace("isGetterSetter missing", isGetterSetter(this, new QName("nothing")));
        trace("isGetterSetter null", isGetterSetter(null, new QName("acc")));
        var members:Object = getMemberNames(new Simple());
        var names:Array = [];
        for each (var q:QName in members) {
            names.push(q.localName);
        }
        names.sort();
        trace("getMemberNames", names.join(","));
        var dyn:Object = {zeta: 1, alpha: 2};
        names = [];
        for each (var dq:QName in getMemberNames(dyn)) {
            names.push(dq.localName);
        }
        names.sort();
        trace("getMemberNames dynamic", names.join(","));
        names = [];
        for each (var cq:QName in getMemberNames(Simple, true)) {
            names.push(cq.localName);
        }
        names.sort();
        trace("getMemberNames class instanceNames", names.join(","));
        names = [];
        for each (var sq:QName in getMemberNames(Simple)) {
            names.push(sq.localName);
        }
        names.sort();
        trace("getMemberNames class", names.join(","));
        trace("getMemberNames null", getMemberNames(null));
        var simple:Simple = new Simple();
        var bound:Function = simple.hello;
        trace("getSavedThis bound", getSavedThis(bound) === simple);
        trace("getSavedThis plain", getSavedThis(function():void {}));
        trace("getSavedThis null", getSavedThis(null));
        var scopes:Array = getLexicalScopes(function():void {});
        // The release Flash Player 32 returns null here (measured).
        trace("getLexicalScopes", scopes);
        trace("getLexicalScopes null", getLexicalScopes(null));

        trace("// sensors");
        trace("Accelerometer", Accelerometer.isSupported, new Accelerometer().muted);
        var accel:Accelerometer = new Accelerometer();
        accel.setRequestedUpdateInterval(0);
        accel.setRequestedUpdateInterval(100);
        attempt("accel interval -1", function():void { accel.setRequestedUpdateInterval(-1); });
        trace("Geolocation", Geolocation.isSupported, new Geolocation().muted);
        var geo:Geolocation = new Geolocation();
        geo.setRequestedUpdateInterval(0);
        geo.setRequestedUpdateInterval(100);
        attempt("geo interval -1", function():void { geo.setRequestedUpdateInterval(-1); });

        trace("// GeolocationEvent");
        trace("UPDATE", GeolocationEvent.UPDATE);
        var ev:GeolocationEvent = new GeolocationEvent(GeolocationEvent.UPDATE);
        trace("defaults", ev.latitude, ev.longitude, ev.altitude, ev.horizontalAccuracy, ev.verticalAccuracy, ev.speed, ev.heading, ev.timestamp);
        ev = new GeolocationEvent(GeolocationEvent.UPDATE, true, false, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5, 8.5);
        trace("values", ev.latitude, ev.longitude, ev.altitude, ev.horizontalAccuracy, ev.verticalAccuracy, ev.speed, ev.heading, ev.timestamp);
        ev.latitude = 9;
        ev.heading = 10;
        trace("setters", ev.latitude, ev.heading);
        var evc:GeolocationEvent = ev.clone() as GeolocationEvent;
        trace("clone", evc !== ev, evc.type, evc.bubbles, evc.latitude, evc.longitude, evc.altitude, evc.horizontalAccuracy, evc.verticalAccuracy, evc.speed, evc.heading, evc.timestamp);
        trace(ev.toString());
    }

    private static function attempt(label:String, fn:Function):void {
        try {
            fn();
            trace(label, "no error");
        } catch (e:Error) {
            trace(label, "THREW", getQualifiedClassName(e), e.errorID);
        }
    }
}
}

class Simple {
    public var field:int = 1;
    private var secret:int = 2;
    public static var staticField:int = 3;
    public function hello():void {}
    public function get prop():int { return 0; }
}
