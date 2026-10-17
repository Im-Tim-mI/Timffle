// Load the packed Timffle extension into a throwaway headless Chrome profile over
// the CDP pipe, then run difftest SWFs through it.
// usage: node smoke.mjs <unpackedExtDir> <profileDir> <outDir> <embedPageUrl|-> <test...>
import { spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";

const [, , extDir, profileDir, outDir, embedPage, ...tests] = process.argv;
const RESULTS = process.env.DIFFTEST_RESULTS || new URL("../../difftest/results", import.meta.url).pathname;
const RUNNER = "chromeext";
const EMBED_RUNNER = "chromeext-embed";
const TIMEOUT_MS = 60000;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

fs.mkdirSync(outDir, { recursive: true });
const chrome = spawn(
    "google-chrome",
    [
        "--headless=new",
        "--remote-debugging-pipe",
        "--enable-unsafe-extension-debugging",
        `--user-data-dir=${profileDir}`,
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-sync",
        "--disable-dev-shm-usage",
        "--use-angle=swiftshader",
        "--enable-unsafe-swiftshader",
        "--autoplay-policy=no-user-gesture-required",
        "--window-size=1024,768",
        "about:blank",
    ],
    {
        stdio: [
            "ignore",
            "ignore",
            fs.openSync(path.join(outDir, "chrome-stderr.log"), "w"),
            "pipe",
            "pipe",
        ],
    },
);

const toChrome = chrome.stdio[3];
const fromChrome = chrome.stdio[4];
let buf = Buffer.alloc(0);
let nextId = 1;
const pending = new Map();
const sessionLogs = new Map();

fromChrome.on("data", (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    let i;
    while ((i = buf.indexOf(0)) !== -1) {
        const msg = JSON.parse(buf.subarray(0, i).toString("utf8"));
        buf = buf.subarray(i + 1);
        if (msg.id && pending.has(msg.id)) {
            const { resolve, reject } = pending.get(msg.id);
            pending.delete(msg.id);
            if (msg.error) reject(new Error(JSON.stringify(msg.error)));
            else resolve(msg.result);
            continue;
        }
        const log = msg.sessionId && sessionLogs.get(msg.sessionId);
        if (!log) continue;
        const p = msg.params;
        if (msg.method === "Runtime.consoleAPICalled") {
            log.push(
                `[console.${p.type}] ` +
                    p.args.map((a) => a.value ?? a.description ?? a.type).join(" "),
            );
        } else if (msg.method === "Runtime.exceptionThrown") {
            const d = p.exceptionDetails;
            log.push(`[exception] ${d.exception?.description ?? d.text}`);
        } else if (msg.method === "Log.entryAdded") {
            log.push(`[log.${p.entry.level}] ${p.entry.text} ${p.entry.url ?? ""}`);
        }
    }
});

function send(method, params = {}, sessionId, timeout = 30000) {
    const id = nextId++;
    const msg = { id, method, params };
    if (sessionId) msg.sessionId = sessionId;
    toChrome.write(JSON.stringify(msg) + "\0");
    return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        setTimeout(() => {
            if (pending.delete(id)) reject(new Error(`timeout: ${method}`));
        }, timeout);
    });
}

const PLAYER_STATE = `(() => {
    const find = (root) => {
        for (const el of root.querySelectorAll("*")) {
            if (el.tagName.startsWith("RUFFLE-")) return el;
        }
        return null;
    };
    const p = find(document);
    return JSON.stringify({
        title: document.title,
        playerTag: p && p.tagName,
        readyState: p ? p.readyState : null,
        swfVersion: p && p.metadata ? p.metadata.swfVersion : null,
        isAs3: p && p.metadata ? p.metadata.isActionScript3 : null,
        leftoverEmbeds: document.querySelectorAll("embed, object").length,
    });
})()`;

async function runPage(url, resFile, label) {
    fs.rmSync(resFile, { force: true });
    const { targetId } = await send("Target.createTarget", { url: "about:blank" });
    const { sessionId } = await send("Target.attachToTarget", { targetId, flatten: true });
    sessionLogs.set(sessionId, []);
    await send("Runtime.enable", {}, sessionId);
    await send("Log.enable", {}, sessionId);
    await send("Page.enable", {}, sessionId);
    const t0 = Date.now();
    await send("Page.navigate", { url }, sessionId);
    let reported = false;
    while (Date.now() - t0 < TIMEOUT_MS) {
        if (fs.existsSync(resFile) && fs.statSync(resFile).size > 0) {
            reported = true;
            break;
        }
        await sleep(500);
    }
    const elapsed = (Date.now() - t0) / 1000;
    let state;
    try {
        const r = await send(
            "Runtime.evaluate",
            { expression: PLAYER_STATE, returnByValue: true },
            sessionId,
        );
        state = r.result.value;
    } catch (e) {
        state = `evaluate failed: ${e.message}`;
    }
    await send("Target.closeTarget", { targetId }).catch(() => {});
    fs.writeFileSync(
        path.join(outDir, `${label}.console.log`),
        sessionLogs.get(sessionId).join("\n") + "\n",
    );
    console.log(
        `${reported ? "REPORTED " : "NO-REPORT"} ${label} ${elapsed.toFixed(1)}s ${state}`,
    );
    return reported;
}

let failed = false;
try {
    const { id: extId } = await send("Extensions.loadUnpacked", { path: extDir });
    console.log(`EXTENSION_ID ${extId}`);
    await sleep(2000);
    const { targetInfos } = await send("Target.getTargets");
    for (const t of targetInfos) console.log(`TARGET ${t.type} ${t.url}`);

    for (const test of tests) {
        const swf = `http://127.0.0.1:18765/t/${RUNNER}/${test}.swf`;
        const ok = await runPage(
            `chrome-extension://${extId}/player.html#${swf}`,
            path.join(RESULTS, RUNNER, `${test}.txt`),
            `${RUNNER}-${test}`,
        );
        failed ||= !ok;
    }
    if (embedPage !== "-") {
        const ok = await runPage(
            embedPage,
            path.join(RESULTS, EMBED_RUNNER, "t0hello.txt"),
            `${EMBED_RUNNER}-t0hello`,
        );
        failed ||= !ok;
    }
} catch (e) {
    console.log(`ERROR ${e.stack ?? e}`);
    failed = true;
} finally {
    await send("Browser.close", {}, undefined, 5000).catch(() => {});
    await sleep(1000);
    if (chrome.exitCode === null) chrome.kill("SIGKILL");
}
process.exit(failed ? 1 : 0);
