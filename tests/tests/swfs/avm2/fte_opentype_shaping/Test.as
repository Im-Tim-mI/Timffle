package {
    import flash.display.Sprite;
    import flash.geom.Rectangle;
    import flash.text.engine.*;

    // Timffle: OpenType shaping of flash.text.engine text in DefineFont4 (CFF) fonts.
    // test.swf = this file compiled with asc plus two DefineFont4 tags: "Exo 2" (the
    // subset font of visual/definefont4) and "LigaTestSans" (a subset of Source Sans 3,
    // SIL OFL 1.1, renamed; see LICENSE-fonts.txt). Recorded with Flash Player 32.
    // Atom edges are printed rounded to twips (Flash keeps them in finer units).
    public class Test extends Sprite {
        private static function r(n:Number):String {
            return String(Math.round(n * 20) / 20);
        }
        private static function line(font:String, text:String, lig:String, kern:String,
                                     tcase:String = "default", dcase:String = "default",
                                     dwidth:String = "default", size:Number = 40):TextLine {
            var ef:ElementFormat = new ElementFormat(new FontDescription(font, "normal", "normal", "embeddedCFF"), size);
            ef.ligatureLevel = lig;
            ef.kerning = kern;
            ef.typographicCase = tcase;
            ef.digitCase = dcase;
            ef.digitWidth = dwidth;
            return new TextBlock(new TextElement(text, ef)).createTextLine(null, 10000);
        }
        private static function dump(tag:String, l:TextLine):void {
            if (l == null) {
                trace(tag + " null");
                return;
            }
            var s:String = tag + " atoms=" + l.atomCount + " textWidth=" + r(l.textWidth) + " |";
            for (var i:int = 0; i < l.atomCount; i++) {
                var b:Rectangle = l.getAtomBounds(i);
                s += " " + l.getAtomTextBlockBeginIndex(i) + "-" + l.getAtomTextBlockEndIndex(i) + "@" + r(b.x) + ".." + r(b.x + b.width);
            }
            trace(s);
        }
        public function Test() {
            // (The Exo 2 subset has no "V", "y" or "h".)
            var words:Object = {
                "Exo 2": ["fi", "fl", "ffi", "ff", "ft", "fft", "To", "Ta", "Tefi", "DefineFont4."],
                "LigaTestSans": ["fi", "fl", "ffi", "ff", "ft", "fft", "AV", "To", "Ta", "they", "Tefi", "DefineFont4."]
            };
            for each (var font:String in ["Exo 2", "LigaTestSans"]) {
                for each (var w:String in words[font]) {
                    for each (var lv:String in ["none", "minimum", "common", "uncommon", "exotic"]) {
                        dump(font + " [" + w + "] ligatureLevel=" + lv, line(font, w, lv, "on"));
                    }
                    for each (var k:String in ["on", "off", "auto"]) {
                        dump(font + " [" + w + "] kerning=" + k, line(font, w, "common", k));
                    }
                }
            }
            for each (var tc:String in ["default", "smallCaps", "capsAndSmallCaps"]) {
                dump("LigaTestSans typographicCase=" + tc + " [Hello World]", line("LigaTestSans", "Hello World", "common", "on", tc));
            }
            for each (var dc:String in ["default", "lining", "oldStyle"]) {
                for each (var dw:String in ["default", "proportional", "tabular"]) {
                    dump("LigaTestSans digitCase=" + dc + " digitWidth=" + dw + " [0123456789 1101]",
                        line("LigaTestSans", "0123456789 1101", "common", "on", "default", dc, dw));
                }
            }
            for each (var sz:Number in [12, 20, 30, 72]) {
                dump("Exo 2 fontSize=" + sz + " [DefineFont4.]", line("Exo 2", "DefineFont4.", "common", "on", "default", "default", "default", sz));
            }
            // A ligature across two TextElements (same format, then another colour).
            var fd:FontDescription = new FontDescription("Exo 2", "normal", "normal", "embeddedCFF");
            var e1:ElementFormat = new ElementFormat(fd, 40);
            var e2:ElementFormat = new ElementFormat(fd, 40);
            var e3:ElementFormat = new ElementFormat(fd, 40);
            e3.color = 0xFF0000;
            for each (var second:ElementFormat in [e2, e3]) {
                var v:Vector.<ContentElement> = new Vector.<ContentElement>();
                v.push(new TextElement("Def", e1));
                v.push(new TextElement("ineFont4.", second));
                dump("Exo 2 [Def|ineFont4.] color=" + second.color.toString(16), new TextBlock(new GroupElement(v)).createTextLine(null, 10000));
            }
            var l:TextLine = line("Exo 2", "DefineFont4.", "common", "on");
            var q:String = "Exo 2 [DefineFont4.] getAtomIndexAtCharIndex";
            for (var c:int = 0; c < 12; c++) {
                q += " " + l.getAtomIndexAtCharIndex(c);
            }
            trace(q);
        }
    }
}
