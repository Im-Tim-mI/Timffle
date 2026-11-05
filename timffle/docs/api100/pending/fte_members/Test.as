// Timffle api100 batch fte: regression test for the Flash Text Engine members.
// NOT YET RUN — move to tests/tests/swfs/avm2/fte_members/ with the test.toml
// next to it, run once, check every line against the Adobe reference and
// write output.txt.
package {
    import flash.display.Sprite;
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;
    import flash.text.engine.*;

    public class Test extends Sprite {
        public function Test() {
            var format:ElementFormat = new ElementFormat();
            var a:TextElement = new TextElement("Hello ", format);
            var b:TextElement = new TextElement("world", format);
            var g:GraphicElement = new GraphicElement(new Sprite(), 10, 12, format);
            var group:GroupElement = new GroupElement(Vector.<ContentElement>([a, b, g]));

            trace("// ContentElement bookkeeping before a block");
            trace(a.groupElement === group, a.textBlock, a.textBlockBeginIndex);
            trace(group.rawText.length, group.text.length, group.rawText.charCodeAt(11).toString(16));
            trace(g.elementWidth, g.elementHeight, g.graphic != null);

            var block:TextBlock = new TextBlock(group);
            trace("// in a block");
            trace(a.textBlock === block, group.textBlock === block, b.textBlockBeginIndex, g.textBlockBeginIndex);
            trace(group.getElementAtCharIndex(0) === a, group.getElementAtCharIndex(6) === b, group.getElementAtCharIndex(11) === g);
            try { group.getElementAtCharIndex(12); } catch (e:Error) { trace(e.errorID); }

            trace("// boundaries");
            trace(block.findNextAtomBoundary(0), block.findPreviousAtomBoundary(5), block.findNextWordBoundary(0), block.findPreviousWordBoundary(8));
            try { block.findNextAtomBoundary(50); } catch (e:Error) { trace(e.errorID); }

            trace("// lines");
            var line:TextLine = block.createTextLine(null, 400);
            trace(line != null, line.atomCount, line.hasGraphicElement, line.getAtomTextBlockBeginIndex(6), line.getAtomTextBlockEndIndex(6));
            trace(line.getAtomIndexAtCharIndex(7), line.getAtomWordBoundaryOnLeft(6), line.getAtomWordBoundaryOnLeft(7), line.getAtomTextRotation(0), line.getAtomBidiLevel(0));
            trace(line.getAtomGraphic(11) === g.graphic, line.getAtomBounds(0).width > 0, line.totalHeight == line.ascent + line.descent);
            trace(line.getBaselinePosition(TextBaseline.ROMAN), line.getBaselinePosition(TextBaseline.ASCENT) == -line.ascent);
            trace(block.getTextLineAtCharIndex(3) === line, block.lastLine === line, block.firstInvalidLine);
            try { block.getTextLineAtCharIndex(99); } catch (e:Error) { trace(e.errorID); }

            trace("// mirror regions");
            var mirror:EventDispatcher = new EventDispatcher();
            trace(line.mirrorRegions);
            b.eventMirror = mirror;
            var regions:Vector.<TextLineMirrorRegion> = line.mirrorRegions;
            trace(regions.length, regions[0].element === b, regions[0].mirror === mirror, regions[0].textLine === line, regions[0].bounds.width > 0);
            trace(line.getMirrorRegion(mirror) != null, line.getMirrorRegion(new EventDispatcher()));

            trace("// group operations");
            var inner:GroupElement = group.groupElements(0, 2);
            trace(group.elementCount, inner.elementCount, a.groupElement === inner, inner.groupElement === group);
            group.ungroupElements(0);
            trace(group.elementCount, a.groupElement === group, inner.elementCount);
            var merged:TextElement = group.mergeTextElements(0, 2);
            trace(merged === a, a.text, group.elementCount, b.groupElement);
            try { group.mergeTextElements(0, 2); } catch (e:Error) { trace(e.errorID); }
            try { group.ungroupElements(0); } catch (e:Error) { trace(e.errorID); }

            trace("// justifier / fonts / metrics");
            trace(TextJustifier.getJustifierForLocale("ja") is EastAsianJustifier, TextJustifier.getJustifierForLocale("en-US") is SpaceJustifier);
            trace(TextJustifier.getJustifierForLocale("zh-TW").lineJustification);
            try { TextJustifier.getJustifierForLocale(null); } catch (e:Error) { trace(e.errorID); }
            trace(FontDescription.isFontCompatible("NoSuchFont", FontWeight.NORMAL, FontPosture.NORMAL));
            trace(FontDescription.isDeviceFontCompatible("_sans", FontWeight.NORMAL, FontPosture.NORMAL));
            try { FontDescription.isFontCompatible("x", "heavy", FontPosture.NORMAL); } catch (e:Error) { trace(e.errorID); }
            var m:FontMetrics = new ElementFormat(null, 20).getFontMetrics();
            trace(m.emBox.width, m.emBox.height, m.emBox.y < 0, m.underlineOffset, m.subscriptScale);

            trace("// block properties");
            block.lineRotation = TextRotation.ROTATE_90;
            var rotated:TextLine = block.createTextLine(null, 400);
            trace(rotated.rotation);
            block.tabStops = Vector.<TabStop>([new TabStop(TabAlignment.START, 100)]);
            trace(block.tabStops.length);
            block.releaseLineCreationData();
            trace(block.dump().indexOf("<TextBlock") == 0, line.dump().indexOf("<TextLine") == 0);

            trace("// line splitting");
            var block2:TextBlock = new TextBlock(new TextElement("aaa bbb ccc", new ElementFormat(null, 20)));
            var l1:TextLine = block2.createTextLine(null, 60);
            var l2:TextLine = block2.createTextLine(l1, 60);
            trace(l1.rawTextLength, l2.rawTextLength, block2.textLineCreationResult);
            var tiny:TextLine = block2.createTextLine(l2, 1);
            trace(tiny, block2.textLineCreationResult);
            trace(block2.createTextLine(l2, 1, 0, true) != null);
        }
    }
}
