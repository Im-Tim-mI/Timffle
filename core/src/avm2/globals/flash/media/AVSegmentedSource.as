package flash.media {
    // Timffle: the HLS/DASH manifest source of the Adobe Primetime player
    // (see AVStream.as). Loading a manifest is part of the playback that
    // `AuthorizedFeatures.enableHLSPlayback()` unlocks, and nothing is ever
    // unlocked on this player, so `load()`, `loadManifest()` and
    // `loadWithBackgroundManifest()` answer `AVResult.PLAYBACK_NOT_ENABLED`
    // (57) without touching the network, and no manifest is ever loaded:
    // the timeline, period, track, profile, cue point and tag queries answer
    // the way they do for a source with no manifest (null objects, zero
    // counts, no bandwidth measured, no preferred start time), and every
    // other operation on the (absent) timeline returns the same
    // `PLAYBACK_NOT_ENABLED` result. The configuration members
    // (`useRedirectedUrl`, `networkingParams`, `cookieHeader`,
    // `masterUpdateInterval`, custom headers) are stored so a player's
    // settings round-trip; a null URL or header name is `TypeError #2007`.
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
        private var _customHeaders:Object = {};

        public function AVSegmentedSource() {
            super();
        }

        private function notEnabled():AVResult {
            return new AVResult(AVResult.PLAYBACK_NOT_ENABLED);
        }

        public function addCustomHeader(headerName:String, args:Vector.<String>):void {
            if (headerName == null) {
                Error.throwError(TypeError, 2007, "headerName");
            }
            this._customHeaders[headerName] = args;
        }

        public function clearPauseAtPeriodEnd(periodIndex:int):AVResult {
            return this.notEnabled();
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
            return new AVInsertionResult(AVResult.PLAYBACK_NOT_ENABLED, -1, false);
        }

        public function insertByVirtualTime(insertionTime:Number, handle:int, userData:int = 0, replaceDuration:Number = 0):AVInsertionResult {
            return new AVInsertionResult(AVResult.PLAYBACK_NOT_ENABLED, -1, false);
        }

        public function load(url:String, containerType:String = "HLS", userData:int = 0):AVResult {
            if (url == null) {
                Error.throwError(TypeError, 2007, "url");
            }
            return this.notEnabled();
        }

        public function loadManifest(manifest:String, userData:int = 0, containerType:String = "HLS"):AVResult {
            if (manifest == null) {
                Error.throwError(TypeError, 2007, "manifest");
            }
            return this.notEnabled();
        }

        public function loadWithBackgroundManifest(url:String, backgroundUrl:String, userData:int, containerType:String):AVResult {
            if (url == null) {
                Error.throwError(TypeError, 2007, "url");
            }
            return this.notEnabled();
        }

        public function releaseManifest(handle:int):AVResult {
            return this.notEnabled();
        }

        public function removeByLocalTime(periodIndex:int, startTime:Number, endTime:Number, removeAll:Boolean):AVResult {
            return this.notEnabled();
        }

        public function removeByVirtualTime(virtualStartTime:Number, virtualEndTime:Number):AVResult {
            return this.notEnabled();
        }

        public function removeByVirtualTimeWithReplacement(virtualStartTime:Number, virtualEndTime:Number, replaceWithBackgroundManifest:Boolean):AVResult {
            return this.notEnabled();
        }

        public function selectTrack(periodIndex:int, payloadType:String, trackIndex:int):AVResult {
            return this.notEnabled();
        }

        public function selectTrackString(periodIndex:int, payloadType:String, trackName:String):AVResult {
            return this.notEnabled();
        }

        public function setABRParameters(params:AVABRParameters):AVResult {
            if (params == null) {
                Error.throwError(TypeError, 2007, "params");
            }
            return this.notEnabled();
        }

        public function setBandwidth(bitsPerSecond:int):AVResult {
            return this.notEnabled();
        }

        public function setCuePointTags(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return this.notEnabled();
        }

        public function setHoldAt(time:Number):AVResult {
            return this.notEnabled();
        }

        public function setPauseAtPeriodEnd(periodIndex:int, userData:int = 0):AVResult {
            return this.notEnabled();
        }

        public function setSubscribedTags(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return this.notEnabled();
        }

        public function setSubscribedTagsForBackgroundManifest(tags:Array):AVResult {
            if (tags == null) {
                Error.throwError(TypeError, 2007, "tags");
            }
            return this.notEnabled();
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
            this._networkingParams = value;
        }

        public function set useRedirectedUrl(value:Boolean):void {
            this._useRedirectedUrl = value;
        }
    }
}
