package flash.display {
    import flash.geom.Matrix;

    [API("662")]
    public final class GraphicsShaderFill implements IGraphicsFill, IGraphicsData {
        // Timffle: read by the native drawGraphicsData code.
        [Ruffle(NativeAccessible)]
        public var shader:Shader;

        [Ruffle(NativeAccessible)]
        public var matrix:Matrix;

        public function GraphicsShaderFill(shader:Shader = null, matrix:Matrix = null) {
            this.shader = shader;
            this.matrix = matrix;
        }
    }
}
