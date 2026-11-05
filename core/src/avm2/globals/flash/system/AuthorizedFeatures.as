package flash.system {
    import flash.display.AVLoader;
    import flash.media.AVStream;
    import flash.media.AVURLLoader;
    import flash.media.AVURLStream;
    import flash.net.URLStream;

    // Timffle: an `AuthorizedFeatures` token unlocks Adobe Primetime features
    // (HLS playback through AVStream, the disk cache, the application
    // installer). Tokens come only from `AuthorizedFeaturesLoader`, which
    // asks Adobe's authorization service; Flash Player 32 refuses to
    // construct one directly (`ArgumentError #2012`, measured with
    // timffle/difftest/src/D60Media.hx). This player contacts no
    // authorization service, so no token exists and nothing is ever enabled:
    // Flash Player on a machine without the feature.
    [API("688")]
    public final class AuthorizedFeatures {
        public function AuthorizedFeatures() {
            throw new ArgumentError("Error #2012: AuthorizedFeatures$ class cannot be instantiated.", 2012);
        }

        public function enableAVLoader(loader:AVLoader):Boolean {
            return false;
        }

        public function enableDiskCache(stream:URLStream):Boolean {
            return false;
        }

        public function enableHLSPlayback(stream:AVStream):Boolean {
            return false;
        }

        public function enableAVURLLoader(loader:AVURLLoader):Boolean {
            return false;
        }

        public function enableAVURLStream(stream:AVURLStream):Boolean {
            return false;
        }

        // Flash's playerglobal types this parameter `MediaPlayer`, a class
        // that no public playerglobal defines (the Haxe externs generated
        // from the SWC resolve it to Dynamic); `Object` accepts whatever a
        // caller has. Nothing is authorized here either way.
        public function enableMediaPlayerHLSPlayback(player:Object):Boolean {
            return false;
        }
    }
}
