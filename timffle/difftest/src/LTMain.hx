import flash.Lib;
import flash.display.Loader;
import flash.events.Event;
import flash.events.HTTPStatusEvent;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.TextEvent;
import flash.net.URLRequest;
import flash.utils.ByteArray;

/** Loader timing probe: in which frame phase does a Loader construct its content, and when do
 *  `init`/`httpStatus`/`complete` fire relative to the frame events of the loading movie?
 *
 *  The root prints every `enterFrame`/`frameConstructed`/`exitFrame` with the Loader's state
 *  (`content`, `numChildren`, `contentLoaderInfo.bytesLoaded`); the child (loadtime/Child.as,
 *  compiled with asc.jar) reports its constructor, `added`/`addedToStage`, frame-1 script and its
 *  own first frame events through `loaderInfo.sharedEvents`. Variants (compile-time defines; see
 *  loadtime/build.sh, which also puts the trace() builds into tests/tests/swfs/avm2/):
 *    -D bytes   loadBytes() the child (embedded as resource "child") instead of load()
 *    -D big     the 300 KB child (ltchildbig.swf), served in chunks so the download spans frames
 *    -D orphan  the Loader is never added to the display list
 *    -D grand   the child's constructor loadBytes a grandchild (ltchildgrand.swf)
 *  Built with -D harness it reports to the difftest server; without, it traces (Ruffle regression test). */
class LTMain {
	static var n = 0;
	static var loader:Loader;
	static var completeFrame = -1;
	static var progressCount = 0;
	static var finished = false;
	/** The frame in which the last byte arrived (`progress` with all bytes). */
	static var dl = -1;

	/** The trace build (Ruffle regression test) prints frames relative to the frame of the last
	 *  byte (`D+k`) and nothing before it: when the bytes arrive depends on the network (the test
	 *  framework reads a local file at once, the difftest server answers a frame later), what
	 *  happens after it is the Loader's own timing. loadtime/lt_regression_output.py turns a golden
	 *  into that form. */
	static function line(s:String) {
		#if !harness
		if (dl < 0)
			return;
		#end
		if (!finished)
			Out.line(s);
	}

	static function f():String {
		#if harness
		return "" + n;
		#else
		return "D+" + (n - dl);
		#end
	}

	static function st():String {
		var c = "null";
		try {
			c = loader.content == null ? "null" : "set";
		} catch (e:flash.errors.Error) {
			c = "Error#" + e.errorID;
		}
		var info = loader.contentLoaderInfo;
		var loaded = info.bytesTotal == 0 ? "none" : info.bytesLoaded == 0 ? "0" : info.bytesLoaded < info.bytesTotal ? "partial" : "all";
		return "content=" + c + " numChildren=" + loader.numChildren + " loaded=" + loaded;
	}

	static function ev(name:String) {
		line("event " + name + " in frame " + f() + " " + st());
	}

	static function main() {
		var name = "lt"
			#if bytes + "bytes" #else + "load" #end
			#if big + "_big" #end
			#if orphan + "_orphan" #end
			#if grand + "_grand" #end;
		Out.start(name);
		var root = Lib.current;
		loader = new Loader();
		var info = loader.contentLoaderInfo;
		info.sharedEvents.addEventListener("lt", function(e:TextEvent) {
			line("  " + e.text + " (frame " + f() + ")");
		});
		info.addEventListener(Event.OPEN, function(_) ev("open"));
		info.addEventListener(ProgressEvent.PROGRESS, function(e:ProgressEvent) {
			progressCount++;
			#if harness
			line("~ progress " + e.bytesLoaded + "/" + e.bytesTotal + " in frame " + n);
			#end
			if (progressCount == 1)
				ev("progress(first)");
			if (e.bytesLoaded == e.bytesTotal) {
				dl = n;
				ev("progress(all bytes)");
			}
		});
		info.addEventListener(Event.INIT, function(_) ev("init"));
		info.addEventListener(HTTPStatusEvent.HTTP_STATUS, function(e:HTTPStatusEvent) {
			#if harness
			line("~ httpStatus " + e.status);
			#end
			ev("httpStatus");
		});
		info.addEventListener(Event.COMPLETE, function(_) {
			ev("complete");
			completeFrame = n;
		});
		info.addEventListener(IOErrorEvent.IO_ERROR, function(_) ev("ioError"));

		root.addEventListener(Event.ENTER_FRAME, function(_) {
			n++;
			line("enterFrame " + f() + " " + st());
		});
		root.addEventListener(Event.FRAME_CONSTRUCTED, function(_) line("frameConstructed " + f() + " " + st()));
		root.addEventListener(Event.EXIT_FRAME, function(_) {
			line("exitFrame " + f() + " " + st());
			if (!finished && ((completeFrame >= 0 && n >= completeFrame + 2) || n >= 30)) {
				line("progress events: " + (progressCount >= 2 ? ">=2" : "" + progressCount));
				finished = true;
				Out.finish();
			}
		});

		#if !orphan
		root.addChild(loader);
		#end
		line("before load " + st());
		#if bytes
		var bytes:ByteArray = haxe.Resource.getBytes("child").getData();
		loader.loadBytes(bytes);
		#else
		var file = #if grand "ltchildgrand" #elseif big "ltchildbig" #else "ltchild" #end;
		#if harness
		var url = H.BASE + "/asset/" + file + ".swf" #if big + "?chunks=4&cdelay=0.25" #end;
		#else
		var url = file + ".swf";
		#end
		loader.load(new URLRequest(url));
		#end
		line("after load " + st());
	}
}
