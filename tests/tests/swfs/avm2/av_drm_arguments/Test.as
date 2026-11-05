package {
    import flash.display.AVLoader;
    import flash.display.Sprite;
    import flash.media.AVCaptionStyle;
    import flash.media.AVInsertionResult;
    import flash.media.AVNetworkingParams;
    import flash.media.AVSegmentedSource;
    import flash.media.AVStream;
    import flash.media.AVURLLoader;
    import flash.media.AVURLStream;
    import flash.net.URLRequest;
    import flash.net.drm.DRMContentData;
    import flash.net.drm.DRMManager;
    import flash.net.drm.LoadVoucherSetting;
    import flash.system.AuthorizedFeaturesLoader;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;

    // Timffle: the synchronous answers of the Adobe Primetime classes (AVSegmentedSource,
    // AVStream, AVURLLoader, AVURLStream, AVLoader, AuthorizedFeaturesLoader) when
    // nothing has been authorized, and the argument checks of DRMManager. output.txt
    // was recorded with the real Flash Player 32 (twice, same output). The DRM events
    // are left out: this Flash Player has the Adobe Access module, this player has not.
    public class Test extends Sprite {
        private function v(x:*):String {
            return x === null ? "null" : typeof x == "string" ? "'" + x + "'" : String(x);
        }

        private function attempt(label:String, f:Function):void {
            try {
                trace(label + " -> " + v(f()));
            } catch (e:Error) {
                trace(label + " threw " + getQualifiedClassName(e) + " #" + e.errorID + (e.errorID == 0 ? " '" + e.message + "'" : ""));
            }
        }

        private function res(r:*):String {
            return r == null ? "null" : String(r.result);
        }

        public function Test() {
            trace("== AVSegmentedSource");
            var seg:AVSegmentedSource = new AVSegmentedSource();
            attempt("load", function():* { return res(seg.load("http://127.0.0.1:1/master.m3u8")); });
            attempt("load DASH", function():* { return res(seg.load("http://127.0.0.1:1/manifest.mpd", AVSegmentedSource.DASH, 7)); });
            attempt("load('')", function():* { return res(seg.load("")); });
            attempt("load(null)", function():* { return res(seg.load(null)); });
            attempt("loadManifest", function():* { return res(seg.loadManifest("#EXTM3U")); });
            attempt("loadWithBackgroundManifest", function():* { return res(seg.loadWithBackgroundManifest("a", "b", 0, AVSegmentedSource.HLS)); });
            attempt("getTimeline", function():* { return seg.getTimeline(); });
            attempt("getPeriodInfo(0)", function():* { return seg.getPeriodInfo(0); });
            attempt("getTrackCount", function():* { return seg.getTrackCount(0, AVSegmentedSource.VIDEO); });
            attempt("getABRProfileCount", function():* { return seg.getABRProfileCount(0); });
            attempt("getPerceivedBandwidth", function():* { return seg.getPerceivedBandwidth(); });
            attempt("getMediaPreferredStartTime", function():* { return seg.getMediaPreferredStartTime(); });
            attempt("selectTrack", function():* { return res(seg.selectTrack(0, AVSegmentedSource.AUDIO, 0)); });
            attempt("selectTrackString", function():* { return res(seg.selectTrackString(0, AVSegmentedSource.AUDIO_LANGUAGE, "en")); });
            attempt("setBandwidth", function():* { return res(seg.setBandwidth(1000000)); });
            attempt("setHoldAt", function():* { return res(seg.setHoldAt(10)); });
            attempt("setPauseAtPeriodEnd", function():* { return res(seg.setPauseAtPeriodEnd(0)); });
            attempt("clearPauseAtPeriodEnd", function():* { return res(seg.clearPauseAtPeriodEnd(0)); });
            attempt("releaseManifest", function():* { return res(seg.releaseManifest(1)); });
            attempt("removeByVirtualTime", function():* { return res(seg.removeByVirtualTime(0, 1)); });
            attempt("removeByLocalTime", function():* { return res(seg.removeByLocalTime(0, 0, 1, true)); });
            attempt("removeByVirtualTimeWithReplacement", function():* { return res(seg.removeByVirtualTimeWithReplacement(0, 1, false)); });
            attempt("setSubscribedTags", function():* { return res(seg.setSubscribedTags(["#EXT-X-CUE"])); });
            attempt("setSubscribedTagsForBackgroundManifest", function():* { return res(seg.setSubscribedTagsForBackgroundManifest([])); });
            attempt("setCuePointTags", function():* { return res(seg.setCuePointTags([])); });
            attempt("setSubscribedTags(null)", function():* { return res(seg.setSubscribedTags(null)); });
            attempt("insertByVirtualTime", function():* { return seg.insertByVirtualTime(5, 1); });
            attempt("insertByLocalTime", function():* { return seg.insertByLocalTime(0, 5, 1); });
            attempt("networkingParams", function():* { return seg.networkingParams + " readSetCookieHeader=" + seg.networkingParams.readSetCookieHeader; });
            attempt("networkingParams = new(false)", function():* { var p:AVNetworkingParams = new AVNetworkingParams(false); seg.networkingParams = p; return "same=" + (seg.networkingParams === p) + " readSetCookieHeader=" + seg.networkingParams.readSetCookieHeader; });
            attempt("networkingParams = null", function():* { seg.networkingParams = null; return "ok"; });
            attempt("cookieHeader/masterUpdateInterval/useRedirectedUrl", function():* { seg.cookieHeader = "a=b"; seg.masterUpdateInterval = 5000; seg.useRedirectedUrl = true; return "ok"; });
            attempt("addCustomHeader(X, [1])", function():* { seg.addCustomHeader("X-Test", new <String>["1"]); return "ok"; });
            attempt("addCustomHeader(X, [])", function():* { seg.addCustomHeader("X-Test", new Vector.<String>()); return "ok"; });
            attempt("addCustomHeader(null, null)", function():* { seg.addCustomHeader(null, null); return "ok"; });
            attempt("dispose", function():* { seg.dispose(); return "ok"; });
            attempt("load after dispose", function():* { return res(seg.load("http://127.0.0.1:1/x.m3u8")); });

            trace("== AVStream");
            attempt("new AVStream(null)", function():* { return new AVStream(null); });
            var stream:AVStream = new AVStream(new AVSegmentedSource());
            attempt("play", function():* { return res(stream.play()); });
            attempt("pause", function():* { return res(stream.pause()); });
            attempt("resume", function():* { return stream.resume(); });
            attempt("seek", function():* { return res(stream.seek(10)); });
            attempt("seekToKeyFrame", function():* { return res(stream.seekToKeyFrame(10, false)); });
            attempt("seekToLivePoint", function():* { return res(stream.seekToLivePoint()); });
            attempt("seekToLocalTime", function():* { return res(stream.seekToLocalTime(0, 1)); });
            attempt("fastForward", function():* { return res(stream.fastForward(2)); });
            attempt("rewind", function():* { return res(stream.rewind(2)); });
            attempt("step", function():* { return res(stream.step(1)); });
            attempt("setPlaySpeed", function():* { stream.setPlaySpeed(2, 0); return "ok"; });
            attempt("playState", function():* { return stream.playState.state; });
            attempt("time/frameTime/currentFPS", function():* { return stream.time + "," + stream.frameTime + "," + stream.currentFPS; });
            attempt("bufferLength/backBufferLength/clientLivePoint", function():* { return stream.bufferLength + "," + stream.backBufferLength + "," + stream.clientLivePoint; });
            attempt("droppedFrames/decoderType/renderType", function():* { return stream.droppedFrames + "," + stream.decoderType + "," + stream.renderType; });
            attempt("useHardwareDecoder", function():* { var a:* = stream.useHardwareDecoder; stream.useHardwareDecoder = false; return a + "/" + stream.useHardwareDecoder; });
            attempt("captionsEnabled", function():* { var a:* = stream.captionsEnabled; stream.captionsEnabled = true; return a + "/" + stream.captionsEnabled; });
            attempt("volume", function():* { var a:* = stream.volume; stream.volume = 0.25; var b:* = stream.volume; stream.volume = 5; var c:* = stream.volume; stream.volume = -1; return [a, b, c, stream.volume].join(","); });
            attempt("bufferTime/initialBufferTime/backBufferTime", function():* { stream.bufferTime = 3; stream.initialBufferTime = 1; stream.backBufferTime = -1; return "ok"; });
            attempt("captionStyle = null", function():* { stream.captionStyle = null; return "ok"; });
            attempt("captionStyle = new", function():* { stream.captionStyle = new AVCaptionStyle(); return "ok"; });
            attempt("dispose", function():* { stream.dispose(); return "ok"; });
            attempt("play after dispose", function():* { return res(stream.play()); });

            trace("== AVURLLoader / AVURLStream / AVLoader");
            var ul:AVURLLoader = new AVURLLoader();
            attempt("AVURLLoader.stream", function():* { return getQualifiedClassName(ul.stream) + " same=" + (ul.stream == ul.stream) + " connected=" + ul.stream.connected; });
            attempt("AVURLLoader.dataFormat", function():* { return ul.dataFormat; });
            attempt("AVURLLoader.load", function():* { ul.cookieHeader = "a=b"; ul.load(new URLRequest("test.txt")); return "ok"; });
            attempt("AVURLLoader.load(null)", function():* { ul.load(null); return "ok"; });
            attempt("AVURLLoader.close", function():* { ul.close(); return "ok"; });
            attempt("new AVURLLoader(request)", function():* { return new AVURLLoader(new URLRequest("test.txt")); });
            var us:AVURLStream = new AVURLStream();
            attempt("AVURLStream.load", function():* { us.cookieHeader = "a=b"; us.load(new URLRequest("test.txt")); return "ok"; });
            attempt("AVURLStream.load(null)", function():* { us.load(null); return "ok"; });
            attempt("AVURLStream.connected", function():* { return us.connected; });
            attempt("AVURLStream.close", function():* { us.close(); return "ok"; });
            attempt("AVLoader.load", function():* { new AVLoader().load(new URLRequest("test.txt")); return "ok"; });

            trace("== AuthorizedFeaturesLoader (synchronous part)");
            attempt("authorizedFeatures", function():* { return new AuthorizedFeaturesLoader().authorizedFeatures; });
            attempt("loadAuthorizedFeaturesFromData(null)", function():* { new AuthorizedFeaturesLoader().loadAuthorizedFeaturesFromData(null); return "ok"; });

            trace("== DRMManager argument checks");
            var m:DRMManager = DRMManager.getDRMManager();
            var cd:DRMContentData = new DRMContentData();
            attempt("loadVoucher(cd, bogus)", function():* { m.loadVoucher(cd, "bogus"); return "ok"; });
            attempt("loadVoucher(null, allowServer)", function():* { m.loadVoucher(null, LoadVoucherSetting.ALLOW_SERVER); return "ok"; });
            attempt("loadVoucher(cd, null)", function():* { m.loadVoucher(cd, null); return "ok"; });
            attempt("loadPreviewVoucher(null)", function():* { m.loadPreviewVoucher(null); return "ok"; });
            attempt("returnVoucher(null, ...)", function():* { m.returnVoucher(null, true, "l", "p"); return "ok"; });
            attempt("returnVoucher(url, null, null)", function():* { m.returnVoucher("http://127.0.0.1:1/", true, null, null); return "ok"; });
            attempt("new DRMContentData(bytes)", function():* { var b:ByteArray = new ByteArray(); b.writeUTFBytes("not drm metadata"); var d:DRMContentData = new DRMContentData(b); return [d.serverURL, d.licenseID, d.domain, d.authenticationMethod].join(","); });
            attempt("DRMContentData().getVoucherAccessInfo()", function():* { return new DRMContentData().getVoucherAccessInfo(); });
        }
    }
}
