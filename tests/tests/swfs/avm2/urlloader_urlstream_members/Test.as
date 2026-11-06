package {
import flash.display.Sprite;
import flash.events.Event;
import flash.net.URLLoader;
import flash.net.URLStream;
import flash.utils.describeType;

// URLLoader.addEventListener (the override Flash's playerglobal declares) and
// URLStream.diskCacheEnabled (always false in Flash Player).
public class Test extends Sprite {
    public function Test() {
        var loader:URLLoader = new URLLoader();
        trace("addEventListener declaredBy: " + describeType(URLLoader).factory.method.(@name == "addEventListener").@declaredBy);

        loader.addEventListener("custom", function(e:Event):void {
            trace("custom listener called: " + e.type + " on " + e.target);
        });
        trace("hasEventListener: " + loader.hasEventListener("custom"));
        loader.dispatchEvent(new Event("custom"));

        var captured:Boolean = false;
        loader.addEventListener("weak", function(e:Event):void { captured = true; }, false, 5, true);
        loader.dispatchEvent(new Event("weak"));
        trace("weak/priority listener called: " + captured);

        var stream:URLStream = new URLStream();
        trace("diskCacheEnabled: " + stream.diskCacheEnabled);
        var acc:XMLList = describeType(stream).accessor.(@name == "diskCacheEnabled");
        trace("diskCacheEnabled access: " + acc.@access + " type " + acc.@type);
        trace("connected: " + stream.connected);
    }
}
}
