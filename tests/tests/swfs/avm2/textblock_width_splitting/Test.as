// Timffle: TextBlock.createTextLine/recreateTextLine break a paragraph at
// `width` (one visual line per TextLine), honour `fitSomething`, report
// textLineCreationResult, and TextBlock.bidiLevel orders the line (UAX #9).
// The device font is Noto Sans (test.toml), so glyph widths are deterministic;
// the widths used below are derived from measured lines.
package {
import flash.display.Sprite;
import flash.text.engine.*;

public class Test extends Sprite {
    private var format:ElementFormat = new ElementFormat(new FontDescription(), 20);

    public function Test() {
        var w4:Number = measure("aaaa");
        var w9:Number = measure("aaaa aaaa");
        trace("widths consistent: " + (w4 > 0) + " " + (w9 > 2 * w4));

        trace("-- fits: two words");
        dump("aaaa aaaa aaaa", w9 + 1);

        trace("-- fits: one word");
        dump("aaaa aaaa aaaa", w4 + 1);

        trace("-- exact width of a word");
        dump("aaaa aaaa", w4);

        trace("-- emergency break inside a word");
        dump("aaaaaaaa", w4 + 1);

        trace("-- nothing fits");
        dump("aaaa", 1);

        trace("-- nothing fits, fitSomething");
        dump("aaaa", 1, true);

        trace("-- explicit line breaks keep their line");
        dump("aa\naa aa\r\naa", w4 + 1);

        trace("-- splitting with a group of elements");
        var elements:Vector.<ContentElement> = new <ContentElement>[
            new TextElement("aaaa ", format),
            new TextElement("aaaa aaaa", format)
        ];
        dumpBlock(new TextBlock(new GroupElement(elements)), w4 + 1, false);

        trace("-- recreateTextLine re-breaks");
        var block:TextBlock = new TextBlock(new TextElement("aaaa aaaa aaaa", format));
        var line:TextLine = block.createTextLine(null, 10000);
        trace("created: rawTextLength=" + line.rawTextLength + " " + block.textLineCreationResult);
        var same:TextLine = block.recreateTextLine(line, null, w4 + 1);
        trace("recreated: same=" + (same === line) + " rawTextLength=" + line.rawTextLength
            + " textBlockBeginIndex=" + line.textBlockBeginIndex + " " + block.textLineCreationResult);
        var next:TextLine = block.createTextLine(line, w4 + 1);
        trace("next: rawTextLength=" + next.rawTextLength + " textBlockBeginIndex=" + next.textBlockBeginIndex
            + " previousLine=" + (next.previousLine === line));
        trace("recreate insufficient: " + block.recreateTextLine(next, line, 1) + " " + block.textLineCreationResult);

        trace("-- bidiLevel");
        bidi("abc", 0);
        bidi("abc", 1);
        bidi("ab 12", 1);
        bidi("12 34", 1);
        try {
            new TextBlock().bidiLevel = -1;
        } catch (e:Error) {
            trace("bidiLevel = -1: " + e);
        }
        var invalidated:TextBlock = new TextBlock(new TextElement("abc", format));
        var invalidatedLine:TextLine = invalidated.createTextLine(null, 10000);
        invalidated.bidiLevel = 1;
        trace("after bidiLevel change: " + invalidatedLine.validity + " firstInvalidLine=" + (invalidated.firstInvalidLine === invalidatedLine));
    }

    private function measure(text:String):Number {
        var block:TextBlock = new TextBlock(new TextElement(text, format));
        return block.createTextLine(null, 10000).textWidth;
    }

    private function dump(text:String, width:Number, fitSomething:Boolean = false):void {
        dumpBlock(new TextBlock(new TextElement(text, format)), width, fitSomething);
    }

    private function dumpBlock(block:TextBlock, width:Number, fitSomething:Boolean):void {
        var line:TextLine = block.createTextLine(null, width, 0, fitSomething);
        var index:int = 0;
        while (line) {
            trace("line " + index + ": rawTextLength=" + line.rawTextLength
                + " textBlockBeginIndex=" + line.textBlockBeginIndex
                + " atomCount=" + line.atomCount
                + " " + block.textLineCreationResult);
            line = block.createTextLine(line, width, 0, fitSomething);
            index++;
        }
        trace("done: " + line + " " + block.textLineCreationResult);
    }

    private function bidi(text:String, level:int):void {
        var block:TextBlock = new TextBlock(new TextElement(text, format));
        block.bidiLevel = level;
        var line:TextLine = block.createTextLine(null, 10000);
        var levels:Array = [];
        for (var i:int = 0; i < line.atomCount; i++) {
            levels.push(line.getAtomBidiLevel(i));
        }
        var last:int = line.atomCount - 1;
        trace("\"" + text + "\" bidiLevel=" + level + ": levels=" + levels.join(",")
            + " firstAtomLeftOfLast=" + (line.getAtomBounds(0).x < line.getAtomBounds(last).x)
            + " rawTextLength=" + line.rawTextLength);
    }
}
}
