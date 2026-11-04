package {
import flash.display.Sprite;
import flash.display.StageDisplayState;
import flash.geom.Rectangle;
import flash.media.StageVideo;

// The flash.display.Stage members that used to be stubs. Expected values are those of the
// standalone Flash Player 32.0.0.465 in a 1024x768 window-less (Xvfb) session, measured with
// timffle/difftest/src/D42Stage.hx and D43StageFull.hx: colour correction unsupported, no soft
// keyboard, no GPU window mode, eight StageVideo slots, mouseLock only in full screen,
// fullScreenSourceRect rounded and clamped to 302x74 .. 2880x2880.
public class Test extends Sprite {
    public function Test() {
        trace("allowsFullScreen = " + stage.allowsFullScreen);
        trace("allowsFullScreenInteractive = " + stage.allowsFullScreenInteractive);
        trace("colorCorrection = " + stage.colorCorrection);
        trace("colorCorrectionSupport = " + stage.colorCorrectionSupport);
        trace("constructor = " + stage.constructor);
        trace("displayContextInfo = " + stage.displayContextInfo);
        trace("fullScreenWidth x fullScreenHeight = " + stage.fullScreenWidth + "x" + stage.fullScreenHeight);
        trace("fullScreenSourceRect = " + stage.fullScreenSourceRect);
        trace("mouseLock = " + stage.mouseLock);
        trace("softKeyboardRect = " + stage.softKeyboardRect);
        trace("softKeyboardRect is the same object: " + (stage.softKeyboardRect === stage.softKeyboardRect));
        trace("wmodeGPU = " + stage.wmodeGPU);
        trace("isFocusInaccessible() = " + stage.isFocusInaccessible());

        var videos:Vector.<StageVideo> = stage.stageVideos;
        trace("stageVideos.length = " + videos.length + ", fixed = " + videos.fixed);
        trace("stageVideos is the same object: " + (stage.stageVideos === videos));
        trace("stageVideos[0] is the same object: " + (stage.stageVideos[0] === videos[0]));
        trace("stageVideos[0] = " + videos[0] + ", is StageVideo: " + (videos[0] is StageVideo));
        try {
            new StageVideo();
            trace("new StageVideo() did not throw");
        } catch (e:ArgumentError) {
            trace("new StageVideo() threw ArgumentError #" + e.errorID);
        }

        for each (var value:String in ["on", "off", "default", "ON", "bogus", ""]) {
            try {
                stage.colorCorrection = value;
                trace("colorCorrection = '" + value + "' -> " + stage.colorCorrection);
            } catch (e:Error) {
                trace("colorCorrection = '" + value + "' threw " + e.name + " #" + e.errorID);
            }
        }
        try {
            stage.colorCorrection = null;
            trace("colorCorrection = null -> " + stage.colorCorrection);
        } catch (e:Error) {
            trace("colorCorrection = null threw " + e.name + " #" + e.errorID);
        }

        // constructor assignments are ignored
        stage.constructor = 1;
        trace("after constructor = 1: " + stage.constructor);

        // fullScreenSourceRect: a rounded, clamped copy
        var rect:Rectangle = new Rectangle(1, 2, 3, 4);
        stage.fullScreenSourceRect = rect;
        var got:Rectangle = stage.fullScreenSourceRect;
        trace("fullScreenSourceRect = (1,2,3,4) -> " + got + ", same object: " + (got === rect));
        got.x = 99;
        rect.y = 77;
        trace("after mutating both: " + stage.fullScreenSourceRect);
        var samples:Array = [
            [0, 0, 100, 100], [0, 0, 400, 300], [0, 0, 1000, 1000], [0, 0, 2000, 50], [10, 10, 0, 0],
            [0, 0, 301, 73], [0, 0, 303, 75], [-100, -100, 50, 1000], [0.4, 0.5, 0.6, 1.5],
            [1.5, -6.7, 2.2, 0], [NaN, 1, 2, 3], [1e9, -1e9, 1e9, 1e9]
        ];
        for each (var s:Array in samples) {
            stage.fullScreenSourceRect = new Rectangle(s[0], s[1], s[2], s[3]);
            trace("fullScreenSourceRect = (" + s.join(",") + ") -> " + stage.fullScreenSourceRect);
        }
        stage.fullScreenSourceRect = null;
        trace("fullScreenSourceRect = null -> " + stage.fullScreenSourceRect);

        // mouseLock can only be assigned in full-screen mode
        for each (var lock:Boolean in [true, false]) {
            try {
                stage.mouseLock = lock;
                trace("mouseLock = " + lock + " (normal) -> " + stage.mouseLock);
            } catch (e:Error) {
                trace("mouseLock = " + lock + " (normal) threw " + e.name + " #" + e.errorID);
            }
        }
        stage.displayState = StageDisplayState.FULL_SCREEN;
        trace("displayState = " + stage.displayState);
        // The test host has no pointer lock: the request is refused and mouseLock stays false,
        // as in Flash Player on a platform without mouse lock.
        stage.mouseLock = true;
        trace("mouseLock = true (full screen) -> " + stage.mouseLock);
        stage.mouseLock = false;
        trace("mouseLock = false (full screen) -> " + stage.mouseLock);
        stage.fullScreenSourceRect = new Rectangle(0, 0, 200, 150);
        trace("fullScreenSourceRect while full screen -> " + stage.fullScreenSourceRect + ", stage " + stage.stageWidth + "x" + stage.stageHeight);
        stage.displayState = StageDisplayState.NORMAL;
        trace("displayState = " + stage.displayState + ", mouseLock = " + stage.mouseLock);
        stage.fullScreenSourceRect = null;
    }
}
}
