/** Probe: new PrintJob().start() on a machine without a printer. start() may block on a native dialog;
 *  the driver screenshots the display while it is blocked. The line before the call is posted early
 *  via a separate URLLoader so the harness records that the call began. */
import flash.printing.PrintJob;

class IsSupPrint {
	static function main() {
		Out.start("issupprint");
		Out.line("PrintJob.isSupported = " + PrintJob.isSupported);
		var t0 = flash.Lib.getTimer();
		Out.line("calling start()");
		var r = "?";
		try {
			var pj = new PrintJob();
			r = Std.string(pj.start());
			Out.line("start() returned " + r);
			Out.line("~ ms=" + (flash.Lib.getTimer() - t0));
			Out.line("paperWidth=" + pj.paperWidth + " paperHeight=" + pj.paperHeight + " orientation=" + pj.orientation);
		} catch (e:flash.errors.Error) {
			Out.line("start() THREW " + e.name + " #" + e.errorID + " " + e.message);
			Out.line("~ ms=" + (flash.Lib.getTimer() - t0));
		}
		Out.finish();
	}
}
