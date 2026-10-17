// Interactive CDP driver for the real-account test of the packed Timffle extension + connection helper.
// usage: node rl-driver.mjs <extSrcDir> <helperBinary> <workDir> <stepsJson> <startUrl> <credFile>
// (A foreground step runner: the session ends when the steps are done, then Chrome is closed.)
//   credFile: two lines, account then password (0600). They are only ever typed into the page by /cred and are masked
//   (together with the md5 of the password) in everything this driver prints or returns.
// Control API (127.0.0.1:<controlPort>):
//   GET  /shot?name=N          screenshot -> <workDir>/../shots/N.png
//   POST /click?x=&y=          left click at viewport coords (move first)    POST /dblclick?x=&y=
//   POST /move?x=&y=           mouse move
//   POST /cred?field=account|password   types the credential from the file, key by key
//   POST /type                 body = text, typed key by key (never logged)
//   POST /key?key=Enter|Tab|Backspace|Escape
//   GET  /console?since=N      masked console lines from index N (lines mentioning passwords are dropped)
//   POST /eval                 body = JS expression evaluated in the page (masked result)
//   POST /goto?url=            navigate the page
//   POST /quit                 close Chrome and exit
import { spawn, execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import path from "node:path";

const [, , extSrc, helperBin, workDir, controlPort, startUrl, credFile] = process.argv;
const [ACCT, PASS] = fs.readFileSync(credFile, "utf8").split("\n");
const md5 = (s) => crypto.createHash("md5").update(s).digest("hex");
const SECRETS = [PASS, md5(PASS), md5(PASS).toUpperCase(), ACCT].filter(Boolean);
const mask = (s) => SECRETS.reduce((acc, secret) => acc.split(secret).join("<masked>"), String(s));
const SENSITIVE = /pass|pwd|密碼|密码|token|session/i;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const ts = () => new Date().toISOString().slice(11, 23);
const shotsDir = path.join(path.dirname(workDir), "shots");

const home = path.join(workDir, "home");
const env = {
    ...process.env,
    HOME: home,
    XDG_DATA_HOME: path.join(workDir, "data"),
    XDG_CONFIG_HOME: path.join(workDir, "config"),
    ...(process.env.TEST_FONTCONFIG ? { FONTCONFIG_FILE: process.env.TEST_FONTCONFIG } : {}),
};
fs.mkdirSync(home, { recursive: true, mode: 0o700 });
console.log(`${ts()} helper install: ${execFileSync(helperBin, ["--install"], { env, encoding: "utf8" }).trim().slice(0, 120)}`);
const userDataDir = path.join(workDir, "config", "google-chrome");
const extDir = path.join(workDir, "ext");
fs.rmSync(extDir, { recursive: true, force: true });
fs.cpSync(extSrc, extDir, { recursive: true });

const chrome = spawn(
    "google-chrome",
    [
        "--headless=new",
        "--remote-debugging-pipe",
        "--enable-unsafe-extension-debugging",
        `--user-data-dir=${userDataDir}`,
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-background-networking",
        "--disable-component-update",
        "--disable-sync",
        "--disable-dev-shm-usage",
        "--use-angle=swiftshader",
        "--enable-unsafe-swiftshader",
        "--autoplay-policy=no-user-gesture-required",
        "--window-size=1280,900",
        "about:blank",
    ],
    // (Chrome gets the real environment: with the disposable HOME its user data directory would be the default one,
    // for which Chrome refuses remote debugging.)
    {
        env: { ...process.env, ...(env.FONTCONFIG_FILE ? { FONTCONFIG_FILE: env.FONTCONFIG_FILE } : {}) },
        stdio: ["ignore", "ignore", fs.openSync(path.join(workDir, "chrome-stderr.log"), "w"), "pipe", "pipe"],
    },
);
chrome.on("exit", (code) => {
    console.log(`${ts()} chrome exited ${code}`);
    process.exit(0);
});

const toChrome = chrome.stdio[3];
let buf = Buffer.alloc(0);
let nextId = 1;
const pending = new Map();
const consoleLines = [];
let pageSession = null;

function fmtConsole(p) {
    const args = p.args.map((a) => a.value ?? a.description ?? a.type);
    if (typeof args[0] === "string" && args[0].includes("%c")) {
        const n = args[0].split("%c").length - 1;
        return [args[0].replaceAll("%c", ""), ...args.slice(1 + n)].join(" ");
    }
    return args.join(" ");
}

chrome.stdio[4].on("data", (chunk) => {
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
        if (!pageSession || msg.sessionId !== pageSession) continue;
        const p = msg.params;
        let line = null;
        if (msg.method === "Runtime.consoleAPICalled") line = `[${p.type}] ${fmtConsole(p)}`;
        else if (msg.method === "Runtime.exceptionThrown")
            line = `[exception] ${p.exceptionDetails.exception?.description ?? p.exceptionDetails.text}`;
        else if (msg.method === "Log.entryAdded") line = `[log.${p.entry.level}] ${p.entry.text} ${p.entry.url ?? ""}`;
        if (line && !SENSITIVE.test(line)) consoleLines.push(`${ts()} ${mask(line).slice(0, 400)}`);
    }
});

function send(method, params = {}, sessionId, timeout = 30000) {
    const id = nextId++;
    const m = { id, method, params };
    if (sessionId) m.sessionId = sessionId;
    toChrome.write(JSON.stringify(m) + "\0");
    return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
        setTimeout(() => {
            if (pending.delete(id)) reject(new Error(`timeout: ${method}`));
        }, timeout);
    });
}

const key = (type, k) => send("Input.dispatchKeyEvent", { type, ...k }, pageSession);

