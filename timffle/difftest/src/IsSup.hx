/** Probe: isSupported / device-list properties on a machine without the matching hardware.
 *  Camera, Microphone, AudioDeviceManager, PrintJob, Capabilities.has*, Worker, WorkerDomain, Mutex.
 *  Build with -D harness (Flash) or without (trace). PrintJob.start() is in IsSupPrint (it can block on a dialog). */
import flash.media.*;
import flash.system.Capabilities;

class IsSup {
	static function qn(o:Dynamic):String {
		return o == null ? "null" : untyped __global__["flash.utils.getQualifiedClassName"](o);
	}

	static function cls(n:String):Dynamic {
		return untyped __global__["flash.utils.getDefinitionByName"](n);
	}

	static function prop(label:String, c:String, p:String) {
		try {
			var v:Dynamic = Reflect.field(cls(c), p);
			var s = v == null ? "null" : Std.string(v);
			if (Std.isOfType(v, Array))
				s = "[" + (v : Array<Dynamic>).join(",") + "] length=" + (v : Array<Dynamic>).length;
			Out.line(label + " = " + s);
		} catch (e:flash.errors.Error) {
			Out.line(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function step(label:String, f:Void->String) {
		try {
			Out.line(label + " = " + f());
		} catch (e:flash.errors.Error) {
			Out.line(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function main() {
		Out.start("issup");
		Out.line("begin");
		prop("Camera.isSupported", "flash.media.Camera", "isSupported");
		prop("Microphone.isSupported", "flash.media.Microphone", "isSupported");
		prop("AudioDeviceManager.isSupported", "flash.media.AudioDeviceManager", "isSupported");
		prop("PrintJob.isSupported", "flash.printing.PrintJob", "isSupported");
		prop("Capabilities.hasPrinting", "flash.system.Capabilities", "hasPrinting");
		prop("Worker.isSupported", "flash.system.Worker", "isSupported");
		prop("WorkerDomain.isSupported", "flash.system.WorkerDomain", "isSupported");
		prop("Mutex.isSupported", "flash.concurrent.Mutex", "isSupported");
		prop("Condition.isSupported", "flash.concurrent.Condition", "isSupported");
		prop("Camera.names", "flash.media.Camera", "names");
		prop("Microphone.names", "flash.media.Microphone", "names");
				for (p in ["hasAudio", "hasMP3", "hasVideoEncoder", "hasAudioEncoder", "hasStreamingAudio", "hasStreamingVideo", "avHardwareDisable",
			"localFileReadDisable", "hasEmbeddedVideo", "hasAccessibility", "hasIME", "hasTLS", "hasScreenBroadcast", "hasScreenPlayback"])
			prop("Capabilities." + p, "flash.system.Capabilities", p);
		step("Camera.getCamera()", function() return qn(cls("flash.media.Camera").getCamera()));
		step("Camera.getCamera(\"0\")", function() return qn(cls("flash.media.Camera").getCamera("0")));
		step("Microphone.getMicrophone()", function() return qn(cls("flash.media.Microphone").getMicrophone()));
		step("Microphone.getEnhancedMicrophone()", function() return qn(cls("flash.media.Microphone").getEnhancedMicrophone()));
		step("new AudioDeviceManager()", function() {
			Type.createInstance(cls("flash.media.AudioDeviceManager"), []);
			return "created";
		});
		step("AudioDeviceManager.audioDeviceManager", function() {
			var m:Dynamic = Reflect.field(cls("flash.media.AudioDeviceManager"), "audioDeviceManager");
			if (m == null)
				return "null";
			var n:Array<Dynamic> = m.deviceNames;
			return qn(m) + " deviceNames=[" + n.join(",") + "] length=" + n.length + " selectedDeviceIndex=" + m.selectedDeviceIndex;
		});
		step("new PrintJob()", function() return qn(Type.createInstance(cls("flash.printing.PrintJob"), [])));
		step("PrintJob fields before start", function() {
			var pj = Type.createInstance(cls("flash.printing.PrintJob"), []);
			return "paperHeight=" + pj.paperHeight + " paperWidth=" + pj.paperWidth + " orientation=" + pj.orientation + " pageHeight=" + pj.pageHeight;
		});
		step("Worker.current", function() {
			var w:Dynamic = Reflect.field(cls("flash.system.Worker"), "current");
			return qn(w) + " isPrimordial=" + w.isPrimordial + " state=" + w.state;
		});
		step("WorkerDomain.current", function() return qn(Reflect.field(cls("flash.system.WorkerDomain"), "current")));
		step("new Mutex().tryLock()", function() return Std.string(Type.createInstance(cls("flash.concurrent.Mutex"), []).tryLock()));
		Out.line("ver=" + Capabilities.version.split(" ")[1]);
		Out.finish();
	}
}
