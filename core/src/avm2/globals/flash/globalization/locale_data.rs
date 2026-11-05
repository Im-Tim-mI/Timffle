//! Timffle: locale data shared by the `flash.globalization` classes.
//!
//! Flash Player implements `flash.globalization` on top of the operating
//! system's locale services (Windows NLS, ICU on Mac/Linux). This player runs
//! inside a browser or a desktop shell without a per-locale OS service, so the
//! data Flash would read from the OS is compiled into the binary here: number
//! and currency conventions, month/weekday names, the date/time patterns used
//! by `DateTimeStyle`, and the first weekday. Locales without a table fall back
//! exactly as Flash documents it: a locale of the same language reports
//! `usingFallbackWarning`, an unknown language falls back to the player's
//! default locale and reports `usingDefaultWarning`.

use crate::avm2::activation::Activation;
use crate::system_properties::Language;

/// Values of `flash.globalization.LastOperationStatus` used by this module.
pub const NO_ERROR: &str = "noError";
pub const USING_FALLBACK_WARNING: &str = "usingFallbackWarning";
pub const USING_DEFAULT_WARNING: &str = "usingDefaultWarning";
pub const ILLEGAL_ARGUMENT_ERROR: &str = "illegalArgumentError";
pub const PARSE_ERROR: &str = "parseError";
pub const PATTERN_SYNTAX_ERROR: &str = "patternSyntaxError";
pub const UNEXPECTED_TOKEN: &str = "unexpectedToken";

