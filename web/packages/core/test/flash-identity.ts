import { strict as assert } from "assert";
import {
    FLASH_IDENTITY_FALLBACK,
    FLASH_IDENTITY_FIRST,
    flashVersionString,
    shouldRetryWithFallback,
} from "../src/flash-identity";

const refused = {
    versionRead: true,
    removedAfterMs: 0,
    flashLeft: false,
    userActive: false,
    major: 32,
};

describe("Flash identity", function () {
    it("starts as Flash Player 32 and falls back to 34", function () {
        assert.deepEqual(FLASH_IDENTITY_FIRST, {
            major: 32,
            description: "Shockwave Flash 32.0 r0",
            filename: "pepflashplayer.dll",
        });
        assert.deepEqual(FLASH_IDENTITY_FALLBACK, {
            major: 34,
            description: "Shockwave Flash 34.0 r0",
            filename: "pepflashplayer.dll",
        });
    });
    it("gives movies a Windows version string", function () {
        assert.equal(flashVersionString(32), "WIN 32,0,0,465");
        assert.equal(flashVersionString(34), "WIN 34,0,0,465");
    });
    it("retries a page that read the version and took Flash out", function () {
        assert.equal(shouldRetryWithFallback(refused), true);
    });
    it("does not retry in other cases", function () {
        for (const change of [
            { versionRead: false },
            { flashLeft: true },
            { userActive: true },
            { removedAfterMs: 3000 },
            { major: 34 },
        ]) {
            assert.equal(
                shouldRetryWithFallback({ ...refused, ...change }),
                false,
                JSON.stringify(change),
            );
        }
    });
});
