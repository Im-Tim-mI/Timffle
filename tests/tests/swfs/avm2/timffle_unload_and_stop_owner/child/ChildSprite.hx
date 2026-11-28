package;
import flash.display.Sprite;
import flash.events.Event;
/** Child-defined class; constructed by parent code in one case and by child code in another. */
class ChildSprite extends Sprite {
	public function new() {
		super();
		var key = ChildApi.tag + "_selflistener"; // who constructed this instance
		addEventListener(Event.ENTER_FRAME, function(_) ChildApi.bump(key));
	}
}
