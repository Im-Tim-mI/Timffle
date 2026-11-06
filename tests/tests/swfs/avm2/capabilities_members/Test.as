package {
import flash.display.Sprite;
import flash.system.Capabilities;

// Every flash.system.Capabilities member. The expected values are those of Flash Player 32
// on a machine without accessibility aids, IME, printer, debugger or touchscreen
// (timffle/difftest/src/D41Capabilities.hx run on 32.0.0.465); machine-dependent members
// (cpuArchitecture, cpuAddressSize, supports64BitProcesses) are checked for consistency only.
public class Test extends Sprite {
    public function Test() {
        trace("_internal = " + Capabilities._internal);
        trace("avHardwareDisable = " + Capabilities.avHardwareDisable);
        trace("cpuAddressSize is 32 or 64: " + (Capabilities.cpuAddressSize == 32 || Capabilities.cpuAddressSize == 64));
        trace("cpuArchitecture is known: " + (["PowerPC", "x86", "SPARC", "ARM"].indexOf(Capabilities.cpuArchitecture) >= 0));
        trace("hasAccessibility = " + Capabilities.hasAccessibility);
        trace("hasAudio = " + Capabilities.hasAudio);
        trace("hasAudioEncoder = " + Capabilities.hasAudioEncoder);
        trace("hasEmbeddedVideo = " + Capabilities.hasEmbeddedVideo);
        trace("hasIME = " + Capabilities.hasIME);
        trace("hasMP3 = " + Capabilities.hasMP3);
        trace("hasPrinting = " + Capabilities.hasPrinting);
        trace("hasScreenBroadcast = " + Capabilities.hasScreenBroadcast);
        trace("hasScreenPlayback = " + Capabilities.hasScreenPlayback);
        trace("hasStreamingAudio = " + Capabilities.hasStreamingAudio);
        trace("hasStreamingVideo = " + Capabilities.hasStreamingVideo);
        trace("hasTLS = " + Capabilities.hasTLS);
        trace("hasVideoEncoder = " + Capabilities.hasVideoEncoder);
        trace("isDebugger = " + Capabilities.isDebugger);
        trace("isEmbeddedInAcrobat = " + Capabilities.isEmbeddedInAcrobat);
        trace("language = " + Capabilities.language);
        trace("localFileReadDisable = " + Capabilities.localFileReadDisable);
        trace("manufacturer = " + Capabilities.manufacturer);
        trace("maxLevelIDC = " + Capabilities.maxLevelIDC);
        trace("os = " + Capabilities.os);
        trace("pixelAspectRatio = " + Capabilities.pixelAspectRatio);
        trace("playerType = " + Capabilities.playerType);
        trace("screenColor = " + Capabilities.screenColor);
        trace("screenDPI = " + Capabilities.screenDPI);
        trace("screenResolutionX = " + Capabilities.screenResolutionX);
        trace("screenResolutionY = " + Capabilities.screenResolutionY);
        trace("supports32BitProcesses = " + Capabilities.supports32BitProcesses);
        trace("touchscreenType = " + Capabilities.touchscreenType);
        trace("version = " + Capabilities.version);

        trace("hasMultiChannelAudio('5.1') = " + Capabilities.hasMultiChannelAudio("5.1"));
        trace("hasMultiChannelAudio('7.1') = " + Capabilities.hasMultiChannelAudio("7.1"));
        trace("hasMultiChannelAudio('') = " + Capabilities.hasMultiChannelAudio(""));
        trace("hasMultiChannelAudio(null) = " + Capabilities.hasMultiChannelAudio(null));
        try {
            Capabilities["hasMultiChannelAudio"]();
            trace("hasMultiChannelAudio() did not throw");
        } catch (e:ArgumentError) {
            trace("hasMultiChannelAudio() threw ArgumentError #" + e.errorID);
        }

        var serverString:String = Capabilities.serverString;
        var keys:Array = [];
        var values:Object = {};
        for each (var pair:String in serverString.split("&")) {
            var kv:Array = pair.split("=");
            keys.push(kv[0]);
            values[kv[0]] = kv[1];
        }
        trace("serverString keys = " + keys.join(","));
        for each (var key:String in keys) {
            if (key == "ARCH" || key == "CAS" || key == "PR64") {
                continue;
            }
            trace("serverString " + key + " = " + values[key]);
        }
        trace("ARCH matches cpuArchitecture: " + (values["ARCH"] == Capabilities.cpuArchitecture));
        trace("CAS matches cpuAddressSize: " + (values["CAS"] == String(Capabilities.cpuAddressSize)));
        trace("PR64 matches supports64BitProcesses: " + (values["PR64"] == (Capabilities.supports64BitProcesses ? "t" : "f")));
        trace("V decodes to version: " + (decodeURIComponent(values["V"]) == Capabilities.version));
        trace("M decodes to manufacturer: " + (decodeURIComponent(values["M"]) == Capabilities.manufacturer));
        trace("OS decodes to os: " + (decodeURIComponent(values["OS"]) == Capabilities.os));
    }
}
}
