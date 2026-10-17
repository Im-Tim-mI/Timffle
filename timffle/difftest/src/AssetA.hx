/** Tiny SWF loaded by the loader/URLLoader cancel tests. Its root holds one child named "AssetA", so a test can
 *  tell which asset a Loader really holds (setting Lib.current.name from a loaded root throws in Flash and
 *  would suppress init/complete, and the root's class name is a generated boot_NNNN). */
class AssetA {
	static function main() {
		var s = new flash.display.Sprite();
		s.name = "AssetA";
		flash.Lib.current.addChild(s);
	}
}
