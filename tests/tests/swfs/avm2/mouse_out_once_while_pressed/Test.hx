import flash.display.Sprite;
import flash.events.MouseEvent;

// Press on a box, drag out of it, back in, out again, release outside: Flash Player 32 sends
// mouseOut/rollOut and mouseOver/rollOver once per change, out of the old object first.
class Test {
  static function log(s:String) { flash.Lib.trace(s); }
  static function main() {
    var root = flash.Lib.current;
    var below = new Sprite(); below.name = "below";
    below.graphics.beginFill(0x3366CC); below.graphics.drawRect(0, 0, 200, 150); below.graphics.endFill();
    below.x = 200; below.y = 150; root.addChild(below);
    var box = new Sprite(); box.name = "box";
    box.graphics.beginFill(0x996633); box.graphics.drawRect(-40, -10, 80, 20); box.graphics.endFill();
    box.x = 300; box.y = 200; root.addChild(box);
    for (o in [below, box]) {
      var n = o.name;
      o.addEventListener(MouseEvent.MOUSE_OVER, function(e:MouseEvent) { log("mouseOver " + n + " t=" + e.target.name); });
      o.addEventListener(MouseEvent.MOUSE_OUT, function(e:MouseEvent) { log("mouseOut " + n + " t=" + e.target.name); });
      o.addEventListener(MouseEvent.ROLL_OVER, function(e:MouseEvent) { log("rollOver " + n + " t=" + e.target.name); });
      o.addEventListener(MouseEvent.ROLL_OUT, function(e:MouseEvent) { log("rollOut " + n + " t=" + e.target.name); });
      o.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) { log("down " + n); });
      o.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent) { log("up " + n); });
    }
    root.stage.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent) { log("move " + e.stageX + "," + e.stageY + " target=" + e.target.name); });
    log("ready");
  }
}
