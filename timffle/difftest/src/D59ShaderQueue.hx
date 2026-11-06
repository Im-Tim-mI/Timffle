/** Probe (no golden): ShaderJob asynchronous queue in Flash Player 32 — completion timing of several
 *  queued jobs, ByteArray/Vector targets, a disposed BitmapData target, and whether cancel() of a
 *  queued job stalls the queue (D58 saw jobs after a cancelled one never complete). Build with
 *  -swf-version 32; runs without input. */
import flash.Lib;
import flash.display.*;
import flash.events.Event;
import flash.events.ShaderEvent;
import flash.utils.ByteArray;

@:file("../../../tests/tests/swfs/avm2/pixelbender_shaderdata/simple_shader.pbj")
class SimplePbj2 extends ByteArray {}

class D59ShaderQueue {
	static var qn:Dynamic;
	static var frame = 0;
	static var startFrame = 0;

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			H.log(label + " THREW " + qn(e) + " #" + e.errorID + " " + e.message);
		}
	}

	static function makeShader():Shader {
		var sh = new Shader(new SimplePbj2());
		untyped sh.data.radius.value = [100];
		untyped sh.data.otherParam.value = [0];
		return sh;
	}

	static function hexp(bd:BitmapData):String {
		return StringTools.hex(bd.getPixel32(0, 0), 8);
	}

	static function phase2() {
		var sh = makeShader();
		startFrame = frame;
		var bd3 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobC = new ShaderJob(sh, bd3);
		jobC.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobC complete (cancelled!) frame+" + (frame - startFrame));
		});
		step("start async then cancel", function() {
			jobC.start();
			H.log("C progress after start=" + jobC.progress);
			jobC.cancel();
			H.log("after cancel progress=" + jobC.progress + " pixel=" + hexp(bd3));
		});
		step("restart after cancel", function() {
			jobC.start(true);
			H.log("restart after cancel ok pixel=" + hexp(bd3) + " progress=" + jobC.progress);
		});
		step("cancel after sync complete then start", function() {
			jobC.cancel();
			H.log("progress after cancel of finished=" + jobC.progress);
			jobC.start(true);
			H.log("start after cancel of finished ok progress=" + jobC.progress);
		});
		var bd4 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobG = new ShaderJob(sh, bd4);
		jobG.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobG complete frame+" + (frame - startFrame) + " pixel=" + hexp(bd4));
		});
		var bd5 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobH = new ShaderJob(sh, bd5);
		jobH.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobH complete frame+" + (frame - startFrame) + " pixel=" + hexp(bd5));
		});
		step("start G, cancel a fresh queued job, start H", function() {
			jobG.start();
			var jobX = new ShaderJob(sh, new BitmapData(2, 2));
			jobX.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
				H.log("jobX complete (cancelled!)");
			});
			jobX.start();
			jobX.cancel();
			jobH.start();
			H.log("G, X(cancelled), H started");
		});
		haxe.Timer.delay(function() {
			H.log("# phase2 end frames elapsed=" + (frame - startFrame) + " G progress=" + jobG.progress + " H progress=" + jobH.progress);
			H.done();
		}, 1500);
	}

	static function main() {
		H.init("d59shaderqueue", 20000);
		qn = untyped __global__["flash.utils.getQualifiedClassName"];
		Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) {
			frame++;
			if (frame - startFrame <= 3) H.log("# enterFrame " + frame);
		});
		var sh = makeShader();
		var bd2 = new BitmapData(4, 4, true, 0xFF0000FF);
		var jobA = new ShaderJob(sh, bd2);
		jobA.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobA complete frame+" + (frame - startFrame) + " pixel=" + hexp(bd2));
		});
		var ba4 = new ByteArray();
		ba4.writeByte(1);
		ba4.position = 1;
		var jobD = new ShaderJob(sh, ba4, 1, 1);
		jobD.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			ba4.position = 0;
			H.log("jobD complete frame+" + (frame - startFrame) + " byteArray same=" + (e.byteArray == ba4) + " bitmapData=" + e.bitmapData + " vector=" + e.vector + " length=" + ba4.length + " f0=" + ba4.readFloat() + " progress=" + jobD.progress);
		});
		var vec5 = new flash.Vector<Float>();
		vec5.push(7);
		var jobE = new ShaderJob(sh, vec5, 1, 1);
		jobE.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobE complete frame+" + (frame - startFrame) + " vector same=" + (e.vector == vec5) + " length=" + vec5.length + " v0=" + vec5[0]);
		});
		var bdF = new BitmapData(2, 2);
		var jobF = new ShaderJob(sh, bdF);
		jobF.addEventListener(ShaderEvent.COMPLETE, function(e:ShaderEvent) {
			H.log("jobF complete (disposed target) frame+" + (frame - startFrame) + " bitmapData same=" + (e.bitmapData == bdF) + " progress=" + jobF.progress);
		});
		step("start A, E, D, F", function() {
			jobA.start();
			jobE.start();
			jobD.start();
			jobF.start();
			bdF.dispose();
			H.log("started A E D F (F target disposed) at frame " + frame + " D position=" + ba4.position);
		});
		var baPos = new ByteArray();
		baPos.writeInt(0);
		baPos.writeInt(0);
		baPos.position = 4;
		var jobP = new ShaderJob(sh, baPos, 1, 1);
		step("sync bytearray position", function() {
			jobP.start(true);
			H.log("sync bytearray with position 4 before: length=" + baPos.length + " position=" + baPos.position);
		});
		var vecPos = new flash.Vector<Float>();
		for (i in 0...10) vecPos.push(i);
		var jobV = new ShaderJob(sh, vecPos, 1, 1);
		step("sync vector longer", function() {
			jobV.start(true);
			H.log("sync vector longer: length=" + vecPos.length + " v4..5=" + vecPos[4] + "," + vecPos[5]);
		});
		var fixedVec = new flash.Vector<Float>(2, true);
		var jobFx = new ShaderJob(sh, fixedVec, 1, 1);
		step("sync fixed vector", function() {
			jobFx.start(true);
			H.log("sync fixed vector: length=" + fixedVec.length + " fixed=" + fixedVec.fixed);
		});
		haxe.Timer.delay(phase2, 800);
	}
}
