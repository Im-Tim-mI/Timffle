/** Probe: flash.globalization in Flash Player 32 for zh-TW / zh-CN / en-US / ja-JP / de-DE —
 *  DateTimeFormatter patterns, names and formatted output; NumberFormatter defaults, output,
 *  out-of-range settings (status vs ArgumentError); CurrencyFormatter defaults, output,
 *  parse(); StringTools case mapping; Collator representative comparisons.
 *  Builds with -D harness (Flash, reports to the difftest server) or without (trace, Ruffle test). */
import flash.globalization.*;

class S1Global {
	static var locales = ["en-US", "zh-TW", "zh-CN", "ja-JP", "de-DE"];

	static function step(label:String, f:Void->Void) {
		try {
			f();
		} catch (e:flash.errors.Error) {
			Out.line(label + " THREW " + e.name + " #" + e.errorID);
		}
	}

	static function hex(n:UInt):String {
		return untyped n.toString(16);
	}

	static function v(x:flash.Vector<String>):String {
		var a = [];
		for (s in x) a.push(s);
		return "[" + a.join("|") + "]";
	}

	static function dtf() {
		Out.line("// DateTimeFormatter");
		var names = DateTimeFormatter.getAvailableLocaleIDNames();
		Out.line("available=" + names.length + " has zh-TW=" + (names.indexOf("zh-TW") >= 0) + " zh-CN=" + (names.indexOf("zh-CN") >= 0) + " ja-JP=" + (names.indexOf("ja-JP") >= 0) + " de-DE=" + (names.indexOf("de-DE") >= 0) + " zh-Hant-TW=" + (names.indexOf("zh-Hant-TW") >= 0));
		// 2024-03-05 14:07:09.045 in UTC (formatUTC), plus `format` for the player's zone
		var d = new Date(2024, 2, 5, 14, 7, 9);
		var utc:Date = Date.fromTime(untyped __global__["Date"].UTC(2024, 2, 5, 14, 7, 9, 45));
		for (loc in locales) {
			step(loc, function() {
				var f = new DateTimeFormatter(loc);
				Out.line(loc + " actual=" + f.actualLocaleIDName + " status=" + f.lastOperationStatus + " firstWeekday=" + f.getFirstWeekday());
				var styles = [DateTimeStyle.LONG, DateTimeStyle.MEDIUM, DateTimeStyle.SHORT, DateTimeStyle.NONE];
				var sn = ["long", "medium", "short", "none"];
				for (i in 0...4) {
					f.setDateTimeStyles(styles[i], DateTimeStyle.NONE);
					var pd = f.getDateTimePattern();
					f.setDateTimeStyles(DateTimeStyle.NONE, styles[i]);
					var pt = f.getDateTimePattern();
					f.setDateTimeStyles(styles[i], styles[i]);
					Out.line(loc + " " + sn[i] + " date=[" + pd + "] time=[" + pt + "] both=[" + f.getDateTimePattern() + "] -> " + f.formatUTC(utc));
				}
				f.setDateTimeStyles(DateTimeStyle.LONG, DateTimeStyle.LONG);
				Out.line(loc + " local=" + f.format(d));
				Out.line(loc + " months=" + v(f.getMonthNames()) + " short=" + v(f.getMonthNames(DateTimeNameStyle.SHORT_ABBREVIATION)) + " longAbbr=" + v(f.getMonthNames(DateTimeNameStyle.LONG_ABBREVIATION)) + " standalone=" + v(f.getMonthNames(DateTimeNameStyle.FULL, DateTimeNameContext.STANDALONE)));
				Out.line(loc + " weekdays=" + v(f.getWeekdayNames()) + " short=" + v(f.getWeekdayNames(DateTimeNameStyle.SHORT_ABBREVIATION)) + " longAbbr=" + v(f.getWeekdayNames(DateTimeNameStyle.LONG_ABBREVIATION)));
				f.setDateTimePattern("yyyy-MM-dd EEEE EEE MMM MMMM a h:mm:ss K k H z Z v Q QQQ w D F 'o''clock'");
				Out.line(loc + " pattern status=" + f.lastOperationStatus + " -> " + f.formatUTC(utc));
				f.setDateTimePattern("G GGGG yy y yyyyy MMMMM EEEEE S SS SSSSS");
				Out.line(loc + " pattern2 -> " + f.formatUTC(utc));
			});
		}
		step("bad pattern", function() {
			var f = new DateTimeFormatter("en-US");
			f.setDateTimePattern("xx");
			Out.line("xx status=" + f.lastOperationStatus + " pattern=[" + f.getDateTimePattern() + "]");
			f.setDateTimePattern(null);
			Out.line("null pattern status=" + f.lastOperationStatus);
		});
		step("bad style", function() {
			var f = new DateTimeFormatter("en-US");
			f.setDateTimeStyles(cast "bogus", DateTimeStyle.SHORT);
			Out.line("bogus style status=" + f.lastOperationStatus);
		});
		step("bad nameStyle", function() {
			var f = new DateTimeFormatter("en-US");
			var m = f.getMonthNames(cast "bogus");
			Out.line("bogus nameStyle -> " + (m == null ? "null" : "" + m.length) + " status=" + f.lastOperationStatus);
		});
		step("invalid date", function() {
			var f = new DateTimeFormatter("en-US");
			var s = f.format(Date.fromTime(Math.NaN));
			Out.line("NaN date -> [" + s + "] status=" + f.lastOperationStatus);
			s = f.format(null);
			Out.line("null date -> [" + s + "] status=" + f.lastOperationStatus);
		});
	}

