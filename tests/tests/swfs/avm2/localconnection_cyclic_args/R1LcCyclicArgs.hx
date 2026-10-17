import flash.events.AsyncErrorEvent;
import flash.events.Event;
import flash.events.StatusEvent;
import flash.net.LocalConnection;

/** LocalConnection.send with cyclic / shared object graphs as arguments.
 * Ruffle used to recurse forever while serializing these (stack overflow). */
class R1LcCyclicArgs {
	static var rx:LocalConnection;
	static var tx:LocalConnection;

	static function main() {
		Out.start("r1lc_cyclic_args");
		rx = new LocalConnection();
		tx = new LocalConnection();
		tx.addEventListener(StatusEvent.STATUS, function(e:StatusEvent) Out.line("tx status: " + e.level));
		rx.addEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent) Out.line("rx asyncError: " + e.error));

		var c:Dynamic = {};
		c.selfObject = function(v:Dynamic) {
			Out.line("selfObject: name=" + v.name + " v.me === v: " + (v.me == v) + " v.me.me === v: " + (v.me.me == v));
		};
		c.selfArray = function(v:Array<Dynamic>) {
			Out.line("selfArray: length=" + v.length + " v[0]=" + v[0] + " v[1]=" + v[1] + " v[2] === v: " + (v[2] == v));
		};
		c.indirect = function(v:Dynamic) {
			Out.line("indirect: v.child.parent === v: " + (v.child.parent == v) + " v.child.name=" + v.child.name);
		};
		c.arrayInObject = function(v:Dynamic) {
			Out.line("arrayInObject: v.list[0] === v: " + (v.list[0] == v) + " v.list[1]=" + v.list[1]);
		};
		c.shared = function(v:Dynamic) {
			Out.line("shared: v.a.n=" + v.a.n + " v.b.n=" + v.b.n + " v.a === v.b: " + (v.a == v.b));
		};
		c.twoArgs = function(a:Dynamic, b:Dynamic) {
			Out.line("twoArgs: a.me === a: " + (a.me == a) + " b.me === b: " + (b.me == b) + " a === b: " + (a == b));
		};
		rx.client = c;
		rx.connect("_r1rx");

		var obj:Dynamic = {name: "self"};
		obj.me = obj;
		var arr:Array<Dynamic> = [1, "two"];
		arr.push(arr);
		var parent:Dynamic = {};
		parent.child = {name: "kid", parent: parent};
		var holder:Dynamic = {};
		holder.list = [holder, "x"];
		var leaf:Dynamic = {n: 1};
		var sharedArg:Dynamic = {a: leaf, b: leaf};

		var frame = 0;
		flash.Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) {
			frame++;
			if (frame == 2) {
				tx.send("_r1rx", "selfObject", obj);
				tx.send("_r1rx", "selfArray", arr);
				tx.send("_r1rx", "indirect", parent);
				tx.send("_r1rx", "arrayInObject", holder);
				tx.send("_r1rx", "shared", sharedArg);
				tx.send("_r1rx", "twoArgs", obj, obj);
				Out.line("all sends returned");
			} else if (frame == 10) {
				Out.line("done");
				Out.finish();
			}
		});
	}
}
