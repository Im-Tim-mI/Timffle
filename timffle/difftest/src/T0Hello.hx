/** Harness smoke test: proves load -> log -> report -> quit works in a player. */
class T0Hello {
	static function main() {
		H.init("t0hello");
		H.log("stage=" + (flash.Lib.current.stage != null));
		H.log("playerType=" + flash.system.Capabilities.playerType);
		H.log("~ version=" + flash.system.Capabilities.version);
		H.done();
	}
}
