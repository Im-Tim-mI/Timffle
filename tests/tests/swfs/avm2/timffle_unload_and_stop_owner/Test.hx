package;
import flash.display.Loader;
import flash.display.Sprite;
import flash.events.Event;
import flash.system.ApplicationDomain;
import flash.system.LoaderContext;
import flash.utils.ByteArray;

/** Which listeners and timers Loader.unloadAndStop() stops, by who constructed the object, who
 * registered the listener and whose code the handler is. The child is loaded with loadBytes into the
 * parent's ApplicationDomain (how games install code modules and then unloadAndStop the loader).
 * output.txt is the real Flash Player 32 debugger's output. */
class Test extends Sprite {
	var loader:Loader;
	var frames = 0;
	var api:Dynamic;
	var obj:Sprite;
	var keep:Array<Dynamic> = [];

	static function main() flash.Lib.current.addChild(new Test());

	public function new() {
		super();
		addEventListener(Event.ADDED_TO_STAGE, init);
	}

	function init(_) {
		loader = new Loader();
		loader.contentLoaderInfo.addEventListener(Event.INIT, onInit);
		var bytes:ByteArray = haxe.Resource.getBytes("child").getData();
		loader.loadBytes(bytes, new LoaderContext(false, ApplicationDomain.currentDomain));
		addChild(loader);
	}

	function onInit(_) {
		api = ApplicationDomain.currentDomain.getDefinition("ChildApi");
		var bump = api.bump;
		var parentFn = function(k:String):Dynamic return function(_) bump(k);
		obj = new Sprite();
		addChild(obj);
		api.setup(stage, obj, parentFn, ParentSprite);
		obj.addEventListener(Event.ENTER_FRAME, function(_) bump("sprite_parentnew_parenthandler"));
		var childSpriteCls:Class<Dynamic> = cast ApplicationDomain.currentDomain.getDefinition("ChildSprite");
		api.tag = "childclass_parentnew";
		var cs:Sprite = untyped __new__(childSpriteCls);
		cs.addEventListener(Event.ENTER_FRAME, function(_) bump("childclass_parentnew_parenthandler"));
		cs.addEventListener(Event.ENTER_FRAME, api.childFn("childclass_parentnew_childhandler"));
		keep.push(cs);
		var sh:flash.display.Shape = api.makeShape();
		sh.addEventListener(Event.ENTER_FRAME, function(_) bump("shape_childnew_parentadded_parenthandler"));
		keep.push(sh);
		var sp:Sprite = api.makeSprite();
		sp.addEventListener(Event.ENTER_FRAME, function(_) bump("sprite_childnew_parentadded_parenthandler"));
		keep.push(sp);
		stage.addEventListener(Event.ENTER_FRAME, api.childFn("stage_parentadded_childhandler"));
		stage.addEventListener(Event.ENTER_FRAME, function(_) bump("stage_parentadded_parenthandler"));
		var t = new flash.utils.Timer(100);
		t.addEventListener(flash.events.TimerEvent.TIMER, api.childFn("timer_parentnew_childhandler"));
		t.start();
		keep.push(t);
		untyped __global__["flash.utils.setTimeout"](api.childCb("timeout_parentcall_childcb"), 1500);
		addEventListener(Event.ENTER_FRAME, tick);
	}

	function tick(_) {
		frames++;
		if (frames == 30) {
			flash.Lib.trace("before unloadAndStop: " + api.report());
			api.reset();
			loader.unloadAndStop(true);
			api.afterUnload(obj);
			flash.Lib.trace("unloaded: content=" + loader.content + " numChildren=" + loader.numChildren);
		}
		if (frames == 90) {
			flash.Lib.trace("after unloadAndStop: " + api.report());
			flash.Lib.trace("done");
		}
	}
}
