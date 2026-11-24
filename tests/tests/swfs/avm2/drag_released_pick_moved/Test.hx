import flash.display.Sprite;
import flash.events.MouseEvent;

// A startDrag(lockCenter) object carried with the mouse button UP is picked where it moved to: the object below it never gets the move (Flash Player 32).
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
      log("down target=" + e.target.name); stick.startDrag(true); stick.mouseEnabled = false;
    });
    root.stage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent) {
      log("up target=" + e.target.name + " stick=" + stick.x + "," + stick.y + " (still dragging)");
    });
    log("ready");
  }
}
