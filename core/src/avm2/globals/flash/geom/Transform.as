package flash.geom {
    import flash.display.DisplayObject;
    import flash.geom.Matrix3D;
    import flash.geom.PerspectiveProjection;

    public class Transform {
        [Ruffle(NativeAccessible)]
        private var displayObject:DisplayObject;

        function Transform(object:DisplayObject) {
            this.displayObject = object;
        }

        public native function get colorTransform():ColorTransform;
        public native function set colorTransform(value:ColorTransform):void;
        public native function get matrix():Matrix;
        public native function set matrix(value:Matrix):void;

        // Timffle: the colour transform the object is drawn with: its own one
        // multiplied by every ancestor's up to the stage. Off the display list
        // it is just the object's own (measured on Flash Player 32,
        // timffle/difftest/src/D60Media.hx); a new object every time.
        public native function get concatenatedColorTransform():ColorTransform;

        public native function get concatenatedMatrix():Matrix;
        public native function get pixelBounds():Rectangle;

        public native function get matrix3D():Matrix3D;
        public native function set matrix3D(m:Matrix3D):*;

        public native function get perspectiveProjection():PerspectiveProjection;
        public native function set perspectiveProjection(val:PerspectiveProjection):void;

        public native function getRelativeMatrix3D(relativeTo:DisplayObject):Matrix3D;
    }
}
