package {
import flash.display.Sprite;
import flash.events.Event;
import flash.events.StatusEvent;
import flash.net.LocalConnection;

// LocalConnection.allowDomain() / allowInsecureDomain(): argument checking,
// and that same-domain sends still reach receivers with and without allow lists.
public class Test extends Sprite {
    // Static, so the connections are never collected while the test runs.
    static var receiverAll:LocalConnection = new LocalConnection();
    static var receiverNone:LocalConnection = new LocalConnection();
    static var receiverUnder:LocalConnection = new LocalConnection();
    static var sender:LocalConnection = new LocalConnection();
    static var frame:uint = 0;

    public function Test() {
        tryAllow("allowDomain()", function():void { receiverAll.allowDomain(); });
        tryAllow("allowDomain('*')", function():void { receiverAll.allowDomain("*"); });
        tryAllow("allowDomain('a.example', 'b.example')", function():void { receiverAll.allowDomain("a.example", "b.example"); });
        tryAllow("allowInsecureDomain('*')", function():void { receiverUnder.allowInsecureDomain("*"); });
        tryAllow("allowDomain(null)", function():void { receiverAll.allowDomain(null); });
        tryAllow("allowDomain(5)", function():void { receiverAll.allowDomain(5); });
        tryAllow("allowDomain('ok', {})", function():void { receiverAll.allowDomain("ok", {}); });
        tryAllow("allowInsecureDomain(undefined)", function():void { receiverAll.allowInsecureDomain(undefined); });
        tryAllow("allowInsecureDomain('x', 7)", function():void { receiverAll.allowInsecureDomain("x", 7); });

        receiverAll.client = { hello: function(who:String):void { trace("receiverAll.hello(" + who + ")"); } };
        receiverNone.client = { hello: function(who:String):void { trace("receiverNone.hello(" + who + ")"); } };
        receiverUnder.client = { hello: function(who:String):void { trace("receiverUnder.hello(" + who + ")"); } };
        receiverAll.connect("allowed");
        receiverNone.connect("plain");
        receiverUnder.connect("_under");

        sender.addEventListener(StatusEvent.STATUS, function(e:StatusEvent):void {
            trace("sender status: " + e.level);
        });

        addEventListener(Event.ENTER_FRAME, onFrame);
    }

    static function tryAllow(label:String, f:Function):void {
        try {
            f();
            trace(label + ": ok");
        } catch (e:Error) {
            trace(label + ": " + e.name + " #" + e.errorID + " " + e.message);
        }
    }

    function onFrame(e:Event):void {
        frame++;
        if (frame == 1) {
            trace("--- send to 'allowed' (allowDomain('*'))");
            sender.send("allowed", "hello", "frame1");
        } else if (frame == 2) {
            trace("--- send to 'plain' (no allowDomain, same domain)");
            sender.send("plain", "hello", "frame2");
        } else if (frame == 3) {
            trace("--- send to '_under' (allowInsecureDomain('*'))");
            sender.send("_under", "hello", "frame3");
        } else if (frame == 4) {
            trace("--- send to 'nobody'");
            sender.send("nobody", "hello", "frame4");
        } else if (frame == 5) {
            trace("done");
            removeEventListener(Event.ENTER_FRAME, onFrame);
        }
    }
}
}
