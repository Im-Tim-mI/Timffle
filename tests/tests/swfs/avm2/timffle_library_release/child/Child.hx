import flash.display.Sprite;
import flash.display.BitmapData;

/** The SWF that the test loads again and again. It has a document class (a SymbolClass binding),
 * a static counter (fresh per load in Flash: every load gets its own classes and statics) and an
 * embedded bitmap bound to a class through SymbolClass, so instantiating it goes through the library. */
@:bitmap("pix.png")
class Pix extends BitmapData {}

@:keep
class Child extends Sprite {
	public static var count:Int = 0;

	public function new() {
		super();
		graphics.beginFill(0x00FF00);
		graphics.drawRect(0, 0, 20, 20);
		graphics.endFill();
	}

	public static function bump():Int {
		return ++count;
	}

	public static function pix():BitmapData {
		return new Pix(0, 0);
	}

	public static function main() {}
}
