package {
    import flash.display.Sprite;
    import flash.globalization.Collator;
    import flash.globalization.CollatorMode;
    import flash.globalization.CurrencyFormatter;
    import flash.globalization.CurrencyParseResult;
    import flash.globalization.DateTimeFormatter;
    import flash.globalization.DateTimeNameContext;
    import flash.globalization.DateTimeNameStyle;
    import flash.globalization.DateTimeStyle;
    import flash.globalization.LocaleID;
    import flash.globalization.NumberFormatter;
    import flash.globalization.NumberParseResult;
    import flash.globalization.StringTools;

    public class Test extends Sprite {
        public function Test() {
            testLocaleID();
            testStringTools();
            testNumberFormatter();
            testCurrencyFormatter();
            testDateTimeFormatter();
            testCollator();
        }

        private function testLocaleID():void {
            trace("// LocaleID");
            var names:Array = ["ar-SA", "EN_us", "en-US-POSIX", "zh-TW", "zh-Hans", "mn-CN", "ja",
                "zh-CN@collation=pinyin;calendar=chinese", "de-DE-u-co-phonebk", "en-US@Collation"];
            for each (var n:String in names) {
                var id:LocaleID = new LocaleID(n);
                var kv:Object = id.getKeysAndValues();
                var kvStatus:String = id.lastOperationStatus;
                var keys:Array = [];
                for (var k:String in kv) {
                    keys.push(k + "=" + kv[k]);
                }
                keys.sort();
                trace(n + " -> name=" + id.name + " lang=" + id.getLanguage()
                    + " script=" + id.getScript() + " (" + id.lastOperationStatus + ")"
                    + " region=" + id.getRegion() + " (" + id.lastOperationStatus + ")"
                    + " variant=" + id.getVariant() + " rtl=" + id.isRightToLeft()
                    + " keys=[" + keys.join(",") + "] (" + kvStatus + ")");
            }
            trace("i-default: " + new LocaleID(LocaleID.DEFAULT).name);
            var want:Vector.<String> = new <String>["zh-Hant-TW", "fr", "en-US"];
            var have:Vector.<String> = new <String>["en", "zh-CN", "en-GB", "zh-TW", "de-DE", "fr-FR", "fr-CA"];
            trace("determinePreferredLocales: " + LocaleID.determinePreferredLocales(want, have).join(","));
            try {
                new LocaleID(null);
            } catch (e:Error) {
                trace("null name: " + e.errorID);
            }
        }

        private function testStringTools():void {
            trace("// StringTools");
            var st:StringTools = new StringTools("en-US");
            trace(st.actualLocaleIDName + " " + st.lastOperationStatus);
            trace(st.toUpperCase("iI ıİ ß ΣςσβΰΐΣ") + " | " + st.toLowerCase("iI ıİ ΟΔΥΣΣΕΥΣ") + " " + st.lastOperationStatus);
            var tr:StringTools = new StringTools("tr-TR");
            trace(tr.actualLocaleIDName + " " + tr.lastOperationStatus);
            trace(tr.toUpperCase("iI ıİ") + " | " + tr.toLowerCase("iI ıİ"));
            var fallback:StringTools = new StringTools("fr-CH");
            trace(fallback.actualLocaleIDName + " " + fallback.lastOperationStatus);
            var unknown:StringTools = new StringTools("xx-YY");
            trace(unknown.actualLocaleIDName + " " + unknown.lastOperationStatus);
            trace(StringTools.getAvailableLocaleIDNames().indexOf("zh-TW") >= 0);
        }

        private function testNumberFormatter():void {
            trace("// NumberFormatter");
            var nf:NumberFormatter = new NumberFormatter("en-US");
            trace(nf.actualLocaleIDName + " " + nf.lastOperationStatus + " frac=" + nf.fractionalDigits
                + " sep=" + nf.groupingSeparator + nf.decimalSeparator + " neg=" + nf.negativeNumberFormat);
            trace(nf.formatNumber(123456789.12) + " " + nf.formatInt(-1234567) + " " + nf.formatUint(4294967295));
            nf.fractionalDigits = 3;
            trace(nf.formatNumber(123.4) + " " + nf.formatNumber(0.12) + " " + nf.formatNumber(2.5) + " " + nf.formatNumber(0.0005));
            nf.trailingZeros = false;
            trace(nf.formatNumber(123.4) + " " + nf.formatNumber(0.12) + " " + nf.formatNumber(0));
            nf.leadingZero = false;
            trace(nf.formatNumber(0.12) + " " + nf.formatNumber(0));
            nf.trailingZeros = true;
            trace(nf.formatNumber(0.12) + " " + nf.formatNumber(0));
            nf.leadingZero = true;
            nf.fractionalDigits = 2;
            nf.groupingPattern = "3;2;*";
            trace(nf.groupingPattern + " " + nf.formatNumber(123456789.12));
            nf.groupingPattern = "3";
            trace(nf.groupingPattern + " " + nf.formatNumber(123456789.12));
            nf.groupingPattern = "3;";
            trace(nf.groupingPattern + " " + nf.lastOperationStatus);
            nf.groupingPattern = "3;*";
            nf.useGrouping = false;
            trace(nf.formatNumber(123456789.12));
            nf.useGrouping = true;
            for (var f:uint = 0; f <= 4; f++) {
                nf.negativeNumberFormat = f;
                trace("neg " + f + ": " + nf.formatNumber(-1234.5) + " parse(" + nf.parseNumber(nf.formatNumber(-1234.5)) + ")");
            }
            nf.negativeNumberFormat = 9;
            trace(nf.negativeNumberFormat + " " + nf.lastOperationStatus);
            nf.negativeNumberFormat = 1;
            nf.digitsType = 0x0660;
            trace(nf.formatNumber(-1234.5));
            nf.digitsType = 0x30;
            var r:NumberParseResult = nf.parse("Total: 123,567,89,0.254 USD");
            trace(r.value + " " + r.startIndex + " " + r.endIndex + " " + nf.lastOperationStatus);
            r = nf.parse("abc");
            trace(r.value + " " + r.startIndex + " " + r.endIndex + " " + nf.lastOperationStatus);
            trace(nf.parseNumber("  1,234.5  ") + " " + nf.parseNumber("+12") + " " + nf.parseNumber("12abc") + " " + nf.lastOperationStatus);
            trace(nf.parseNumber("1.23e40") + " " + nf.parseNumber("(123)") + " " + nf.parseNumber("- 123"));

            var de:NumberFormatter = new NumberFormatter("de-DE");
            de.fractionalDigits = 2;
            trace(de.actualLocaleIDName + " " + de.formatNumber(1234567.891) + " " + de.parseNumber("1.234,5"));
            var fr:NumberFormatter = new NumberFormatter("fr-FR");
            fr.fractionalDigits = 2;
            trace(fr.actualLocaleIDName + " " + escape(fr.formatNumber(1234567.891)));
            var zh:NumberFormatter = new NumberFormatter("zh-TW");
            trace(zh.actualLocaleIDName + " " + zh.formatNumber(1234567.891) + " " + zh.lastOperationStatus);
            var ja:NumberFormatter = new NumberFormatter("ja");
            trace(ja.requestedLocaleIDName + " " + ja.actualLocaleIDName + " " + ja.lastOperationStatus + " " + ja.formatNumber(-1234567));
            try {
                new NumberFormatter(null);
            } catch (e:Error) {
                trace("null locale: " + e.errorID);
            }
        }

        private function testCurrencyFormatter():void {
            trace("// CurrencyFormatter");
            var cf:CurrencyFormatter = new CurrencyFormatter("en-US");
            trace(cf.actualLocaleIDName + " " + cf.lastOperationStatus + " " + cf.currencyISOCode + " " + cf.currencySymbol
                + " frac=" + cf.fractionalDigits + " pos=" + cf.positiveCurrencyFormat + " neg=" + cf.negativeCurrencyFormat);
            trace(cf.format(123456789.19) + " | " + cf.format(123456789.19, true) + " | " + cf.format(-1234.5, true) + " | " + cf.format(-1234.5));
            trace(cf.formattingWithCurrencySymbolIsSafe("USD") + " " + cf.formattingWithCurrencySymbolIsSafe("CAD"));
            cf.setCurrency("EUR", "€");
            trace(cf.currencyISOCode + " " + cf.currencySymbol + " " + cf.lastOperationStatus + " " + cf.format(1.5, true));
            cf.setCurrency("eur", "€");
            trace(cf.currencyISOCode + " " + cf.lastOperationStatus);
            cf.setCurrency("USD", "$");
            for (var p:uint = 0; p <= 3; p++) {
                cf.positiveCurrencyFormat = p;
                trace("pos " + p + ": " + cf.format(12.34, true));
            }
            var negs:Array = [];
            for (var n:uint = 0; n <= 15; n++) {
                cf.negativeCurrencyFormat = n;
                negs.push(n + ":" + cf.format(-12.34, true));
            }
            trace(negs.join(" "));
            cf.negativeCurrencyFormat = 16;
            trace(cf.negativeCurrencyFormat + " " + cf.lastOperationStatus);
            cf.negativeCurrencyFormat = 0;
            cf.positiveCurrencyFormat = 0;
            cf.fractionalDigits = 3;
            trace(cf.format(0.12, true) + " " + cf.format(0, true));
            cf.trailingZeros = false;
            cf.leadingZero = false;
            trace(cf.format(0.12, true) + " " + cf.format(0, true));
            cf.trailingZeros = true;
            cf.leadingZero = true;
            cf.fractionalDigits = 2;
            cf.groupingPattern = "3;2;*";
            trace(cf.format(123456789.12, true));
            cf.groupingPattern = "3;*";
            cf.useGrouping = false;
            trace(cf.format(123456789, true));
            cf.useGrouping = true;
            var inputs:Array = ["$123,456.78", "(USD 123.45)", "-1,234.5 USD", "Dollar 123,567,89,0.254", "123.45", "12abc34", "$ -12.50", "$(12.50)"];
            for each (var s:String in inputs) {
                var pr:CurrencyParseResult = cf.parse(s);
                trace("parse(" + s + "): " + pr.value + " [" + pr.currencyString + "] " + cf.lastOperationStatus);
            }
            var de:CurrencyFormatter = new CurrencyFormatter("de-DE");
            trace(de.currencyISOCode + " " + de.currencySymbol + " " + de.format(1234.5, true) + " " + de.format(-1234.5, true) + " " + de.format(1234.5));
            var ja:CurrencyFormatter = new CurrencyFormatter("ja-JP");
            trace(ja.currencyISOCode + " " + ja.currencySymbol + " frac=" + ja.fractionalDigits + " " + ja.format(1234.5, true) + " " + ja.format(-1234.5, true));
            var zh:CurrencyFormatter = new CurrencyFormatter("zh-TW");
            trace(zh.currencyISOCode + " " + zh.currencySymbol + " " + zh.format(1234.5, true) + " " + zh.format(-1234.5, true));
            var fallback:CurrencyFormatter = new CurrencyFormatter("fr-CH");
            trace(fallback.actualLocaleIDName + " " + fallback.lastOperationStatus + " " + fallback.currencyISOCode);
        }

        private function testDateTimeFormatter():void {
            trace("// DateTimeFormatter");
            var date:Date = new Date(Date.UTC(2005, 8, 8, 13, 43, 1, 7));
            var dtf:DateTimeFormatter = new DateTimeFormatter("en-US");
            trace(dtf.actualLocaleIDName + " " + dtf.lastOperationStatus + " " + dtf.getDateStyle() + "/" + dtf.getTimeStyle() + " [" + dtf.getDateTimePattern() + "]");
            trace(dtf.formatUTC(date) + " | " + dtf.format(date));
            var styles:Array = [DateTimeStyle.LONG, DateTimeStyle.MEDIUM, DateTimeStyle.SHORT, DateTimeStyle.NONE];
            for each (var ds:String in styles) {
                for each (var ts:String in styles) {
                    dtf.setDateTimeStyles(ds, ts);
                    trace(ds + "/" + ts + " [" + dtf.getDateTimePattern() + "] " + dtf.formatUTC(date));
                }
            }
            try {
                dtf.setDateTimeStyles("bogus", "long");
            } catch (e:Error) {
                trace("bogus style: " + e.errorID);
            }
            dtf.setDateTimePattern("EEEE, MMM. d, yyyy 'at' h 'o''clock' a");
            trace(dtf.getDateStyle() + "/" + dtf.getTimeStyle() + " " + dtf.lastOperationStatus + " " + dtf.formatUTC(date));
            dtf.setDateTimePattern("mm''ss''");
            trace(dtf.formatUTC(date));
            dtf.setDateTimePattern("G GGGG yy yyyy M MM MMM MMMM MMMMM d dd E EEEE Q QQ QQQ w ww W D DDD F a h hh H HH K k m s S SS SSS SSSSS z zzzz Z ZZZZ v");
            trace(dtf.formatUTC(date));
            trace(dtf.format(date));
            dtf.setDateTimePattern("xx");
            trace(dtf.lastOperationStatus + " " + dtf.getDateTimePattern());
            trace(dtf.getMonthNames().join(",") + " | " + dtf.getMonthNames(DateTimeNameStyle.LONG_ABBREVIATION, DateTimeNameContext.FORMAT).join(","));
            trace(dtf.getWeekdayNames().join(",") + " | " + dtf.getWeekdayNames(DateTimeNameStyle.SHORT_ABBREVIATION).join(",") + " first=" + dtf.getFirstWeekday());
            try {
                dtf.getMonthNames("bogus");
            } catch (e:Error) {
                trace("bogus nameStyle: " + e.errorID);
            }
            var invalid:Date = new Date(NaN);
            trace("[" + dtf.formatUTC(invalid) + "] " + dtf.lastOperationStatus);

            var zh:DateTimeFormatter = new DateTimeFormatter("zh-TW");
            trace(zh.actualLocaleIDName + " [" + zh.getDateTimePattern() + "] " + zh.formatUTC(date));
            zh.setDateTimeStyles(DateTimeStyle.SHORT, DateTimeStyle.SHORT);
            trace(zh.formatUTC(date) + " | " + zh.getMonthNames().join(",") + " | " + zh.getWeekdayNames(DateTimeNameStyle.LONG_ABBREVIATION).join(",") + " first=" + zh.getFirstWeekday());
            var ja:DateTimeFormatter = new DateTimeFormatter("ja-JP", DateTimeStyle.LONG, DateTimeStyle.NONE);
            trace(ja.actualLocaleIDName + " [" + ja.getDateTimePattern() + "] " + ja.formatUTC(date) + " | " + ja.getWeekdayNames().join(","));
            ja.setDateTimePattern("yyyy年M月d日 a h時m分");
            trace(ja.formatUTC(date));
            var de:DateTimeFormatter = new DateTimeFormatter("de-DE", DateTimeStyle.LONG, DateTimeStyle.SHORT);
            trace(de.actualLocaleIDName + " [" + de.getDateTimePattern() + "] " + de.formatUTC(date) + " | " + de.getMonthNames(DateTimeNameStyle.LONG_ABBREVIATION).join(",") + " first=" + de.getFirstWeekday());
            var fallback:DateTimeFormatter = new DateTimeFormatter("de-AT");
            trace(fallback.actualLocaleIDName + " " + fallback.lastOperationStatus);
            trace(DateTimeFormatter.getAvailableLocaleIDNames().join(","));
        }

        private function testCollator():void {
            trace("// Collator");
            var c:Collator = new Collator("en-US");
            trace(c.actualLocaleIDName + " " + c.lastOperationStatus);
            var pairs:Array = [["a", "b"], ["a", "A"], ["e", "é"], ["resume", "RÉSUMÉ"], ["résumé", "rf"], ["2", "a"], ["", "a"],
                ["app", "apple"], ["coté", "côte"], ["version10", "version2"], ["Ａｱ", "Aア"], ["カナ", "かな"], ["O'Brian", "OBrian"], ["a b", "ab"]];
            var p:Array;
            for each (p in pairs) {
                trace(p[0] + " vs " + p[1] + ": " + c.compare(p[0], p[1]) + " " + c.equals(p[0], p[1]));
            }
            trace("// ignoreCase");
            c.ignoreCase = true;
            trace(c.lastOperationStatus + " " + c.compare("abc", "ABC") + " " + c.compare("a", "A") + " " + c.compare("resume", "RÉSUMÉ"));
            trace("// ignoreDiacritics");
            c.ignoreCase = false;
            c.ignoreDiacritics = true;
            trace(c.compare("e", "é") + " " + c.equals("coté", "côte") + " " + c.compare("resume", "RÉSUMÉ"));
            trace("// ignoreSymbols");
            c.ignoreDiacritics = false;
            c.ignoreSymbols = true;
            trace(c.equals("O'Brian", "OBrian") + " " + c.equals("O Brian", "OBrian") + " " + c.equals("ab", "a-c"));
            trace("// numericComparison");
            c.ignoreSymbols = false;
            c.numericComparison = true;
            var versions:Array = ["version10", "version2", "version1", "version010"];
            versions.sort(c.compare);
            trace(versions.join(",") + " " + c.compare("version2", "version10"));
            trace("// ignoreCharacterWidth / ignoreKanaType");
            c.numericComparison = false;
            c.ignoreCharacterWidth = true;
            trace(c.equals("Ａｱ", "Aア") + " " + c.equals("カナ", "かな"));
            c.ignoreKanaType = true;
            trace(c.equals("カナ", "かな") + " " + c.compare("ｶﾅ", "かな"));
            trace("// matching");
            var m:Collator = new Collator("en-US", CollatorMode.MATCHING);
            trace(m.equals("Car", "car") + " " + m.equals("coté", "côte") + " " + m.equals("Ａｱ", "Aア") + " " + m.equals("O'Brian", "OBrian"));
            var sorted:Array = ["banana", "Apple", "cherry", "apple", "Äpfel", "zebra"];
            sorted.sort(new Collator("en-US").compare);
            trace(sorted.join(","));
            trace("// locales");
            var sv:Collator = new Collator("sv-SE");
            var svWords:Array = ["ö", "a", "z", "å", "ä", "o"];
            svWords.sort(sv.compare);
            trace(sv.actualLocaleIDName + " " + svWords.join(","));
            var phone:Collator = new Collator("de-DE@collation=phonebook");
            trace(phone.actualLocaleIDName + " " + phone.compare("Müller", "Mueller") + " " + new Collator("de-DE").compare("Müller", "Mueller"));
            var fallback:Collator = new Collator("fr-CH");
            trace(fallback.actualLocaleIDName + " " + fallback.lastOperationStatus);
            var unknown:Collator = new Collator("xx-YY");
            trace(unknown.actualLocaleIDName + " " + unknown.lastOperationStatus);
            trace(Collator.getAvailableLocaleIDNames().length);
        }
    }
}
