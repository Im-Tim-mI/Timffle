package;
import flash.display.Shape;
import flash.display.Stage;
import flash.events.Event;
import flash.events.TimerEvent;
import flash.utils.Timer;

/** Code compiled into the child swf; the parent reaches it through the shared ApplicationDomain. */
class ChildApi {
	public static var counts:Map<String, Int> = new Map();
	static var keep:Array<Dynamic> = [];
	public static var tag:String = "";

	public static function bump(k:String):Void counts.set(k, (counts.exists(k) ? counts.get(k) : 0) + 1);
	public static function childFn(k:String):Dynamic return function(_) bump(k);
	public static function childCb(k:String):Dynamic return function() bump(k);
	public static function makeShape():Shape { var s = new Shape(); keep.push(s); return s; }
	public static function makeSprite():flash.display.Sprite { var s = new flash.display.Sprite(); keep.push(s); return s; }

	// parentObj: a Sprite the PARENT's code constructed; parentFn(k): a handler that is parent code;
	// parentCls: a Sprite subclass defined in the parent swf.
	public static function setup(st:Stage, parentObj:flash.display.Sprite, parentFn:Dynamic, parentCls:Class<Dynamic>):Void {
		var a1 = new Shape(); a1.addEventListener(Event.ENTER_FRAME, childFn("shape_childnew_childhandler")); keep.push(a1);
		var a2 = new Shape(); a2.addEventListener(Event.ENTER_FRAME, parentFn("shape_childnew_parenthandler")); keep.push(a2);
		var a3 = new flash.display.Bitmap(); a3.addEventListener(Event.ENTER_FRAME, childFn("bitmap_childnew_childhandler")); keep.push(a3);
		var b1 = new flash.display.Sprite(); b1.addEventListener(Event.ENTER_FRAME, childFn("sprite_childnew_childhandler")); keep.push(b1);
		var b2 = new flash.display.Sprite(); b2.addEventListener(Event.ENTER_FRAME, parentFn("sprite_childnew_parenthandler")); keep.push(b2);
		var b3 = new flash.display.Sprite(); st.addChild(b3); b3.addEventListener(Event.ENTER_FRAME, childFn("sprite_childnew_onstage")); keep.push(b3);
		var b4 = new flash.display.Sprite(); b4.addEventListener(Event.EXIT_FRAME, childFn("sprite_childnew_exitframe")); b4.addEventListener(Event.FRAME_CONSTRUCTED, childFn("sprite_childnew_frameconstructed")); keep.push(b4);
		var b5 = new flash.display.MovieClip(); b5.addEventListener(Event.ENTER_FRAME, childFn("movieclip_childnew_childhandler")); keep.push(b5);
		var b6 = new flash.text.TextField(); b6.addEventListener(Event.ENTER_FRAME, childFn("textfield_childnew_childhandler")); keep.push(b6);
		var b7 = new flash.display.SimpleButton(); b7.addEventListener(Event.ENTER_FRAME, childFn("button_childnew_childhandler")); keep.push(b7);
		var b8 = new flash.display.Loader(); b8.addEventListener(Event.ENTER_FRAME, childFn("loader_childnew_childhandler")); keep.push(b8);
		tag = "childclass_childnew"; var c1 = new ChildSprite(); c1.addEventListener(Event.ENTER_FRAME, parentFn("childclass_childnew_parenthandler")); keep.push(c1);
		var c2:flash.display.Sprite = untyped __new__(parentCls); c2.addEventListener(Event.ENTER_FRAME, childFn("parentclass_childnew_childhandler")); keep.push(c2);
		parentObj.addEventListener(Event.ENTER_FRAME, childFn("sprite_parentnew_childhandler"));
		st.addEventListener(Event.ENTER_FRAME, childFn("stage_childadded_childhandler"));
		st.addEventListener(Event.ENTER_FRAME, parentFn("stage_childadded_parenthandler"));
		var t1 = new Timer(100); t1.addEventListener(TimerEvent.TIMER, childFn("timer_childnew_childhandler")); t1.start(); keep.push(t1);
		var t2 = new Timer(100); t2.addEventListener(TimerEvent.TIMER, parentFn("timer_childnew_parenthandler")); t2.start(); keep.push(t2);
		untyped __global__["flash.utils.setTimeout"](childCb("timeout_childcall_childcb"), 1500);
		untyped __global__["flash.utils.setTimeout"](parentFn("timeout_childcall_parentcb"), 1500);
	}

	// called by the parent right after unloadAndStop: new registrations by the child's code still work
	public static function afterUnload(parentObj:flash.display.Sprite):Void {
		untyped __global__["flash.utils.setTimeout"](childCb("after_timeout_childcall"), 300);
		var t = new Timer(100); t.addEventListener(TimerEvent.TIMER, childFn("after_timer_childnew")); t.start(); keep.push(t);
		var s = new flash.display.Sprite(); s.addEventListener(Event.ENTER_FRAME, childFn("after_sprite_childnew")); keep.push(s);
		parentObj.addEventListener(Event.ENTER_FRAME, childFn("after_sprite_parentnew_childhandler"));
	}

	public static function reset():Void counts = new Map();

	/** The keys that fired at least once, sorted; counts are timing-dependent and left out. */
	public static function report():String {
		var keys = [for (k in counts.keys()) if (counts.get(k) > 0) k];
		keys.sort(Reflect.compare);
		return keys.join(" ");
	}
}
