import flash.display.Sprite;
import flash.display.StageDisplayState;
import flash.events.Event;
import flash.events.FullScreenEvent;
import flash.events.MouseEvent;

class LockTest {
    static function main() {
        var st = flash.Lib.current.stage;
        var s = new Sprite();
        s.graphics.beginFill(0x808080);
        s.graphics.drawRect(0, 0, 400, 300);
        flash.Lib.current.addChild(s);
        st.addEventListener(FullScreenEvent.FULL_SCREEN, function(e:FullScreenEvent) {
            trace("fullScreen=" + e.fullScreen + " displayState=" + st.displayState);
            if (e.fullScreen) {
                try { st.mouseLock = true; trace("mouseLock=" + st.mouseLock); }
                catch (err:flash.errors.Error) { trace("mouseLock error " + err.errorID); }
            } else {
                trace("after exit mouseLock=" + st.mouseLock);
            }
        });
        st.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
            try { st.mouseLock = true; } catch (err:flash.errors.Error) { trace("mouseLock outside full screen: error " + err.errorID); }
            st.displayState = StageDisplayState.FULL_SCREEN_INTERACTIVE;
        });
        st.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent) {
            if (st.mouseLock) trace("move movementX=" + e.movementX + " movementY=" + e.movementY);
        });
        trace("ready");
    }
}
