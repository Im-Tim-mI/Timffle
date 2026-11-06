package flash.display3D.textures {
    import flash.media.Camera;
    import flash.net.NetStream;

    // Timffle: this player has no hardware video-to-texture path, so
    // Context3D.supportsVideoTexture is false and Context3D.createVideoTexture()
    // returns null — a VideoTexture instance can therefore never be obtained
    // (the class is abstract; `new VideoTexture()` throws like in Flash). The
    // members below are the complete Flash API surface and behave as an
    // unattached texture: attachNetStream()/attachCamera() record the source
    // (null detaches) and videoWidth/videoHeight are 0 until a frame has been
    // decoded, which never happens here.
    [Ruffle(Abstract)]
    public final class VideoTexture extends TextureBase {
        private var _netStream:NetStream = null;
        private var _camera:Camera = null;

        [API("706")]
        public function get videoWidth():int {
            return 0;
        }

        [API("706")]
        public function get videoHeight():int {
            return 0;
        }

        [API("706")]
        public function attachNetStream(netStream:NetStream):void {
            this._camera = null;
            this._netStream = netStream;
        }

        [API("706")]
        public function attachCamera(theCamera:Camera):void {
            this._netStream = null;
            this._camera = theCamera;
        }
    }
}
