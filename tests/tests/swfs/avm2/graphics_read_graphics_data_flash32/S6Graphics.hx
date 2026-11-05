/** Golden for Graphics.readGraphicsData: runs only the readGraphicsData parts of D55Graphics (r*) and
 *  D56Graphics2 (s*, c1, g*) — the structures Flash Player 32 reports — without the pixel probes.
 *  Builds with -D harness (Flash) or without (Ruffle test). Build with -swf-version 32. */
@:access(D55Graphics)
@:access(D56Graphics2)
class S6Graphics {
	static function main() {
		Out.start("s6graphics");
		var q = untyped __global__["flash.utils.getQualifiedClassName"];
		D55Graphics.qn = q;
		D56Graphics2.qn = q;
		D55Graphics.step("readData", D55Graphics.readData);
		D56Graphics2.step("readData", D56Graphics2.readData);
		Out.finish();
	}
}
