import flash.display.Sprite;
import flash.display.BitmapData;

/** The SWF that is loaded again and again. Its library is deliberately heavy in decoded form:
 * a 1024x1024 bitmap (4 MiB once decoded, small in the SWF) and a document class. Nothing
 * instantiates the bitmap, so only the library registration (not BitmapData pixels) is what the
 * collector gets to hear about. */
@:bitmap("big.png")
class Big extends BitmapData {}

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

	public static function main() {}
}
