import flash.display.Sprite;
import flash.events.MouseEvent;

// A startDrag(false) object (keeps its grab offset, here 15 px below the pointer) is picked where it moved to, even with the button held (Flash Player 32); only lockCenter + held picks at the previous position (see drag_pick_before_move).
class Test {
  static var stick:Sprite;
  static function log(s:String) { flash.Lib.trace(s); }
  static function main() {
    var root = flash.Lib.current;
    var ctrl = new Sprite(); ctrl.name = "lower"; root.addChild(ctrl);
    var below = new Sprite(); below.name = "target";
    below.graphics.beginFill(0x3366CC); below.graphics.drawRect(0, 0, 200, 150); below.graphics.endFill();
    below.x = 200; below.y = 150; ctrl.addChild(below);
    var top = new Sprite(); top.name = "upper"; root.addChild(top);
    stick = new Sprite(); stick.name = "dragged";
    stick.graphics.beginFill(0x996633); stick.graphics.drawRect(-40, -10, 80, 20); stick.graphics.endFill();
    stick.x = 300; stick.y = 200; stick.mouseChildren = false; top.addChild(stick);
    root.stage.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent) {
      log("move " + e.stageX + "," + e.stageY + " target=" + e.target.name + " stick=" + stick.x + "," + stick.y);
    });
    below.addEventListener(MouseEvent.ROLL_OVER, function(e:MouseEvent) { log("rollOver target stick=" + stick.x + "," + stick.y); });
    below.addEventListener(MouseEvent.ROLL_OUT, function(e:MouseEvent) { log("rollOut target"); });
    stick.addEventListener(MouseEvent.ROLL_OVER, function(e:MouseEvent) { log("rollOver dragged"); });
    stick.addEventListener(MouseEvent.ROLL_OUT, function(e:MouseEvent) { log("rollOut dragged"); });
    stick.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
      stick.y += 15; log("down target=" + e.target.name + " stick shifted to " + stick.x + "," + stick.y); stick.startDrag(false); stick.mouseEnabled = false;
    });
    root.stage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent) {
      stick.stopDrag(); log("up target=" + e.target.name + " stick=" + stick.x + "," + stick.y + " -> stopDrag");
    });
    log("ready");
  }
}
