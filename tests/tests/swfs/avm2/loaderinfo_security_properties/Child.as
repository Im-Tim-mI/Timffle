package {
import flash.display.Sprite;
import flash.events.Event;

public class Child extends Sprite {
    public function Child() {
        addEventListener(Event.ADDED_TO_STAGE, function(e:Event):void {
            trace("--- child constructed");
            trace("child sees parentSandboxBridge.greeting: " + (loaderInfo.parentSandboxBridge ? loaderInfo.parentSandboxBridge.greeting : null));
            try {
                loaderInfo.childSandboxBridge = { reply: "hello from child" };
                trace("child sets childSandboxBridge: ok");
            } catch (e:Error) {
                trace("child sets childSandboxBridge: " + e.name + " #" + e.errorID);
            }
            try {
                loaderInfo.parentSandboxBridge = { oops: true };
                trace("child sets parentSandboxBridge: ok");
            } catch (e:Error) {
                trace("child sets parentSandboxBridge: " + e.name + " #" + e.errorID);
            }
        });
    }
}
}
