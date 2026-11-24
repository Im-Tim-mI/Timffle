// startDrag(false) (grab offset, here 15 px below the pointer): picked where it moved to, the pointer never re-enters the dragged clip. Flash Player 32.
stop();
function box(name, depth, color, x, y, w, h) {
    var mc = _root.createEmptyMovieClip(name, depth);
    mc.beginFill(color);
    mc.moveTo(x, y); mc.lineTo(x + w, y); mc.lineTo(x + w, y + h); mc.lineTo(x, y + h);
    mc.endFill();
    return mc;
}
box("below", 1, 0x3366CC, 200, 150, 200, 150);
var d = box("drag", 2, 0x996633, -40, -10, 80, 20);
d._x = 300; d._y = 200;
below.trackAsMenu = true;
below.onRollOver = function() { trace("rollOver below drag=" + drag._x + "," + drag._y); };
below.onRollOut = function() { trace("rollOut below"); };
below.onDragOver = function() { trace("dragOver below drag=" + drag._x + "," + drag._y); };
below.onDragOut = function() { trace("dragOut below"); };
drag.onRollOver = function() { trace("rollOver drag"); };
drag.onRollOut = function() { trace("rollOut drag"); };
drag.onDragOver = function() { trace("dragOver drag"); };
drag.onDragOut = function() { trace("dragOut drag"); };
drag.onPress = function() { this._y += 15; this.startDrag(false); trace("press drag -> shifted to " + this._x + "," + this._y + ", startDrag(false)"); };
drag.onRelease = function() { this.stopDrag(); trace("release drag -> stopDrag drag=" + drag._x + "," + drag._y); };
drag.onReleaseOutside = drag.onRelease;
var mm = {};
mm.onMouseMove = function() { trace("move " + _root._xmouse + "," + _root._ymouse + " drag=" + drag._x + "," + drag._y); };
mm.onMouseDown = function() { trace("mouseDown " + _root._xmouse + "," + _root._ymouse); };
mm.onMouseUp = function() { trace("mouseUp " + _root._xmouse + "," + _root._ymouse); };
Mouse.addListener(mm);
trace("ready");
