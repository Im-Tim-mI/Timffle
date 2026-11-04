package flash.media {
    // Timffle: H.264 encoder settings. Measured on Flash Player 32
    // (timffle/difftest/src/D60Media.hx): codec "H264Avc", default profile
    // "baseline" and level "2.1"; `setProfileLevel` accepts the profile
    // case-insensitively but stores it as given, the level must be one of the
    // `H264Level` strings exactly ("3.0" or "" are refused); a wrong profile or
    // level is `ArgumentError #2008`, a null one `TypeError #1009`.
    [API("674")]
    public class H264VideoStreamSettings extends VideoStreamSettings {
        private static const LEVELS:Array = ["1", "1b", "1.1", "1.2", "1.3", "2", "2.1", "2.2", "3", "3.1", "3.2", "4", "4.1", "4.2", "5", "5.1"];

        private var _level:String = "2.1";
        private var _profile:String = "baseline";

        public function H264VideoStreamSettings() {
            super();
        }

        override public function get codec():String {
            return "H264Avc";
        }

        public function get level():String {
            return this._level;
        }

        public function get profile():String {
            return this._profile;
        }

        public function setProfileLevel(profile:String, level:String):void {
            var lowerProfile:String = profile.toLowerCase();
            level.toLowerCase();
            if (lowerProfile != "baseline" && lowerProfile != "main") {
                throw new ArgumentError("Error #2008: Parameter profile must be one of the accepted values.", 2008);
            }
            if (LEVELS.indexOf(level) < 0) {
                throw new ArgumentError("Error #2008: Parameter level must be one of the accepted values.", 2008);
            }
            this._profile = profile;
            this._level = level;
        }
    }
}
