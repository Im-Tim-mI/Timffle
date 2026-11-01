package {
    import flash.display.Sprite;
    public class Test extends Sprite {
        public function Test() {
            var x:XML = <Item ID="7" code="007" empty="" b="true" n="null"/>;
            var s:String = "7";
            var i:int = 7;
            var u:uint = 7;
            var d:Number = 7.0;
            var nul:* = null;
            var und:* = undefined;
            // other operand already on the stack (value == xml.@attr)
            trace("1 " + (s == x.@ID) + " " + (i == x.@ID) + " " + (u == x.@ID) + " " + (d == x.@ID) + " " + ("8" == x.@ID));
            trace("2 " + (7 == x.@code) + " " + ("007" == x.@code) + " " + ("" == x.@empty) + " " + (0 == x.@empty));
            trace("3 " + (und == x.@missing) + " " + (nul == x.@missing) + " " + ("" == x.@missing) + " " + (und == x.@ID));
            trace("4 " + (true == x.@b) + " " + (nul == x.@n) + " " + ("null" == x.@n));
            // xml.@attr == constant / local (one push in between)
            trace("5 " + (x.@ID == 7) + " " + (x.@ID == "7") + " " + (x.@ID == 7.5) + " " + (x.@ID == i) + " " + (x.@ID == s));
            trace("6 " + (x.@missing == undefined) + " " + (x.@missing == null) + " " + (x.@ID == null) + " " + (x.@ID == true));
            trace("7 " + (x.@ID != 7) + " " + (x.@ID != 8) + " " + (!(s == x.@ID)));
            if (x.@ID == 7) trace("8 if true"); else trace("8 if false");
            if (s != x.@code) trace("9 ne true"); else trace("9 ne false");
            // other operand is XML / XMLList: normal path
            var y:XML = <a ID="7"/>;
            trace("10 " + (y.@ID == x.@ID) + " " + (x.@ID == y.@ID) + " " + (y == x.@ID));
            // any name, more than one match, namespaces
            trace("11 " + ("7" == x.@*) + " " + (x.@* == "7"));
            var ns:Namespace = new Namespace("p", "urn:p");
            var z:XML = <z xmlns:p="urn:p" ID="1" p:ID="2"/>;
            trace("12 " + ("1" == z.@ID) + " " + ("2" == z.@ns::ID) + " " + ("1" == z.@ns::ID) + " " + ("2" == z.@*::ID));
            // object with valueOf/toString
            var o:Object = { toString: function():String { return "7"; } };
            trace("13 " + (o == x.@ID) + " " + (x.@ID == o));
            // search loops in both orders
            var t:XML = <T/>;
            for (var k:int = 0; k < 200; k++) t.appendChild(<Item ID={k * 2} code={"c" + k}/>);
            var found:int = -1;
            var list:XMLList = t.Item;
            for (k = 0; k < list.length(); k++) { if ("150" == list[k].@ID) { found = k; break; } }
            trace("15 found " + found);
            found = -1;
            for (k = 0; k < list.length(); k++) { if (list[k].@code == "c42") { found = k; break; } }
            trace("16 found " + found);
            // child-list cache must follow changes
            trace("17 " + t.Item.length() + " " + t.Other.length());
            t.appendChild(<Item ID="9999"/>);
            trace("18 " + t.Item.length() + " last " + t.Item[t.Item.length() - 1].@ID);
            delete t.Item[0];
            trace("19 " + t.Item.length() + " first " + t.Item[0].@ID);
            t.Item[0].setLocalName("Other");
            trace("20 " + t.Item.length() + " " + t.Other.length() + " first " + t.Item[0].@ID);
            t.Item[0].setNamespace(ns);
            trace("21 " + t.Item.length() + " " + t.ns::Item.length());
            t.Item[5] = <Item ID="replaced"/>;
            trace("22 " + t.Item.length() + " " + t.Item[5].@ID);
            t.insertChildBefore(t.Item[0], <Item ID="front"/>);
            trace("23 " + t.Item.length() + " " + t.Item[0].@ID);
            var c:XML = t.copy();
            trace("24 " + c.Item.length() + " " + (c.Item[0] == t.Item[0]) + " " + (c.Item[0] === t.Item[0]));
            t.setChildren(<Item ID="only"/>);
            trace("25 " + t.Item.length() + " " + c.Item.length());
            var big:XML = <B/>;
            for (k = 0; k < 100; k++) big.appendChild(<R v={k}/>);
            var a1:XMLList = big.R;
            var a2:XMLList = big.R;
            trace("26 " + (a1 === a2) + " " + a1.length() + " " + a2.length());
            a1[0] = <R v="changed"/>;
            trace("27 " + big.R[0].@v + " " + a2[0].@v + " " + big.R.length());
            trace("28 " + big.r.length() + " " + big.*.length());
            default xml namespace = ns;
            trace("29 " + big.R.length());
        }
    }
}
