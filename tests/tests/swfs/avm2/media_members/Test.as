// Timffle: flash.media members that Ruffle stubbed or lacked — Sound (url, bytesLoaded,
// isBuffering, isURLInaccessible, close, extract, loadPCMFromByteArray, load with a context),
// SoundMixer.audioPlaybackMode/useSpeakerphoneForVoice, flash.media.scanHardware/avSendToURL,
// AuthorizedFeatures, ExternalInterface.marshallExceptions, Transform.concatenatedColorTransform,
// Video.videoWidth/videoHeight/clear/attachNetStream(null)/attachCamera, VideoStreamSettings and
// H264VideoStreamSettings. Every expected line comes from the real Flash Player 32 probes
// timffle/difftest/src/D60Media.hx and D61Extract.hx, except the lines marked "(Ruffle)".
package {
    import flash.display.*;
    import flash.events.*;
    import flash.external.ExternalInterface;
    import flash.geom.ColorTransform;
    import flash.media.*;
    import flash.net.*;
    import flash.system.AuthorizedFeatures;
    import flash.utils.*;

    public class Test extends MovieClip {
        private var vid:Video;
        private var mp3:ByteArray;
        private var ticks:int = 0;

        public function Test() {
            step("newSound", newSound);
            step("pcm", pcm);
            step("soundMixer", soundMixer);
            step("mediaPackage", mediaPackage);
            step("marshall", marshall);
            step("concatenated", concatenated);
            step("vss", vss);
            step("h264", h264);
            step("videoNew", videoNew);
            var loader:URLLoader = new URLLoader();
            loader.dataFormat = URLLoaderDataFormat.BINARY;
            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                mp3 = loader.data as ByteArray;
                trace("# mp3 bytes=" + mp3.length);
                step("embedded", embedded);
                step("loadUrl", loadUrl);
            });
            loader.load(new URLRequest("noise.mp3"));
        }

        private static function step(label:String, f:Function):void {
            try {
                f();
            } catch (e:Error) {
                trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
            }
        }

        private static function sprops(s:Sound):String {
            return "url=" + s.url + " bytesLoaded=" + s.bytesLoaded + " bytesTotal=" + s.bytesTotal + " isBuffering=" + s.isBuffering
                + " isURLInaccessible=" + s.isURLInaccessible + " length=" + Math.round(s.length * 1000) / 1000;
        }

        private static function f4(n:Number):String {
            return String(Math.round(n * 10000) / 10000);
        }

        private static function floats(ba:ByteArray, from:int, count:int):String {
            ba.position = from;
            var v:Array = [];
            for (var i:int = 0; i < count && ba.bytesAvailable >= 4; i++) {
                v.push(f4(ba.readFloat()));
            }
            return v.join(",");
        }

        private static function ct(c:ColorTransform):String {
            return "(" + c.redMultiplier + "," + c.greenMultiplier + "," + c.blueMultiplier + "," + c.alphaMultiplier + " | " + c.redOffset + ","
                + c.greenOffset + "," + c.blueOffset + "," + c.alphaOffset + ")";
        }

        private function newSound():void {
            var s:Sound = new Sound();
            trace("new Sound: " + sprops(s));
            step("close new", function():void { s.close(); trace("close new ok"); });
            var ba:ByteArray = new ByteArray();
            trace("extract new -> " + s.extract(ba, 10) + " length=" + ba.length);
            trace("extract null -> " + s.extract(null, 10));
        }

        private function pcmSound(count:int, left:Number, right:Number, rate:Number = 44100):Sound {
            var s:Sound = new Sound();
            var ba:ByteArray = new ByteArray();
            for (var i:int = 0; i < count; i++) {
                ba.writeFloat(left);
                ba.writeFloat(right);
            }
            ba.position = 0;
            s.loadPCMFromByteArray(ba, count, "float", true, rate);
            return s;
        }

        private function pcm():void {
            var s:Sound = pcmSound(5000, 0.5, -0.25);
            var out:ByteArray = new ByteArray();
            trace("pcm 5000: " + sprops(s));
            trace("pcm 5000 extract(4,2000) -> " + s.extract(out, 4, 2000) + " " + floats(out, 0, 8) + " position=" + out.position);
            out = new ByteArray();
            out.endian = Endian.LITTLE_ENDIAN;
            trace("pcm 5000 extract(2,2000) LE -> " + s.extract(out, 2, 2000) + " " + floats(out, 0, 4));
            out.endian = Endian.BIG_ENDIAN;
            trace("same bytes read BE -> " + floats(out, 0, 4));
            out = new ByteArray();
            trace("pcm 5000 extract(1e9,0) -> " + s.extract(out, 1e9, 0) + " length=" + out.length);
            out = new ByteArray();
            trace("pcm 5000 extract(10,5000) -> " + s.extract(out, 10, 5000) + " extract(10,4997) -> " + s.extract(out, 10, 4997) + " length=" + out.length);
            out = new ByteArray();
            trace("pcm 5000 extract(0,0) -> " + s.extract(out, 0, 0) + " extract(-5,0) -> " + s.extract(out, -5, 0) + " extract(NaN,0) -> " + s.extract(out, NaN, 0)
                + " extract(2.7,0) -> " + s.extract(out, 2.7, 0) + " length=" + out.length);
            // sequential cursor: explicit start, then two sequential reads, compared with explicit ones
            var a:ByteArray = new ByteArray(); s.extract(a, 2, 2000);
            var b:ByteArray = new ByteArray(); s.extract(b, 2);
            var c:ByteArray = new ByteArray(); s.extract(c, 2, -7);
            var d:ByteArray = new ByteArray(); s.extract(d, 2, 2002);
            var e:ByteArray = new ByteArray(); s.extract(e, 2, 2004);
            trace("sequential after 2000: " + floats(b, 0, 4) + " == 2002: " + floats(d, 0, 4) + "; -7 continues: " + floats(c, 0, 4) + " == 2004: " + floats(e, 0, 4));
            var tail:ByteArray = new ByteArray();
            s.extract(tail, 10, 4998);
            trace("after reading the tail, sequential extract -> " + s.extract(tail, 10));
            var pos:ByteArray = new ByteArray();
            pos.writeUTFBytes("abcdefgh");
            pos.position = 4;
            trace("into pos 4 -> " + s.extract(pos, 3, 2000) + " length=" + pos.length + " position=" + pos.position);
            pos.position = 0;
            trace("prefix kept=" + pos.readUTFBytes(4) + " floats=" + floats(pos, 4, 6));
            step("pcm again", function():void { s.loadPCMFromByteArray(new ByteArray(), 100, "float", true, 44100); trace("pcm again ok"); });
            step("pcm again with bytes", function():void {
                var ba:ByteArray = new ByteArray();
                for (var i:int = 0; i < 20; i++) ba.writeFloat(1);
                ba.position = 0;
                s.loadPCMFromByteArray(ba, 10, "float", true, 44100);
                trace("pcm again with bytes ignored: position=" + ba.position + " " + sprops(s));
            });
            step("pcm then load", function():void { s.load(new URLRequest("noise.mp3")); trace("pcm then load ok"); });

            var m:Sound = new Sound();
            var mb:ByteArray = new ByteArray();
            mb.endian = Endian.LITTLE_ENDIAN;
            for (var i:int = 0; i < 3000; i++) mb.writeShort(i == 0 ? 16384 : -8192);
            mb.position = 0;
            m.loadPCMFromByteArray(mb, 3000, "short", false, 44100);
            out = new ByteArray();
            trace("pcm short mono 3000: " + sprops(m) + " position=" + mb.position + " extract(2,1500) -> " + m.extract(out, 2, 1500) + " " + floats(out, 0, 4));

            var r:Sound = pcmSound(3000, 0.5, 0.125, 22050);
            trace("pcm 22050: " + sprops(r));
            var cl:Sound = pcmSound(3000, 2.5, -3);
            out = new ByteArray();
            trace("pcm clipping extract(2,1000) -> " + cl.extract(out, 2, 1000) + " " + floats(out, 0, 4));
            var pr:Sound = pcmSound(3000, 0.123456789, 1 / 3);
            out = new ByteArray();
            pr.extract(out, 1, 1000);
            out.position = 0;
            var pa:Number = out.readFloat(), pb:Number = out.readFloat();
            trace("pcm precision -> " + pa + " " + pb + " (x32768: " + (pa * 32768) + " " + (pb * 32768) + ")");
            trace("pcm rate 8000: " + sprops(pcmSound(8, 0.25, 0.25, 8000)));
            trace("pcm rate 48000: " + sprops(pcmSound(8, 0.25, 0.25, 48000)));
            trace("pcm rate 12345: " + sprops(pcmSound(1, 0.25, 0.25, 12345)));

            var fp:Sound = new Sound();
            var fb:ByteArray = new ByteArray();
            for (i = 0; i < 20; i++) fb.writeFloat(i);
            fb.position = 8;
            fp.loadPCMFromByteArray(fb, 3, "float", true, 44100);
            out = new ByteArray();
            trace("pcm from position 8 -> " + fp.extract(out, 3, 0) + " position after=" + fb.position + " " + sprops(fp));

            var ba:ByteArray = new ByteArray();
            ba.writeFloat(0.5);
            ba.position = 0;
            step("pcm too few bytes", function():void { new Sound().loadPCMFromByteArray(ba, 100, "float", true, 44100); trace("pcm too few bytes ok"); });
            ba = new ByteArray();
            ba.writeFloat(0); ba.writeFloat(0);
            ba.position = 0;
            step("pcm bad format", function():void { new Sound().loadPCMFromByteArray(ba, 1, "double", true, 44100); trace("pcm bad format ok"); });
            step("pcm null format", function():void { new Sound().loadPCMFromByteArray(ba, 1, null, true, 44100); trace("pcm null format ok"); });
            step("pcm null bytes", function():void { new Sound().loadPCMFromByteArray(null, 1, "float", true, 44100); trace("pcm null bytes ok"); });
            step("pcm zero samples", function():void { new Sound().loadPCMFromByteArray(new ByteArray(), 0, "float", true, 44100); trace("pcm zero samples ok"); });
            var pl:Sound = pcmSound(4410, 0.1, 0.1);
            var ch:SoundChannel = pl.play();
            trace("pcm play -> " + getQualifiedClassName(ch) + " length=" + pl.length);
            if (ch != null) ch.stop();
            step("close pcm", function():void { pl.close(); trace("close pcm ok"); });
        }

        private function soundMixer():void {
            trace("audioPlaybackMode=" + SoundMixer.audioPlaybackMode + " useSpeakerphoneForVoice=" + SoundMixer.useSpeakerphoneForVoice + " (Ruffle: false, Flash reads null)");
            for each (var v:String in ["voice", "ambient", "media", "VOICE", "bogus", "", null]) {
                SoundMixer.audioPlaybackMode = v;
                trace("audioPlaybackMode set " + v + " -> " + SoundMixer.audioPlaybackMode);
            }
            SoundMixer.useSpeakerphoneForVoice = true;
            trace("useSpeakerphoneForVoice set true -> " + SoundMixer.useSpeakerphoneForVoice);
            SoundMixer.useSpeakerphoneForVoice = false;
            trace("useSpeakerphoneForVoice set false -> " + SoundMixer.useSpeakerphoneForVoice);
        }

        private function mediaPackage():void {
            trace("scanHardware() -> " + flash.media.scanHardware());
            step("avSendToURL(null,null)", function():void { flash.media.avSendToURL(null, null); trace("avSendToURL(null,null) ok"); });
            step("avSendToURL(null,req)", function():void { flash.media.avSendToURL(null, new URLRequest("noise.mp3")); trace("avSendToURL(null,req) ok"); });
            step("new AuthorizedFeatures", function():void { new AuthorizedFeatures(); trace("new AuthorizedFeatures ok"); });
        }

        private function marshall():void {
            trace("marshallExceptions default=" + ExternalInterface.marshallExceptions + " available=" + ExternalInterface.available);
            ExternalInterface.marshallExceptions = true;
            trace("marshallExceptions after set=" + ExternalInterface.marshallExceptions);
            ExternalInterface.marshallExceptions = false;
        }

        private function concatenated():void {
            var a:Sprite = new Sprite();
            var b:Sprite = new Sprite();
            var c:Shape = new Shape();
            a.addChild(b);
            b.addChild(c);
            a.transform.colorTransform = new ColorTransform(0.5, 2, 1, 0.5, 10, -20, 300, 5);
            b.transform.colorTransform = new ColorTransform(0.5, 0.5, 2, 1, 40, 10, -10, -10);
            c.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 0, 0, 0, 0);
            trace("detached c=" + ct(c.transform.concatenatedColorTransform));
            trace("detached b=" + ct(b.transform.concatenatedColorTransform));
            trace("detached a=" + ct(a.transform.concatenatedColorTransform));
            addChild(a);
            trace("attached c=" + ct(c.transform.concatenatedColorTransform));
            trace("attached b=" + ct(b.transform.concatenatedColorTransform));
            trace("attached a=" + ct(a.transform.concatenatedColorTransform));
            trace("root=" + ct(this.transform.concatenatedColorTransform));
            trace("stage=" + ct(stage.transform.concatenatedColorTransform));
            this.transform.colorTransform = new ColorTransform(0.25, 1, 1, 1, 3, 0, 0, 0);
            trace("root tinted c=" + ct(c.transform.concatenatedColorTransform));
            trace("root tinted root=" + ct(this.transform.concatenatedColorTransform));
            this.transform.colorTransform = new ColorTransform();
            trace("same object=" + (c.transform.concatenatedColorTransform == c.transform.concatenatedColorTransform));
            var got:ColorTransform = c.transform.concatenatedColorTransform;
            got.redMultiplier = 9;
            trace("mutate copy -> " + ct(c.transform.concatenatedColorTransform));
            c.alpha = 0.5;
            trace("alpha 0.5 c=" + ct(c.transform.concatenatedColorTransform) + " own=" + ct(c.transform.colorTransform));
            removeChild(a);
            trace("removed c=" + ct(c.transform.concatenatedColorTransform));
            var p:Sprite = new Sprite();
            var q:Shape = new Shape();
            p.addChild(q);
            p.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 200, -200, 0, 0);
            q.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 200, -200, 0, 0);
            trace("offset detached q=" + ct(q.transform.concatenatedColorTransform));
            addChild(p);
            trace("offset attached q=" + ct(q.transform.concatenatedColorTransform));
            removeChild(p);
        }

        private function vss():void {
            var v:VideoStreamSettings = new VideoStreamSettings();
            trace("vss default bandwidth=" + v.bandwidth + " codec=" + v.codec + " fps=" + v.fps + " height=" + v.height + " keyFrameInterval=" + v.keyFrameInterval
                + " quality=" + v.quality + " width=" + v.width);
            v.setKeyFrameInterval(5);
            v.setMode(320, 240, 15);
            v.setQuality(50000, 80);
            trace("vss set bandwidth=" + v.bandwidth + " fps=" + v.fps + " height=" + v.height + " keyFrameInterval=" + v.keyFrameInterval + " quality=" + v.quality
                + " width=" + v.width);
            v.setKeyFrameInterval(0); trace("kfi 0 -> " + v.keyFrameInterval);
            v.setKeyFrameInterval(500); trace("kfi 500 -> " + v.keyFrameInterval);
            v.setKeyFrameInterval(-1); trace("kfi -1 -> " + v.keyFrameInterval);
            v.setKeyFrameInterval(-7); trace("kfi -7 -> " + v.keyFrameInterval);
            v.setMode(-1, -1, -1); trace("mode -1 -> " + v.width + "x" + v.height + "@" + v.fps);
            v.setMode(0, 0, 0); trace("mode 0 -> " + v.width + "x" + v.height + "@" + v.fps);
            v.setMode(-5, 10, -5); trace("mode -5 -> " + v.width + "x" + v.height + "@" + v.fps);
            v.setMode(100, 50, 7.5); trace("mode 7.5 -> " + v.width + "x" + v.height + "@" + v.fps);
            v.setMode(100, 50, NaN); trace("mode NaN -> " + v.width + "x" + v.height + "@" + v.fps);
            v.setQuality(0, 0); trace("q 0,0 -> " + v.bandwidth + "/" + v.quality);
            v.setQuality(0, 150); trace("q 0,150 -> " + v.bandwidth + "/" + v.quality);
            v.setQuality(-1, -1); trace("q -1,-1 -> " + v.bandwidth + "/" + v.quality);
            v.setQuality(1000, 50); trace("q 1000,50 -> " + v.bandwidth + "/" + v.quality);
        }

        private function h264():void {
            var v:H264VideoStreamSettings = new H264VideoStreamSettings();
            trace("h264 default codec=" + v.codec + " level=" + v.level + " profile=" + v.profile + " bandwidth=" + v.bandwidth + " fps=" + v.fps + " kfi=" + v.keyFrameInterval
                + " quality=" + v.quality + " " + v.width + "x" + v.height + " is VSS=" + (v is VideoStreamSettings));
            for each (var pl:Array in [["main", "3.1"], ["baseline", "1b"], ["main", "5.1"], ["MAIN", "3"], ["high", "3"], ["main", "6"], ["main", "3.0"], ["main", "1.0"],
                [null, "3"], ["main", null], ["main", ""], ["baseline", "2.2"]]) {
                step("setProfileLevel " + pl[0] + "," + pl[1], function():void {
                    v.setProfileLevel(pl[0], pl[1]);
                    trace("setProfileLevel " + pl[0] + "," + pl[1] + " -> profile=" + v.profile + " level=" + v.level);
                });
            }
            v.setMode(640, 480, 30);
            v.setQuality(0, 90);
            v.setKeyFrameInterval(10);
            trace("h264 after set " + v.width + "x" + v.height + "@" + v.fps + " q=" + v.quality + " bw=" + v.bandwidth + " kfi=" + v.keyFrameInterval + " codec=" + v.codec);
        }

        private function videoNew():void {
            vid = new Video();
            trace("video new videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight + " w=" + vid.width + " h=" + vid.height);
            vid.clear();
            trace("video clear on new ok");
            vid.attachNetStream(null);
            trace("video attachNetStream(null) on new ok");
            vid.attachCamera(null);
            trace("video attachCamera(null) ok videoWidth=" + vid.videoWidth);
            trace("getCamera=" + Camera.getCamera());
            addChild(vid);
        }

        private function embedded():void {
            var n:Sound = new Sound();
            n.loadCompressedDataFromByteArray(mp3, mp3.length);
            trace("mp3 bytes: " + sprops(n) + " samples=" + Math.round(n.length * 44.1));
            step("close mp3", function():void { n.close(); trace("close mp3 ok"); });
            var ba:ByteArray = new ByteArray();
            trace("mp3 extract(ba,100) -> " + n.extract(ba, 100) + " length=" + ba.length + " position=" + ba.position + " endian=" + ba.endian);
            ba = new ByteArray();
            trace("mp3 extract(ba,10,1e9) -> " + n.extract(ba, 10, 1e9) + " length=" + ba.length);
            ba = new ByteArray();
            trace("mp3 extract(ba,1e9,0) -> " + n.extract(ba, 1e9, 0) + " length=" + ba.length);
            var total:int = Math.round(n.length * 44.1);
            ba = new ByteArray();
            trace("mp3 extract(ba,10,total-3) -> " + n.extract(ba, 10, total - 3) + " extract(ba,10,total) -> " + n.extract(ba, 10, total) + " length=" + ba.length);
            var x:ByteArray = new ByteArray(); n.extract(x, 2, 2000);
            var y:ByteArray = new ByteArray(); n.extract(y, 2);
            var z:ByteArray = new ByteArray(); n.extract(z, 2, 2002);
            trace("mp3 sequential == explicit 2002: " + (floats(y, 0, 4) == floats(z, 0, 4)) + " nonzero=" + (floats(x, 0, 4) != "0,0,0,0"));
        }

        private function loadUrl():void {
            var s:Sound = new Sound();
            var seen:Array = [];
            var log:Function = function(e:Event):void {
                seen.push(e.type);
                trace("sound event " + e.type + ": " + sprops(s).replace(/url=\S+noise\.mp3/, "url=<noise.mp3>"));
            };
            s.addEventListener(Event.OPEN, log);
            s.addEventListener(ProgressEvent.PROGRESS, log);
            s.addEventListener(Event.ID3, log);
            s.addEventListener(IOErrorEvent.IO_ERROR, log);
            s.addEventListener(Event.COMPLETE, function(e:Event):void {
                log(e);
                step("close after complete", function():void { s.close(); trace("close after complete ok"); });
                step("close twice", function():void { s.close(); trace("close twice ok"); });
                var ba:ByteArray = new ByteArray();
                trace("loaded extract(ba,4,0) -> " + s.extract(ba, 4, 0) + " length=" + ba.length);
                var ch:SoundChannel = s.play();
                trace("loaded play -> " + getQualifiedClassName(ch));
                if (ch != null) ch.stop();
                step("load again after close", function():void { s.load(new URLRequest("noise.mp3")); trace("load again after close ok"); });
                trace("events=" + seen.join(","));
                load404();
            });
            s.load(new URLRequest("noise.mp3"), new SoundLoaderContext(2000, false));
            trace("after load(): " + sprops(s));
            step("load twice", function():void { s.load(new URLRequest("noise.mp3")); trace("load twice ok"); });
            step("close while loading", function():void {
                var t:Sound = new Sound();
                t.load(new URLRequest("noise.mp3"));
                t.addEventListener(Event.OPEN, function(e:Event):void { trace("closed sound got " + e.type + " (must not happen)"); });
                t.close();
                trace("close while loading ok " + sprops(t));
                t.load(new URLRequest("missing.mp3"));
                trace("load after close-while-loading ok");
                t.close();
            });
        }

        private function load404():void {
            var s:Sound = new Sound();
            var log:Function = function(e:Event):void {
                trace("404 event " + e.type + ": " + sprops(s) + (e is IOErrorEvent ? " text=" + IOErrorEvent(e).text + " id=" + IOErrorEvent(e).errorID : ""));
            };
            s.addEventListener(Event.OPEN, log);
            s.addEventListener(ProgressEvent.PROGRESS, log);
            s.addEventListener(Event.COMPLETE, log);
            s.addEventListener(IOErrorEvent.IO_ERROR, function(e:Event):void {
                log(e);
                step("close after ioError", function():void { s.close(); trace("close after ioError ok"); });
                step("load after ioError", function():void { s.load(new URLRequest("noise.mp3")); trace("load after ioError ok"); });
                s.close();
                video();
            });
            s.load(new URLRequest("missing.mp3"));
            trace("404 after load(): " + sprops(s));
        }

        private function video():void {
            var nc:NetConnection = new NetConnection();
            nc.connect(null);
            var ns:NetStream = new NetStream(nc);
            var done:Boolean = false;
            ns.client = {
                onMetaData: function(o:Object):void {
                    trace("onMetaData " + o.width + "x" + o.height + " video videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
                }
            };
            ns.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent):void {
                // (status order differs from Flash upstream: only the end of the stream is used here)
                if (e.info.code == "NetStream.Play.Stop" && !done) {
                    done = true;
                    trace("netStatus " + e.info.code + " videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
                    trace("after play videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight + " w=" + vid.width + " h=" + vid.height);
                    var bd:BitmapData = new BitmapData(vid.width, vid.height, false, 0xFF00FF);
                    bd.draw(vid);
                    trace("pixel before clear=" + (bd.getPixel(10, 10) != 0xFF00FF ? "video" : "background"));
                    vid.clear();
                    trace("after clear videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
                    bd.fillRect(bd.rect, 0xFF00FF);
                    bd.draw(vid);
                    trace("pixel after clear=" + (bd.getPixel(10, 10) != 0xFF00FF ? "video" : "background"));
                    vid.attachNetStream(null);
                    trace("after attachNetStream(null) videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
                    bd.fillRect(bd.rect, 0xFF00FF);
                    bd.draw(vid);
                    trace("pixel after detach=" + (bd.getPixel(10, 10) != 0xFF00FF ? "video" : "background") + " (Ruffle)");
                    vid.attachNetStream(ns);
                    bd.fillRect(bd.rect, 0xFF00FF);
                    bd.draw(vid);
                    trace("pixel after reattach=" + (bd.getPixel(10, 10) != 0xFF00FF ? "video" : "background") + " videoWidth=" + vid.videoWidth + " (Ruffle)");
                    trace("# done");
                }
            });
            vid.attachNetStream(ns);
            trace("after attach videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
            ns.play("test_video.flv");
            trace("after play() videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
        }
    }
}
