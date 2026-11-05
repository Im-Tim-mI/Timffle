package {
import flash.display.*;
import flash.events.Event;
import flash.geom.Matrix;
import flash.net.URLLoader;
import flash.net.URLLoaderDataFormat;
import flash.net.URLRequest;
import flash.utils.ByteArray;
import flash.utils.getQualifiedClassName;

// Graphics.beginShaderFill / lineShaderStyle / GraphicsShaderFill: the Pixel Bender shader
// (simple_shader.pbj writes a constant pixel: red = radius / 255, alpha 1) is evaluated over
// the fill's bounds and used as a bitmap fill. Pixel lines need a GPU renderer (imgtests);
// error codes: null shader -> TypeError #2007 (Flash), Shader without byte code ->
// ArgumentError #2004 (inferred from Adobe's documented ArgumentError family).
public class Test extends Sprite {
    private var pbj:ByteArray;

    public function Test() {
        var self:Test = this;
        step("errors", errors);
        var loader:URLLoader = new URLLoader();
        loader.dataFormat = URLLoaderDataFormat.BINARY;
        loader.addEventListener(Event.COMPLETE, function(e:Event):void {
            pbj = loader.data as ByteArray;
            trace("# pbj loaded bytes=" + pbj.length);
            step("fills", self.fills);
        });
        loader.load(new URLRequest("simple_shader.pbj"));
    }

    private static function step(label:String, f:Function):void {
        try {
            f();
        } catch (e:Error) {
            trace(label + " THREW " + getQualifiedClassName(e) + " #" + e.errorID);
        }
    }

    private static function hex(v:uint):String {
        var s:String = v.toString(16).toUpperCase();
        while (s.length < 8) s = "0" + s;
        return s;
    }

    private static function mat(m:Matrix):String {
        return m == null ? "null" : "[" + m.a + "," + m.b + "," + m.c + "," + m.d + "," + m.tx + "," + m.ty + "]";
    }

    private static function px(d:DisplayObject, x:int, y:int):String {
        var bd:BitmapData = new BitmapData(40, 40, true, 0);
        bd.draw(d);
        return x + "," + y + "=" + hex(bd.getPixel32(x, y));
    }

    private function makeShader():Shader {
        var bytes:ByteArray = new ByteArray();
        bytes.writeBytes(pbj);
        var sh:Shader = new Shader(bytes);
        sh.data.radius.value = [100];
        sh.data.otherParam.value = [0];
        return sh;
    }

    private function errors():void {
        var s:Shape = new Shape();
        step("beginShaderFill null", function():void { s.graphics.beginShaderFill(null); });
        step("lineShaderStyle null", function():void { s.graphics.lineShaderStyle(null); });
        step("beginShaderFill empty shader", function():void { s.graphics.beginShaderFill(new Shader()); });
        trace("after errors n=" + s.graphics.readGraphicsData().length);
    }

    private function fills():void {
        var sh:Shader = makeShader();

        // fill with the default matrix
        var s:Shape = new Shape();
        s.graphics.beginShaderFill(sh);
        s.graphics.drawRect(0, 0, 20, 20);
        s.graphics.endFill();
        var v:Vector.<IGraphicsData> = s.graphics.readGraphicsData();
        trace("fill n=" + v.length + " " + getQualifiedClassName(v[0]) + " shader same=" + (GraphicsShaderFill(v[0]).shader == sh) + " matrix=" + mat(GraphicsShaderFill(v[0]).matrix));
        trace("fill pixel " + px(s, 10, 10) + " " + px(s, 30, 30));

        // fill with a matrix
        s = new Shape();
        s.graphics.beginShaderFill(sh, new Matrix(2, 0, 0, 2, 5, 5));
        s.graphics.drawRect(10, 10, 20, 20);
        s.graphics.endFill();
        v = s.graphics.readGraphicsData();
        trace("fill+matrix matrix=" + mat(GraphicsShaderFill(v[0]).matrix) + " pixel " + px(s, 20, 20) + " " + px(s, 5, 5));

        // stroke
        s = new Shape();
        s.graphics.lineStyle(4);
        s.graphics.lineShaderStyle(sh);
        s.graphics.moveTo(0, 10);
        s.graphics.lineTo(20, 10);
        v = s.graphics.readGraphicsData();
        trace("stroke n=" + v.length + " fill=" + getQualifiedClassName(GraphicsStroke(v[0]).fill) + " shader same=" + (GraphicsShaderFill(GraphicsStroke(v[0]).fill).shader == sh));
        trace("stroke pixel " + px(s, 10, 10) + " " + px(s, 10, 20));

        // drawGraphicsData with a GraphicsShaderFill
        s = new Shape();
        var gd:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
        gd.push(new GraphicsShaderFill(sh, new Matrix(1, 0, 0, 1, 2, 3)));
        var p:GraphicsPath = new GraphicsPath();
        p.moveTo(0, 0); p.lineTo(20, 0); p.lineTo(20, 20); p.lineTo(0, 20);
        gd.push(p);
        gd.push(new GraphicsEndFill());
        s.graphics.drawGraphicsData(gd);
        v = s.graphics.readGraphicsData();
        trace("graphicsData n=" + v.length + " " + getQualifiedClassName(v[0]) + " matrix=" + mat(GraphicsShaderFill(v[0]).matrix) + " pixel " + px(s, 10, 10));
        step("graphicsData null shader", function():void {
            var gd2:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
            gd2.push(new GraphicsShaderFill(null));
            s.graphics.drawGraphicsData(gd2);
        });
    }
}
}
