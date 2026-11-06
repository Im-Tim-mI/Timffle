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
// (simple_shader.pbj writes a constant pixel: red = radius / 255, alpha 1) fills the shape.
// Every check is its own step so one failure does not hide the others. output.txt was
// recorded with Flash Player 32 (Wine); pixel lines need a GPU renderer here (imgtests).
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
            self.fills();
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

    private static function classes(s:Shape):String {
        var v:Vector.<IGraphicsData> = s.graphics.readGraphicsData();
        var out:Array = [];
        for each (var d:IGraphicsData in v) {
            var name:String = getQualifiedClassName(d);
            if (d is GraphicsShaderFill) {
                name += " matrix=" + mat(GraphicsShaderFill(d).matrix);
            } else if (d is GraphicsStroke) {
                name += " fill=" + getQualifiedClassName(GraphicsStroke(d).fill);
            }
            out.push(name);
        }
        return "n=" + v.length + " [" + out.join(", ") + "]";
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
        step("after errors", function():void { trace("after errors " + classes(s)); });
    }

    private function fills():void {
        var sh:Shader = makeShader();

        // fill with the default matrix
        var s:Shape = new Shape();
        s.graphics.beginShaderFill(sh);
        s.graphics.drawRect(0, 0, 20, 20);
        s.graphics.endFill();
        step("fill pixel", function():void { trace("fill pixel " + px(s, 10, 10) + " " + px(s, 30, 30)); });
        step("fill data", function():void { trace("fill data " + classes(s)); });

        // fill with a matrix
        var s2:Shape = new Shape();
        s2.graphics.beginShaderFill(sh, new Matrix(2, 0, 0, 2, 5, 5));
        s2.graphics.drawRect(10, 10, 20, 20);
        s2.graphics.endFill();
        step("fill+matrix pixel", function():void { trace("fill+matrix pixel " + px(s2, 20, 20) + " " + px(s2, 5, 5)); });
        step("fill+matrix data", function():void { trace("fill+matrix data " + classes(s2)); });

        // stroke
        var s3:Shape = new Shape();
        s3.graphics.lineStyle(4);
        s3.graphics.lineShaderStyle(sh);
        s3.graphics.moveTo(0, 10);
        s3.graphics.lineTo(20, 10);
        step("stroke pixel", function():void { trace("stroke pixel " + px(s3, 10, 10) + " " + px(s3, 10, 20)); });
        step("stroke data", function():void { trace("stroke data " + classes(s3)); });

        // solid fill and shader fill in one shape, in both orders
        var s5:Shape = new Shape();
        s5.graphics.beginFill(0x0000FF);
        s5.graphics.drawRect(0, 0, 10, 10);
        s5.graphics.endFill();
        s5.graphics.beginShaderFill(sh);
        s5.graphics.drawRect(20, 20, 10, 10);
        s5.graphics.endFill();
        step("solid then shader data", function():void { trace("solid then shader data " + classes(s5)); });
        step("solid then shader pixel", function():void { trace("solid then shader pixel " + px(s5, 5, 5) + " " + px(s5, 25, 25)); });
        var s6:Shape = new Shape();
        s6.graphics.beginShaderFill(sh);
        s6.graphics.drawRect(0, 0, 10, 10);
        s6.graphics.endFill();
        s6.graphics.beginFill(0x0000FF);
        s6.graphics.drawRect(20, 20, 10, 10);
        s6.graphics.endFill();
        step("shader then solid data", function():void { trace("shader then solid data " + classes(s6)); });
        // a shader stroke next to a plain stroke
        var s7:Shape = new Shape();
        s7.graphics.lineStyle(2, 0xFF0000);
        s7.graphics.moveTo(0, 0);
        s7.graphics.lineTo(10, 0);
        s7.graphics.lineStyle(2);
        s7.graphics.lineShaderStyle(sh);
        s7.graphics.lineTo(10, 10);
        step("plain then shader stroke data", function():void { trace("plain then shader stroke data " + classes(s7)); });
        // the shader fill cleared again
        var s8:Shape = new Shape();
        s8.graphics.beginShaderFill(sh);
        s8.graphics.drawRect(0, 0, 10, 10);
        s8.graphics.endFill();
        s8.graphics.clear();
        s8.graphics.beginFill(0x0000FF);
        s8.graphics.drawRect(0, 0, 10, 10);
        s8.graphics.endFill();
        step("cleared shader fill data", function():void { trace("cleared shader fill data " + classes(s8)); });

        // drawGraphicsData with a GraphicsShaderFill
        var s4:Shape = new Shape();
        step("graphicsData draw", function():void {
            var gd:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
            gd.push(new GraphicsShaderFill(sh, new Matrix(1, 0, 0, 1, 2, 3)));
            var p:GraphicsPath = new GraphicsPath();
            p.moveTo(0, 0); p.lineTo(20, 0); p.lineTo(20, 20); p.lineTo(0, 20);
            gd.push(p);
            gd.push(new GraphicsEndFill());
            s4.graphics.drawGraphicsData(gd);
            trace("graphicsData pixel " + px(s4, 10, 10));
        });
        step("graphicsData data", function():void { trace("graphicsData data " + classes(s4)); });
        step("graphicsData null shader", function():void {
            var gd2:Vector.<IGraphicsData> = new Vector.<IGraphicsData>();
            gd2.push(new GraphicsShaderFill(null));
            s4.graphics.drawGraphicsData(gd2);
            trace("graphicsData null shader: ok");
        });
    }
}
}
