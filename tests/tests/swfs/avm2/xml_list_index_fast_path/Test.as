package {
    import flash.display.Sprite;
    public class Test extends Sprite {
        public function Test() {
            var data:XML = <Root><Item ID="7" code="007"/><Item ID="-5" code="x"/><Item ID="12"><sub>3</sub></Item><Other ID="9"/></Root>;
            var list:XMLList = data.Item;
            trace("length " + list.length());
            var i:int = 0;
            var n:Number = 1;
            var u:uint = 2;
            trace("int index " + list[i].@ID + " number index " + list[n].@ID + " uint index " + list[u].@ID);
            trace("past end " + list[3] + " " + (list[3] === undefined));
            trace("fractional " + list[1.5]);
            var neg:int = -1;
            trace("negative " + list[neg]);
            trace("string index " + list["1"].@ID);
            trace("same node === " + (list[0] === list[0]) + " " + (list[0] === data.Item[0]));
            trace("attr == int " + (list[0].@ID == 7) + " " + (7 == list[0].@ID) + " " + (list[1].@ID == -5));
            trace("attr == leading zero " + (list[0].@code == 7) + " " + (list[0].@code == "007"));
            trace("attr == number " + (list[0].@ID == 7.0) + " " + (list[0].@ID == 7.5));
            trace("attr != int " + (list[0].@ID != 8));
            trace("missing attr " + (list[1].@nope == 0) + " " + (list[1].@nope == undefined));
            trace("complex content " + (list[2] == 12) + " simple " + (list[2].sub == 3));
            trace("list of two " + (data.Item.@ID == 7));
            trace("xml vs list " + (list[0].@ID == data.Item[0].@ID));
            var found:XML = null;
            for (var k:int = 0; k < list.length(); k++) {
                if (12 == list[k].@ID) { found = list[k]; break; }
            }
            trace("search " + found.toXMLString().replace(/\s+/g, " "));
            list[0].@ID = "8";
            trace("after set " + list[0].@ID + " " + data.Item[0].@ID + " " + (list[0].@ID == 8));
        }
    }
}
