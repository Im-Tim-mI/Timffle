import flash.utils.Dictionary;

/** Exploration: the order in which `for (k in dict)` / `for each` visit a Dictionary with function / object / string keys. */
class D10DictOrder {
	static function keysOf(d:Dictionary):Array<Dynamic> {
		var r:Array<Dynamic> = untyped __keys__(d);
		return r;
	}

	static function main() {
		H.init("d10dict_order", 20000);
		// closures of distinct bound methods, like Tick's _renderMap keyed by renderHandler
		var owners:Array<Dynamic> = [];
		for (i in 0...12)
			owners.push(new Owner(i));
		var d:Dictionary = new Dictionary();
		for (o in owners)
			untyped d[o.handler] = o.id;
		var order:Array<Int> = [];
		for (k in keysOf(d))
			order.push(untyped d[k]);
		H.log("function keys, insertion 0..11 -> for-in order " + order.join(","));

		var d2:Dictionary = new Dictionary();
		for (o in owners)
			untyped d2[o] = o.id;
		var order2:Array<Int> = [];
		for (k in keysOf(d2))
			order2.push(untyped d2[k]);
		H.log("object keys, insertion 0..11 -> for-in order " + order2.join(","));

		var d3:Dictionary = new Dictionary();
		for (i in 0...12)
			untyped d3["k" + i] = i;
		var order3:Array<Int> = [];
		for (k in keysOf(d3))
			order3.push(untyped d3[k]);
		H.log("string keys, insertion 0..11 -> for-in order " + order3.join(","));

		// keys re-inserted after a delete
		untyped __delete__(d, owners[3].handler);
		untyped d[owners[3].handler] = 3;
		var order4:Array<Int> = [];
		for (k in keysOf(d))
			order4.push(untyped d[k]);
		H.log("function keys after delete+reinsert of 3 -> " + order4.join(","));
		H.done();
	}
}

class Owner {
	public var id:Int;
	public var handler:Dynamic;

	public function new(i:Int) {
		id = i;
		handler = function() return i;
	}
}
