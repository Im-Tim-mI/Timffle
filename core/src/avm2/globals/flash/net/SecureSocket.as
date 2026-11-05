package flash.net {
    import flash.errors.IllegalOperationError;
    import flash.security.CertificateStatus;
    import flash.security.X509Certificate;
    import flash.utils.ByteArray;

    // Timffle: Flash Player on a platform without SSL/TLS sockets. This player has no TLS
    // stack behind `Socket` (the web build tunnels sockets through a WebSocket proxy), so
    // `isSupported` is false and, as the AS3 reference says for that case, the constructor
    // throws an IllegalOperationError. The certificate members answer like an unconnected
    // socket (status "unknown", no certificate; a null or empty certificate is #2004 like
    // Flash Player 32).
    [API("672")]
    public class SecureSocket extends Socket {
        public function SecureSocket() {
            super();
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }

        public static function get isSupported():Boolean {
            return false;
        }

        [API("674")]
        public function get serverCertificate():X509Certificate {
            return null;
        }

        public function get serverCertificateStatus():String {
            return CertificateStatus.UNKNOWN;
        }

        [API("674")]
        public function addBinaryChainBuildingCertificate(certificate:ByteArray, trusted:Boolean):void {
            if (certificate == null || certificate.length == 0) {
                throw new ArgumentError("Error #2004: One of the parameters is invalid.", 2004);
            }
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }

        override public function connect(host:String, port:int):void {
            throw new IllegalOperationError("Error #2014: Feature is not available at this time.", 2014);
        }
    }
}
