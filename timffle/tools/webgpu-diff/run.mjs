#!/usr/bin/env node
// run.mjs <unpacked ext dir> <out dir> [--filter regex] [--jobs N] [--swfs dir] [--renderers a,b]
// Renders every selected Ruffle regression SWF (see select_tests.py) in headless Chrome with the
// Timffle extension, once per renderer (storage.sync preferredRenderer), and saves one PNG per
// test and renderer into <out dir>/<renderer>/<test>.png plus <out dir>/results.json.
// Then run compare.py <out dir> to get report.md and side-by-side images.
import fs from "node:fs/promises";
import path from "node:path";
import http from "node:http";
import { execFileSync } from "node:child_process";
import { Chrome, delay } from "../native-regress/chrome-cdp-native.mjs";
import { fileURLToPath } from "node:url";
const REPO_ROOT = fileURLToPath(new URL("../../../", import.meta.url));

const here = path.dirname(new URL(import.meta.url).pathname);
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(k); return i >= 0 ? argv[i + 1] : d; };
const [extDir, outDir] = argv.filter((a, i) => !a.startsWith("--") && (i === 0 || !argv[i - 1].startsWith("--")));
if (!extDir || !outDir) { console.error("usage: node run.mjs <ext dir> <out dir> [--filter regex] [--jobs N] [--swfs dir] [--renderers a,b]"); process.exit(2); }
const jobs = +opt("--jobs", 3);
const swfRoot = opt("--swfs", REPO_ROOT + "tests/tests/swfs");
const renderers = opt("--renderers", "wgpu-webgl,webgpu").split(",");
const filter = opt("--filter", null);
const WEBGPU_ARGS = ["--enable-unsafe-webgpu", "--enable-features=Vulkan", "--use-webgpu-adapter=swiftshader"];
const LOAD_TIMEOUT = +(process.env.LOAD_TIMEOUT || 25000);
const SETTLE_MS = +(process.env.SETTLE_MS || 500);
process.env.CHROME_WINDOW_SIZE ||= "1600,1200";

await fs.mkdir(outDir, { recursive: true });
const sel = JSON.parse(execFileSync("python3", ["-I", path.join(here, "select_tests.py"), swfRoot, ...(filter ? ["--filter", filter] : [])], { maxBuffer: 1 << 26 }).toString());
const tests = sel.tests;
console.log(`${tests.length} tests selected (${Object.keys(sel.skipped).length} skipped by toml rules)`);
await fs.writeFile(path.join(outDir, "tests.json"), JSON.stringify(sel, null, 1));

