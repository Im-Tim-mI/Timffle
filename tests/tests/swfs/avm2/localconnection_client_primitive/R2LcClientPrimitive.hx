import flash.net.LocalConnection;

/** LocalConnection.client rejects non-objects with TypeError #2004.
 * Ruffle used to panic ("Expected Object or null as parameter"). */
class R2LcClientPrimitive {
	static function main() {
		Out.start("r2lc_client_primitive");
		var lc = new LocalConnection();
		var original:Dynamic = {};
		lc.client = original;
		var values:Array<Dynamic> = [5, -1, 1.5, "str", "", true, false, null];
		untyped values.push(__global__["undefined"]);
		for (v in values) {
			try {
				lc.client = v;
				Out.line("client = " + v + ": accepted");
			} catch (e:flash.errors.Error) {
				// errorID only: release players omit the message text, debug players include it
				Out.line("client = " + v + ": threw " + U.cls(e) + " #" + e.errorID);
			}
		}
		Out.line("client is still the original: " + (lc.client == original));
		var other:Dynamic = {};
		lc.client = other;
		Out.line("an object is accepted: " + (lc.client == other));
		Out.line("done");
		Out.finish();
	}
}
