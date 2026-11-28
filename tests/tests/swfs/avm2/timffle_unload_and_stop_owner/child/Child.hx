package;
import flash.display.Sprite;
import flash.events.Event;
/** Document class of the child swf: its root sits on the display list under the parent's Loader. */
class Child extends Sprite {
	public function new() {
		super();
		addEventListener(Event.ENTER_FRAME, function(_) ChildApi.bump("childroot_enterframe"));
	}
	static function main() {
		flash.Lib.current.addChild(new Child());
		ChildSprite; // keep the class
	}
}
