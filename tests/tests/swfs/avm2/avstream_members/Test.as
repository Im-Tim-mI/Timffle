package {
import flash.display.Sprite;
import flash.utils.getQualifiedClassName;
import flash.media.AVInsertionResult;
import flash.media.AVNetworkingParams;
import flash.media.AVResult;
import flash.media.AVSegmentedSource;
import flash.media.AVSource;
import flash.media.AVStream;
import flash.media.AVURLLoader;
import flash.media.AVURLStream;
import flash.net.URLRequest;
import flash.system.AuthorizedFeatures;
import flash.utils.describeType;

// Flash Player without Adobe Primetime authorization: the AV classes exist
// and are configurable, but nothing can be enabled; the result codes are the
// ones Flash Player 32 gives (measured, see av_drm_arguments) and the AV
// loaders refuse to load (#2037).
public class Test extends Sprite {
    public function Test() {
        trace("== AVSource");
        var source:AVSource = new AVSource();
        source.dispose();
        source.dispose();
        trace("AVSource dispose twice ok");

        trace("== AVSegmentedSource");
        var seg:AVSegmentedSource = new AVSegmentedSource();
        trace("load = " + seg.load("http://example.invalid/master.m3u8").result + " (PLAYBACK_NOT_ENABLED = " + AVResult.PLAYBACK_NOT_ENABLED + ")");
        trace("load DASH = " + seg.load("http://example.invalid/manifest.mpd", AVSegmentedSource.DASH, 7).result);
        try {
            seg.load(null);
            trace("load(null) did not throw");
        } catch (e:Error) {
            trace("load(null) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        trace("loadManifest = " + seg.loadManifest("#EXTM3U").result);
        trace("loadWithBackgroundManifest = " + seg.loadWithBackgroundManifest("a", "b", 0, AVSegmentedSource.HLS).result);
        trace("getTimeline = " + seg.getTimeline());
        trace("getBackgroundTimeline = " + seg.getBackgroundTimeline());
        trace("getPeriodInfo(0) = " + seg.getPeriodInfo(0));
        trace("getTrackCount(0, video) = " + seg.getTrackCount(0, AVSegmentedSource.VIDEO));
        trace("getTrackInfo = " + seg.getTrackInfo(0, AVSegmentedSource.AUDIO, 0));
        trace("getABRProfileCount(0) = " + seg.getABRProfileCount(0));
        trace("getABRProfileInfoAtIndex = " + seg.getABRProfileInfoAtIndex(0, 0));
        trace("getCuePoint = " + seg.getCuePoint(0, 0));
        trace("getSubscribedTag = " + seg.getSubscribedTag(0, 0));
        trace("getTimelineSubscribedTag = " + seg.getTimelineSubscribedTag(0));
        trace("getPerceivedBandwidth = " + seg.getPerceivedBandwidth());
        trace("getMediaPreferredStartTime = " + seg.getMediaPreferredStartTime());
        trace("selectTrack = " + seg.selectTrack(0, AVSegmentedSource.AUDIO, 0).result);
        trace("selectTrackString = " + seg.selectTrackString(0, AVSegmentedSource.AUDIO_LANGUAGE, "en").result);
        trace("setBandwidth = " + seg.setBandwidth(1000000).result);
        trace("setHoldAt = " + seg.setHoldAt(10).result);
        trace("setPauseAtPeriodEnd = " + seg.setPauseAtPeriodEnd(0).result);
        trace("clearPauseAtPeriodEnd = " + seg.clearPauseAtPeriodEnd(0).result);
        trace("releaseManifest = " + seg.releaseManifest(1).result);
        trace("removeByVirtualTime = " + seg.removeByVirtualTime(0, 1));
        trace("removeByLocalTime = " + seg.removeByLocalTime(0, 0, 1, true));
        trace("removeByVirtualTimeWithReplacement = " + seg.removeByVirtualTimeWithReplacement(0, 1, false));
        trace("setSubscribedTags = " + seg.setSubscribedTags(["#EXT-X-CUE"]).result);
        trace("setSubscribedTagsForBackgroundManifest = " + seg.setSubscribedTagsForBackgroundManifest([]).result);
        trace("setCuePointTags = " + seg.setCuePointTags([]).result);
        try {
            seg.setSubscribedTags(null);
            trace("setSubscribedTags(null) did not throw");
        } catch (e:Error) {
            trace("setSubscribedTags(null) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        var ins:AVInsertionResult = seg.insertByVirtualTime(5, 1);
        trace("insertByVirtualTime = " + ins);
        trace("insertByLocalTime = " + seg.insertByLocalTime(0, 5, 1));
        trace("networkingParams = " + seg.networkingParams + ", readSetCookieHeader = " + seg.networkingParams.readSetCookieHeader);
        var params:AVNetworkingParams = new AVNetworkingParams(true);
        seg.networkingParams = params;
        trace("networkingParams after set is the same object: " + (seg.networkingParams === params));
        try {
            seg.networkingParams = null;
            trace("networkingParams = null did not throw");
        } catch (e:Error) {
            trace("networkingParams = null threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        seg.cookieHeader = "a=b";
        seg.masterUpdateInterval = 5000;
        seg.useRedirectedUrl = true;
        trace("configuration setters ok");
        try {
            seg.addCustomHeader("X-Test", new <String>["1"]);
            trace("addCustomHeader did not throw");
        } catch (e:Error) {
            trace("addCustomHeader threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        try {
            seg.addCustomHeader(null, null);
            trace("addCustomHeader(null) did not throw");
        } catch (e:Error) {
            trace("addCustomHeader(null) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        seg.dispose();
        trace("dispose ok, load after dispose = " + seg.load("http://example.invalid/x.m3u8").result);

        trace("== AVStream");
        try {
            new AVStream(null);
            trace("new AVStream(null) did not throw");
        } catch (e:Error) {
            trace("new AVStream(null) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        var stream:AVStream = new AVStream(new AVSegmentedSource());
        trace("play = " + stream.play().result);
        trace("pause = " + stream.pause().result);
        trace("resume = " + stream.resume());
        trace("seek = " + stream.seek(10).result);
        trace("seekToKeyFrame = " + stream.seekToKeyFrame(10, false).result);
        trace("seekToLivePoint = " + stream.seekToLivePoint().result);
        trace("seekToLocalTime = " + stream.seekToLocalTime(0, 1).result);
        trace("fastForward = " + stream.fastForward(2).result);
        trace("rewind = " + stream.rewind(2).result);
        trace("step = " + stream.step(1).result);
        stream.setPlaySpeed(2, 0);
        trace("setPlaySpeed ok");
        trace("playState.state = " + stream.playState.state);
        trace("time = " + stream.time + ", frameTime = " + stream.frameTime + ", currentFPS = " + stream.currentFPS);
        trace("bufferLength = " + stream.bufferLength + ", backBufferLength = " + stream.backBufferLength + ", clientLivePoint = " + stream.clientLivePoint);
        trace("droppedFrames = " + stream.droppedFrames);
        trace("decoderType = " + stream.decoderType + ", renderType = " + stream.renderType);
        trace("useHardwareDecoder = " + stream.useHardwareDecoder);
        stream.useHardwareDecoder = false;
        trace("useHardwareDecoder after set = " + stream.useHardwareDecoder);
        trace("captionsEnabled = " + stream.captionsEnabled);
        stream.captionsEnabled = true;
        trace("captionsEnabled after set = " + stream.captionsEnabled);
        trace("volume = " + stream.volume);
        stream.volume = 0.25;
        trace("volume after set 0.25 = " + stream.volume);
        stream.volume = 5;
        trace("volume after set 5 = " + stream.volume);
        stream.volume = -1;
        trace("volume after set -1 = " + stream.volume);
        stream.bufferTime = 3;
        stream.initialBufferTime = 1;
        stream.backBufferTime = 30;
        trace("buffer setters ok");
        try {
            stream.captionStyle = null;
            trace("captionStyle = null did not throw");
        } catch (e:Error) {
            trace("captionStyle = null threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        stream.dispose();
        trace("dispose ok, play after dispose = " + stream.play().result);

        trace("== AVURLLoader");
        var loader:AVURLLoader = new AVURLLoader();
        trace("stream = " + loader.stream + ", dataFormat = " + loader.dataFormat);
        loader.cookieHeader = "a=b";
        try {
            loader.load(new URLRequest("test.txt"));
            trace("load did not throw");
        } catch (e:Error) {
            trace("load threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        try {
            loader.load(null);
            trace("load(null) did not throw");
        } catch (e:Error) {
            trace("load(null) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        try {
            loader.close();
            trace("close did not throw");
        } catch (e:Error) {
            trace("close threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        try {
            new AVURLLoader(new URLRequest("test.txt"));
            trace("new AVURLLoader(request) did not throw");
        } catch (e:Error) {
            trace("new AVURLLoader(request) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        loader.addEventListener("complete", function(e:*):void {});
        trace("hasEventListener(complete) = " + loader.hasEventListener("complete"));

        trace("== AVURLStream");
        var urlStream:AVURLStream = new AVURLStream();
        urlStream.cookieHeader = "a=b";
        trace("connected = " + urlStream.connected);
        try {
            urlStream.load(new URLRequest("test.txt"));
            trace("load did not throw");
        } catch (e:Error) {
            trace("load threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        trace("connected after load = " + urlStream.connected);
        try {
            urlStream.close();
            trace("close did not throw");
        } catch (e:Error) {
            trace("close threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }

        trace("== AuthorizedFeatures");
        var methods:XMLList = describeType(AuthorizedFeatures).factory.method.@name;
        var names:Array = [];
        for each (var n:String in methods) {
            names.push(n);
        }
        names.sort();
        trace("methods = " + names.join(","));
    }
}
}