/// Per-language names (month and weekday names, AM/PM markers).
pub struct Names {
    pub months: [&'static str; 12],
    pub months_abbr: [&'static str; 12],
    /// Month names in `DateTimeNameContext.FORMAT` context (genitive forms in
    /// Slavic languages); `None` when identical to the standalone names.
    pub months_format: Option<[&'static str; 12]>,
    pub weekdays: [&'static str; 7],
    pub weekdays_abbr: [&'static str; 7],
    pub am_pm: [&'static str; 2],
}

/// One locale as Flash Player would obtain it from the OS.
pub struct LocaleData {
    /// Canonical locale ID name, e.g. `en-US`.
    pub id: &'static str,
    pub language: &'static str,
    pub names: &'static Names,
    pub decimal_separator: &'static str,
    pub grouping_separator: &'static str,
    /// Zero digit of the digit set (`NationalDigitsType`).
    pub digits_type: u32,
    pub negative_number_format: u32,
    pub currency_iso: &'static str,
    pub currency_symbol: &'static str,
    pub currency_fraction_digits: i32,
    pub positive_currency_format: u32,
    pub negative_currency_format: u32,
    /// 0 = Sunday … 6 = Saturday.
    pub first_weekday: i32,
    /// Date patterns for `DateTimeStyle.LONG`, `MEDIUM`, `SHORT`.
    pub date_patterns: [&'static str; 3],
    /// Time patterns for `DateTimeStyle.LONG`, `MEDIUM`, `SHORT`.
    pub time_patterns: [&'static str; 3],
}

static EN: Names = Names {
    months: [
        "January",
        "February",
        "March",
        "April",
        "May",
        "June",
        "July",
        "August",
        "September",
        "October",
        "November",
        "December",
    ],
    months_abbr: [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ],
    months_format: None,
    weekdays: [
        "Sunday",
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
    ],
    weekdays_abbr: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
    am_pm: ["AM", "PM"],
};

static DE: Names = Names {
    months: [
        "Januar",
        "Februar",
        "März",
        "April",
        "Mai",
        "Juni",
        "Juli",
        "August",
        "September",
        "Oktober",
        "November",
        "Dezember",
    ],
    months_abbr: [
        "Jan", "Feb", "Mär", "Apr", "Mai", "Jun", "Jul", "Aug", "Sep", "Okt", "Nov", "Dez",
    ],
    months_format: None,
    weekdays: [
        "Sonntag",
        "Montag",
        "Dienstag",
        "Mittwoch",
        "Donnerstag",
        "Freitag",
        "Samstag",
    ],
    weekdays_abbr: ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"],
    am_pm: ["vorm.", "nachm."],
};

static FR: Names = Names {
    months: [
        "janvier",
        "février",
        "mars",
        "avril",
        "mai",
        "juin",
        "juillet",
        "août",
        "septembre",
        "octobre",
        "novembre",
        "décembre",
    ],
    months_abbr: [
        "janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.",
        "déc.",
    ],
    months_format: None,
    weekdays: [
        "dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi",
    ],
    weekdays_abbr: ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."],
    am_pm: ["AM", "PM"],
};

static ES: Names = Names {
    months: [
        "enero",
        "febrero",
        "marzo",
        "abril",
        "mayo",
        "junio",
        "julio",
        "agosto",
        "septiembre",
        "octubre",
        "noviembre",
        "diciembre",
    ],
    months_abbr: [
        "ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sep", "oct", "nov", "dic",
    ],
    months_format: None,
    weekdays: [
        "domingo",
        "lunes",
        "martes",
        "miércoles",
        "jueves",
        "viernes",
        "sábado",
    ],
    weekdays_abbr: ["dom", "lun", "mar", "mié", "jue", "vie", "sáb"],
    am_pm: ["a. m.", "p. m."],
};

static IT: Names = Names {
    months: [
        "gennaio",
        "febbraio",
        "marzo",
        "aprile",
        "maggio",
        "giugno",
        "luglio",
        "agosto",
        "settembre",
        "ottobre",
        "novembre",
        "dicembre",
    ],
    months_abbr: [
        "gen", "feb", "mar", "apr", "mag", "giu", "lug", "ago", "set", "ott", "nov", "dic",
    ],
    months_format: None,
    weekdays: [
        "domenica",
        "lunedì",
        "martedì",
        "mercoledì",
        "giovedì",
        "venerdì",
        "sabato",
    ],
    weekdays_abbr: ["dom", "lun", "mar", "mer", "gio", "ven", "sab"],
    am_pm: ["AM", "PM"],
};

static PT: Names = Names {
    months: [
        "janeiro",
        "fevereiro",
        "março",
        "abril",
        "maio",
        "junho",
        "julho",
        "agosto",
        "setembro",
        "outubro",
        "novembro",
        "dezembro",
    ],
    months_abbr: [
        "jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez",
    ],
    months_format: None,
    weekdays: [
        "domingo",
        "segunda-feira",
        "terça-feira",
        "quarta-feira",
        "quinta-feira",
        "sexta-feira",
        "sábado",
    ],
    weekdays_abbr: ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"],
    am_pm: ["AM", "PM"],
};

static NL: Names = Names {
    months: [
        "januari",
        "februari",
        "maart",
        "april",
        "mei",
        "juni",
        "juli",
        "augustus",
        "september",
        "oktober",
        "november",
        "december",
    ],
    months_abbr: [
        "jan", "feb", "mrt", "apr", "mei", "jun", "jul", "aug", "sep", "okt", "nov", "dec",
    ],
    months_format: None,
    weekdays: [
        "zondag",
        "maandag",
        "dinsdag",
        "woensdag",
        "donderdag",
        "vrijdag",
        "zaterdag",
    ],
    weekdays_abbr: ["zo", "ma", "di", "wo", "do", "vr", "za"],
    am_pm: ["a.m.", "p.m."],
};

static SV: Names = Names {
    months: [
        "januari",
        "februari",
        "mars",
        "april",
        "maj",
        "juni",
        "juli",
        "augusti",
        "september",
        "oktober",
        "november",
        "december",
    ],
    months_abbr: [
        "jan", "feb", "mar", "apr", "maj", "jun", "jul", "aug", "sep", "okt", "nov", "dec",
    ],
    months_format: None,
    weekdays: [
        "söndag", "måndag", "tisdag", "onsdag", "torsdag", "fredag", "lördag",
    ],
    weekdays_abbr: ["sön", "mån", "tis", "ons", "tors", "fre", "lör"],
    am_pm: ["fm", "em"],
};

static PL: Names = Names {
    months: [
        "styczeń",
        "luty",
        "marzec",
        "kwiecień",
        "maj",
        "czerwiec",
        "lipiec",
        "sierpień",
        "wrzesień",
        "październik",
        "listopad",
        "grudzień",
    ],
    months_abbr: [
        "sty", "lut", "mar", "kwi", "maj", "cze", "lip", "sie", "wrz", "paź", "lis", "gru",
    ],
    months_format: Some([
        "stycznia",
        "lutego",
        "marca",
        "kwietnia",
        "maja",
        "czerwca",
        "lipca",
        "sierpnia",
        "września",
        "października",
        "listopada",
        "grudnia",
    ]),
    weekdays: [
        "niedziela",
        "poniedziałek",
        "wtorek",
        "środa",
        "czwartek",
        "piątek",
        "sobota",
    ],
    weekdays_abbr: ["niedz.", "pon.", "wt.", "śr.", "czw.", "pt.", "sob."],
    am_pm: ["AM", "PM"],
};

static RU: Names = Names {
    months: [
        "январь",
        "февраль",
        "март",
        "апрель",
        "май",
        "июнь",
        "июль",
        "август",
        "сентябрь",
        "октябрь",
        "ноябрь",
        "декабрь",
    ],
    months_abbr: [
        "янв", "фев", "мар", "апр", "май", "июн", "июл", "авг", "сен", "окт", "ноя", "дек",
    ],
    months_format: Some([
        "января",
        "февраля",
        "марта",
        "апреля",
        "мая",
        "июня",
        "июля",
        "августа",
        "сентября",
        "октября",
        "ноября",
        "декабря",
    ]),
    weekdays: [
        "воскресенье",
        "понедельник",
        "вторник",
        "среда",
        "четверг",
        "пятница",
        "суббота",
    ],
    weekdays_abbr: ["Вс", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"],
    am_pm: ["AM", "PM"],
};

static TR: Names = Names {
    months: [
        "Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim",
        "Kasım", "Aralık",
    ],
    months_abbr: [
        "Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara",
    ],
    months_format: None,
    weekdays: [
        "Pazar",
        "Pazartesi",
        "Salı",
        "Çarşamba",
        "Perşembe",
        "Cuma",
        "Cumartesi",
    ],
    weekdays_abbr: ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"],
    am_pm: ["ÖÖ", "ÖS"],
};

static JA: Names = Names {
    months: [
        "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月",
    ],
    months_abbr: [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
    ],
    months_format: None,
    weekdays: [
        "日曜日",
        "月曜日",
        "火曜日",
        "水曜日",
        "木曜日",
        "金曜日",
        "土曜日",
    ],
    weekdays_abbr: ["日", "月", "火", "水", "木", "金", "土"],
    am_pm: ["午前", "午後"],
};

static KO: Names = Names {
    months: [
        "1월", "2월", "3월", "4월", "5월", "6월", "7월", "8월", "9월", "10월", "11월", "12월",
    ],
    months_abbr: [
        "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12",
    ],
    months_format: None,
    weekdays: [
        "일요일",
        "월요일",
        "화요일",
        "수요일",
        "목요일",
        "금요일",
        "토요일",
    ],
    weekdays_abbr: ["일", "월", "화", "수", "목", "금", "토"],
    am_pm: ["오전", "오후"],
};

static ZH_HANT: Names = Names {
    months: [
        "一月",
        "二月",
        "三月",
        "四月",
        "五月",
        "六月",
        "七月",
        "八月",
        "九月",
        "十月",
        "十一月",
        "十二月",
    ],
    months_abbr: [
        "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月",
    ],
    months_format: None,
    weekdays: [
        "星期日",
        "星期一",
        "星期二",
        "星期三",
        "星期四",
        "星期五",
        "星期六",
    ],
    weekdays_abbr: ["週日", "週一", "週二", "週三", "週四", "週五", "週六"],
    am_pm: ["上午", "下午"],
};

static ZH_HANS: Names = Names {
    months: [
        "一月",
        "二月",
        "三月",
        "四月",
        "五月",
        "六月",
        "七月",
        "八月",
        "九月",
        "十月",
        "十一月",
        "十二月",
    ],
    months_abbr: [
        "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月",
    ],
    months_format: None,
    weekdays: [
        "星期日",
        "星期一",
        "星期二",
        "星期三",
        "星期四",
        "星期五",
        "星期六",
    ],
    weekdays_abbr: ["周日", "周一", "周二", "周三", "周四", "周五", "周六"],
    am_pm: ["上午", "下午"],
};

const NBSP: &str = "\u{a0}";

/// The locales this player carries data for. The first entry of each language
/// is the fallback for other regions of that language.
pub static LOCALES: &[LocaleData] = &[
    LocaleData {
        id: "en-US",
        language: "en",
        names: &EN,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "USD",
        currency_symbol: "$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 0,
        first_weekday: 0,
        date_patterns: ["EEEE, MMMM d, yyyy", "MMM d, yyyy", "M/d/yyyy"],
        time_patterns: ["h:mm:ss a", "h:mm:ss a", "h:mm a"],
    },
    LocaleData {
        id: "en-GB",
        language: "en",
        names: &EN,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "GBP",
        currency_symbol: "£",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 1,
        date_patterns: ["EEEE, d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "en-CA",
        language: "en",
        names: &EN,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "CAD",
        currency_symbol: "$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["EEEE, MMMM d, yyyy", "MMM d, yyyy", "yyyy-MM-dd"],
        time_patterns: ["h:mm:ss a", "h:mm:ss a", "h:mm a"],
    },
    LocaleData {
        id: "en-AU",
        language: "en",
        names: &EN,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "AUD",
        currency_symbol: "$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 1,
        date_patterns: ["EEEE, d MMMM yyyy", "d MMM yyyy", "d/MM/yyyy"],
        time_patterns: ["h:mm:ss a", "h:mm:ss a", "h:mm a"],
    },
    LocaleData {
        id: "de-DE",
        language: "de",
        names: &DE,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["EEEE, d. MMMM yyyy", "dd.MM.yyyy", "dd.MM.yy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "fr-FR",
        language: "fr",
        names: &FR,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["EEEE d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "fr-CA",
        language: "fr",
        names: &FR,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "CAD",
        currency_symbol: "$",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 0,
        date_patterns: ["EEEE d MMMM yyyy", "d MMM yyyy", "yyyy-MM-dd"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "es-ES",
        language: "es",
        names: &ES,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["EEEE, d 'de' MMMM 'de' yyyy", "d MMM yyyy", "dd/MM/yyyy"],
        time_patterns: ["H:mm:ss", "H:mm:ss", "H:mm"],
    },
    LocaleData {
        id: "es-MX",
        language: "es",
        names: &ES,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "MXN",
        currency_symbol: "$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["EEEE, d 'de' MMMM 'de' yyyy", "d MMM yyyy", "dd/MM/yyyy"],
        time_patterns: ["h:mm:ss a", "h:mm:ss a", "h:mm a"],
    },
    LocaleData {
        id: "it-IT",
        language: "it",
        names: &IT,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 2,
        negative_currency_format: 9,
        first_weekday: 1,
        date_patterns: ["EEEE d MMMM yyyy", "d MMM yyyy", "dd/MM/yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "pt-BR",
        language: "pt",
        names: &PT,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "BRL",
        currency_symbol: "R$",
        currency_fraction_digits: 2,
        positive_currency_format: 2,
        negative_currency_format: 9,
        first_weekday: 0,
        date_patterns: [
            "EEEE, d 'de' MMMM 'de' yyyy",
            "d 'de' MMM 'de' yyyy",
            "dd/MM/yyyy",
        ],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "pt-PT",
        language: "pt",
        names: &PT,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: [
            "EEEE, d 'de' MMMM 'de' yyyy",
            "d 'de' MMM 'de' yyyy",
            "dd/MM/yyyy",
        ],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "nl-NL",
        language: "nl",
        names: &NL,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "EUR",
        currency_symbol: "€",
        currency_fraction_digits: 2,
        positive_currency_format: 2,
        negative_currency_format: 12,
        first_weekday: 1,
        date_patterns: ["EEEE d MMMM yyyy", "d MMM yyyy", "dd-MM-yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "sv-SE",
        language: "sv",
        names: &SV,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "SEK",
        currency_symbol: "kr",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["EEEE d MMMM yyyy", "d MMM yyyy", "yyyy-MM-dd"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "pl-PL",
        language: "pl",
        names: &PL,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "PLN",
        currency_symbol: "zł",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["EEEE, d MMMM yyyy", "d MMM yyyy", "dd.MM.yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "ru-RU",
        language: "ru",
        names: &RU,
        decimal_separator: ",",
        grouping_separator: NBSP,
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "RUB",
        currency_symbol: "₽",
        currency_fraction_digits: 2,
        positive_currency_format: 3,
        negative_currency_format: 8,
        first_weekday: 1,
        date_patterns: ["d MMMM yyyy 'г.'", "d MMM yyyy 'г.'", "dd.MM.yyyy"],
        time_patterns: ["H:mm:ss", "H:mm:ss", "H:mm"],
    },
    LocaleData {
        id: "tr-TR",
        language: "tr",
        names: &TR,
        decimal_separator: ",",
        grouping_separator: ".",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "TRY",
        currency_symbol: "₺",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 1,
        date_patterns: ["d MMMM yyyy EEEE", "d MMM yyyy", "d.MM.yyyy"],
        time_patterns: ["HH:mm:ss", "HH:mm:ss", "HH:mm"],
    },
    LocaleData {
        id: "ja-JP",
        language: "ja",
        names: &JA,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "JPY",
        currency_symbol: "¥",
        currency_fraction_digits: 0,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["yyyy年M月d日EEEE", "yyyy/MM/dd", "yyyy/MM/dd"],
        time_patterns: ["H:mm:ss", "H:mm:ss", "H:mm"],
    },
    LocaleData {
        id: "ko-KR",
        language: "ko",
        names: &KO,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "KRW",
        currency_symbol: "₩",
        currency_fraction_digits: 0,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["yyyy년 M월 d일 EEEE", "yyyy. M. d.", "yyyy-MM-dd"],
        time_patterns: ["a h:mm:ss", "a h:mm:ss", "a h:mm"],
    },
    LocaleData {
        id: "zh-CN",
        language: "zh",
        names: &ZH_HANS,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "CNY",
        currency_symbol: "¥",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 2,
        first_weekday: 1,
        date_patterns: ["yyyy年M月d日EEEE", "yyyy年M月d日", "yyyy/M/d"],
        time_patterns: ["H:mm:ss", "H:mm:ss", "H:mm"],
    },
    LocaleData {
        id: "zh-TW",
        language: "zh",
        names: &ZH_HANT,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "TWD",
        currency_symbol: "NT$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["yyyy年M月d日 EEEE", "yyyy年M月d日", "yyyy/M/d"],
        time_patterns: ["a hh:mm:ss", "a hh:mm:ss", "a hh:mm"],
    },
    LocaleData {
        id: "zh-HK",
        language: "zh",
        names: &ZH_HANT,
        decimal_separator: ".",
        grouping_separator: ",",
        digits_type: 0x30,
        negative_number_format: 1,
        currency_iso: "HKD",
        currency_symbol: "HK$",
        currency_fraction_digits: 2,
        positive_currency_format: 0,
        negative_currency_format: 1,
        first_weekday: 0,
        date_patterns: ["yyyy年M月d日EEEE", "yyyy年M月d日", "d/M/yyyy"],
        time_patterns: ["a h:mm:ss", "a h:mm:ss", "a h:mm"],
    },
];

/// A locale ID name split into its BCP 47 / UTS #35 components.
#[derive(Default, Debug, Clone)]
pub struct ParsedLocale {
    pub language: String,
    pub script: String,
    pub region: String,
    pub variants: Vec<String>,
    /// `key=value` pairs from an `@key=value;…` suffix or a `-u-` extension.
    pub keys: Vec<(String, String)>,
    /// Set when the `@` suffix contains a token without `=`.
    pub unexpected_token: bool,
    /// The `@` suffix tokens without `=`, kept so that the canonical name
    /// still reports them.
    pub bad_tokens: Vec<String>,
    /// Set when the name could not be parsed as a language tag at all.
    pub unparsable: bool,
}

fn titlecase(s: &str) -> String {
    let mut chars = s.chars();
    match chars.next() {
        Some(c) => c
            .to_uppercase()
            .chain(chars.flat_map(|c| c.to_lowercase()))
            .collect(),
        None => String::new(),
    }
}

fn u_key_name(key: &str) -> &str {
    match key {
        "co" => "collation",
        "ca" => "calendar",
        "cu" => "currency",
        "nu" => "numbers",
        "va" => "variableTop",
        "hc" => "hours",
        "fw" => "firstDay",
        "ms" => "measure",
        "tz" => "timezone",
        other => other,
    }
}

fn u_value_name<'a>(key: &'a str, value: &'a str) -> &'a str {
    match (key, value) {
        ("collation", "phonebk") => "phonebook",
        ("collation", "trad") => "traditional",
        ("collation", "gb2312") => "gb2312han",
        ("collation", "dict") => "dictionary",
        _ => value,
    }
}

/// Parses `name` the way `LocaleID` does: subtags separated by `-` or `_`,
/// an optional `@key=value;key=value` suffix, and a `-u-` extension.
pub fn parse_locale(name: &str) -> ParsedLocale {
    let mut parsed = ParsedLocale::default();
    let (tag, keywords) = match name.find('@') {
        Some(idx) => (&name[..idx], Some(&name[idx + 1..])),
        None => (name, None),
    };

    let subtags: Vec<&str> = tag.split(['-', '_']).filter(|s| !s.is_empty()).collect();
    let mut iter = subtags.iter().peekable();

    let is_alpha = |s: &str| s.chars().all(|c| c.is_ascii_alphabetic());
    let is_digit = |s: &str| s.chars().all(|c| c.is_ascii_digit());

    match iter.next() {
        Some(first) if is_alpha(first) && (2..=8).contains(&first.len()) => {
            parsed.language = first.to_ascii_lowercase();
        }
        Some(first) if first.eq_ignore_ascii_case("i") || first.eq_ignore_ascii_case("x") => {
            // Grandfathered / private-use tags such as "i-default", "x-iv_mathan".
            parsed.language = first.to_ascii_lowercase();
            if let Some(second) = iter.next() {
                parsed.language.push('-');
                parsed.language.push_str(&second.to_ascii_lowercase());
            }
        }
        _ => {
            parsed.unparsable = true;
            parsed.language = name.to_string();
            return parsed;
        }
    }

    if let Some(s) = iter.peek()
        && s.len() == 4
        && is_alpha(s)
    {
        parsed.script = titlecase(s);
        iter.next();
    }
    if let Some(s) = iter.peek()
        && ((s.len() == 2 && is_alpha(s)) || (s.len() == 3 && is_digit(s)))
    {
        parsed.region = s.to_ascii_uppercase();
        iter.next();
    }
    while let Some(s) = iter.next() {
        if s.len() == 1 {
            // Extension singleton, e.g. "-u-co-phonebk-nu-arab" or "-x-private".
            let singleton = s.to_ascii_lowercase();
            let mut parts = Vec::new();
            while let Some(next) = iter.peek() {
                if next.len() == 1 {
                    break;
                }
                parts.push(next.to_ascii_lowercase());
                iter.next();
            }
            if singleton == "u" {
                let mut i = 0;
                while i < parts.len() {
                    let key = u_key_name(&parts[i]).to_string();
                    let mut values = Vec::new();
                    i += 1;
                    while i < parts.len() && parts[i].len() > 2 {
                        values.push(parts[i].clone());
                        i += 1;
                    }
                    let value = values.join("-");
                    let value = u_value_name(&key, &value).to_string();
                    parsed.keys.push((key, value));
                }
            } else if singleton == "x" {
                parsed.variants.push(format!("x-{}", parts.join("-")));
            }
            continue;
        }
        parsed.variants.push(s.to_ascii_uppercase());
    }

    if let Some(keywords) = keywords {
        for pair in keywords.split(';').filter(|s| !s.is_empty()) {
            match pair.split_once('=') {
                Some((k, v)) => parsed
                    .keys
                    .push((k.trim().to_ascii_lowercase(), v.trim().to_ascii_lowercase())),
                None => {
                    parsed.unexpected_token = true;
                    parsed.bad_tokens.push(pair.trim().to_ascii_lowercase());
                }
            }
        }
    }
    parsed
}

/// The canonical form of a locale name as `LocaleID.name` reports it.
pub fn canonical_name(name: &str) -> String {
    let parsed = parse_locale(name);
    if parsed.unparsable {
        return name.to_string();
    }
    let mut out = parsed.language.clone();
    if !parsed.script.is_empty() {
        out.push('-');
        out.push_str(&parsed.script);
    }
    if !parsed.region.is_empty() {
        out.push('-');
        out.push_str(&parsed.region);
    }
    for v in &parsed.variants {
        out.push('-');
        out.push_str(v);
    }
    if !parsed.keys.is_empty() || !parsed.bad_tokens.is_empty() {
        out.push('@');
        let pairs: Vec<String> = parsed
            .keys
            .iter()
            .map(|(k, v)| format!("{k}={v}"))
            .chain(parsed.bad_tokens.iter().cloned())
            .collect();
        out.push_str(&pairs.join(";"));
    }
    out
}

/// The default script of a language, used by `LocaleID.getScript()`.
pub fn default_script(language: &str, region: &str) -> &'static str {
    match language {
        "zh" => {
            if matches!(region, "TW" | "HK" | "MO") {
                "Hant"
            } else {
                "Hans"
            }
        }
        "mn" => {
            if region == "CN" {
                "Mong"
            } else {
                "Cyrl"
            }
        }
        "sr" => {
            if matches!(region, "ME" | "BA" | "HR") {
                "Latn"
            } else {
                "Cyrl"
            }
        }
        "pa" => {
            if region == "PK" {
                "Arab"
            } else {
                "Guru"
            }
        }
        "ja" => "Jpan",
        "ko" => "Kore",
        "ru" | "uk" | "bg" | "be" | "mk" | "kk" | "ky" | "tg" => "Cyrl",
        "ar" | "fa" | "ur" | "ps" | "sd" | "ug" | "ckb" => "Arab",
        "he" | "yi" => "Hebr",
        "el" => "Grek",
        "th" => "Thai",
        "lo" => "Laoo",
        "km" => "Khmr",
        "my" => "Mymr",
        "ka" => "Geor",
        "hy" => "Armn",
        "hi" | "mr" | "ne" | "sa" | "kok" | "mai" => "Deva",
        "bn" | "as" => "Beng",
        "gu" => "Gujr",
        "ta" => "Taml",
        "te" => "Telu",
        "kn" => "Knda",
        "ml" => "Mlym",
        "or" => "Orya",
        "si" => "Sinh",
        "am" | "ti" => "Ethi",
        "bo" | "dz" => "Tibt",
        "dv" => "Thaa",
        "en" | "de" | "fr" | "es" | "it" | "pt" | "nl" | "sv" | "da" | "nb" | "nn" | "no"
        | "fi" | "pl" | "cs" | "sk" | "hu" | "ro" | "hr" | "sl" | "tr" | "az" | "lt" | "lv"
        | "et" | "id" | "ms" | "vi" | "tl" | "fil" | "sw" | "af" | "ca" | "eu" | "gl" | "ga"
        | "cy" | "is" | "mt" | "sq" | "bs" | "uz" | "eo" | "la" => "Latn",
        _ => "",
    }
}

/// The default region of a language, used by `LocaleID.getRegion()`.
pub fn default_region(language: &str, script: &str) -> &'static str {
    match language {
        "en" => "US",
        "de" => "DE",
        "fr" => "FR",
        "es" => "ES",
        "it" => "IT",
        "pt" => "BR",
        "nl" => "NL",
        "sv" => "SE",
        "da" => "DK",
        "nb" | "nn" | "no" => "NO",
        "fi" => "FI",
        "pl" => "PL",
        "cs" => "CZ",
        "sk" => "SK",
        "hu" => "HU",
        "ro" => "RO",
        "hr" => "HR",
        "sl" => "SI",
        "tr" => "TR",
        "az" => "AZ",
        "lt" => "LT",
        "lv" => "LV",
        "et" => "EE",
        "id" => "ID",
        "ms" => "MY",
        "vi" => "VN",
        "tl" | "fil" => "PH",
        "ru" => "RU",
        "uk" => "UA",
        "bg" => "BG",
        "be" => "BY",
        "mk" => "MK",
        "kk" => "KZ",
        "sr" => "RS",
        "el" => "GR",
        "he" => "IL",
        "ar" => "SA",
        "fa" => "IR",
        "ur" => "PK",
        "hi" | "mr" | "bn" | "gu" | "ta" | "te" | "kn" | "ml" | "pa" | "or" => "IN",
        "th" => "TH",
        "lo" => "LA",
        "km" => "KH",
        "my" => "MM",
        "ja" => "JP",
        "ko" => "KR",
        "zh" => {
            if script == "Hant" {
                "TW"
            } else {
                "CN"
            }
        }
        "ka" => "GE",
        "hy" => "AM",
        "is" => "IS",
        "ga" => "IE",
        "af" => "ZA",
        "sw" => "KE",
        "ca" | "eu" | "gl" => "ES",
        "cy" => "GB",
        "mt" => "MT",
        "sq" => "AL",
        "bs" => "BA",
        "uz" => "UZ",
        "mn" => "MN",
        "ne" => "NP",
        "si" => "LK",
        "am" => "ET",
        _ => "",
    }
}

/// Whether text in this locale flows right to left.
pub fn is_right_to_left(parsed: &ParsedLocale) -> bool {
    if !parsed.script.is_empty() {
        return matches!(
            parsed.script.as_str(),
            "Arab" | "Hebr" | "Thaa" | "Syrc" | "Nkoo" | "Adlm" | "Samr" | "Mand" | "Rohg"
        );
    }
    matches!(
        parsed.language.as_str(),
        "ar" | "he"
            | "fa"
            | "ur"
            | "yi"
            | "ps"
            | "sd"
            | "ug"
            | "dv"
            | "ckb"
            | "syr"
            | "arc"
            | "nqo"
            | "ks"
    )
}

/// The locale ID the player uses for `LocaleID.DEFAULT` (`"i-default"`):
/// derived from the host language reported by `Capabilities.language`.
pub fn default_locale_id(activation: &mut Activation<'_, '_>) -> &'static str {
    match activation.context.system.language {
        Language::Czech => "cs-CZ",
        Language::Danish => "da-DK",
        Language::Dutch => "nl-NL",
        Language::English => "en-US",
        Language::Finnish => "fi-FI",
        Language::French => "fr-FR",
        Language::German => "de-DE",
        Language::Hungarian => "hu-HU",
        Language::Italian => "it-IT",
        Language::Japanese => "ja-JP",
        Language::Korean => "ko-KR",
        Language::Norwegian => "nb-NO",
        Language::Polish => "pl-PL",
        Language::Portuguese => "pt-BR",
        Language::Russian => "ru-RU",
        Language::SimplifiedChinese => "zh-CN",
        Language::Spanish => "es-ES",
        Language::Swedish => "sv-SE",
        Language::TraditionalChinese => "zh-TW",
        Language::Turkish => "tr-TR",
        Language::Unknown => "en-US",
    }
}

/// Looks up the locale table for a requested locale ID name.
///
/// Returns the locale actually used and the `LastOperationStatus` value Flash
/// reports for that outcome: `noError` for an exact match (or for
/// `LocaleID.DEFAULT`), `usingFallbackWarning` when another locale of the same
/// language is used, `usingDefaultWarning` when the language is unknown and
/// the player's default locale is used instead.
pub fn resolve(
    activation: &mut Activation<'_, '_>,
    requested: &str,
) -> (&'static LocaleData, &'static str) {
    let default_id = default_locale_id(activation);
    let (name, is_default) = if requested == "i-default" || requested.is_empty() {
        (default_id, true)
    } else {
        (requested, false)
    };
    let parsed = parse_locale(name);

    let exact = LOCALES.iter().find(|l| {
        let p = parse_locale(l.id);
        p.language == parsed.language && p.region == parsed.region
    });
    if let Some(locale) = exact {
        return (locale, NO_ERROR);
    }

    let same_language: Vec<&LocaleData> = LOCALES
        .iter()
        .filter(|l| l.language == parsed.language)
        .collect();
    if !same_language.is_empty() {
        let wanted_script = if parsed.script.is_empty() {
            default_script(&parsed.language, &parsed.region).to_string()
        } else {
            parsed.script.clone()
        };
        let by_script = same_language.iter().find(|l| {
            let p = parse_locale(l.id);
            default_script(&p.language, &p.region) == wanted_script
        });
        let locale = by_script.copied().unwrap_or(same_language[0]);
        let status = if is_default {
            NO_ERROR
        } else {
            USING_FALLBACK_WARNING
        };
        return (locale, status);
    }

    // Unknown language: use the player's default locale.
    let default_parsed = parse_locale(default_id);
    let locale = LOCALES
        .iter()
        .find(|l| l.language == default_parsed.language)
        .unwrap_or(&LOCALES[0]);
    (locale, USING_DEFAULT_WARNING)
}

/// Sorted list of locale ID names, for `getAvailableLocaleIDNames()`.
pub fn available_locale_id_names() -> Vec<&'static str> {
    let mut names: Vec<&'static str> = LOCALES.iter().map(|l| l.id).collect();
    names.sort_unstable();
    names
}
