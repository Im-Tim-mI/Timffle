import flash.events.AsyncErrorEvent;
import flash.events.Event;
import flash.events.StatusEvent;
import flash.net.LocalConnection;

/** LocalConnection cases that abort ruffle 0.7.1 (losing any report), one per SWF.
 * Build with -D lc_cycle_obj | lc_cycle_arr | lc_client_prim; see build_all.sh. */
class T3LcCrash {
	// static: a LocalConnection only referenced from a local can be GC'd, closing it
	static var rx:LocalConnection;
	static var tx:LocalConnection;

	static function main() {
		#if lc_cycle_obj
		var name = "t3lc_cycle_obj";
		#elseif lc_cycle_arr
		var name = "t3lc_cycle_arr";
		#else
		var name = "t3lc_client_prim";
		#end
		H.init(name, 15000);
		rx = new LocalConnection();
		tx = new LocalConnection();
		tx.addEventListener(StatusEvent.STATUS, function(e:StatusEvent) H.log("tx status level=" + e.level));
		rx.addEventListener(AsyncErrorEvent.ASYNC_ERROR, function(e:AsyncErrorEvent) H.log("rx asyncError " + e.text + " error=" + H.err(e.error)));
		var c:Dynamic = {};
		c.m = Reflect.makeVarArgs(function(a:Array<Dynamic>) {
			var v:Dynamic = a[0];
			H.log("received " + U.repr(v));
			if (Std.isOfType(v, String))
				return null;
			#if lc_cycle_obj
			H.log("v.me === v: " + (v.me == v));
			#elseif lc_cycle_arr
			H.log("v[2] === v: " + (v[2] == v));
			#end
			return null;
		});
		rx.client = c;
		rx.connect("t3rx");
		#if lc_client_prim
		for (p in ([5, "str", true, 1.5] : Array<Dynamic>))
			H.attempt("client=" + U.repr(p), function() {
				rx.client = p;
				H.log("client=" + U.repr(p) + " ok");
			});
		H.log("client still original: " + (rx.client == c));
		H.done();
		#else
		#if lc_cycle_obj
		var v:Dynamic = {name: "self"};
		v.me = v;
		#else
		var v:Array<Dynamic> = [1, "two"];
		v.push(v);
		#end
		var frame = 0;
		flash.Lib.current.stage.addEventListener(Event.ENTER_FRAME, function(_) {
			frame++;
			if (frame == 2) {
				H.attempt("send control", function() tx.send("t3rx", "m", "control"));
				H.attempt("send cyclic", function() tx.send("t3rx", "m", v));
				H.log("sends returned");
			} else if (frame == 8)
				H.done();
		});
		#end
	}
}
