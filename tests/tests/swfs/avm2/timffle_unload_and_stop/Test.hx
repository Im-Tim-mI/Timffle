import flash.Lib;
import flash.display.Loader;
import flash.display.MovieClip;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.TimerEvent;
import flash.net.URLRequest;
import flash.utils.Timer;

/** Loads child/loaded.swf, lets it run a few frames, calls Loader.unloadAndStop() and checks
 * (Adobe, Loader.unloadAndStop): sounds stopped, stage listeners removed, enterFrame listeners
 * removed, timers stopped — for the child only: the parent's own timer and enterFrame listener keep
 * running. (The clip stop is not observable here: a script-made MovieClip has one frame.) */
class Test {
	static var root:Sprite;
	static var loader:Loader;
	static var child:Dynamic;
	static var clip:MovieClip;
	static var timer:Timer;
	static var frame = 0;
	static var parentTimerTicks = 0;
	static var parentFrames = 0;
	static var snapshot:Array<Int>;

	static function counts():Array<Int> {
		return [child.timerTicks, child.intervalTicks, child.stageFrames, child.ownFrames];
	}

	static function onFrame(_) {
		frame++;
		parentFrames++;
		if (frame == 1) {
			loader = new Loader();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, function(_) {
				root.addChild(loader);
				var cls:Dynamic = loader.contentLoaderInfo.applicationDomain.getDefinition("Child");
				child = cls.instance;
				clip = child.clip;
				timer = child.timer;
				Out.line("loaded: timer.running=" + timer.running + " channel=" + (child.channel != null));
			});
			loader.load(new URLRequest("child/loaded.swf"));
		} else if (child != null && frame == 8) {
			var c = counts();
			Out.line("before unloadAndStop: child timer ticked=" + (c[0] > 0) + " interval ticked=" + (c[1] > 0)
				+ " stage frames=" + (c[2] > 0) + " own frames=" + (c[3] > 0));
			Out.line("parent before: timer ticked=" + (parentTimerTicks > 0));
			loader.unloadAndStop();
			Out.line("after unloadAndStop: content=" + Std.string(loader.content) + " timer.running=" + timer.running
				+ " loaderInfo.content=" + Std.string(loader.contentLoaderInfo.content));
		} else if (child != null && frame == 9) {
			// Counted from the frame after the call: the dispatch that ran unloadAndStop is over.
			snapshot = counts();
			parentTimerTicks = 0;
			parentFrames = 0;
		} else if (snapshot != null && frame == 14) {
			var c = counts();
			Out.line("child since unloadAndStop: timer ticks=" + (c[0] - snapshot[0]) + " interval ticks=" + (c[1] - snapshot[1])
				+ " stage frames=" + (c[2] - snapshot[2]) + " own frames=" + (c[3] - snapshot[3]));
			Out.line("parent since unloadAndStop: timer ticked=" + (parentTimerTicks > 0) + " frames=" + parentFrames);
			Out.line("done");
			Out.finish();
		}
	}

	public static function main() {
		Out.start("timffle_unload_and_stop");
		root = Lib.current;
		var t = new Timer(10);
		t.addEventListener(TimerEvent.TIMER, function(_) parentTimerTicks++);
		t.start();
		root.stage.addEventListener(Event.ENTER_FRAME, onFrame);
	}
}
