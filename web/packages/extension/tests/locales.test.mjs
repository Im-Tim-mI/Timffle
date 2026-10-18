// The message catalogs (assets/_locales/<language>/messages.json) hold Timffle's own texts under keys that start
// with "timffle_". They are written in timffle/locales and copied here by timffle/scripts/sync_locales.py; these
// tests look at the result: every language of the extension has every text, nothing technical was lost in
// translation, and the pages and sources use exactly the texts that exist.
import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_ALLOWED_ORIGINS } from "../src/socket-proxy.ts";
import { languages, readCatalog, readSources } from "./catalog-support.mjs";

const PREFIX = "timffle_";
const own = (catalog) =>
    Object.fromEntries(Object.entries(catalog).filter(([key]) => key.startsWith(PREFIX)));
const en = own(readCatalog("en"));
const keys = Object.keys(en);
const message = (language, key) => readCatalog(language)[key]?.message;
const nonEnglish = languages.filter((language) => language !== "en");

const PLACEHOLDER = /\$([A-Za-z0-9_@]+)\$/gu;
const LITERAL = /\{[a-z]+\}/gu;
const TAG = /<\/?\d>/gu;
const all = (pattern, text) => [...text.matchAll(pattern)].map((match) => match[0].toLowerCase()).sort();

test("the extension keeps the languages of Ruffle", () => {
    assert.ok(languages.length >= 36, `only ${languages.length} languages`);
    for (const language of ["en", "zh_TW", "zh_CN", "ja", "ko", "ar", "he", "pt_BR", "pt_PT", "de", "fr", "es", "ru"]) {
        assert.ok(languages.includes(language), `${language} is missing`);
    }
});

test("every language has every text of Timffle, and nothing else of Timffle's", () => {
    assert.ok(keys.length > 50);
    for (const language of languages) {
        const catalog = own(readCatalog(language));
        assert.deepEqual(
            Object.keys(catalog).sort(),
            [...keys].sort(),
            `${language}: the set of timffle_ texts differs from English`,
        );
        for (const [key, entry] of Object.entries(catalog)) {
            assert.equal(typeof entry.message, "string", `${language}/${key}`);
            assert.notEqual(entry.message.trim(), "", `${language}/${key} is empty`);
        }
    }
});

test("placeholders, {host}/{port} and <n> tags survive translation", () => {
    for (const language of nonEnglish) {
        for (const key of keys) {
            const text = message(language, key);
            const want = en[key].message;
            assert.deepEqual(all(PLACEHOLDER, text), all(PLACEHOLDER, want), `${language}/${key}: placeholders`);
            assert.deepEqual(all(LITERAL, text), all(LITERAL, want), `${language}/${key}: {host}/{port}`);
            assert.deepEqual(all(TAG, text), all(TAG, want), `${language}/${key}: tags`);
        }
    }
});

test("every placeholder a text uses is defined, with the same content in every language", () => {
    for (const language of languages) {
        const catalog = readCatalog(language);
        for (const key of keys) {
            const used = all(PLACEHOLDER, catalog[key].message).map((token) => token.slice(1, -1));
            const defined = Object.keys(catalog[key].placeholders ?? {}).map((name) => name.toLowerCase());
            assert.deepEqual(used.sort(), defined.sort(), `${language}/${key}`);
            assert.deepEqual(catalog[key].placeholders ?? {}, en[key].placeholders ?? {}, `${language}/${key}`);
        }
    }
});

/** Names in the sources that start like the texts but are not texts. */
const NOT_TEXTS = new Set(["timffle_socket_helper" /* the native messaging host */]);

test("pages and sources use exactly the texts that exist", () => {
    const used = new Set();
    for (const [name, source] of Object.entries(readSources("assets", ".html"))) {
        for (const match of source.matchAll(/data-i18n(?:-rich)?="([^"]+)"/gu)) {
            assert.ok(match[1] in en, `${name}: ${match[1]} is not in the catalog`);
            used.add(match[1]);
        }
    }
    for (const [name, source] of Object.entries(readSources("src", ".ts"))) {
        for (const match of source.matchAll(/"(timffle_[a-z0-9_]+)"/gu)) {
            if (NOT_TEXTS.has(match[1])) {
                continue;
            }
            assert.ok(match[1] in en, `${name}: ${match[1]} is not in the catalog`);
            used.add(match[1]);
        }
    }
    const unused = keys.filter((key) => !used.has(key));
    assert.deepEqual(unused, [], "texts that nothing shows");
});

test("no page keeps text of its own for what the catalog provides", () => {
    for (const [name, source] of Object.entries(readSources("assets", ".html"))) {
        if (!["options.html", "popup.html", "prompt.html"].includes(name)) {
            continue;
        }
        assert.doesNotMatch(source, /[㐀-鿿]/u, `${name} has Chinese text outside the catalog`);
        assert.doesNotMatch(source, /translate="no"[^>]*data-i18n|data-i18n[^>]*translate="no"/u, `${name}: localized text marked translate=no`);
    }
});

