/** Probe (no golden): flash.media members Ruffle still stubs or lacks — Sound (url, bytesLoaded,
 *  isBuffering, isURLInaccessible, close, extract, loadPCMFromByteArray, load with context),
 *  SoundMixer.audioPlaybackMode/useSpeakerphoneForVoice, flash.media.scanHardware/avSendToURL,
 *  Transform.concatenatedColorTransform, ExternalInterface.marshallExceptions, Video.videoWidth/
 *  videoHeight/clear/attachNetStream(null)/attachCamera, VideoStreamSettings and
 *  H264VideoStreamSettings. Build with -swf-version 32; run in the standalone Flash Player 32
 *  projector served over HTTP (loads /asset/noise.mp3 and /asset/test_video.flv from bin/). */
import flash.Lib;
import flash.display.*;
import flash.events.*;
import flash.external.ExternalInterface;
import flash.geom.ColorTransform;
import flash.media.*;
import flash.net.*;
import flash.utils.ByteArray;

@:sound("../../../tests/tests/swfs/avm2/sound_rootless/noise.mp3")
class Noise extends flash.media.Sound {}

class D60Media {
	static var qn:Dynamic;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function sprops(s:Sound):String {
		return "url=" + s.url + " bytesLoaded=" + s.bytesLoaded + " bytesTotal=" + s.bytesTotal + " isBuffering=" + s.isBuffering
			+ " isURLInaccessible=" + Reflect.field(s, "isURLInaccessible") + " length=" + s.length;
	}

	static function f3(n:Float):String {
		return Std.string(Math.round(n * 1000) / 1000);
	}

	static function ct(c:ColorTransform):String {
		return "(" + c.redMultiplier + "," + c.greenMultiplier + "," + c.blueMultiplier + "," + c.alphaMultiplier + " | " + c.redOffset + ","
			+ c.greenOffset + "," + c.blueOffset + "," + c.alphaOffset + ")";
	}

	static function extractInfo(label:String, s:Sound, len:Float, start:Float, ?pos:Int) {
		step(label, function() {
			var ba = new ByteArray();
			if (pos != null) {
				ba.writeUTFBytes("abcdefgh");
				ba.position = pos;
			}
			var r = start == -2 ? s.extract(ba, len) : s.extract(ba, len, start);
			var first = "";
			if (ba.length >= 8) {
				ba.position = pos == null ? 0 : pos;
				var v = [];
				for (i in 0...4) {
					if (ba.bytesAvailable >= 4)
						v.push(f3(ba.readFloat()));
				}
				first = v.join(",");
			}
			H.log(label + " -> " + r + " length=" + ba.length + " position=" + ba.position + " endian=" + ba.endian + " first=" + first);
		});
	}

