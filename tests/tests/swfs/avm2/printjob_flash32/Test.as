package {
	import flash.display.MovieClip;
	import flash.display.Sprite;
	import flash.geom.Rectangle;
	import flash.media.AudioDeviceManager;
	import flash.media.Camera;
	import flash.media.Microphone;
	import flash.printing.PrintJob;
	import flash.printing.PrintJobOptions;
	import flash.system.Capabilities;
	import flash.utils.setTimeout;

	// Recorded with Flash Player 32 (Wine) on a machine without a camera or a printer:
	// the isSupported answers that do not depend on devices, the PrintJob members before
	// start(), the one-job-at-a-time rule (#2141), and start() when the print dialog is
	// cancelled (in Flash Player the dialog was dismissed by hand; this player has no
	// dialog and answers the same way).
	public class Test extends MovieClip {
		private static function show(label:String, f:Function):void {
			try {
				var v:* = f();
				trace(label + " = " + v + " (" + typeof v + ")");
			} catch (e:Error) {
				trace(label + " threw " + Object(e).constructor + " #" + e.errorID);
			}
		}

		public function Test() {
			show("Camera.isSupported", function():* { return Camera.isSupported; });
			show("Microphone.isSupported", function():* { return Microphone.isSupported; });
			show("AudioDeviceManager.isSupported", function():* { return AudioDeviceManager.isSupported; });
			show("PrintJob.isSupported", function():* { return PrintJob.isSupported; });
			show("Capabilities.hasPrinting", function():* { return Capabilities.hasPrinting; });
			show("Camera.names.length", function():* { return Camera.names.length; });
			show("Camera.getCamera()", function():* { return Camera.getCamera(); });

			var a:PrintJob;
			var b:PrintJob;
			show("first new PrintJob()", function():* { a = new PrintJob(); return a; });
			show("orientation", function():* { return a.orientation; });
			show("paperHeight", function():* { return a.paperHeight; });
			show("paperWidth", function():* { return a.paperWidth; });
			show("pageHeight", function():* { return a.pageHeight; });
			show("pageWidth", function():* { return a.pageWidth; });
			show("second new PrintJob() while the first is in use", function():* { b = new PrintJob(); return b; });
			show("addPage(sprite)", function():* { a.addPage(new Sprite()); return "returned"; });
			show("addPage(sprite, rect, options, 1)", function():* {
				a.addPage(new Sprite(), new Rectangle(0, 0, 10, 10), new PrintJobOptions(), 1);
				return "returned";
			});
			show("addPage(null)", function():* { a.addPage(null); return "returned"; });
			show("send()", function():* { a.send(); return "returned"; });
			show("paperHeight after send", function():* { return a.paperHeight; });
			show("orientation after send", function():* { return a.orientation; });
			show("new PrintJob() after send", function():* { b = new PrintJob(); return b; });
			show("send() of that job", function():* { b.send(); return "returned"; });

			setTimeout(function():void {
				var pj:PrintJob = new PrintJob();
				show("start() (dialog cancelled)", function():* { return pj.start(); });
				show("paperHeight", function():* { return pj.paperHeight; });
				show("paperWidth", function():* { return pj.paperWidth; });
				show("pageHeight", function():* { return pj.pageHeight; });
				show("pageWidth", function():* { return pj.pageWidth; });
				show("orientation", function():* { return pj.orientation; });
				show("addPage(sprite)", function():* { pj.addPage(new Sprite()); return "returned"; });
				var c:PrintJob;
				show("new PrintJob() after the failed start", function():* { c = new PrintJob(); return c; });
				show("start() again", function():* { return pj.start(); });
				show("send()", function():* { pj.send(); return "returned"; });
				show("new PrintJob() while that one is in use", function():* { return new PrintJob(); });
				show("its send()", function():* { c.send(); return "returned"; });
				show("new PrintJob() after it was sent", function():* { return new PrintJob(); });
				trace("done");
			}, 200);
		}
	}
}
