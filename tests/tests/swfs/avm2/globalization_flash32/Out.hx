/** Output for tests that double as ruffle regression tests.
 * With -D harness: lines go through H (reported to the difftest server).
 * Without: plain trace(), for ruffle's tests/swfs/.../output.txt format. */
class Out {
	public static function start(name:String) {
		#if harness
		H.init(name, 15000);
		#end
	}

	public static function line(s:String) {
		#if harness
		H.log(s);
		#else
		flash.Lib.trace(s);
		#end
	}

	public static function finish() {
		#if harness
		H.done();
		#end
	}
}