	static function main() {
		H.init("d60media", 60000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		var st = Lib.current.stage;

		// ---- Sound: fresh object
		step("new Sound", function() {
			var s = new Sound();
			H.log("new Sound: " + sprops(s));
			step("close new", function() {
				s.close();
				H.log("close new ok");
			});
			step("extract new", function() {
				var ba = new ByteArray();
				H.log("extract new -> " + s.extract(ba, 10) + " length=" + ba.length);
			});
			step("extract null target", function() H.log("extract null -> " + s.extract(null, 10)));
		});

		// ---- Sound: library symbol
		var n = new Noise();
		step("embedded props", function() H.log("embedded: " + sprops(n) + " samples=" + Math.round(n.length * 44.1)));
		step("close embedded", function() {
			n.close();
			H.log("close embedded ok");
		});
		extractInfo("extract(ba,100)", n, 100, -2);
		extractInfo("extract(ba,100) again (sequential)", n, 100, -2);
		extractInfo("extract(ba,10,0)", n, 10, 0);
		extractInfo("extract(ba,10,5)", n, 10, 5);
		extractInfo("extract(ba,10) after explicit", n, 10, -2);
		extractInfo("extract(ba,10,-1)", n, 10, -1);
		extractInfo("extract(ba,10,-7)", n, 10, -7);
		extractInfo("extract(ba,10,1e9)", n, 10, 1e9);
		extractInfo("extract(ba,1e9,0)", n, 1e9, 0);
		extractInfo("extract(ba,0,0)", n, 0, 0);
		extractInfo("extract(ba,-5,0)", n, -5, 0);
		extractInfo("extract(ba,2.7,0)", n, 2.7, 0);
		extractInfo("extract(ba,10,2.6)", n, 10, 2.6);
		extractInfo("extract(ba,NaN,0)", n, Math.NaN, 0);
		extractInfo("extract(ba,10,NaN)", n, 10, Math.NaN);
		extractInfo("extract into pos 4", n, 3, 0, 4);
		extractInfo("extract into pos 8 (end)", n, 3, 0, 8);
		step("extract null target embedded", function() H.log("extract null embedded -> " + n.extract(null, 10)));
		step("extract past end position", function() {
			var ba = new ByteArray();
			var total = Math.round(n.length * 44.1);
			var r = n.extract(ba, 10, total - 3);
			H.log("extract(ba,10,total-3) -> " + r + " length=" + ba.length);
			var ba2 = new ByteArray();
			H.log("extract(ba,10,total) -> " + n.extract(ba2, 10, total) + " length=" + ba2.length);
			var ba3 = new ByteArray();
			H.log("extract(ba,10,total+5) -> " + n.extract(ba3, 10, total + 5) + " length=" + ba3.length);
		});
		step("extract little endian", function() {
			var ba = new ByteArray();
			ba.endian = flash.utils.Endian.LITTLE_ENDIAN;
			var r = n.extract(ba, 2, 0);
			ba.position = 0;
			H.log("extract LE -> " + r + " first=" + f3(ba.readFloat()) + " endian=" + ba.endian);
		});
		step("extract whole and stats", function() {
			var ba = new ByteArray();
			var r = n.extract(ba, 1e9, 0);
			ba.position = 0;
			var mx = 0.0, sum = 0.0, cnt = 0, nz = 0;
			while (ba.bytesAvailable >= 4) {
				var v = ba.readFloat();
				if (Math.abs(v) > mx)
					mx = Math.abs(v);
				sum += Math.abs(v);
				cnt++;
				if (v != 0)
					nz++;
			}
			H.log("whole -> " + r + " floats=" + cnt + " max=" + f3(mx) + " mean=" + f3(sum / cnt) + " nonzero=" + nz);
		});

		// ---- loadPCMFromByteArray
		step("pcm float stereo", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...100) {
				ba.writeFloat(i / 100);
				ba.writeFloat(-i / 100);
			}
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 100, "float", true, 44100);
			H.log("pcm float stereo: " + sprops(s) + " position=" + ba.position);
			var out = new ByteArray();
			var r = s.extract(out, 5, 0);
			out.position = 0;
			var v = [];
			while (out.bytesAvailable >= 4)
				v.push(f3(out.readFloat()));
			H.log("pcm float stereo extract -> " + r + " " + v.join(","));
			step("pcm again", function() {
				s.loadPCMFromByteArray(ba, 100, "float", true, 44100);
				H.log("pcm again ok " + sprops(s));
			});
			step("pcm then load", function() {
				s.load(new URLRequest(H.BASE + "/asset/noise.mp3"));
				H.log("pcm then load ok");
			});
			step("pcm then loadCompressed", function() {
				s.loadCompressedDataFromByteArray(new ByteArray(), 0);
				H.log("pcm then loadCompressed ok");
			});
		});
		step("pcm short mono 22050", function() {
			var s = new Sound();
			var ba = new ByteArray();
			ba.endian = flash.utils.Endian.LITTLE_ENDIAN;
			for (i in 0...50)
				ba.writeShort(i * 100);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 50, "short", false, 22050);
			H.log("pcm short mono 22050: " + sprops(s) + " position=" + ba.position);
			var out = new ByteArray();
			var r = s.extract(out, 6, 0);
			out.position = 0;
			var v = [];
			while (out.bytesAvailable >= 4)
				v.push(f3(out.readFloat()));
			H.log("pcm short mono extract -> " + r + " " + v.join(","));
		});
		step("pcm short BE", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...4)
				ba.writeShort(16384);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 2, "short", true, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 2, 0);
			out.position = 0;
			var v = [];
			while (out.bytesAvailable >= 4)
				v.push(f3(out.readFloat()));
			H.log("pcm short BE extract -> " + r + " " + v.join(",") + " length=" + s.length);
		});
		step("pcm too few bytes", function() {
			var s = new Sound();
			var ba = new ByteArray();
			ba.writeFloat(0.5);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 100, "float", true, 44100);
			H.log("pcm too few bytes: " + sprops(s) + " position=" + ba.position);
		});
		step("pcm from position", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...20)
				ba.writeFloat(i);
			ba.position = 8;
			s.loadPCMFromByteArray(ba, 3, "float", true, 44100);
			var out = new ByteArray();
			var r = s.extract(out, 3, 0);
			out.position = 0;
			var v = [];
			while (out.bytesAvailable >= 4)
				v.push(f3(out.readFloat()));
			H.log("pcm from position 8 -> " + r + " " + v.join(",") + " position after=" + ba.position + " " + sprops(s));
		});
		step("pcm bad format", function() {
			var s = new Sound();
			var ba = new ByteArray();
			ba.writeFloat(0);
			ba.writeFloat(0);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 1, "double", true, 44100);
			H.log("pcm bad format ok: " + sprops(s));
		});
		step("pcm null format", function() {
			var s = new Sound();
			var ba = new ByteArray();
			ba.writeFloat(0);
			ba.writeFloat(0);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 1, null, true, 44100);
			H.log("pcm null format ok: " + sprops(s));
		});
		step("pcm bad rate", function() {
			var s = new Sound();
			var ba = new ByteArray();
			ba.writeFloat(0);
			ba.writeFloat(0);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 1, "float", true, 12345);
			H.log("pcm bad rate ok: " + sprops(s));
		});
		step("pcm rate 8000", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...16)
				ba.writeFloat(0.25);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 8, "float", true, 8000);
			H.log("pcm rate 8000: " + sprops(s));
		});
		step("pcm rate 48000", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...16)
				ba.writeFloat(0.25);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 8, "float", true, 48000);
			H.log("pcm rate 48000: " + sprops(s));
		});
		step("pcm null bytes", function() {
			var s = new Sound();
			s.loadPCMFromByteArray(null, 1, "float", true, 44100);
			H.log("pcm null bytes ok");
		});
		step("pcm zero samples", function() {
			var s = new Sound();
			var ba = new ByteArray();
			s.loadPCMFromByteArray(ba, 0, "float", true, 44100);
			H.log("pcm zero samples: " + sprops(s));
			step("pcm zero then again", function() {
				s.loadPCMFromByteArray(ba, 0, "float", true, 44100);
				H.log("pcm zero then again ok");
			});
		});
		step("pcm then play", function() {
			var s = new Sound();
			var ba = new ByteArray();
			for (i in 0...4410 * 2)
				ba.writeFloat(0.1);
			ba.position = 0;
			s.loadPCMFromByteArray(ba, 4410, "float", true, 44100);
			var ch = s.play();
			H.log("pcm play -> " + qn(ch) + " length=" + s.length);
			if (ch != null)
				ch.stop();
		});

		// ---- SoundMixer
		step("SoundMixer defaults", function() {
			var sm:Dynamic = SoundMixer;
			H.log("audioPlaybackMode=" + sm.audioPlaybackMode + " useSpeakerphoneForVoice=" + sm.useSpeakerphoneForVoice);
		});
		for (v in ["voice", "ambient", "media", "VOICE", "bogus", "", null]) {
			step("audioPlaybackMode=" + v, function() {
				var sm:Dynamic = SoundMixer;
				sm.audioPlaybackMode = v;
				H.log("audioPlaybackMode set " + v + " -> " + sm.audioPlaybackMode);
			});
		}
		step("useSpeakerphoneForVoice=true", function() {
			var sm:Dynamic = SoundMixer;
			sm.useSpeakerphoneForVoice = true;
			H.log("useSpeakerphoneForVoice set true -> " + sm.useSpeakerphoneForVoice);
			sm.useSpeakerphoneForVoice = false;
			H.log("useSpeakerphoneForVoice set false -> " + sm.useSpeakerphoneForVoice);
		});

		// ---- flash.media package functions
		step("scanHardware", function() {
			var f:Dynamic = untyped __global__["flash.media.scanHardware"];
			H.log("scanHardware type=" + qn(f));
			if (f != null)
				H.log("scanHardware() -> " + f());
		});
		step("avSendToURL", function() {
			var f:Dynamic = untyped __global__["flash.media.avSendToURL"];
			H.log("avSendToURL type=" + qn(f));
			if (f != null) {
				step("avSendToURL(null,null)", function() H.log("avSendToURL(null,null) -> " + f(null, null)));
				step("avSendToURL(null,req)", function() H.log("avSendToURL(null,req) -> " + f(null, new URLRequest(H.BASE + "/data/blob?size=1"))));
				var af:Dynamic = untyped __global__["flash.system.AuthorizedFeatures"];
				H.log("AuthorizedFeatures type=" + qn(af));
				if (af != null) {
					step("new AuthorizedFeatures", function() {
						var a = Type.createInstance(af, []);
						H.log("AuthorizedFeatures instance " + qn(a));
						step("avSendToURL(af,req)", function() H.log("avSendToURL(af,req) -> " + f(a, new URLRequest(H.BASE + "/data/blob?size=1"))));
					});
				}
			}
		});

		// ---- ExternalInterface.marshallExceptions
		step("marshallExceptions", function() {
			H.log("marshallExceptions default=" + ExternalInterface.marshallExceptions + " available=" + ExternalInterface.available);
			ExternalInterface.marshallExceptions = true;
			H.log("marshallExceptions after set=" + ExternalInterface.marshallExceptions);
			ExternalInterface.marshallExceptions = false;
		});

		// ---- Transform.concatenatedColorTransform
		step("concatenatedColorTransform", function() {
			var a = new Sprite();
			var b = new Sprite();
			var c = new Shape();
			a.addChild(b);
			b.addChild(c);
			a.transform.colorTransform = new ColorTransform(0.5, 2, 1, 0.5, 10, -20, 300, 5);
			b.transform.colorTransform = new ColorTransform(0.5, 0.5, 2, 1, 40, 10, -10, -10);
			c.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 0, 0, 0, 0);
			H.log("detached c=" + ct(c.transform.concatenatedColorTransform));
			H.log("detached b=" + ct(b.transform.concatenatedColorTransform));
			H.log("detached a=" + ct(a.transform.concatenatedColorTransform));
			Lib.current.addChild(a);
			H.log("attached c=" + ct(c.transform.concatenatedColorTransform));
			H.log("attached b=" + ct(b.transform.concatenatedColorTransform));
			H.log("attached a=" + ct(a.transform.concatenatedColorTransform));
			H.log("root=" + ct(Lib.current.transform.concatenatedColorTransform));
			H.log("stage=" + ct(st.transform.concatenatedColorTransform));
			Lib.current.transform.colorTransform = new ColorTransform(0.25, 1, 1, 1, 3, 0, 0, 0);
			H.log("root tinted c=" + ct(c.transform.concatenatedColorTransform));
			H.log("root tinted root=" + ct(Lib.current.transform.concatenatedColorTransform));
			Lib.current.transform.colorTransform = new ColorTransform();
			var same = c.transform.concatenatedColorTransform == c.transform.concatenatedColorTransform;
			H.log("same object=" + same);
			var got = c.transform.concatenatedColorTransform;
			got.redMultiplier = 9;
			H.log("mutate copy -> " + ct(c.transform.concatenatedColorTransform));
			c.alpha = 0.5;
			H.log("alpha 0.5 c=" + ct(c.transform.concatenatedColorTransform) + " own=" + ct(c.transform.colorTransform));
			var tr = c.transform;
			H.log("transform keeps object=" + (tr == c.transform));
			Lib.current.removeChild(a);
			H.log("removed c=" + ct(c.transform.concatenatedColorTransform));
		});
		step("concatenated precision", function() {
			var a = new Sprite();
			var b = new Shape();
			a.addChild(b);
			a.transform.colorTransform = new ColorTransform(0.3, 1.7, 1, 1, 0.4, 100.6, 0, 0);
			b.transform.colorTransform = new ColorTransform(0.3, 1.7, 1, 1, 0.4, 100.6, 0, 0);
			H.log("precision a own=" + ct(a.transform.colorTransform) + " b concat=" + ct(b.transform.concatenatedColorTransform));
			a.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 200, -200, 0, 0);
			b.transform.colorTransform = new ColorTransform(1, 1, 1, 1, 200, -200, 0, 0);
			H.log("offset sum b concat=" + ct(b.transform.concatenatedColorTransform));
			a.transform.colorTransform = new ColorTransform(2, 2, 2, 2, 0, 0, 0, 0);
			b.transform.colorTransform = new ColorTransform(0.5, 3, 128, -1, 50, 50, 50, 50);
			H.log("mul b concat=" + ct(b.transform.concatenatedColorTransform) + " b own=" + ct(b.transform.colorTransform));
		});

		// ---- VideoStreamSettings
		step("VideoStreamSettings", function() {
			var v = new VideoStreamSettings();
			var d:Dynamic = v;
			H.log("vss default bandwidth=" + d.bandwidth + " codec=" + d.codec + " fps=" + d.fps + " height=" + d.height + " keyFrameInterval=" + d.keyFrameInterval
				+ " quality=" + d.quality + " width=" + d.width);
			v.setKeyFrameInterval(5);
			v.setMode(320, 240, 15);
			v.setQuality(50000, 80);
			H.log("vss set bandwidth=" + d.bandwidth + " fps=" + d.fps + " height=" + d.height + " keyFrameInterval=" + d.keyFrameInterval + " quality=" + d.quality
				+ " width=" + d.width);
			step("vss setKeyFrameInterval 0", function() {
				v.setKeyFrameInterval(0);
				H.log("kfi 0 -> " + d.keyFrameInterval);
			});
			step("vss setKeyFrameInterval 500", function() {
				v.setKeyFrameInterval(500);
				H.log("kfi 500 -> " + d.keyFrameInterval);
			});
			step("vss setKeyFrameInterval -1", function() {
				v.setKeyFrameInterval(-1);
				H.log("kfi -1 -> " + d.keyFrameInterval);
			});
			step("vss setKeyFrameInterval -7", function() {
				v.setKeyFrameInterval(-7);
				H.log("kfi -7 -> " + d.keyFrameInterval);
			});
			step("vss setMode -1", function() {
				v.setMode(-1, -1, -1);
				H.log("mode -1 -> " + d.width + "x" + d.height + "@" + d.fps);
			});
			step("vss setMode 0", function() {
				v.setMode(0, 0, 0);
				H.log("mode 0 -> " + d.width + "x" + d.height + "@" + d.fps);
			});
			step("vss setMode -5", function() {
				v.setMode(-5, 10, -5);
				H.log("mode -5 -> " + d.width + "x" + d.height + "@" + d.fps);
			});
			step("vss setMode 7.5fps", function() {
				v.setMode(100, 50, 7.5);
				H.log("mode 7.5 -> " + d.width + "x" + d.height + "@" + d.fps);
			});
			step("vss setMode NaN", function() {
				v.setMode(100, 50, Math.NaN);
				H.log("mode NaN -> " + d.width + "x" + d.height + "@" + d.fps);
			});
			step("vss setQuality 0,0", function() {
				v.setQuality(0, 0);
				H.log("q 0,0 -> " + d.bandwidth + "/" + d.quality);
			});
			step("vss setQuality 0,150", function() {
				v.setQuality(0, 150);
				H.log("q 0,150 -> " + d.bandwidth + "/" + d.quality);
			});
			step("vss setQuality -1,-1", function() {
				v.setQuality(-1, -1);
				H.log("q -1,-1 -> " + d.bandwidth + "/" + d.quality);
			});
			step("vss setQuality 1000,50", function() {
				v.setQuality(1000, 50);
				H.log("q 1000,50 -> " + d.bandwidth + "/" + d.quality);
			});
		});
		step("H264VideoStreamSettings", function() {
			var cls:Dynamic = untyped __global__["flash.media.H264VideoStreamSettings"];
			H.log("H264VideoStreamSettings type=" + qn(cls));
			var v:Dynamic = Type.createInstance(cls, []);
			H.log("h264 default codec=" + v.codec + " level=" + v.level + " profile=" + v.profile + " bandwidth=" + v.bandwidth + " fps=" + v.fps + " kfi=" + v.keyFrameInterval
				+ " quality=" + v.quality + " " + v.width + "x" + v.height + " is VSS=" + Std.isOfType(v, VideoStreamSettings));
			for (pl in [["main", "3.1"], ["baseline", "1b"], ["main", "5.1"], ["MAIN", "3"], ["high", "3"], ["main", "6"], ["main", "3.0"], ["main", "1.0"], [null, "3"], ["main", null],
				["main", ""], ["baseline", "2.2"]]) {
				step("setProfileLevel " + pl[0] + "," + pl[1], function() {
					v.setProfileLevel(pl[0], pl[1]);
					H.log("setProfileLevel " + pl[0] + "," + pl[1] + " -> profile=" + v.profile + " level=" + v.level);
				});
			}
			step("h264 setMode", function() {
				v.setMode(640, 480, 30);
				v.setQuality(0, 90);
				v.setKeyFrameInterval(10);
				H.log("h264 after set " + v.width + "x" + v.height + "@" + v.fps + " q=" + v.quality + " bw=" + v.bandwidth + " kfi=" + v.keyFrameInterval + " codec=" + v.codec);
			});
		});

		// ---- Video
		var vid = new Video();
		step("Video new", function() {
			H.log("video new videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight + " w=" + vid.width + " h=" + vid.height);
			vid.clear();
			H.log("video clear on new ok");
			vid.attachNetStream(null);
			H.log("video attachNetStream(null) on new ok");
		});
		step("Video attachCamera null", function() {
			vid.attachCamera(null);
			H.log("video attachCamera(null) ok videoWidth=" + vid.videoWidth);
		});
		step("Video attachCamera getCamera", function() {
			var cam = Camera.getCamera();
			H.log("getCamera=" + qn(cam));
			vid.attachCamera(cam);
			H.log("video attachCamera(getCamera()) ok");
		});
		Lib.current.addChild(vid);

		// ---- async part: Sound.load and Video/NetStream
		U.step("sound load ok", function(next) {
			var s = new Sound();
			var seen = [];
			var ctx = new SoundLoaderContext(2000, false);
			var log = function(e:Event) {
				seen.push(e.type);
				H.log("sound event " + e.type + ": " + sprops(s));
			};
			s.addEventListener(Event.OPEN, log);
			s.addEventListener(ProgressEvent.PROGRESS, log);
			s.addEventListener(Event.ID3, log);
			s.addEventListener(IOErrorEvent.IO_ERROR, log);
			s.addEventListener(Event.COMPLETE, function(e:Event) {
				log(e);
				step("close after complete", function() {
					s.close();
					H.log("close after complete ok " + sprops(s));
				});
				step("close twice", function() {
					s.close();
					H.log("close twice ok");
				});
				extractInfo("loaded extract(ba,4,0)", s, 4, 0);
				step("loaded play", function() {
					var ch = s.play();
					H.log("loaded play -> " + qn(ch));
					if (ch != null)
						ch.stop();
				});
				step("load again after close", function() {
					s.load(new URLRequest(H.BASE + "/asset/noise.mp3"));
					H.log("load again after close ok");
				});
				U.after(300, function() {
					H.log("after 300ms: " + sprops(s) + " events=" + seen.join(","));
					next();
				});
			});
			s.load(new URLRequest("/asset/noise.mp3"), ctx);
			H.log("after load() (relative url): " + sprops(s));
			step("load twice", function() {
				s.load(new URLRequest(H.BASE + "/asset/noise.mp3"));
				H.log("load twice ok");
			});
		});
		U.step("sound load 404", function(next) {
			var s = new Sound();
			var log = function(e:Event) {
				H.log("404 event " + e.type + ": " + sprops(s) + (Std.isOfType(e, IOErrorEvent) ? " text=" + cast(e, IOErrorEvent).text + " id=" + cast(e, IOErrorEvent).errorID : ""));
			};
			s.addEventListener(Event.OPEN, log);
			s.addEventListener(ProgressEvent.PROGRESS, log);
			s.addEventListener(Event.COMPLETE, log);
			s.addEventListener(IOErrorEvent.IO_ERROR, function(e:Event) {
				log(e);
				step("close after ioError", function() {
					s.close();
					H.log("close after ioError ok");
				});
				step("load after ioError", function() {
					s.load(new URLRequest(H.BASE + "/asset/noise.mp3"));
					H.log("load after ioError ok");
				});
				U.after(300, function() {
					H.log("404 after 300ms: " + sprops(s));
					next();
				});
			});
			s.load(new URLRequest(H.BASE + "/data/404"));
			H.log("404 after load(): " + sprops(s));
		});
		U.step("sound load slow then close", function(next) {
			var s = new Sound();
			var log = function(e:Event) {
				H.log("slow event " + e.type + ": " + sprops(s));
			};
			s.addEventListener(Event.OPEN, log);
			s.addEventListener(ProgressEvent.PROGRESS, log);
			s.addEventListener(Event.COMPLETE, log);
			s.addEventListener(IOErrorEvent.IO_ERROR, log);
			s.load(new URLRequest(H.BASE + "/asset/noise.mp3?delay=1.5"));
			H.log("slow after load(): " + sprops(s));
			var ch = s.play();
			H.log("slow play while loading -> " + qn(ch));
			U.after(400, function() {
				H.log("slow at 400ms: " + sprops(s));
				step("close while loading", function() {
					s.close();
					H.log("close while loading ok " + sprops(s));
				});
				step("load after close while loading", function() {
					s.load(new URLRequest(H.BASE + "/asset/noise.mp3"));
					H.log("load after close-while-loading ok");
				});
				U.after(2500, function() {
					H.log("slow at end: " + sprops(s));
					next();
				});
			});
		});
		U.step("sound load not-mp3", function(next) {
			var s = new Sound();
			var log = function(e:Event) {
				H.log("notmp3 event " + e.type + ": " + sprops(s));
			};
			s.addEventListener(Event.OPEN, log);
			s.addEventListener(ProgressEvent.PROGRESS, log);
			s.addEventListener(Event.COMPLETE, log);
			s.addEventListener(IOErrorEvent.IO_ERROR, log);
			s.load(new URLRequest(H.BASE + "/data/blob?size=3000"));
			U.after(800, function() {
				H.log("notmp3 at end: " + sprops(s));
				next();
			});
		});
		U.step("video netstream", function(next) {
			var nc = new NetConnection();
			nc.connect(null);
			var ns = new NetStream(nc);
			ns.client = {
				onMetaData: function(o:Dynamic) H.log("onMetaData " + o.width + "x" + o.height + " video videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight)
			};
			ns.addEventListener(NetStatusEvent.NET_STATUS, function(e:NetStatusEvent) {
				H.log("netStatus " + e.info.code + " videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
			});
			vid.attachNetStream(ns);
			H.log("after attach videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
			ns.play(H.BASE + "/asset/test_video.flv");
			H.log("after play videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
			U.after(1500, function() {
				H.log("at 1500ms videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight + " w=" + vid.width + " h=" + vid.height + " time=" + ns.time);
				var bd = new BitmapData(Std.int(vid.width), Std.int(vid.height), false, 0xFF00FF);
				bd.draw(vid);
				H.log("pixel before clear=" + StringTools.hex(bd.getPixel(10, 10), 6));
				vid.clear();
				H.log("after clear videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
				bd.fillRect(bd.rect, 0xFF00FF);
				bd.draw(vid);
				H.log("pixel after clear=" + StringTools.hex(bd.getPixel(10, 10), 6));
				U.after(300, function() {
					bd.fillRect(bd.rect, 0xFF00FF);
					bd.draw(vid);
					H.log("pixel 300ms after clear (stream playing)=" + StringTools.hex(bd.getPixel(10, 10), 6) + " videoWidth=" + vid.videoWidth);
					ns.pause();
					vid.attachNetStream(null);
					H.log("after attachNetStream(null) videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
					bd.fillRect(bd.rect, 0xFF00FF);
					bd.draw(vid);
					H.log("pixel after detach=" + StringTools.hex(bd.getPixel(10, 10), 6));
					ns.resume();
					U.after(300, function() {
						bd.fillRect(bd.rect, 0xFF00FF);
						bd.draw(vid);
						H.log("pixel 300ms after detach (stream resumed)=" + StringTools.hex(bd.getPixel(10, 10), 6) + " videoWidth=" + vid.videoWidth);
						vid.attachNetStream(ns);
						H.log("reattach videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
						U.after(200, function() {
							bd.fillRect(bd.rect, 0xFF00FF);
							bd.draw(vid);
							H.log("pixel after reattach=" + StringTools.hex(bd.getPixel(10, 10), 6) + " videoWidth=" + vid.videoWidth);
							ns.close();
							H.log("after ns.close videoWidth=" + vid.videoWidth + " videoHeight=" + vid.videoHeight);
							bd.fillRect(bd.rect, 0xFF00FF);
							bd.draw(vid);
							H.log("pixel after ns.close=" + StringTools.hex(bd.getPixel(10, 10), 6));
							next();
						});
					});
				});
			});
		});
		U.run();
	}
}