// Words and symbols that must stay as they are, whatever the language: names, protocols, things the user types.
const MUST_CONTAIN = {
    timffle_prompt_page_title: ["Timffle"],
    timffle_prompt_what: ["TCP", "Flash"],
    timffle_prompt_detail: ["Timffle"],
    timffle_options_websocket: ["WebSocket"],
    timffle_options_url: ["URL", "token"],
    timffle_options_allowed_proxy: ["token"],
    timffle_options_allowed_help: ["HTTP", "HTTPS", "SWF", "*"],
    timffle_options_proxy_list_help: ["token"],
    timffle_note_ask: ["Timffle", "WebSocket"],
    timffle_note_helper: ["TCP", "Chrome", "helper"],
    timffle_note_proxy: ["WebSocket", "Chrome", "URL", "token"],
    timffle_helper_missing: ["helper"],
    timffle_popup_allow_site_proxy: ["token"],
    timffle_error_url_required: ["URL", "WebSocket"],
    timffle_error_invalid_url: ["ws://", "wss://"],
    timffle_error_credentials: ["URL", "token"],
    timffle_error_fragment: ["#", "WebSocket", "URL"],
    timffle_error_invalid_origin: ["HTTP/HTTPS"],
    timffle_error_origins_required: ["WebSocket"],
    timffle_attribution: ["<1>Ruffle</1>", "<2>Timffle</2>"],
};

test("names, protocols and what the user types are kept", () => {
    for (const key of Object.keys(MUST_CONTAIN)) {
        assert.ok(key in en, `${key} is not a text`);
    }
    for (const language of languages) {
        for (const [key, tokens] of Object.entries(MUST_CONTAIN)) {
            for (const token of tokens) {
                // "token" is a common noun in some languages (German: Token); everything else is exact.
                const [text, wanted] =
                    token === "token"
                        ? [message(language, key).toLowerCase(), token]
                        : [message(language, key), token];
                assert.ok(
                    text.includes(wanted),
                    `${language}/${key} lost ${JSON.stringify(token)}: ${message(language, key)}`,
                );
            }
        }
    }
});

const GAME_NAMES = ["摩爾莊園", "賽爾號", "小花仙", "彈彈堂"];
const GAME_NAMES_SIMPLIFIED = ["摩尔庄园", "赛尔号", "小花仙", "弹弹堂"];

test("the list of default websites names the games and the hosts that really are the defaults", () => {
    const hosts = [...new Set(DEFAULT_ALLOWED_ORIGINS.map((origin) => new URL(origin).hostname))];
    assert.equal(hosts.length, 4);
    for (const language of languages) {
        const text = message(language, "timffle_options_allowed_help");
        for (const host of hosts) {
            assert.ok(text.includes(host), `${language}: ${host}`);
        }
        for (const name of language === "zh_CN" ? GAME_NAMES_SIMPLIFIED : GAME_NAMES) {
            assert.ok(text.includes(name), `${language}: ${name}`);
        }
        // Nothing else that looks like a host of the games.
        assert.deepEqual(
            [...new Set(text.match(/[a-z]+\.61\.com\.tw/gu))].sort(),
            [...hosts].sort(),
            `${language}: hosts`,
        );
    }
});

test("the instructions quote the words of the buttons and choices", () => {
    for (const language of languages) {
        const note = message(language, "timffle_note_ask");
        for (const key of ["timffle_allow", "timffle_choice_allow", "timffle_choice_deny", "timffle_choice_ask"]) {
            assert.ok(note.includes(message(language, key)), `${language}: the note does not say “${message(language, key)}”`);
        }
        const conflict = message(language, "timffle_conflict");
        for (const key of ["timffle_choice_allow", "timffle_choice_deny"]) {
            assert.ok(conflict.includes(message(language, key)), `${language}: the list conflict does not say “${message(language, key)}”`);
        }
    }
});

test("long texts are translated, not copied from English", () => {
    for (const language of nonEnglish) {
        for (const key of keys) {
            const text = message(language, key);
            if (en[key].message.length > 30 && language !== "en") {
                assert.notEqual(text, en[key].message, `${language}/${key} is still English`);
            }
        }
    }
});

// Each language is written in its own script; a text in the wrong one means a slip while translating.
const SCRIPT = {
    ar: /\p{Script=Arabic}/u,
    he: /\p{Script=Hebrew}/u,
    th: /\p{Script=Thai}/u,
    ru: /\p{Script=Cyrillic}/u,
    uk: /\p{Script=Cyrillic}/u,
    tt: /\p{Script=Cyrillic}/u,
    ko: /\p{Script=Hangul}/u,
    ja: /[\p{Script=Hiragana}\p{Script=Katakana}]/u,
    zh_TW: /\p{Script=Han}/u,
    zh_CN: /\p{Script=Han}/u,
};

test("each language is written in its own script", () => {
    for (const [language, script] of Object.entries(SCRIPT)) {
        for (const key of keys) {
            if (en[key].message.length > 30) {
                assert.match(message(language, key), script, `${language}/${key}`);
            }
        }
    }
    for (const language of nonEnglish.filter((language) => !(language in SCRIPT))) {
        for (const key of keys) {
            if (en[key].message.length > 30) {
                // Latin script: no Chinese, Cyrillic, Arabic... mixed in (the game names are the exception).
                const text = message(language, key).replace(/摩爾莊園|賽爾號|小花仙|彈彈堂/gu, "");
                assert.doesNotMatch(text, /[^\p{Script=Latin}\p{Script=Common}\p{Script=Inherited}]/u, `${language}/${key}`);
            }
        }
    }
});

test("Traditional and Simplified Chinese differ where they should", () => {
    assert.equal(message("zh_TW", "timffle_options_enable").includes("啟用"), true);
    assert.equal(message("zh_CN", "timffle_options_enable").includes("启用"), true);
    assert.equal(message("zh_CN", "timffle_options_enable").includes("啟用"), false);
});