// Static server: /t/<i>/ -> page with the embed, /t/<i>/<file> -> file from the test directory.
const server = http.createServer(async (req, res) => {
    const m = /^\/t\/(\d+)\/([^?]*)/.exec(req.url);
    const t = m && tests[+m[1]];
    if (!t) { res.statusCode = 404; return res.end(); }
    const file = decodeURIComponent(m[2]);
    if (file === "") {
        res.setHeader("Content-Type", "text/html; charset=utf-8");
        return res.end(`<!doctype html><html><head><meta charset="utf-8"><title>${t.name}</title></head><body style="margin:0;background:#ffffff">` +
            `<embed src="test.swf" type="application/x-shockwave-flash" width="${t.width}" height="${t.height}" style="display:block"></body></html>`);
    }
    try {
        const p = path.join(path.dirname(t.swf), file);
        if (!p.startsWith(path.dirname(t.swf))) throw new Error("outside");
        const d = await fs.readFile(p);
        res.setHeader("Content-Type", file.endsWith(".swf") ? "application/x-shockwave-flash" : "application/octet-stream");
        res.end(d);
    } catch { res.statusCode = 404; res.end(); }
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const origin = "http://127.0.0.1:" + server.address().port;
const PLAYER = 'document.querySelector("ruffle-embed,ruffle-object,ruffle-player")';
const fileName = (name) => name.replace(/\//g, "__") + ".png";

const results = {
    version: JSON.parse(await fs.readFile(path.join(extDir, "manifest.json"), "utf8")).version,
    chrome: execFileSync("google-chrome", ["--version"]).toString().trim(),
    chromeArgs: WEBGPU_ARGS, jobs, settleMs: SETTLE_MS, started: new Date().toISOString(), renderers: {},
};
const t0 = Date.now();

async function runRenderer(pref) {
    const rt0 = Date.now();
    const dir = path.join(outDir, pref); await fs.mkdir(dir, { recursive: true });
    const work = path.join(outDir, "chrome-" + pref); await fs.rm(work, { recursive: true, force: true });
    const chrome = new Chrome(work, { recordEvents: true, args: WEBGPU_ARGS });
    const out = { tests: {}, launchMs: 0, totalMs: 0 };
    results.renderers[pref] = out;
    try {
        const loaded = await chrome.send("Extensions.loadUnpacked", { path: path.resolve(extDir) });
        const opts = await chrome.tab("chrome-extension://" + loaded.id + "/options.html");
        await chrome.wait(opts.sessionId, "document.readyState==='complete'");
        await chrome.eval(opts.sessionId, 'chrome.storage.sync.set({autostart:true,autoplay:"on",unmuteOverlay:"hidden",preferredRenderer:' + JSON.stringify(pref) + "})");
        await chrome.wait(opts.sessionId, "chrome.scripting.getRegisteredContentScripts().then(r=>r.map(x=>x.id).join().includes('ruffle'))", 30000);
        await delay(400);
        out.launchMs = Date.now() - rt0;
        let next = 0, done = 0;
        const worker = async (wi) => {
            let tab = await chrome.tab("about:blank");
            while (next < tests.length) {
                const i = next++; const t = tests[i];
                const r = { ok: false, ms: 0, renderer: null, errors: [] };
                const ts = Date.now();
                const s = tab.sessionId;
                chrome.events = chrome.events.filter((e) => e.sessionId !== s);
                try {
                    await chrome.send("Page.navigate", { url: `${origin}/t/${i}/` }, s);
                    await chrome.wait(s, PLAYER + "?.readyState>=2", LOAD_TIMEOUT);
                    const logs = () => chrome.events.filter((e) => e.sessionId === s);
                    const rendererLine = () => logs().map((e) => e.method === "Runtime.consoleAPICalled" ? e.params.args.map((a) => a.value ?? "").join(" ") : "").map((m) => /Used renderer: ([\w-]+)/.exec(m)?.[1]).find(Boolean);
                    const end = Date.now() + 5000;
                    while (!rendererLine() && Date.now() < end) await delay(100);
                    r.renderer = rendererLine() ?? null;
                    await delay(SETTLE_MS);
                    const rect = JSON.parse(await chrome.eval(s, `JSON.stringify(${PLAYER}.getBoundingClientRect())`));
                    r.rect = { x: rect.x, y: rect.y, w: rect.width, h: rect.height };
                    const shot = await chrome.send("Page.captureScreenshot", { format: "png", captureBeyondViewport: true, clip: { x: rect.x, y: rect.y, width: Math.max(1, rect.width), height: Math.max(1, rect.height), scale: 1 } }, s);
                    await fs.writeFile(path.join(dir, fileName(t.name)), Buffer.from(shot.data, "base64"));
                    r.errors = logs().flatMap((e) => {
                        if (e.method === "Runtime.consoleAPICalled" && (e.params.type === "error" || e.params.type === "assert")) return [e.params.args.slice(0, 3).map((a) => a.value ?? a.description ?? "").join(" ").slice(0, 400)];
                        if (e.method === "Runtime.exceptionThrown") return ["exception: " + (e.params.exceptionDetails.exception?.description ?? e.params.exceptionDetails.text).slice(0, 400)];
                        if (e.method === "Log.entryAdded" && e.params.entry.level === "error") return ["log: " + e.params.entry.text.slice(0, 400)];
                        return [];
                    }).filter((m) => !/favicon|ERR_FILE_NOT_FOUND|404 \(Not Found\)/.test(m));
                    r.ok = true;
                } catch (e) {
                    r.errors.push("harness: " + e.message);
                    try { await chrome.send("Target.closeTarget", { targetId: tab.targetId }); } catch { }
                    try { tab = await chrome.tab("about:blank"); } catch (e2) { r.errors.push("harness: cannot recreate tab: " + e2.message); break; }
                }
                // drop this session's events so memory doesn't grow
                chrome.events = chrome.events.filter((e) => e.sessionId !== s);
                r.ms = Date.now() - ts;
                out.tests[t.name] = r;
                done++;
                if (done % 20 === 0 || done === tests.length) console.log(`[${pref}] ${done}/${tests.length} (${((Date.now() - rt0) / 1000).toFixed(0)} s)`);
            }
        };
        await Promise.all(Array.from({ length: Math.max(1, jobs) }, (_, i) => worker(i)));
    } finally {
        const exited = new Promise((r) => chrome.process.once("exit", r));
        await chrome.close();
        await Promise.race([exited, delay(10000)]);
        try { chrome.process.kill("SIGKILL"); } catch { }
        await Promise.race([exited, delay(3000)]);
    }
    out.totalMs = Date.now() - rt0;
    if (process.env.KEEP_CHROME_DIR) await fs.rm(path.join(work, "profile"), { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
    else await fs.rm(work, { recursive: true, force: true, maxRetries: 5, retryDelay: 500 });
}

try {
    for (const pref of renderers) {
        console.log(`== renderer ${pref}`);
        await runRenderer(pref);
        await fs.writeFile(path.join(outDir, "results.json"), JSON.stringify(results, null, 1));
    }
} finally {
    server.close();
}
results.totalMs = Date.now() - t0;
await fs.writeFile(path.join(outDir, "results.json"), JSON.stringify(results, null, 1));
for (const pref of renderers) {
    const r = results.renderers[pref];
    const vals = Object.values(r.tests);
    const bad = vals.filter((x) => x.renderer !== pref).length;
    console.log(`${pref}: ${vals.filter((x) => x.ok).length}/${vals.length} rendered, ${bad} with a different/missing renderer line, ${vals.filter((x) => x.errors.length).length} with console errors, ${(r.totalMs / 1000).toFixed(0)} s`);
}
console.log(`total ${(results.totalMs / 1000).toFixed(0)} s`);
