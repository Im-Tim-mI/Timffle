import flash.Lib;
import flash.display.MovieClip;
import flash.display.Sprite;
import flash.events.Event;
import flash.events.TimerEvent;
import flash.media.Sound;
import flash.media.SoundChannel;
import flash.utils.Timer;

/** The loaded SWF: everything Loader.unloadAndStop() must stop, counted so the parent can check it. */
@:sound("tone.wav")
class Tone extends Sound {}

@:keep
class Child extends Sprite {
	public var clip:MovieClip;
	public var timer:Timer;
	public var channel:SoundChannel;
	public var timerTicks:Int = 0;
	public var intervalTicks:Int = 0;
	public var stageFrames:Int = 0;
	public var ownFrames:Int = 0;

	public function new() {
		super();
		clip = new MovieClip();
		clip.graphics.beginFill(0xFF0000);
		clip.graphics.drawRect(0, 0, 20, 20);
		clip.graphics.endFill();
		addChild(clip);

		timer = new Timer(10);
		timer.addEventListener(TimerEvent.TIMER, function(_) timerTicks++);
		timer.start();

		untyped __global__["flash.utils.setInterval"](function() intervalTicks++, 10);

		channel = new Tone().play(0, 1000);

		addEventListener(Event.ADDED_TO_STAGE, function(_) {
			// A stage listener and an enterFrame listener on the child itself.
			stage.addEventListener(Event.ENTER_FRAME, onStageFrame);
			addEventListener(Event.ENTER_FRAME, onOwnFrame);
		});
	}

	function onStageFrame(_) stageFrames++;
	function onOwnFrame(_) ownFrames++;

	public static var instance:Child;

	public static function main() {
		instance = new Child();
		Lib.current.addChild(instance);
	}
}
