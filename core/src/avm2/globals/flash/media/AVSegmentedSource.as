package flash.media {
    // Timffle: the HLS/DASH manifest source of the Adobe Primetime player
    // (see AVStream.as). Loading a manifest is part of the playback that
    // `AuthorizedFeatures.enableHLSPlayback()` unlocks, and nothing is ever
    // unlocked on this player, so no manifest is ever loaded. The result
    // codes are the ones Flash Player 32 gives a source in that state
    // (measured, tests/tests/swfs/avm2/av_drm_arguments): the load and track
    // calls, `setHoldAt` and `releaseManifest` answer
    // `AVResult.WAITING_FOR_INIT` (17), `setBandwidth` and the period-end
    // pauses `GENERIC_ERROR` (6), the tag setters `SUCCESS` (0); the remove
    // and insert calls return null. The timeline, period, track, profile, cue
    // point and tag queries answer the way they do for a source with no
    // manifest (null objects, zero counts, no bandwidth measured, no preferred
    // start time). `addCustomHeader()` is `ArgumentError #2004` for every
    // argument, and a new `networkingParams` object is not taken (the getter
    // keeps the source's own); `useRedirectedUrl`, `cookieHeader` and
    // `masterUpdateInterval` are stored. A null URL or tag list is
    // `TypeError #2007`.
    [API("688")]
    public class AVSegmentedSource extends AVSource {
        public static const AUDIO:String = "audio";
        public static const AUDIO_DESCRIPTION:String = "audiodescription";
        public static const AUDIO_LANGUAGE:String = "audiolanguage";
        public static const AUDIO_PID:String = "audiopid";
        public static const DASH:String = "DASH";
        public static const DATA:String = "data";
        public static const DATA_DESCRIPTION:String = "datadescription";
        public static const HLS:String = "HLS";
        public static const VIDEO:String = "video";
        public static const VIDEO_DESCRIPTION:String = "videodescription";

        private var _useRedirectedUrl:Boolean = false;
        private var _networkingParams:AVNetworkingParams = new AVNetworkingParams();
        private var _cookieHeader:String = null;
        private var _masterUpdateInterval:int = 0;

        public function AVSegmentedSource() {
            super();
        }

        private function waiting():AVResult {
            return new AVResult(AVResult.WAITING_FOR_INIT);
        }

        private function failed():AVResult {
            return new AVResult(AVResult.GENERIC_ERROR);
        }

        public function addCustomHeader(headerName:String, args:Vector.<String>):void {
            Error.throwError(ArgumentError, 2004);
        }

        public function clearPauseAtPeriodEnd(periodIndex:int):AVResult {
            return this.failed();
        }

        public function getABRProfileCount(periodIndex:int):int {
            return 0;
        }

        public function getABRProfileInfoAtIndex(periodIndex:int, abrProfileIndex:int):AVABRProfileInfo {
            return null;
        }

        public function getBackgroundPeriodInfo(periodIndex:int):AVPeriodInfo {
            return null;
        }

        public function getBackgroundTimeline():AVTimeline {
            return null;
        }

        public function getCuePoint(periodIndex:int, cuePointIndex:int):AVCuePoint {
            return null;
        }

        public function getMediaPreferredStartTime():Number {
            return -1;
        }

        public function getPerceivedBandwidth():uint {
            return 0;
        }

        public function getPeriodInfo(periodIndex:int):AVPeriodInfo {
            return null;
        }

        public function getPeriodInfoWithTagsAcrossIndexes(periodIndex:int, periodIndexTagsAcross:int):AVPeriodInfo {
            return null;
        }

        public function getSubscribedTag(periodIndex:int, tagIndex:int):AVTagData {
            return null;
        }

        public function getSubscribedTagForBackgroundManifest(periodIndex:int, tagIndex:int):AVTagData {
            return null;
        }

        public function getTimeline():AVTimeline {
            return null;
        }

        public function getTimelineSubscribedTag(tagIndex:int):AVTagData {
            return null;
        }

        public function getTimelineSubscribedTagForBackgroundManifest(tagIndex:int):AVTagData {
            return null;
        }

        public function getTrackCount(periodIndex:int, payloadType:String):int {
            return 0;
        }

        public function getTrackInfo(periodIndex:int, payloadType:String, trackIndex:int):AVTrackInfo {
            return null;
        }

        public function insertByLocalTime(periodIndex:int, insertionTime:Number, handle:int, userData:int = 0, replaceDuration:Number = 0):AVInsertionResult {
            return null;
        }

        public function insertByVirtualTime(insertionTime:Number, handle:int, userData:int = 0, replaceDuration:Number = 0):AVInsertionResult {
            return null;
        }

        public function load(url:String, containerType:String = "HLS", userData:int = 0):AVResult {
            if (url == null) {
                Error.throwError(TypeError, 2007, "url");
            }
            return this.waiting();
        }

        public function loadManifest(manifest:String, userData:int = 0, containerType:String = "HLS"):AVResult {
            if (manifest == null) {
                Error.throwError(TypeError, 2007, "manifest");
            }
            return this.waiting();
        }

        public function loadWithBackgroundManifest(url:String, backgroundUrl:String, userData:int, containerType:String):AVResult {
            if (url == null) {
                Error.throwError(TypeError, 2007, "url");
            }
            return this.waiting();
        }

        public function releaseManifest(handle:int):AVResult {
            return this.waiting();
        }

        public function removeByLocalTime(periodIndex:int, startTime:Number, endTime:Number, removeAll:Boolean):AVResult {
            return null;
        }

        public function removeByVirtualTime(virtualStartTime:Number, virtualEndTime:Number):AVResult {
            return null;
        }

        public function removeByVirtualTimeWithReplacement(virtualStartTime:Number, virtualEndTime:Number, replaceWithBackgroundManifest:Boolean):AVResult {
            return null;
        }

        public function selectTrack(periodIndex:int, payloadType:String, trackIndex:int):AVResult {
            return this.waiting();
        }

        public function selectTrackString(periodIndex:int, payloadType:String, trackName:String):AVResult {
            return this.waiting();
        }

        public function setABRParameters(params:AVABRParameters):AVResult {
            if (params == null) {
                Error.throwError(TypeError, 2007, "params");
            }
            return this.waiting();
        }

        public function setBandwidth(bitsPerSecond:int):AVResult {
            return this.failed();
        }

        public function setCuePointTags(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return new AVResult(AVResult.SUCCESS);
        }

        public function setHoldAt(time:Number):AVResult {
            return this.waiting();
        }

        public function setPauseAtPeriodEnd(periodIndex:int, userData:int = 0):AVResult {
            return this.failed();
        }

        public function setSubscribedTags(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return new AVResult(AVResult.SUCCESS);
        }

        public function setSubscribedTagsForBackgroundManifest(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return new AVResult(AVResult.SUCCESS);
        }

        public function set cookieHeader(value:String):void {
            this._cookieHeader = value;
        }

        public function set masterUpdateInterval(value:int):void {
            this._masterUpdateInterval = value;
        }

        public function get networkingParams():AVNetworkingParams {
            return this._networkingParams;
        }

        public function set networkingParams(value:AVNetworkingParams):void {
            if (value == null) {
                Error.throwError(TypeError, 2007, "networkingParams");
            }
        }

        public function set useRedirectedUrl(value:Boolean):void {
            this._useRedirectedUrl = value;
        }
    }
}
