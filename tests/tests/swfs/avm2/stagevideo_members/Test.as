package {
import flash.display.Sprite;
import flash.utils.getQualifiedClassName;
import flash.events.Event;
import flash.events.EventDispatcher;
import flash.events.StageVideoAvailabilityEvent;
import flash.events.StageVideoEvent;
import flash.geom.Point;
import flash.geom.Rectangle;
import flash.media.AVSegmentedSource;
import flash.media.AVStream;
import flash.media.StageVideo;
import flash.net.NetConnection;
import flash.net.NetStream;

// Flash Player on a machine where stage video is unavailable: the stage
// reports "unavailable" to a new listener on the next frame, the eight
// StageVideo objects keep their geometry with the documented validation,
// and attaching a stream answers renderState "unavailable" on the next frame.
public class Test extends Sprite {
    private var frame:int = 0;

    public function Test() {
        stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvailability);
        trace("listener added in frame 1");

        var userEvent:StageVideoAvailabilityEvent = new StageVideoAvailabilityEvent(
            StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, false, false, "available");
        trace("user event: availability = " + userEvent.availability + ", reason = " + userEvent.reason + ", driver = " + userEvent.driver);

        var sv:StageVideo = stage.stageVideos[0];
        trace("stageVideos.length = " + stage.stageVideos.length);
        trace("sv is EventDispatcher: " + (sv is EventDispatcher));
        trace("viewPort = " + sv.viewPort);
        trace("viewPort is a copy: " + (sv.viewPort !== sv.viewPort));
        trace("zoom = " + sv.zoom);
        trace("pan = " + sv.pan);
        trace("depth = " + sv.depth);
        trace("videoWidth = " + sv.videoWidth + ", videoHeight = " + sv.videoHeight);
        trace("colorSpaces = " + sv.colorSpaces + " (length " + sv.colorSpaces.length + ")");

        sv.viewPort = new Rectangle(10, 20, 300, 200);
        trace("viewPort after set = " + sv.viewPort);
        try {
            sv.viewPort = new Rectangle(-9000, 0, 10, 10);
            trace("viewPort x -9000 did not throw");
        } catch (e:Error) {
            trace("viewPort x -9000 threw " + getQualifiedClassName(e) + ": " + e.message + " (#" + e.errorID + ")");
        }
        try {
            sv.viewPort = null;
            trace("viewPort null did not throw");
        } catch (e:Error) {
            trace("viewPort null threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        trace("viewPort kept = " + sv.viewPort);

        sv.zoom = new Point(2, 3);
        trace("zoom after set = " + sv.zoom);
        try {
            sv.zoom = new Point(0.5, 1);
            trace("zoom 0.5 did not throw");
        } catch (e:Error) {
            trace("zoom 0.5 threw " + getQualifiedClassName(e) + ": " + e.message + " (#" + e.errorID + ")");
        }
        try {
            sv.zoom = new Point(1, 9);
            trace("zoom 9 did not throw");
        } catch (e:Error) {
            trace("zoom 9 threw " + getQualifiedClassName(e) + ": " + e.message + " (#" + e.errorID + ")");
        }
        trace("zoom kept = " + sv.zoom);

        sv.pan = new Point(-1, 0.5);
        trace("pan after set = " + sv.pan);
        try {
            sv.pan = new Point(1.5, 0);
            trace("pan 1.5 did not throw");
        } catch (e:Error) {
            trace("pan 1.5 threw " + getQualifiedClassName(e) + ": " + e.message + " (#" + e.errorID + ")");
        }
        trace("pan kept = " + sv.pan);

        sv.depth = 3;
        trace("depth after set = " + sv.depth);
        trace("stageVideos[1].depth = " + stage.stageVideos[1].depth);

        sv.addEventListener(StageVideoEvent.RENDER_STATE, onRenderState);
        var nc:NetConnection = new NetConnection();
        nc.connect(null);
        var ns:NetStream = new NetStream(nc);
        sv.attachNetStream(ns);
        trace("attachNetStream(ns) ok in frame 1");
        sv.attachNetStream(null);
        trace("attachNetStream(null) ok");
        sv.attachCamera(null);
        trace("attachCamera(null) ok");
        sv.attachAVStream(null);
        trace("attachAVStream(null) ok");
        var avs:StageVideo = stage.stageVideos[2];
        avs.addEventListener(StageVideoEvent.RENDER_STATE, onRenderState);
        avs.attachAVStream(new AVStream(new AVSegmentedSource()));
        trace("attachAVStream(stream) ok in frame 1");

        addEventListener(Event.ENTER_FRAME, onEnterFrame);
    }

    private function onEnterFrame(e:Event):void {
        frame++;
        trace("enterFrame " + frame);
    }

    // Both events arrive asynchronously, after the constructor's frame script.
    private function onAvailability(e:StageVideoAvailabilityEvent):void {
        trace("stageVideoAvailability (enterFrames so far: " + frame + "): availability = " + e.availability
            + ", reason = " + e.reason + ", driver = " + e.driver + ", target is stage: " + (e.target === stage));
    }

    private function onRenderState(e:StageVideoEvent):void {
        trace("renderState (enterFrames so far: " + frame + "): status = " + e.status + ", colorSpace = " + e.colorSpace
            + ", target index = " + stage.stageVideos.indexOf(e.target as StageVideo));
    }
}
}
