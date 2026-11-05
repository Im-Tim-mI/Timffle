package {
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.StageVideoAvailabilityEvent;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.media.AudioDeviceManager;
    import flash.media.Camera;
    import flash.media.Microphone;
    import flash.media.MicrophoneEnhancedOptions;
    import flash.media.SoundCodec;
    import flash.media.SoundTransform;
    import flash.media.StageVideo;
    import flash.utils.getDefinitionByName;
    import flash.utils.getQualifiedClassName;

    // Timffle: the validation of StageVideo.viewPort/zoom/pan/depth (which values are
    // RangeError #2004 or #2006), the constructors of StageVideo, Camera, Microphone
    // and AudioDeviceManager and what a constructed Camera/Microphone answers, how
    // often the stage reports its video availability when listeners are added, and
    // which AV classes exist. output.txt was recorded with the real Flash Player 32
    // (twice, same output). The availability value itself, `colorSpaces`, device
    // names and `isSupported` depend on the machine (under Wine stage video is
    // available and a microphone exists) and are left out.
    public class Test extends Sprite {
        private var frame:int = 0;
        private var sv:StageVideo;

        private function err(e:Error):String {
            return getQualifiedClassName(e) + " #" + e.errorID;
        }

        private function v(x:*):String {
            return x === null ? "null" : typeof x == "string" ? "'" + x + "'" : String(x);
        }

        private function tryViewPort(label:String, r:Rectangle):void {
            try {
                sv.viewPort = r;
                trace("viewPort " + label + " ok -> " + sv.viewPort);
            } catch (e:Error) {
                trace("viewPort " + label + " threw " + err(e) + " kept " + sv.viewPort);
            }
        }

        private function tryZoom(label:String, p:Point):void {
            try {
                sv.zoom = p;
                trace("zoom " + label + " ok -> " + sv.zoom);
            } catch (e:Error) {
                trace("zoom " + label + " threw " + err(e) + " kept " + sv.zoom);
            }
        }

        private function tryPan(label:String, p:Point):void {
            try {
                sv.pan = p;
                trace("pan " + label + " ok -> " + sv.pan);
            } catch (e:Error) {
                trace("pan " + label + " threw " + err(e) + " kept " + sv.pan);
            }
        }

        private function attempt(label:String, f:Function):void {
            try {
                trace(label + " -> " + v(f()));
            } catch (e:Error) {
                trace(label + " threw " + err(e));
            }
        }

        private function exists(name:String):String {
            try {
                return name + "=" + (getDefinitionByName(name) != null);
            } catch (e:Error) {
                return name + "=missing(#" + e.errorID + ")";
            }
        }

        public function Test() {
            sv = stage.stageVideos[0];
            trace("// viewPort");
            tryViewPort("(0,0,0,0)", new Rectangle(0, 0, 0, 0));
            tryViewPort("(-8192,-8192,1,1)", new Rectangle(-8192, -8192, 1, 1));
            tryViewPort("(-8193,0,1,1)", new Rectangle(-8193, 0, 1, 1));
            tryViewPort("(8191,8191,1,1)", new Rectangle(8191, 8191, 1, 1));
            tryViewPort("(8192,0,1,1)", new Rectangle(8192, 0, 1, 1));
            tryViewPort("(0,8192,1,1)", new Rectangle(0, 8192, 1, 1));
            tryViewPort("(0,0,-1,1)", new Rectangle(0, 0, -1, 1));
            tryViewPort("(0,0,1,-1)", new Rectangle(0, 0, 1, -1));
            tryViewPort("(0,0,8192,1)", new Rectangle(0, 0, 8192, 1));
            tryViewPort("(0,0,9000,9000)", new Rectangle(0, 0, 9000, 9000));
            tryViewPort("(100,100,8191,8191)", new Rectangle(100, 100, 8191, 8191));
            tryViewPort("(-8192,0,8191,1)", new Rectangle(-8192, 0, 8191, 1));
            tryViewPort("(NaN,0,1,1)", new Rectangle(NaN, 0, 1, 1));
            tryViewPort("(0,0,NaN,1)", new Rectangle(0, 0, NaN, 1));
            tryViewPort("(0,0,Infinity,1)", new Rectangle(0, 0, Infinity, 1));
            tryViewPort("(NaN,0,-1,1)", new Rectangle(NaN, 0, -1, 1));
            tryViewPort("(9000,0,-1,1)", new Rectangle(9000, 0, -1, 1));
            tryViewPort("(1.5,2.5,3.5,4.5)", new Rectangle(1.5, 2.5, 3.5, 4.5));
            tryViewPort("(-8192.5,0,1,1)", new Rectangle(-8192.5, 0, 1, 1));
            tryViewPort("(8191.4,0,1,1)", new Rectangle(8191.4, 0, 1, 1));
            tryViewPort("null", null);
            trace("// zoom");
            tryZoom("(1,1)", new Point(1, 1));
            tryZoom("(0.99,1)", new Point(0.99, 1));
            tryZoom("(1,0)", new Point(1, 0));
            tryZoom("(8,8)", new Point(8, 8));
            tryZoom("(16,16)", new Point(16, 16));
            tryZoom("(16.01,1)", new Point(16.01, 1));
            tryZoom("(1,17)", new Point(1, 17));
            tryZoom("(NaN,1)", new Point(NaN, 1));
            tryZoom("(-1,1)", new Point(-1, 1));
            tryZoom("(2.5,3.5)", new Point(2.5, 3.5));
            tryZoom("null", null);
            trace("// pan");
            tryPan("(0,0)", new Point(0, 0));
            tryPan("(-1,1)", new Point(-1, 1));
            tryPan("(-1.01,0)", new Point(-1.01, 0));
            tryPan("(0,1.01)", new Point(0, 1.01));
            tryPan("(NaN,0)", new Point(NaN, 0));
            tryPan("(0.25,-0.75)", new Point(0.25, -0.75));
            tryPan("null", null);
            trace("// depth");
            sv.depth = -5;
            trace("depth -5 -> " + sv.depth);
            sv.depth = 2147483647;
            trace("depth max -> " + sv.depth);
            trace("colorSpaces is the same object each time: " + (sv.colorSpaces == sv.colorSpaces));
            trace("// constructors");
            attempt("new StageVideo()", function():* { return new StageVideo(); });
            attempt("new AudioDeviceManager()", function():* { return new AudioDeviceManager(); });
            var c:Camera;
            attempt("new Camera()", function():* { c = new Camera(); return c; });
            attempt("camera values", function():* { return [c.activityLevel, c.bandwidth, c.currentFPS, c.fps, c.height, c.index, c.keyFrameInterval, c.loopback, c.motionLevel, c.motionTimeout, c.muted, v(c.name), c.quality, c.width].join(","); });
            attempt("camera setters", function():* { c.setMode(320, 240, 30); c.setQuality(100, 50); c.setKeyFrameInterval(9); c.setMotionLevel(20, 500); c.setLoopback(true); return [c.width, c.height, c.fps, c.bandwidth, c.quality, c.keyFrameInterval, c.motionLevel, c.motionTimeout, c.loopback].join(","); });
            attempt("camera.copyToByteArray(null, null)", function():* { c.copyToByteArray(null, null); return "ok"; });
            attempt("camera.copyToVector(null, null)", function():* { c.copyToVector(null, null); return "ok"; });
            attempt("camera.drawToBitmapData(null)", function():* { c.drawToBitmapData(null); return "ok"; });
            attempt("camera.drawToBitmapData(1x1)", function():* { c.drawToBitmapData(new BitmapData(1, 1)); return "ok"; });
            attempt("Camera.names is a new Array each time", function():* { return Camera.names != Camera.names; });
            var m:Microphone;
            attempt("new Microphone()", function():* { m = new Microphone(); return m; });
            attempt("microphone values", function():* { return [m.activityLevel, v(m.codec), m.enableVAD, m.encodeQuality, v(m.enhancedOptions), m.framesPerPacket, m.gain, m.index, m.muted, v(m.name), m.noiseSuppressionLevel, m.rate, m.silenceLevel, m.silenceTimeout, m.soundTransform.volume, m.useEchoSuppression].join(","); });
            attempt("microphone setters", function():* { m.codec = SoundCodec.SPEEX; m.gain = 80; m.rate = 22; m.encodeQuality = 3; m.framesPerPacket = 4; m.noiseSuppressionLevel = -10; m.enableVAD = true; m.setSilenceLevel(50, 100); m.setUseEchoSuppression(true); m.setLoopBack(true); m.soundTransform = new SoundTransform(0.5); m.enhancedOptions = new MicrophoneEnhancedOptions(); return [v(m.codec), m.gain, m.rate, m.encodeQuality, m.framesPerPacket, m.noiseSuppressionLevel, m.enableVAD, m.silenceLevel, m.silenceTimeout, m.useEchoSuppression, m.soundTransform.volume, v(m.enhancedOptions)].join(","); });
            attempt("microphone.codec = null", function():* { m.codec = null; return v(m.codec); });
            attempt("microphone.codec = bogus", function():* { m.codec = "bogus"; return v(m.codec); });
            attempt("microphone.soundTransform = null", function():* { m.soundTransform = null; return "ok"; });
            trace("// AV classes present");
            trace(exists("flash.media.AVStream") + " " + exists("flash.media.AVPlayer") + " " + exists("flash.media.AVURLLoader") + " " + exists("flash.media.AVURLStream") + " " + exists("flash.display.AVLoader") + " " + exists("flash.system.AuthorizedFeaturesLoader") + " " + exists("flash.media.AVSegmentedSource") + " " + exists("flash.media.MediaPlayer"));
            trace("// availability listeners");
            stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail1);
            stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail2);
            addEventListener(Event.ENTER_FRAME, onFrame);
        }

        private function onAvail1(e:StageVideoAvailabilityEvent):void {
            trace("f" + frame + " listener1, target is stage: " + (e.target == stage) + ", reason is a string: " + (e.reason is String));
        }

        private function onAvail2(e:StageVideoAvailabilityEvent):void {
            trace("f" + frame + " listener2");
        }

        private function onAvail3(e:StageVideoAvailabilityEvent):void {
            trace("f" + frame + " listener3 (added in frame 3)");
        }

        private function onAvail4(e:StageVideoAvailabilityEvent):void {
            trace("f" + frame + " listener4 (capture phase)");
        }

        private function onFrame(e:Event):void {
            frame++;
            if (frame == 3) {
                stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail3);
                trace("f3 listener3 added");
            } else if (frame == 6) {
                stage.removeEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail1);
                stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail1);
                trace("f6 listener1 removed and re-added");
            } else if (frame == 9) {
                stage.addEventListener(StageVideoAvailabilityEvent.STAGE_VIDEO_AVAILABILITY, onAvail4, true);
                trace("f9 listener4 added for the capture phase");
            } else if (frame == 12) {
                trace("// done");
                removeEventListener(Event.ENTER_FRAME, onFrame);
            }
        }
    }
}
