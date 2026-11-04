package flash.media {
    import flash.errors.IllegalOperationError;
    import flash.net.URLRequest;
    import flash.system.AuthorizedFeatures;

    // Timffle: `scanHardware()` asks the player to enumerate the cameras and
    // microphones again. This player has no camera or microphone devices
    // (`Camera.getCamera()` and `Microphone.getMicrophone()` are null), so a
    // rescan finds nothing, like Flash Player on a machine without them;
    // Flash Player 32 returns at once (timffle/difftest/src/D60Media.hx).
    public function scanHardware():void {
    }

    // Timffle: `avSendToURL()` is the Primetime (AVStream) variant of
    // `sendToURL()`, gated by an `AuthorizedFeatures` token. Flash Player 32
    // throws `TypeError #2007` for a null `features` or `request` (measured);
    // no token can exist in this player (`AuthorizedFeatures` cannot be
    // instantiated and no authorization server is contacted), so the request
    // path is never reached.
    [API("688")]
    public function avSendToURL(features:AuthorizedFeatures, request:URLRequest, name:String = null):void {
        if (features == null) {
            throw new TypeError("Error #2007: Parameter features must be non-null.", 2007);
        }
        if (request == null) {
            throw new TypeError("Error #2007: Parameter request must be non-null.", 2007);
        }
        throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
    }
}
