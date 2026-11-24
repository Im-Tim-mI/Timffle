import flash.display.Sprite;
import flash.events.MouseEvent;
import flash.text.TextField;

// A dragged object with mouseEnabled = false still covers the pointer in its
// parent (the upper layer, mouseEnabled = true). Flash picks the object under the mouse
// with the dragged object at its previous position, then moves it, then runs
// the handlers: a move that leaves the old position reaches the object below.
class Test {
  static var tf:TextField; static var lines:Array<String> = [];
  static function log(s:String) { flash.Lib.trace(s); lines.push(s); if (lines.length > 9) lines.shift(); tf.text = lines.join("\n"); }
  static function main() {
    var root = flash.Lib.current;
    var ctrl = new Sprite(); ctrl.name = "lower"; root.addChild(ctrl);
    var below = new Sprite(); below.name = "target";
    below.graphics.beginFill(0x3366CC); below.graphics.drawRect(0, 0, 200, 150); below.graphics.endFill();
    below.x = 200; below.y = 150; ctrl.addChild(below);
    var top = new Sprite(); top.name = "upper"; root.addChild(top);
    var stick = new Sprite(); stick.name = "dragged";
    stick.graphics.beginFill(0x996633); stick.graphics.drawRect(-40, -10, 80, 20); stick.graphics.endFill();
    stick.x = 300; stick.y = 200; stick.mouseChildren = false; top.addChild(stick);
    tf = new TextField(); tf.width = 590; tf.height = 140; tf.x = 5; tf.y = 5; tf.mouseEnabled = false; root.addChild(tf);
    root.stage.addEventListener(MouseEvent.MOUSE_MOVE, function(e:MouseEvent) {
      log("move " + e.stageX + "," + e.stageY + " target=" + e.target.name + " stick=" + stick.x + "," + stick.y);
    });
    stick.addEventListener(MouseEvent.MOUSE_DOWN, function(e:MouseEvent) {
      log("down target=" + e.target.name); stick.startDrag(true); stick.mouseEnabled = false;
    });
    root.stage.addEventListener(MouseEvent.MOUSE_UP, function(e:MouseEvent) {
      stick.stopDrag(); log("up target=" + e.target.name + " stick=" + stick.x + "," + stick.y);
    });
    log("ready");
  }
}