	static function nf() {
		Out.line("// NumberFormatter");
		for (loc in locales) {
			step(loc, function() {
				var f = new NumberFormatter(loc);
				Out.line(loc + " actual=" + f.actualLocaleIDName + " status=" + f.lastOperationStatus + " frac=" + f.fractionalDigits + " group=[" + f.groupingSeparator + "] dec=[" + f.decimalSeparator + "] pattern=" + f.groupingPattern + " negFmt=" + f.negativeNumberFormat + " negSym=[" + f.negativeSymbol + "] digits=" + hex(cast f.digitsType) + " leadingZero=" + f.leadingZero + " trailingZeros=" + f.trailingZeros + " useGrouping=" + f.useGrouping);
				Out.line(loc + " " + f.formatNumber(1234567.891) + " | " + f.formatNumber(-1234.5) + " | " + f.formatNumber(0.5) + " | " + f.formatInt(-1234567) + " | " + f.formatUint(cast 4294967295.0));
				f.fractionalDigits = 2;
				Out.line(loc + " frac2 " + f.formatNumber(1234567.891) + " | " + f.formatNumber(-1234.5) + " | " + f.formatNumber(0.005) + " | " + f.formatNumber(2.345) + " | " + f.formatNumber(-0.001));
				var r = f.parse("x 1,234.56 y");
				Out.line(loc + " parse=" + r.value + " " + r.startIndex + "-" + r.endIndex + " status=" + f.lastOperationStatus);
				r = f.parse("(123)");
				Out.line(loc + " parse(123)=" + r.value + " " + r.startIndex + "-" + r.endIndex + " status=" + f.lastOperationStatus);
				Out.line(loc + " parseNumber=" + f.parseNumber("1234.5") + " status=" + f.lastOperationStatus + " / " + f.parseNumber("1,234.5") + " status=" + f.lastOperationStatus);
			});
		}
		step("out of range", function() {
			var f = new NumberFormatter("en-US");
			step("negativeNumberFormat=7", function() {
				f.negativeNumberFormat = 7;
				Out.line("negFmt=7 -> " + f.negativeNumberFormat + " status=" + f.lastOperationStatus);
			});
			step("fractionalDigits=-1", function() {
				f.fractionalDigits = -1;
				Out.line("frac=-1 -> " + f.fractionalDigits + " status=" + f.lastOperationStatus);
			});
			step("fractionalDigits=25", function() {
				f.fractionalDigits = 25;
				Out.line("frac=25 -> " + f.fractionalDigits + " status=" + f.lastOperationStatus + " " + f.formatNumber(1.5));
			});
			step("groupingPattern=3;", function() {
				f.groupingPattern = "3;";
				Out.line("pattern=3; -> " + f.groupingPattern + " status=" + f.lastOperationStatus);
			});
			step("groupingPattern=abc", function() {
				f.groupingPattern = "abc";
				Out.line("pattern=abc -> " + f.groupingPattern + " status=" + f.lastOperationStatus);
			});
			step("digitsType=5", function() {
				f.digitsType = cast 5;
				Out.line("digitsType=5 -> " + hex(cast f.digitsType) + " status=" + f.lastOperationStatus);
			});
			step("digitsType=arabic", function() {
				f.digitsType = NationalDigitsType.ARABIC_INDIC;
				Out.line("digitsType=arabic -> " + hex(cast f.digitsType) + " status=" + f.lastOperationStatus + " " + f.formatNumber(-1234.5));
				f.digitsType = NationalDigitsType.EUROPEAN;
			});
			step("groupingSeparator=null", function() {
				f.groupingSeparator = null;
				Out.line("groupSep=null -> [" + f.groupingSeparator + "] status=" + f.lastOperationStatus);
			});
			step("groupingSeparator=''", function() {
				f.groupingSeparator = "";
				Out.line("groupSep='' -> [" + f.groupingSeparator + "] status=" + f.lastOperationStatus + " " + f.formatNumber(1234567));
			});
			step("decimalSeparator=ab", function() {
				f.decimalSeparator = "ab";
				Out.line("decSep=ab -> [" + f.decimalSeparator + "] status=" + f.lastOperationStatus + " " + f.formatNumber(1.5));
			});
			step("negativeSymbol=''", function() {
				f.negativeSymbol = "";
				Out.line("negSym='' -> [" + f.negativeSymbol + "] status=" + f.lastOperationStatus + " " + f.formatNumber(-1.5));
			});
			step("negativeSymbol=~", function() {
				var g = new NumberFormatter("en-US");
				g.negativeSymbol = "~";
				Out.line("negSym=~ -> [" + g.negativeSymbol + "] status=" + g.lastOperationStatus + " " + g.formatNumber(-1.5));
				g.negativeSymbol = "-";
				Out.line("negSym=- -> [" + g.negativeSymbol + "] status=" + g.lastOperationStatus);
				var c = new CurrencyFormatter("en-US");
				c.negativeSymbol = "~";
				Out.line("currency negSym=~ -> [" + c.negativeSymbol + "] status=" + c.lastOperationStatus + " " + c.format(-1.5, true));
				c.decimalSeparator = ",";
				Out.line("currency decSep=, -> [" + c.decimalSeparator + "] status=" + c.lastOperationStatus + " " + c.format(-1.5, true));
			});
			step("locale null", function() {
				var g = new NumberFormatter(null);
				Out.line("null locale -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus);
			});
			step("locale bogus", function() {
				var g = new NumberFormatter("xx-YY");
				Out.line("xx-YY -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus);
				g = new NumberFormatter("de-AT");
				Out.line("de-AT -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus + " " + g.formatNumber(1234.5));
				g = new NumberFormatter("de");
				Out.line("de -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus);
				g = new NumberFormatter("zh");
				Out.line("zh -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus);
				g = new NumberFormatter("zh-Hant-TW");
				Out.line("zh-Hant-TW -> " + g.actualLocaleIDName + " status=" + g.lastOperationStatus);
			});
		});
	}

	static function cf() {
		Out.line("// CurrencyFormatter");
		for (loc in locales) {
			step(loc, function() {
				var f = new CurrencyFormatter(loc);
				Out.line(loc + " actual=" + f.actualLocaleIDName + " status=" + f.lastOperationStatus + " iso=" + f.currencyISOCode + " sym=[" + f.currencySymbol + "] frac=" + f.fractionalDigits + " group=[" + f.groupingSeparator + "] dec=[" + f.decimalSeparator + "] pattern=" + f.groupingPattern + " pos=" + f.positiveCurrencyFormat + " neg=" + f.negativeCurrencyFormat + " negSym=[" + f.negativeSymbol + "] leadingZero=" + f.leadingZero + " trailingZeros=" + f.trailingZeros + " useGrouping=" + f.useGrouping);
				Out.line(loc + " " + f.format(1234.567) + " | " + f.format(-1234.5) + " | " + f.format(1234.5, true) + " | " + f.format(-1234.5, true) + " | " + f.format(0.5, true));
				Out.line(loc + " safeUSD=" + f.formattingWithCurrencySymbolIsSafe("USD") + " safeOwn=" + f.formattingWithCurrencySymbolIsSafe(f.currencyISOCode) + " status=" + f.lastOperationStatus);
				f.setCurrency("USD", "US$");
				Out.line(loc + " setCurrency status=" + f.lastOperationStatus + " " + f.format(-1234.5) + " | " + f.format(-1234.5, true));
			});
		}
		step("setCurrency bad", function() {
			var f = new CurrencyFormatter("en-US");
			f.setCurrency("usd", "x");
			Out.line("usd -> iso=" + f.currencyISOCode + " sym=[" + f.currencySymbol + "] status=" + f.lastOperationStatus);
			f.setCurrency("ABCD", "x");
			Out.line("ABCD -> iso=" + f.currencyISOCode + " sym=[" + f.currencySymbol + "] status=" + f.lastOperationStatus);
			f.setCurrency("XYZ", "");
			Out.line("XYZ,'' -> iso=" + f.currencyISOCode + " sym=[" + f.currencySymbol + "] status=" + f.lastOperationStatus + " " + f.format(1, true));
			step("setCurrency null", function() {
				f.setCurrency(null, "x");
				Out.line("null -> iso=" + f.currencyISOCode + " status=" + f.lastOperationStatus);
			});
		});
		step("out of range", function() {
			var f = new CurrencyFormatter("en-US");
			step("positiveCurrencyFormat=4", function() {
				f.positiveCurrencyFormat = 4;
				Out.line("pos=4 -> " + f.positiveCurrencyFormat + " status=" + f.lastOperationStatus);
			});
			step("negativeCurrencyFormat=16", function() {
				f.negativeCurrencyFormat = 16;
				Out.line("neg=16 -> " + f.negativeCurrencyFormat + " status=" + f.lastOperationStatus);
			});
			step("fractionalDigits=-1", function() {
				f.fractionalDigits = -1;
				Out.line("frac=-1 -> " + f.fractionalDigits + " status=" + f.lastOperationStatus);
			});
			step("all negative formats", function() {
				var a = [];
				for (i in 0...16) {
					f.negativeCurrencyFormat = i;
					a.push(i + ":" + f.format(-1.5, true));
				}
				Out.line(a.join(" "));
				a = [];
				for (i in 0...4) {
					f.positiveCurrencyFormat = i;
					a.push(i + ":" + f.format(1.5, true));
				}
				Out.line(a.join(" "));
			});
		});
		step("parse", function() {
			var f = new CurrencyFormatter("en-US");
			var inputs = ["$ 5", "$  5", "USD  5", " $5", "$5 ", "US$ 5", "(USD 5)", "( $5 )", "$5.", "$.5", "$1,23", "$1e3", "$+5", "$1 000", "$1,234,567.891", "$1,234.56", "1234.56 USD", "USD 1234.56", "(€12.5)", "12abc34", "USD 12 EUR", "-$5", "$ 5 -", "5.5$", "  $  1,000  ", "$-5", "-5", "5", "$", "", "1.5 USD extra", "$1.5 USD", "$(1.5)", "($1.5)", "1,2,3.4"];
			for (s in inputs) {
				var r = f.parse(s);
				Out.line("parse[" + s + "] -> " + r.value + " cur=[" + r.currencyString + "] status=" + f.lastOperationStatus);
			}
			step("parse null", function() {
				var r = f.parse(null);
				Out.line("parse null -> " + r.value + " status=" + f.lastOperationStatus);
			});
			var g = new CurrencyFormatter("de-DE");
			for (s in ["5€", "5  €", "5 € ", "-5€", "5 €-", "(5 €)", "1.234,56 €", "€ 1.234,56", "-1,5 €", "1,5 EUR", "1.234,56"]) {
				var r = g.parse(s);
				Out.line("de parse[" + s + "] -> " + r.value + " cur=[" + r.currencyString + "] status=" + g.lastOperationStatus);
			}
		});
	}

	static function st() {
		Out.line("// StringTools");
		var sample = "Iİıi ß Σς ǅ ÀÉ ﬁ";
		for (loc in locales.concat(["tr-TR", "lt-LT"])) {
			step(loc, function() {
				var t = new flash.globalization.StringTools(loc);
				Out.line(loc + " actual=" + t.actualLocaleIDName + " status=" + t.lastOperationStatus + " upper=[" + t.toUpperCase(sample) + "] status=" + t.lastOperationStatus + " lower=[" + t.toLowerCase(sample) + "] status=" + t.lastOperationStatus);
			});
		}
		step("null", function() {
			var t = new flash.globalization.StringTools("en-US");
			Out.line("null -> [" + t.toUpperCase(null) + "] status=" + t.lastOperationStatus);
		});
	}

	static function col() {
		Out.line("// Collator");
		var pairs = [["a", "A"], ["A", "a"], ["a", "b"], ["é", "e"], ["e", "é"], ["ab", "aB"], ["version2", "version10"], ["O'Brian", "OBrian"], ["ａ", "a"], ["ア", "あ"], ["a", "ä"], ["ä", "b"], ["z", "ä"], ["中", "文"], ["一", "丁"], ["ab", "a b"], ["a-b", "ab"], ["10", "9"], ["", "a"], ["æ", "ae"], ["ß", "ss"], ["Z", "a"], ["あ", "い"], ["ア", "イ"], ["cote", "côte"], ["côte", "coté"], ["ok", "OK"]];
		for (loc in locales.concat(["sv-SE"])) {
			step(loc, function() {
				var c = new Collator(loc);
				var a = [];
				for (p in pairs) a.push(p[0] + "/" + p[1] + "=" + c.compare(p[0], p[1]));
				Out.line(loc + " actual=" + c.actualLocaleIDName + " status=" + c.lastOperationStatus + " sorting: " + a.join(" "));
				var m = new Collator(loc, CollatorMode.MATCHING);
				a = [];
				for (p in pairs) a.push(p[0] + "/" + p[1] + "=" + m.compare(p[0], p[1]) + (m.equals(p[0], p[1]) ? "=" : ""));
				Out.line(loc + " matching: " + a.join(" "));
				Out.line(loc + " flags sorting: ignoreCase=" + c.ignoreCase + " ignoreDiacritics=" + c.ignoreDiacritics + " ignoreSymbols=" + c.ignoreSymbols + " ignoreKanaType=" + c.ignoreKanaType + " ignoreCharacterWidth=" + c.ignoreCharacterWidth + " numeric=" + c.numericComparison + " matching: ignoreCase=" + m.ignoreCase + " ignoreDiacritics=" + m.ignoreDiacritics + " ignoreSymbols=" + m.ignoreSymbols + " ignoreKanaType=" + m.ignoreKanaType + " ignoreCharacterWidth=" + m.ignoreCharacterWidth + " numeric=" + m.numericComparison);
			});
		}
		step("flags", function() {
			var c = new Collator("en-US");
			c.numericComparison = true;
			Out.line("numeric: version2/version10=" + c.compare("version2", "version10") + " 10/9=" + c.compare("10", "9") + " a10/a9=" + c.compare("a10", "a9") + " status=" + c.lastOperationStatus);
			c.numericComparison = false;
			c.ignoreCase = true;
			Out.line("ignoreCase: a/A=" + c.compare("a", "A") + " ab/aB=" + c.compare("ab", "aB") + " status=" + c.lastOperationStatus);
			c.ignoreCase = false;
			c.ignoreDiacritics = true;
			Out.line("ignoreDiacritics: é/e=" + c.compare("é", "e") + " a/ä=" + c.compare("a", "ä") + " status=" + c.lastOperationStatus);
			c.ignoreDiacritics = false;
			c.ignoreSymbols = true;
			Out.line("ignoreSymbols: O'Brian/OBrian=" + c.compare("O'Brian", "OBrian") + " ab/a b=" + c.compare("ab", "a b") + " a-b/ab=" + c.compare("a-b", "ab") + " status=" + c.lastOperationStatus);
			c.ignoreSymbols = false;
			c.ignoreCharacterWidth = true;
			Out.line("ignoreWidth: ａ/a=" + c.compare("ａ", "a") + " status=" + c.lastOperationStatus);
			c.ignoreCharacterWidth = false;
			c.ignoreKanaType = true;
			Out.line("ignoreKana: ア/あ=" + c.compare("ア", "あ") + " status=" + c.lastOperationStatus);
			step("compare null", function() {
				Out.line("null/a=" + c.compare(null, "a"));
			});
		});
	}

	static function main() {
		Out.start("s1global");
		dtf();
		nf();
		cf();
		st();
		col();
		Out.finish();
	}
}