const SPECIAL = {
    Enter: { key: "Enter", code: "Enter", windowsVirtualKeyCode: 13, text: "\r" },
    Tab: { key: "Tab", code: "Tab", windowsVirtualKeyCode: 9 },
    Backspace: { key: "Backspace", code: "Backspace", windowsVirtualKeyCode: 8 },
    Escape: { key: "Escape", code: "Escape", windowsVirtualKeyCode: 27 },
};

async function typeText(text) {
    for (const ch of text) {
        const upper = ch.toUpperCase();
        const isLetter = /[a-z]/i.test(ch);
        const isDigit = /[0-9]/.test(ch);
        const shift = isLetter && ch !== ch.toLowerCase();
        const k = {
            key: ch,
            text: ch,
            unmodifiedText: ch.toLowerCase(),
            code: isLetter ? `Key${upper}` : isDigit ? `Digit${ch}` : "",
            windowsVirtualKeyCode: isLetter || isDigit ? upper.charCodeAt(0) : 0,
            modifiers: shift ? 8 : 0,
        };
        await key("keyDown", k);
        await key("keyUp", { key: ch, code: k.code, windowsVirtualKeyCode: k.windowsVirtualKeyCode, modifiers: k.modifiers });
        await sleep(45);
    }
}

async function mouse(type, x, y, extra = {}) {
    await send("Input.dispatchMouseEvent", { type, x, y, button: "left", buttons: 0, ...extra }, pageSession);
}

async function click(x, y, count = 1) {
    await mouse("mouseMoved", x, y);
    await sleep(60);
    for (let i = 1; i <= count; i++) {
        await mouse("mousePressed", x, y, { buttons: 1, clickCount: i });
        await sleep(50);
        await mouse("mouseReleased", x, y, { clickCount: i });
        await sleep(50);
    }
}

async function setup() {
    const { id: extId } = await send("Extensions.loadUnpacked", { path: extDir });
    console.log(`${ts()} extension ${extId}`);
    await sleep(1500);
    const { targetId } = await send("Target.createTarget", { url: "about:blank" });
    ({ sessionId: pageSession } = await send("Target.attachToTarget", { targetId, flatten: true }));
    await send("Runtime.enable", {}, pageSession);
    await send("Log.enable", {}, pageSession);
    await send("Page.enable", {}, pageSession);
    await send("Emulation.setDeviceMetricsOverride", { width: 1280, height: 900, deviceScaleFactor: 1, mobile: false }, pageSession);
    await send("Page.navigate", { url: startUrl }, pageSession);
    console.log(`${ts()} navigated to ${startUrl}`);
}

const steps = JSON.parse(fs.readFileSync(controlPort, "utf8")); // 4th argument: path of the steps file
let consoleCursor = 0;

async function runStep(st) {
    switch (st.op) {
        case "wait":
            await sleep(st.ms);
            break;
        case "shot": {
            const { data } = await send("Page.captureScreenshot", { format: "png" }, pageSession);
            const file = path.join(shotsDir, `${st.name}.png`);
            fs.writeFileSync(file, Buffer.from(data, "base64"), { mode: 0o600 });
            console.log(`${ts()} shot ${st.name}`);
            break;
        }
        case "click":
            await click(st.x, st.y);
            break;
        case "dblclick":
            await click(st.x, st.y, 2);
            break;
        case "move":
            await mouse("mouseMoved", st.x, st.y);
            break;
        case "cred":
            await typeText(st.field === "password" ? PASS : ACCT);
            break;
        case "type":
            await typeText(st.text);
            break;
        case "insert":
            await send("Input.insertText", { text: st.text }, pageSession);
            break;
        case "key": {
            const k = SPECIAL[st.key];
            if (!k) throw new Error(`unknown key ${st.key}`);
            await key("keyDown", k);
            await key("keyUp", { key: k.key, code: k.code, windowsVirtualKeyCode: k.windowsVirtualKeyCode });
            break;
        }
        case "eval": {
            const r = await send("Runtime.evaluate", { expression: st.js, awaitPromise: true, returnByValue: true }, pageSession);
            console.log(`${ts()} eval ${st.label ?? ""}: ${mask(JSON.stringify(r.result?.value ?? r.exceptionDetails ?? null)).slice(0, 600)}`);
            break;
        }
        case "console": {
            const lines = consoleLines.slice(consoleCursor, consoleCursor + (st.max ?? 40));
            consoleCursor += lines.length;
            console.log(`${ts()} console ${st.label ?? ""} (${lines.length} new, ${consoleLines.length - consoleCursor} not shown):`);
            for (const l of lines) console.log("   " + l.slice(0, 220));
            break;
        }
        case "dumpConsole":
            fs.writeFileSync(st.file, consoleLines.join("\n") + "\n", { mode: 0o600 });
            console.log(`${ts()} dumped ${consoleLines.length} masked console lines to ${st.file}`);
            break;
        case "skipConsole":
            consoleCursor = consoleLines.length;
            break;
        case "goto":
            await send("Page.navigate", { url: st.url }, pageSession);
            break;
        default:
            throw new Error(`unknown op ${st.op}`);
    }
}

async function main() {
    await setup();
    for (const st of steps) {
        try {
            await runStep(st);
        } catch (e) {
            console.log(`${ts()} step ${JSON.stringify(st).slice(0, 100)} failed: ${mask(String(e))}`);
        }
    }
    console.log(`${ts()} steps done, closing`);
    await send("Browser.close").catch(() => chrome.kill());
    await sleep(2000);
    process.exit(0);
}

main().catch((e) => {
    console.log(`${ts()} failed: ${mask(String(e))}`);
    chrome.kill();
});
