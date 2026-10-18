// Helpers for the tests that look at the message catalogs (assets/_locales). Not a test itself.
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
export const packageDir = path.resolve(here, "..");
export const localesDir = path.join(packageDir, "assets", "_locales");

export const languages = fs
    .readdirSync(localesDir)
    .filter((name) => fs.statSync(path.join(localesDir, name)).isDirectory())
    .sort();

/** The catalog of one language as Chrome reads it: {key: {message, placeholders?, description?}}. */
export function readCatalog(language) {
    return JSON.parse(
        fs.readFileSync(path.join(localesDir, language, "messages.json"), "utf8"),
    );
}

/**
 * `browser.i18n` as Chrome behaves for the pieces the extension uses: a key
 * missing from the language falls back to English, `$NAME$` placeholders are
 * replaced by the substitutions, and a missing key gives "".
 */
export function fakeI18n(language) {
    const own = readCatalog(language);
    const fallback = readCatalog("en");
    return {
        getMessage(key, substitutions) {
            if (key === "@@ui_locale") {
                return language;
            }
            if (key === "@@bidi_dir") {
                return ["ar", "he"].includes(language) ? "rtl" : "ltr";
            }
            const entry = own[key] ?? fallback[key];
            if (!entry) {
                return "";
            }
            const values =
                substitutions === undefined
                    ? []
                    : Array.isArray(substitutions)
                      ? substitutions
                      : [substitutions];
            return entry.message.replace(/\$([A-Za-z0-9_@]+)\$/gu, (all, name) => {
                const placeholder = Object.entries(entry.placeholders ?? {}).find(
                    ([key]) => key.toLowerCase() === name.toLowerCase(),
                );
                if (!placeholder) {
                    return all;
                }
                const content = placeholder[1].content;
                return content.replace(/\$(\d)/gu, (_, n) => values[Number(n) - 1] ?? "");
            });
        },
    };
}

/** The source files of the extension, name → text. */
export function readSources(directory, extension) {
    const dir = path.join(packageDir, directory);
    return Object.fromEntries(
        fs
            .readdirSync(dir)
            .filter((name) => name.endsWith(extension))
            .sort()
            .map((name) => [name, fs.readFileSync(path.join(dir, name), "utf8")]),
    );
}
