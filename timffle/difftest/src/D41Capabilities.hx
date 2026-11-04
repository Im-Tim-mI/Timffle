/** Probe (no golden): every flash.system.Capabilities member, read by name so undocumented ones
 *  (_internal, cpuAddressSize) are reachable without Haxe externs. Values depend on the machine
 *  (resolution, OS, language); the point is the serverString layout and the constant members. */
class D41Capabilities {
	static var NAMES = [
		"_internal", "avHardwareDisable", "cpuAddressSize", "cpuArchitecture", "hasAccessibility",
		"hasAudio", "hasAudioEncoder", "hasEmbeddedVideo", "hasIME", "hasMP3", "hasPrinting",
		"hasScreenBroadcast", "hasScreenPlayback", "hasStreamingAudio", "hasStreamingVideo",
		"hasTLS", "hasVideoEncoder", "isDebugger", "isEmbeddedInAcrobat", "language", "languages",
		"localFileReadDisable", "manufacturer", "maxLevelIDC", "os", "pixelAspectRatio",
		"playerType", "screenColor", "screenDPI", "screenResolutionX", "screenResolutionY",
		"serverString", "supports32BitProcesses", "supports64BitProcesses", "touchscreenType",
		"version"
	];

	static function main() {
		H.init("d41capabilities");
		var cls:Dynamic = untyped __global__["flash.system.Capabilities"];
		for (n in NAMES) {
			H.attempt(n, function() {
				var v:Dynamic = Reflect.field(cls, n);
				var t:String = untyped __global__["flash.utils.getQualifiedClassName"](v);
				H.log(n + " (" + t + ") = " + Std.string(v));
			});
		}
		for (t in ["5.1", "7.1", "", "bogus"]) {
			H.attempt("hasMultiChannelAudio(" + t + ")", function() {
				H.log("hasMultiChannelAudio(" + t + ") = " + Std.string(cls.hasMultiChannelAudio(t)));
			});
		}
		H.attempt("hasMultiChannelAudio()", function() {
			H.log("hasMultiChannelAudio() = " + Std.string(cls.hasMultiChannelAudio()));
		});
		H.attempt("hasMultiChannelAudio(null)", function() {
			H.log("hasMultiChannelAudio(null) = " + Std.string(cls.hasMultiChannelAudio(null)));
		});
		H.done();
	}
}
