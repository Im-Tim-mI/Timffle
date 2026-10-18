// The pictures of the socket settings, the popup and the question window used in the README.
// Real pages of the built extension in headless Chrome; the helper is installed in a disposable HOME so the
// options page shows it as installed. Two things are not real: the question window is shown for the made-up
// website https://game.example (the page asks the background for its text, which is answered here), and the
// popup is told that the tab's address is the same example name (the real one is a local test address).
//   node socket-ui-shots.mjs <unpacked extension dir> <helper binary> <work dir> <output dir>
// writes options-socket.png, socket-popup.png and socket-question.png into <output dir>.
import {execFileSync} from 'node:child_process';
import fs from 'node:fs/promises';
import http from 'node:http';
import path from 'node:path';
import crypto from 'node:crypto';
import {Chrome, delay} from '../native-regress/chrome-cdp-native.mjs';

const [extensionDir, helper, work, outDir] = process.argv.slice(2);
if (!extensionDir || !helper || !work || !outDir) throw new Error('usage: node socket-ui-shots.mjs <extension dir> <helper binary> <work dir> <output dir>');
const manifest = JSON.parse(await fs.readFile(path.join(extensionDir, 'manifest.json'), 'utf8'));
const digest = crypto.createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest('hex').slice(0, 32);
const ID = [...digest].map(c => 'abcdefghijklmnop'[parseInt(c, 16)]).join('');
await fs.mkdir(outDir, {recursive: true});
const env = {...process.env, HOME: path.join(work, 'home'), XDG_DATA_HOME: path.join(work, 'data'), XDG_CONFIG_HOME: path.join(work, 'config')};
delete env.CHROME_CONFIG_HOME;
await fs.mkdir(env.HOME, {recursive: true, mode: 0o700});
execFileSync(path.resolve(helper), ['--install'], {env, encoding: 'utf8'});
const web = http.createServer((req, res) => { res.setHeader('Content-Type', 'text/html'); res.end('<!doctype html><meta charset="utf-8"><title>game</title><p>no flash</p>'); });
await new Promise(r => web.listen(0, '127.0.0.1', r));
const origin = 'http://127.0.0.1:' + web.address().port;
const chrome = new Chrome(work, {recordEvents: false, userDataDir: path.join(work, 'config', 'google-chrome')});
const attach = async (targetId) => { const {sessionId} = await chrome.send('Target.attachToTarget', {targetId, flatten: true}); for (const m of ['Page.enable', 'Runtime.enable']) await chrome.send(m, {}, sessionId); return sessionId; };
const save = async (sessionId, name, params = {}) => { const shot = await chrome.send('Page.captureScreenshot', {format: 'png', ...params}, sessionId); await fs.writeFile(path.join(outDir, name), Buffer.from(shot.data, 'base64')); console.log('wrote', name); };
const light = (sessionId) => chrome.send('Emulation.setEmulatedMedia', {features: [{name: 'prefers-color-scheme', value: 'light'}]}, sessionId);
try {
  await chrome.send('Extensions.loadUnpacked', {path: path.resolve(extensionDir)});

  // 1. The socket section of the options page, from its top to the bottom of the always-denied list.
  {
    const {targetId} = await chrome.send('Target.createTarget', {url: 'about:blank'});
    const sessionId = await attach(targetId);
    await light(sessionId);
    await chrome.send('Emulation.setDeviceMetricsOverride', {width: 860, height: 1600, deviceScaleFactor: 2, mobile: false}, sessionId);
    await chrome.send('Page.navigate', {url: `chrome-extension://${ID}/options.html`}, sessionId);
    await chrome.wait(sessionId, '(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
    await chrome.wait(sessionId, '(()=>{const s=document.querySelector("#socket-helper-status");return s&&s.dataset.state==="info"&&!s.textContent.startsWith("檢查中")})()', 12000);
    await delay(600);
    const box = await chrome.eval(sessionId, `(()=>{const f=document.querySelector('#socket-proxy-form').getBoundingClientRect();const d=document.querySelector('#socket-proxy-denied').getBoundingClientRect();const help=document.querySelector('#socket-proxy-denied-help').getBoundingClientRect();return {x:f.x,y:f.y+scrollY,w:f.width,h:(help.bottom+scrollY)-(f.y+scrollY)}})()`);
    const pad = 14;
    await save(sessionId, 'options-socket.png', {captureBeyondViewport: true, clip: {x: Math.max(0, box.x - pad), y: Math.max(0, box.y - pad), width: box.w + 2 * pad, height: box.h + 2 * pad, scale: 1}});
    await chrome.send('Target.closeTarget', {targetId});
  }

  // 2. The question window, as the user sees it (540 x 680).
  {
    const {targetId} = await chrome.send('Target.createTarget', {url: 'about:blank'});
    const sessionId = await attach(targetId);
    await light(sessionId);
    await chrome.send('Emulation.setDeviceMetricsOverride', {width: 540, height: 680, deviceScaleFactor: 2, mobile: false}, sessionId);
    await chrome.send('Page.addScriptToEvaluateOnNewDocument', {source: `(() => {
      const ask = chrome.runtime.sendMessage.bind(chrome.runtime);
      chrome.runtime.sendMessage = (message) => message && message.type === 'socket_prompt_get' ? Promise.resolve({origin: 'https://game.example'}) : ask(message);
    })()`}, sessionId);
    await chrome.send('Page.navigate', {url: `chrome-extension://${ID}/prompt.html?id=00000000-0000-4000-8000-000000000000`}, sessionId);
    await chrome.wait(sessionId, '!document.getElementById("prompt").hidden');
    await delay(1300);
    await save(sessionId, 'socket-question.png');
    await chrome.send('Target.closeTarget', {targetId});
  }

  // 3. The popup over a page. It is opened as an ordinary tab so that it can be sized; its answer to "which tab is
  // active" is replaced by a made-up address (https://game.example) of a real tab, so that everything else the popup
  // shows (the tab's status, the options) is real.
  {
    const helperTab = (await chrome.send('Target.createTarget', {url: `chrome-extension://${ID}/options.html`})).targetId;
    const helperSession = await attach(helperTab);
    const {targetId: pageTarget} = await chrome.send('Target.createTarget', {url: origin + '/'});
    await attach(pageTarget);
    await delay(2000);
    const tabId = await chrome.eval(helperSession, `chrome.tabs.query({}).then(tabs=>tabs.find(t=>t.url&&t.url.startsWith(${JSON.stringify(origin)})).id)`);
    const {targetId} = await chrome.send('Target.createTarget', {url: 'about:blank'});
    const sessionId = await attach(targetId);
    await light(sessionId);
    await chrome.send('Emulation.setDeviceMetricsOverride', {width: 340, height: 640, deviceScaleFactor: 2, mobile: false}, sessionId);
    await chrome.send('Page.addScriptToEvaluateOnNewDocument', {source: `(() => {
      chrome.tabs.query = async () => [{id: ${tabId}, url: 'https://game.example/', active: true}];
    })()`}, sessionId);
    await chrome.send('Page.navigate', {url: `chrome-extension://${ID}/popup.html`}, sessionId);
    await chrome.wait(sessionId, '!document.getElementById("socket-container").classList.contains("hidden")');
    await delay(800);
    // The page is as tall as the emulated window; the picture ends where the popup's content does.
    const height = await chrome.eval(sessionId, 'Math.ceil(Math.max(...[...document.querySelectorAll(".buttons-container")].map(e=>e.getBoundingClientRect().bottom)))+12');
    await save(sessionId, 'socket-popup.png', {clip: {x: 0, y: 0, width: 340, height, scale: 1}});
  }
} finally {
  await chrome.close();
  web.close();
}
