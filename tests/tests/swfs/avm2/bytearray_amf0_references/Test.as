package {
    import flash.display.Sprite;
    import flash.net.ObjectEncoding;
    import flash.net.registerClassAlias;
    import flash.utils.ByteArray;

    public class Test extends Sprite {
        private function hex(ba:ByteArray):String {
            var out:Array = [];
            for (var i:uint = 0; i < ba.length; i++) {
                var b:String = ba[i].toString(16);
                out.push(b.length < 2 ? "0" + b : b);
            }
            return out.join(" ");
        }

        private function amf0():ByteArray {
            var ba:ByteArray = new ByteArray();
            ba.objectEncoding = ObjectEncoding.AMF0;
            return ba;
        }

        public function Test() {
            // The same object twice in one array: the second occurrence is a
            // reference (0x07) to table index 1 (the array itself is index 0).
            var o:Object = {a: 1};
            var arr:Array = [o, o];
            var ba:ByteArray = amf0();
            ba.writeObject(arr);
            trace("repeated object: " + hex(ba));
            ba.position = 0;
            var arr2:Array = ba.readObject();
            trace("read back length=" + arr2.length + " same instance=" + (arr2[0] === arr2[1]) + " a=" + arr2[0].a);

            // A cycle: the object refers to itself through reference 0.
            var c:Object = {};
            c.self = c;
            ba = amf0();
            ba.writeObject(c);
            trace("cycle: " + hex(ba));
            ba.position = 0;
            var c2:Object = ba.readObject();
            trace("read back cycle=" + (c2.self === c2));

            // Two different objects with equal contents are both written in full.
            ba = amf0();
            ba.writeObject([{a: 1}, {a: 1}]);
            trace("distinct objects: " + hex(ba));

            // Each writeObject() call starts a fresh reference table: the same
            // object written twice in a row is written in full twice.
            ba = amf0();
            ba.writeObject(o);
            ba.writeObject(o);
            trace("two calls: " + hex(ba));
            ba.position = 0;
            var first:Object = ba.readObject();
            var second:Object = ba.readObject();
            trace("read back two calls: same instance=" + (first === second) + " a=" + first.a + "," + second.a);

            // A shared array inside an object: {p: [2], q: <reference 1>}.
            var shared:Array = [2];
            ba = amf0();
            ba.writeObject({p: shared, q: shared});
            ba.position = 0;
            var s2:Object = ba.readObject();
            trace("shared array: " + hex(ba));
            trace("read back shared array: p===q " + (s2.p === s2.q) + " p[0]=" + s2.p[0]);

            // Typed objects (registerClassAlias) enter the table like plain ones.
            registerClassAlias("T", Typed);
            var t:Typed = new Typed();
            t.n = 3;
            ba = amf0();
            ba.writeObject([t, t]);
            trace("typed object: " + hex(ba));
            ba.position = 0;
            var ts:Array = ba.readObject();
            trace("read back typed: same instance=" + (ts[0] === ts[1]) + " is Typed=" + (ts[0] is Typed) + " n=" + ts[0].n);

            // Reading an AMF0 reference written by hand: {x: {y: 2}, z: <reference 1>}.
            ba = amf0();
            ba.writeByte(0x03);
            ba.writeUTF("x");
            ba.writeByte(0x03);
            ba.writeUTF("y");
            ba.writeByte(0x00);
            ba.writeDouble(2);
            ba.writeShort(0);
            ba.writeByte(0x09);
            ba.writeUTF("z");
            ba.writeByte(0x07);
            ba.writeShort(1);
            ba.writeShort(0);
            ba.writeByte(0x09);
            ba.position = 0;
            var r:Object = ba.readObject();
            trace("hand-written reference: x===z " + (r.x === r.z) + " y=" + r.z.y);
        }
    }
}

class Typed {
    public var n:int;
}
