package flash.display {
    import flash.geom.Matrix;

    [Ruffle(Abstract)]
    public final class Graphics {
        public native function beginBitmapFill(
            bitmap:BitmapData,
            matrix:Matrix = null,
            repeat:Boolean = true,
            smooth:Boolean = false
        ):void;

        [Ruffle(FastCall)]
        public native function beginFill(color:uint, alpha:Number = 1.0):void;

        public native function beginGradientFill(
            type:String,
            colors:Array,
            alphas:Array,
            ratios:Array,
            matrix:Matrix = null,
            spreadMethod:String = "pad",
            interpolationMethod:String = "rgb",
            focalPointRatio:Number = 0
        ):void;

        // Timffle: the shader is evaluated once over the fill's bounds when the shape is
        // first rendered and used as a bitmap fill (see Drawing::add_shader_fill).
        [API("662")]
        public native function beginShaderFill(shader:Shader, matrix:Matrix = null):void;

        [Ruffle(FastCall)]
        public native function clear():void;

        public native function curveTo(controlX:Number, controlY:Number, anchorX:Number, anchorY:Number):void;

        public native function drawCircle(x:Number, y:Number, radius:Number):void;

        public native function drawEllipse(x:Number, y:Number, width:Number, height:Number):void;

        public native function drawRect(x:Number, y:Number, width:Number, height:Number):void;

        public native function drawRoundRect(
            x:Number,
            y:Number,
            width:Number,
            height:Number,
            ellipseWidth:Number,
            ellipseHeight:Number = NaN
        ):void;

        [Ruffle(FastCall)]
        public native function endFill():void;

        public native function lineStyle(
            thickness:Number = NaN,
            color:uint = 0,
            alpha:Number = 1.0,
            pixelHinting:Boolean = false,
            scaleMode:String = "normal",
            caps:String = null,
            joints:String = null,
            miterLimit:Number = 3
        ):void;

        [Ruffle(FastCall)]
        public native function lineTo(x:Number, y:Number):void;

        [Ruffle(FastCall)]
        public native function moveTo(x:Number, y:Number):void;

        public native function lineGradientStyle(
            type:String,
            colors:Array,
            alphas:Array,
            ratios:Array,
            matrix:Matrix = null,
            spreadMethod:String = "pad",
            interpolationMethod:String = "rgb",
            focalPointRatio:Number = 0
        ):void;

        [API("674")]
        public native function cubicCurveTo(
            controlX1:Number,
            controlY1:Number,
            controlX2:Number,
            controlY2:Number,
            anchorX:Number,
            anchorY:Number
        ):void;

        [API("662")]
        public native function copyFrom(sourceGraphics:Graphics):void;

        [API("662")]
        public native function drawPath(commands:Vector.<int>, data:Vector.<Number>, winding:String = "evenOdd"):void;

        public native function drawRoundRectComplex(
            x:Number,
            y:Number,
            width:Number,
            height:Number,
            topLeftRadius:Number,
            topRightRadius:Number,
            bottomLeftRadius:Number,
            bottomRightRadius:Number
        ):void;

        [API("662")]
        public native function drawTriangles(
            vertices:Vector.<Number>,
            indices:Vector.<int> = null,
            uvtData:Vector.<Number> = null,
            culling:String = "none"
        ):void;

        // Timffle: like Flash's playerglobal, a GraphicsPath item goes through
        // drawPathObject() -> drawPath() (visible in error stack traces and sharing
        // drawPath's fill-group rules); other items are handled natively one by one.
        [API("662")]
        public function drawGraphicsData(graphicsData:Vector.<IGraphicsData>):void {
            if (graphicsData == null) {
                Error.throwError(TypeError, 2007, "graphicsData");
            }
            for (var i:int = 0; i < graphicsData.length; i++) {
                var item:IGraphicsData = graphicsData[i];
                if (item is GraphicsPath) {
                    this.drawPathObject(GraphicsPath(item));
                } else if (item != null) {
                    this.drawGraphicsDataItem(item);
                }
            }
        }

        private function drawPathObject(path:GraphicsPath):void {
            if (path.commands != null && path.data != null) {
                this.drawPath(path.commands, path.data, path.winding);
            }
        }

        private native function drawGraphicsDataItem(item:IGraphicsData):void;

        // Timffle: like beginShaderFill, as the stroke's fill.
        [API("662")]
        public native function lineShaderStyle(shader:Shader, matrix:Matrix = null):void;

        [API("662")]
        public native function lineBitmapStyle(
            bitmap:BitmapData,
            matrix:Matrix = null,
            repeat:Boolean = true,
            smooth:Boolean = false
        ):void;

        [API("686")]
        public native function readGraphicsData(recurse:Boolean = true):Vector.<IGraphicsData>;
    }
}
