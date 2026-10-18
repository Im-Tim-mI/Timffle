// The first-use question for sockets, end to end: a page of an unlisted website tries a socket, the extension
// opens its own question window, the answer is kept (or not), and the popup can change it later.
// Headless Chrome + the test-only helper (connects to localhost only); never touches a real game server.
//   node ask-tests.mjs <unpacked extension dir> <localtest helper binary>
// The browser runs in the language TEST_LOCALE (default en, e.g. TEST_LOCALE=zh_TW); texts are expected from the extension's catalog for it.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {loadTexts,norm} from './catalog.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const [extensionDir,helper]=process.argv.slice(2);
assert.ok(extensionDir&&helper,'Usage: node ask-tests.mjs extension-dir localtest-helper-binary');
const manifest=JSON.parse(await fs.readFile(path.join(extensionDir,'manifest.json'),'utf8'));
const locale=process.env.TEST_LOCALE||'en',T=loadTexts(extensionDir,locale);
const digest=crypto.createHash('sha256').update(Buffer.from(manifest.key,'base64')).digest('hex').slice(0,32);
const ID=[...digest].map(c=>'abcdefghijklmnop'[parseInt(c,16)]).join('');
assert.equal(ID,'eandddnbchclalbjkhfelhjhpijifcog');
const output=path.join(root,'ask-'+Date.now());
await fs.mkdir(output,{recursive:true,mode:0o700});
const results=[],cleanup=[],tcpSockets=new Set();let chrome;
process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE='1';
const add=(name,pass,detail={})=>{const r={name,pass,...detail};results.push(r);console.log(JSON.stringify(r));assert.ok(pass,name);};
const listen=async(server,host='127.0.0.1')=>{await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,host,resolve)});cleanup.push(()=>new Promise(r=>server.close(r)));return server.address().port;};
const stat={bytes:0,connections:0};
const echoPort=await listen(net.createServer(s=>{stat.connections++;tcpSockets.add(s);s.on('error',()=>{});s.on('close',()=>tcpSockets.delete(s));let n=0;s.on('data',d=>{stat.bytes+=d.length;n+=d.length;s.write(d);if(n>=6)s.end();});}));
const swf=await fs.readFile(path.join(root,'NativeProbe.swf'));
const pageHtml=(u)=>{
 const vars=new URLSearchParams({host:'127.0.0.1',port:String(echoPort),timeout:u.searchParams.get('timeout')??'20000',size:'6',cancel:'-1'}).toString();
 return '<!doctype html><meta charset="utf-8"><title>Socket question regression</title><script>window.__probe=null;window.nativeProbeDone=s=>window.__probe=JSON.parse(s);window.RufflePlayer={config:{autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas",logLevel:"error"}};</script>'
  +(u.searchParams.has('bare')?'<p>no flash here</p>':('<embed src="/NativeProbe.swf" type="application/x-shockwave-flash" width="400" height="300" allowScriptAccess="always" flashvars="'+vars.replaceAll('&','&amp;')+'">'));};
const web=http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');
 if(u.pathname==='/NativeProbe.swf'){res.setHeader('Content-Type','application/x-shockwave-flash');res.end(swf);return;}
 if(u.pathname==='/framed'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8">'+['popup.html','options.html','onboard.html','prompt.html?id=00000000-0000-4000-8000-000000000000','player.html'].map(p=>'<iframe src="chrome-extension://'+ID+'/'+p+'"></iframe>').join(''));return;}
 if(u.pathname==='/swf-link'){res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><a id="link" href="/NativeProbe.swf">a SWF</a>');return;}
 res.setHeader('Content-Type','text/html');res.end(pageHtml(u));});
const pagePort=await listen(web),origin='http://127.0.0.1:'+pagePort;
const alt=http.createServer((req,res)=>{res.setHeader('Content-Type',req.url.startsWith('/NativeProbe.swf')?'application/x-shockwave-flash':'text/html');res.end(req.url.startsWith('/NativeProbe.swf')?swf:pageHtml(new URL(req.url,'http://x')));});
const altPort=await listen(alt,'127.0.0.1');const altOrigin='http://localhost:'+altPort;
const until=async(fn,ms=8000)=>{const end=Date.now()+ms;while(Date.now()<end){const v=await fn();if(v)return v;await delay(80);}return false;};

// The helper is installed by its own --install into a disposable HOME, like the regression run does.
const work=path.join(output,'chrome');
const installEnv={...process.env,HOME:path.join(work,'home'),XDG_DATA_HOME:path.join(work,'data'),XDG_CONFIG_HOME:path.join(work,'config')};delete installEnv.CHROME_CONFIG_HOME;
const userDataDir=path.join(work,'config','google-chrome');
const installedHelper=path.join(work,'data','timffle-socket-helper','timffle-socket-helper');
const countHelpers=()=>{try{return execFileSync('pgrep',['-f',installedHelper+' chrome-extension://'+ID+'/'],{encoding:'utf8'}).trim().split(/\s+/).filter(Boolean).length;}catch{return 0;}};

const targets=async()=>(await chrome.send('Target.getTargets')).targetInfos;
const promptTargets=async()=>(await targets()).filter(t=>t.url.startsWith('chrome-extension://'+ID+'/prompt.html'));
const attach=async(targetId,methods=['Page.enable','Runtime.enable'])=>{const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});for(const m of methods)await chrome.send(m,{},sessionId);return sessionId;};
const close=(targetId)=>chrome.send('Target.closeTarget',{targetId}).catch(()=>{});
// A real (trusted) click on the middle of an element: the pages ignore script-made clicks.
const click=async(sessionId,selector)=>{
 const r=await chrome.eval(sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');if(!e)return null;e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2,w:b.width,h:b.height}})()');
 assert.ok(r&&r.w>0&&r.h>0,'no visible element '+selector);
 for(const type of ['mouseMoved','mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',buttons:type==='mousePressed'?1:0,clickCount:type==='mouseMoved'?0:1},sessionId);
};
const settingsNow=()=>chrome.eval(opts.sessionId,'chrome.storage.local.get("socketProxySettings").then(x=>x.socketProxySettings??null)');
const setSettings=(value)=>chrome.eval(opts.sessionId,value===null?'chrome.storage.local.remove("socketProxySettings")':'chrome.storage.local.set({socketProxySettings:'+JSON.stringify(value)+'})');
// The extension opens at most 6 question windows a minute (MAX_PROMPTS_PER_MINUTE); a quick run, such as one in a
// language whose popup needs no waiting, must not trip that, so a new page waits while 5 windows are still that young.
const askedAt=[];
const spacing=async()=>{while(askedAt.filter(t=>Date.now()-t<62000).length>=5)await delay(500);};
const fixtureTab=async(site=origin,query='')=>{await spacing();const p=await chrome.tab(site+'/?'+query);return p;};
const probe=(p,ms=20000)=>chrome.wait(p.sessionId,'window.__probe',ms);
const good=r=>r.status==='ok'&&r.badBytes===0&&r.events.filter(x=>x==='connect').length===1&&r.events.filter(x=>x==='close').length===1;
const noConnect=r=>r.status==='ioError'&&r.connectMs===-1&&!r.events.includes('connect')&&!r.connected;
// Waits for the question window of the website, and for its input guard to pass.
const question=async(ms=15000)=>{const t=await until(async()=>(await promptTargets())[0],ms);assert.ok(t,'no question window');askedAt.push(Date.now());const sessionId=await attach(t.targetId);
 await chrome.wait(sessionId,'!document.getElementById("prompt").hidden',8000);await delay(900);return {...t,sessionId};};
const answerWith=async(q,choice)=>{await click(q.sessionId,'#'+choice);};
// The service worker is stopped when idle; talk to it only briefly (an attached debugger keeps it alive).
const withServiceWorker=async(fn)=>{
 await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"wake"}).catch(()=>{})');
 const t=await until(async()=>(await targets()).find(x=>x.type==='service_worker'&&x.url.includes(ID)));
 assert.ok(t,'no service worker');
 const sessionId=await attach(t.targetId,['Runtime.enable']);
 try{return await fn(sessionId);}finally{await chrome.send('Target.detachFromTarget',{sessionId}).catch(()=>{});}
};
const popupUrl='chrome-extension://'+ID+'/popup.html';
// Opens the real action popup over the active tab of the window; one popup at a time.
const openPopup=async(tab)=>{
 await chrome.send('Target.activateTarget',{targetId:tab.targetId});
 await delay(300);
 await withServiceWorker(async(sw)=>{
  const id=await chrome.eval(sw,'chrome.windows.getLastFocused().then(w=>w.id)');
  await chrome.send('Runtime.evaluate',{expression:'chrome.action.openPopup({windowId:'+id+'})',awaitPromise:true,userGesture:true},sw);
 });
 const t=await until(async()=>(await targets()).find(x=>x.url===popupUrl));
 assert.ok(t,'popup did not open');
 const sessionId=await attach(t.targetId);
 await chrome.wait(sessionId,'document.getElementById("version-text").textContent!==""&&document.getElementById("status-text").textContent!=="Timffle is ready to run Flash content in the current tab."',8000).catch(()=>{});
 await delay(900);
 return {targetId:t.targetId,sessionId};
};
const closePopup=async(p)=>{await close(p.targetId);await until(async()=>!(await targets()).some(x=>x.url===popupUrl));};
const popupState=(p)=>chrome.eval(p.sessionId,`(()=>({visible:!document.getElementById('socket-container').classList.contains('hidden'),warning:document.querySelector('.socket-warning').textContent.replace(/\\s+/g,' ').trim(),sites:[...document.querySelectorAll('.socket-site')].map(s=>({origin:s.querySelector('.socket-origin').textContent,state:s.querySelector('.socket-state').textContent,allow:s.querySelector('.socket-allow')?.textContent??null,select:s.querySelector('.socket-select')?.value??null})),reload:!document.getElementById('reload-button').disabled}))()`);
const keyPress=async(sessionId,key,vk)=>{for(const type of ['rawKeyDown','keyUp'])await chrome.send('Input.dispatchKeyEvent',{type,key,code:key,windowsVirtualKeyCode:vk},sessionId);};
// Typing a character key the way a keyboard does (key down with its text, then up): this is what activates a focused button.
const typeKey=async(sessionId,key,code,vk,text)=>{await chrome.send('Input.dispatchKeyEvent',{type:'keyDown',key,code,windowsVirtualKeyCode:vk,text},sessionId);await chrome.send('Input.dispatchKeyEvent',{type:'keyUp',key,code,windowsVirtualKeyCode:vk},sessionId);};
// A button press with no pointer movement before it (a click where the pointer just rests).
const blindClick=async(sessionId,selector)=>{
 const r=await chrome.eval(sessionId,'(()=>{const b=document.querySelector('+JSON.stringify(selector)+').getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()');
 for(const type of ['mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',buttons:type==='mousePressed'?1:0,clickCount:1},sessionId);
};
// The popup only accepts real input, so change the <select> with the keyboard.
const choose=async(p,value,index=0)=>{
 const cur=await chrome.eval(p.sessionId,`(()=>{const s=document.querySelectorAll('.socket-select')[${index}];s.focus();return s.value})()`);
 if(cur===value)return;
 await (value==='ask'?keyPress(p.sessionId,'Home',36):value==='deny'?keyPress(p.sessionId,'End',35):cur==='ask'?keyPress(p.sessionId,'ArrowDown',40):keyPress(p.sessionId,'ArrowUp',38));
};

const only=(process.env.ASK_ONLY||'').split(',').filter(Boolean);
const runs=(name)=>only.length===0||only.includes(name);
let opts;
try{
 await fs.mkdir(installEnv.HOME,{recursive:true,mode:0o700});
 const out=execFileSync(path.resolve(helper),['--install'],{env:installEnv,encoding:'utf8'});
 add('helper-installed',out.includes('installed'));
 chrome=new Chrome(work,{recordEvents:false,fontConfig:process.env.TEST_FONTCONFIG||undefined,userDataDir,locale});
 chrome.tab=async(url)=>{const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});const sessionId=await attach(targetId);await chrome.send('Network.enable',{},sessionId);await chrome.send('Page.navigate',{url},sessionId);return {targetId,sessionId};};
 const loaded=await chrome.send('Extensions.loadUnpacked',{path:path.resolve(extensionDir)});add('stable-extension-id',loaded.id===ID,{id:loaded.id});
 opts=await chrome.tab('chrome-extension://'+ID+'/options.html');
 await chrome.wait(opts.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
 await chrome.eval(opts.sessionId,'chrome.storage.sync.set({autostart:true,autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas"})');
 // Pages loaded before the extension has registered its page-world scripts never get Ruffle; wait for the registration.
 add('page-world-scripts-registered',!!await until(async()=>(await withServiceWorker(sw=>chrome.eval(sw,'chrome.scripting.getRegisteredContentScripts().then(r=>r.map(x=>x.id).sort().join())'))).includes('ruffle'),20000));

 if(runs('basics')){
 // ---- 1. nothing is allowed for this website yet: a page without Flash is left alone, a page that tries a socket is asked
 await setSettings(null);
 const bare=await fixtureTab(origin,'bare=1');
 // The extension has loaded Ruffle into the page once it has put its own hook in the config (reading the socket list is not a safe probe).
 await chrome.wait(bare.sessionId,'typeof window.RufflePlayer?.config?.openInNewTab==="function"',20000);
 // Read the constructor first: reading Ruffle's socket list is what installs the bridge.
 const bareNative=await chrome.eval(bare.sessionId,'Function.prototype.toString.call(WebSocket)');
 const bareProxy=await chrome.eval(bare.sessionId,'window.RufflePlayer?.config?.socketProxy??null');
 const afterRead=await chrome.eval(bare.sessionId,'Function.prototype.toString.call(WebSocket)');
 add('page-without-flash-keeps-native-websocket',/function WebSocket\(\) \{ \[native code\] \}/u.test(bareNative)&&Array.isArray(bareProxy)&&bareProxy.length===1,{bareNative,bareProxy});
 // Positive control: the same test sees the shim once Ruffle has read the list, so the check above can fail.
 add('reading-the-socket-list-installs-the-bridge',!/function WebSocket\(\) \{ \[native code\] \}/u.test(afterRead),{afterRead});
 await close(bare.targetId);

 const before=stat.connections;
 const first=await fixtureTab(origin,'');
 const q1=await question();
 const view=await chrome.eval(q1.sessionId,'({origin:document.getElementById("prompt-origin").textContent,title:document.getElementById("prompt-title").textContent.replace(/\\s+/g," ").trim(),warning:document.getElementById("prompt-warning").textContent.replace(/\\s+/g," ").trim(),buttons:[...document.querySelectorAll("button[data-choice]")].map(b=>b.dataset.choice),focus:document.activeElement?.id})');
 add('first-attempt-opens-the-question',view.origin===origin&&view.buttons.join()==='deny-once,allow-once,deny-always,allow-always',{view});
 add('question-recommends-denying-and-names-online-games',norm(view.warning)===T.plain('timffle_prompt_warning')&&norm(view.title)===norm(T('timffle_prompt_title'))&&view.focus==='deny-once',{warning:view.warning,title:view.title,focus:view.focus});
 add('nothing-connects-while-the-question-is-open',stat.connections===before&&countHelpers()===0);
 const shot=await chrome.send('Page.captureScreenshot',{format:'png'},q1.sessionId);await fs.writeFile(path.join(output,'question.png'),Buffer.from(shot.data,'base64'));
 // With a real window (CHROME_HEADED=1 CHROME_WINDOW_SIZE=none, e.g. under xvfb-run; --window-size would override the size the
 // extension asks for) the question must fit in the window it is opened in.
 const fit=await chrome.eval(q1.sessionId,'({innerWidth,innerHeight,scrollHeight:document.documentElement.scrollHeight,outerWidth,outerHeight})');
 if(process.env.CHROME_HEADED&&process.env.CHROME_WINDOW_SIZE==='none')add('question-fits-its-window-without-scrolling',fit.scrollHeight<=fit.innerHeight,{fit});else console.log(JSON.stringify({info:'question-window',fit}));
 await answerWith(q1,'allow-once');
 const r1=await probe(first,25000);
 add('allow-this-time-connects',good(r1),{r1});
 const s1=await settingsNow();
 add('allow-this-time-saves-nothing',s1===null||!s1.allowedOrigins.includes(origin)&&!(s1.deniedOrigins??[]).includes(origin),{s1});
 add('question-window-closed-after-answer',await until(async()=>(await promptTargets()).length===0),{});
 const sw=await chrome.eval(first.sessionId,'Function.prototype.toString.call(WebSocket)');
 // Reloading the same tab is the same visit: no new question, it just connects.
 await chrome.eval(first.sessionId,'window.__probe=null');
 await chrome.send('Page.reload',{},first.sessionId);
 const r2=await probe(first,25000);
 add('reload-is-the-same-visit',good(r2)&&(await promptTargets()).length===0,{r2});
 // Another tab is another visit.
 const second=await fixtureTab(origin,'');
 const q2=await question();
 add('another-tab-asks-again',(await promptTargets()).length===1&&await chrome.eval(q2.sessionId,'document.getElementById("prompt-origin").textContent')===origin);
 await answerWith(q2,'deny-once');
 const r3=await probe(second,25000);
 add('deny-this-time-refuses',noConnect(r3),{r3});
 const connectionsAfterDeny=stat.connections;
 await chrome.eval(second.sessionId,'window.__probe=null');
 await chrome.send('Page.reload',{},second.sessionId);
 const r4=await probe(second,25000);
 add('denied-visit-does-not-ask-again',noConnect(r4)&&(await promptTargets()).length===0&&stat.connections===connectionsAfterDeny,{r4});
 await close(first.targetId);await close(second.targetId);

 // ---- 2. the lasting answers
 const t3=await fixtureTab(origin,'');
 const q3=await question();
 await answerWith(q3,'allow-always');
 const r5=await probe(t3,25000);
 add('always-allow-connects',good(r5),{r5});
 const s2=await settingsNow();
 add('always-allow-is-saved',s2.allowedOrigins.includes(origin)&&!s2.deniedOrigins.includes(origin)&&s2.allowedOrigins.includes('https://mole.61.com.tw'),{s2});
 await close(t3.targetId);
 const t4=await fixtureTab(origin,'');
 const r6=await probe(t4,25000);
 add('always-allow-is-not-asked-again',good(r6)&&(await promptTargets()).length===0,{r6});
 await close(t4.targetId);
 // Take it back from the options page: asks again.
 const optionsText=await chrome.eval(opts.sessionId,'(async()=>{location.reload();return true})()');
 await delay(500);
 opts.sessionId=opts.sessionId;
 await setSettings({...s2,allowedOrigins:s2.allowedOrigins.filter(o=>o!==origin)});
 const t5=await fixtureTab(origin,'');
 const q5=await question();
 await answerWith(q5,'deny-always');
 const r7=await probe(t5,25000);
 add('always-deny-refuses',noConnect(r7),{r7});
 const s3=await settingsNow();
 add('always-deny-is-saved',s3.deniedOrigins.includes(origin)&&!s3.allowedOrigins.includes(origin),{s3});
 await close(t5.targetId);
 const t6=await fixtureTab(origin,'');
 const r8=await probe(t6,25000);
 add('always-deny-is-not-asked-again',noConnect(r8)&&(await promptTargets()).length===0,{r8});
 const cfg={native:await chrome.eval(t6.sessionId,'Function.prototype.toString.call(WebSocket)'),socketProxy:await chrome.eval(t6.sessionId,'window.RufflePlayer?.config?.socketProxy??null')};
 add('always-deny-gets-no-socket-config-and-native-websocket',(!cfg.socketProxy||cfg.socketProxy.length===0)&&/function WebSocket\(\) \{ \[native code\] \}/u.test(cfg.native),{cfg});
 await close(t6.targetId);


 }
 if(runs('popup')){
 // ---- 3. the popup: one click allows the tab's website, and the choice can be changed or taken back
 await setSettings(null);
 const web1=await fixtureTab(origin,'bare=1');
 await chrome.wait(web1.sessionId,'document.readyState==="complete"');await delay(600);
 let pop=await openPopup(web1);
 let ps=await popupState(pop);
 add('popup-offers-to-allow-this-site',ps.visible&&ps.sites.length===1&&ps.sites[0].origin===origin&&ps.sites[0].state===T('timffle_choice_ask')&&ps.sites[0].allow===T('timffle_popup_allow_site')&&ps.sites[0].select==='ask'&&norm(ps.warning)===norm(T('timffle_popup_warning')),{ps});
 {const shot=await chrome.send('Page.captureScreenshot',{format:'png'},pop.sessionId);await fs.writeFile(path.join(output,'popup-ask.png'),Buffer.from(shot.data,'base64'));}
 const popupHeight=await chrome.eval(pop.sessionId,'document.documentElement.scrollHeight');
 // The Logitech discount box is for the English and Chinese interfaces only. In every other language there is no box and the whole popup
 // fits the 600 px Chrome shows. Where the box is, it is open, so the popup is taller (Chrome scrolls it): what has to fit is everything
 // above the box and its summary line, the end of the box must be reachable by scrolling without sideways overflow, and folding it (a real
 // click) brings the whole popup back under 600 px.
 if(!['en','zh_CN','zh_TW'].includes(locale)){
  add('popup-fits-the-600px-chrome-allows',popupHeight<=600,{popupHeight});
  const gone=await chrome.eval(pop.sessionId,'(()=>{const s=document.getElementById("promo");return s.hidden&&getComputedStyle(s).display==="none"})()');
  add('popup-has-no-discount-box-in-this-language',gone===true,{locale});
 }else{
  await until(()=>chrome.eval(pop.sessionId,'(()=>{const d=document.getElementById("promo"),i=d.querySelector("img");return d.open&&i.complete&&i.naturalWidth===720})()'));
  const top=await chrome.eval(pop.sessionId,'(()=>{const s=document.querySelector("#promo summary").getBoundingClientRect();return {open:document.getElementById("promo").open,summaryBottom:Math.round(s.bottom+scrollY)}})()');
  add('popup-controls-and-the-discount-summary-fit-the-600px-chrome-allows',top.open&&top.summaryBottom<=600,{top,popupHeight});
  const box=await chrome.eval(pop.sessionId,'(()=>{window.scrollTo(0,document.documentElement.scrollHeight);const b=document.querySelector("#promo .promo-note").getBoundingClientRect(),e=document.documentElement;return {viewport:window.innerHeight,innerWidth:window.innerWidth,clientWidth:e.clientWidth,content:e.scrollHeight,scrolled:Math.round(window.scrollY),noteTop:Math.round(b.top),noteBottom:Math.round(b.bottom),sideways:e.scrollWidth>e.clientWidth}})()');
  add('popup-discount-box-is-open-and-scrolls-to-its-end',box.viewport<=600&&box.noteTop>=0&&box.noteBottom<=box.viewport&&!box.sideways&&(box.content<=box.viewport||box.scrolled>0),{box});
  await click(pop.sessionId,'#promo summary');
  await delay(400);
  const folded=await chrome.eval(pop.sessionId,'({open:document.getElementById("promo").open,height:document.documentElement.scrollHeight})');
  add('popup-discount-box-can-be-folded-and-then-the-popup-fits-600px',folded.open===false&&folded.height<=600,{folded});
  await click(pop.sessionId,'#promo summary');
  await delay(400);
 }
 await click(pop.sessionId,'.socket-allow');
 await until(async()=>(await settingsNow())?.allowedOrigins.includes(origin));
 const sa=await settingsNow();
 add('popup-allow-adds-the-origin-without-typing',sa.allowedOrigins.includes(origin)&&!sa.deniedOrigins.includes(origin),{sa});
 await delay(500);ps=await popupState(pop);
 add('popup-shows-always-allowed-and-no-allow-button',ps.sites[0].state===T('timffle_popup_always_allowed')&&ps.sites[0].allow===null&&ps.sites[0].select==='allow',{ps});
 add('popup-asks-for-a-reload-after-allowing',ps.reload===true,{ps});
 {const shot=await chrome.send('Page.captureScreenshot',{format:'png'},pop.sessionId);await fs.writeFile(path.join(output,'popup-allowed.png'),Buffer.from(shot.data,'base64'));}
 await choose(pop,'deny');
 await until(async()=>(await settingsNow())?.deniedOrigins.includes(origin));
 const sd=await settingsNow();
 add('popup-select-always-deny',sd.deniedOrigins.includes(origin)&&!sd.allowedOrigins.includes(origin),{sd});
 await delay(500);ps=await popupState(pop);
 add('popup-shows-always-denied-with-allow-button',ps.sites[0].state===T('timffle_popup_always_denied')&&ps.sites[0].allow!==null&&ps.sites[0].select==='deny',{ps});
 await choose(pop,'ask');
 await until(async()=>{const x=await settingsNow();return x&&!x.deniedOrigins.includes(origin)&&!x.allowedOrigins.includes(origin);});
 await delay(500);ps=await popupState(pop);
 add('popup-select-ask-removes-both',ps.sites[0].state===T('timffle_choice_ask')&&ps.sites[0].select==='ask',{ps});
 await choose(pop,'allow');
 await until(async()=>(await settingsNow())?.allowedOrigins.includes(origin));
 add('popup-select-always-allow',(await settingsNow()).allowedOrigins.includes(origin));
 await closePopup(pop);await close(web1.targetId);
 // What the popup allowed is honoured by a page: no question, it connects.
 const web2=await fixtureTab(origin,'');
 const rPop=await probe(web2,25000);
 add('popup-allowed-site-connects-without-a-question',good(rPop)&&(await promptTargets()).length===0,{rPop});
 await close(web2.targetId);

 // The popup shows this visit's answer, and a frame of another website that was asked about.
 await setSettings(null);
 const portal=await chrome.tab(origin+'/?bare=1');
 await chrome.wait(portal.sessionId,'document.readyState!=="loading"');
 const frameHtml='<!doctype html><meta charset="utf-8"><title>portal</title><iframe id="game" src="'+altOrigin+'/?timeout=20000" width="420" height="320"></iframe>';
 await chrome.eval(portal.sessionId,'document.open();document.write('+JSON.stringify(frameHtml)+');document.close();true');
 const q7=await question();
 const frameView=await chrome.eval(q7.sessionId,'({origin:document.getElementById("prompt-origin").textContent,embedded:document.getElementById("prompt-embedded").hidden?null:document.getElementById("prompt-embedded").textContent})');
 add('question-names-the-frame-and-the-page-around-it',frameView.origin===altOrigin&&frameView.embedded&&frameView.embedded.includes(origin),{frameView});
 await answerWith(q7,'deny-once');
 await delay(1500);
 pop=await openPopup(portal);
 ps=await popupState(pop);
 const frameRow=ps.sites.find(x=>x.origin===altOrigin);
 add('popup-lists-the-frame-that-was-asked-about',ps.sites.length===2&&ps.sites[0].origin===origin&&!!frameRow&&frameRow.state===T('timffle_popup_visit_denied')&&frameRow.allow===T('timffle_allow'),{ps});
 {const shot=await chrome.send('Page.captureScreenshot',{format:'png'},pop.sessionId);await fs.writeFile(path.join(output,'popup-frame.png'),Buffer.from(shot.data,'base64'));}
 await click(pop.sessionId,'.socket-site:nth-of-type(2) .socket-allow');
 await until(async()=>(await settingsNow())?.allowedOrigins.includes(altOrigin));
 add('popup-allows-the-frame-origin-not-the-page',(await settingsNow()).allowedOrigins.includes(altOrigin)&&!(await settingsNow()).allowedOrigins.includes(origin));
 await delay(500);ps=await popupState(pop);
 const portalTabId=await chrome.eval(opts.sessionId,'chrome.tabs.query({}).then(ts=>ts.find(t=>t.url&&t.url.startsWith('+JSON.stringify(origin+'/')+'))?.id)');
 const visitNow=await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"socket_visit_get",tabId:'+portalTabId+'})');
 // The frame is listed only while it has an answer for this visit; a lasting choice replaces that answer, so its row goes.
 add('popup-forgets-the-visit-answer-after-a-lasting-choice',!ps.sites.some(x=>x.origin===altOrigin)&&!(altOrigin in (visitNow?.decisions??{altOrigin:1}))&&(await settingsNow()).allowedOrigins.includes(altOrigin),{ps,visitNow});
 await closePopup(pop);await close(portal.targetId);

 // Pages that are not websites get no Socket section; switched-off sockets show no controls.
 const blank=await chrome.tab('about:blank');await delay(500);
 pop=await openPopup(blank);ps=await popupState(pop);
 add('popup-has-no-socket-section-for-non-websites',ps.visible===false,{ps});
 await closePopup(pop);await close(blank.targetId);
 await setSettings({enabled:false,mode:'helper',proxyUrl:'',allowedOrigins:['https://mole.61.com.tw'],deniedOrigins:[]});
 const off=await fixtureTab(origin,'bare=1');await chrome.wait(off.sessionId,'document.readyState==="complete"');await delay(600);
 pop=await openPopup(off);ps=await popupState(pop);
 add('popup-says-sockets-are-off-and-offers-nothing',ps.visible&&ps.sites.length===1&&ps.sites[0].state===T('timffle_popup_off')&&ps.sites[0].allow===null&&ps.sites[0].select===null,{ps});
 await closePopup(pop);
 await setSettings({enabled:true,mode:'websocket',proxyUrl:'ws://127.0.0.1:1/connect?host={host}&port={port}',allowedOrigins:['https://mole.61.com.tw'],deniedOrigins:[]});
 await delay(500);
 pop=await openPopup(off);ps=await popupState(pop);
 add('popup-with-a-custom-proxy-says-it-never-asks',ps.visible&&ps.sites[0].state===T('timffle_popup_proxy_not_allowed')&&ps.sites[0].allow!==null,{ps});
 await closePopup(pop);await close(off.targetId);
 await setSettings(null);

 }
 if(runs('framing')){
 // ---- 4. a website cannot frame the extension's own pages (popup, settings, question, welcome) and get them clicked
 const framedTab=await chrome.tab(origin+'/framed');
 await chrome.wait(framedTab.sessionId,'document.readyState==="complete"');await delay(1500);
 const tree=(await chrome.send('Page.getFrameTree',{},framedTab.sessionId)).frameTree;
 const childFrames=tree.childFrames??[];
 // Chrome shows an error page, with the extension's address hidden, in a frame it refuses to load.
 const errorFrames=childFrames.filter(f=>f.frame.url==='chrome-error://chromewebdata/').length;
 // A frame that does load is a process of its own (an extension page in a website's frame), so it is a target.
 const loadedFrames=(await targets()).filter(t=>t.type==='iframe'&&t.url.startsWith('chrome-extension://'+ID+'/')).map(t=>new URL(t.url).pathname);
 // Positive control: the page that is exposed (player.html) does load in a frame, so a refusal is the manifest's doing.
 add('extension-pages-cannot-be-framed-by-a-website',errorFrames===4&&loadedFrames.join()==='/player.html',{errorFrames,loadedFrames});
 // What a website does need stays reachable: Ruffle itself and the standalone player (SWF links are redirected to it).
 const reach=await chrome.eval(framedTab.sessionId,'(async()=>{const get=async p=>{try{return (await fetch("chrome-extension://'+ID+'/"+p)).status}catch{return "blocked"}};return {ruffle:await get("dist/ruffle.js"),wasm:await get("dist/ruffle_web_bg.wasm"),player:await get("player.html"),options:await get("options.html"),popup:await get("popup.html"),prompt:await get("prompt.html"),background:await get("dist/background.js")}})()');
 add('a-website-reaches-only-ruffle-and-the-player',reach.ruffle===200&&reach.wasm===200&&reach.player===200&&reach.options==='blocked'&&reach.popup==='blocked'&&reach.prompt==='blocked'&&reach.background===200,{reach});
 await close(framedTab.targetId);
 // The one page a website's links do lead to stays reachable: a SWF address (typed, or followed from a page) is redirected to the standalone player.
 await until(async()=>(await chrome.eval(opts.sessionId,'chrome.declarativeNetRequest.getDynamicRules().then(r=>r.length)'))>0,15000);
 const playerOpen=(sessionId)=>until(async()=>{const r=await chrome.eval(sessionId,'({url:location.href,player:!!document.querySelector("ruffle-player")})').catch(()=>null);return r&&r.url.startsWith('chrome-extension://'+ID+'/player.html#')&&r.player?r:false;},15000);
 const typedSwf=await chrome.tab(origin+'/NativeProbe.swf');
 const typedPlayer=await playerOpen(typedSwf.sessionId);
 add('a-typed-swf-address-opens-the-standalone-player',!!typedPlayer,{typedPlayer});
 await close(typedSwf.targetId);
 const linkPage=await chrome.tab(origin+'/swf-link');
 await chrome.wait(linkPage.sessionId,'!!document.getElementById("link")');
 await chrome.eval(linkPage.sessionId,'document.getElementById("link").click();true');
 const linkedPlayer=await playerOpen(linkPage.sessionId);
 add('a-link-to-a-swf-opens-the-standalone-player',!!linkedPlayer,{linkedPlayer});
 await close(linkPage.targetId);
 // Defence in depth: should a browser ever let a page frame them, they offer nothing. Frame them from an extension page, which can.
 const inner=await chrome.eval(opts.sessionId,'(async()=>{const out={};for(const p of ["options.html","popup.html","prompt.html?id=00000000-0000-4000-8000-000000000000"]){const f=document.createElement("iframe");f.src=chrome.runtime.getURL(p);document.body.append(f);await new Promise(r=>f.addEventListener("load",r));await new Promise(r=>setTimeout(r,1200));const d=f.contentDocument;out[p.split("?")[0]]={bodyChildren:d.body.children.length,sites:d.querySelectorAll(".socket-site").length,socketHidden:d.getElementById("socket-container")?.classList.contains("hidden")??null,buttons:d.querySelectorAll("button[data-choice]").length,inputs:d.querySelectorAll("input,textarea,select").length};f.remove();}return out})()');
 add('framed-pages-offer-nothing',inner['options.html'].bodyChildren===0&&inner['options.html'].inputs===0&&inner['prompt.html'].bodyChildren===0&&inner['prompt.html'].buttons===0&&inner['popup.html'].sites===0&&inner['popup.html'].socketHidden===true,{inner});

 }
 if(runs('guard')){
 // ---- 7. what counts as an answer in the question window
 await setSettings(null);
 const tg=await fixtureTab(origin,'');
 const qg=await question();
 const before=stat.connections;
 const open=async()=>(await promptTargets()).length===1&&await chrome.eval(qg.sessionId,'!document.getElementById("prompt").hidden');
 await chrome.eval(qg.sessionId,'document.getElementById("allow-once").click();document.getElementById("allow-always").click();true');
 await delay(500);
 add('script-made-clicks-do-not-answer',await open()&&stat.connections===before);
 // Tab moves from the safe button to "allow"; Enter and Space are the keys of a game's login form.
 await keyPress(qg.sessionId,'Tab',9);
 const focused=await chrome.eval(qg.sessionId,'document.activeElement?.id');
 await typeKey(qg.sessionId,'Enter','Enter',13,'\r');
 await typeKey(qg.sessionId,' ','Space',32,' ');
 await delay(500);
 add('keyboard-cannot-allow',focused==='allow-once'&&await open()&&stat.connections===before,{focused});
 await blindClick(qg.sessionId,'#allow-always');
 await delay(500);
 add('a-click-without-the-pointer-having-moved-over-the-button-does-not-allow',await open()&&stat.connections===before);
 // The window loses the focus: nothing counts until it has it again and the first moment has passed.
 await chrome.eval(qg.sessionId,'window.dispatchEvent(new Event("blur"));true');
 await click(qg.sessionId,'#deny-once');
 await delay(500);
 add('nothing-counts-while-the-window-has-no-focus',await open());
 await chrome.eval(qg.sessionId,'window.dispatchEvent(new Event("focus"));true');
 await click(qg.sessionId,'#deny-once');
 await delay(300);
 add('a-click-right-after-getting-the-focus-is-ignored',await open());
 await delay(900);
 await click(qg.sessionId,'#deny-once');
 const rg=await probe(tg,25000);
 add('a-deliberate-click-answers-after-all-that',noConnect(rg)&&await until(async()=>(await promptTargets()).length===0),{rg});
 await close(tg.targetId);
 // The keyboard can always refuse: the safe button has the focus when the question opens.
 const tk=await fixtureTab(origin,'');
 const qk=await question();
 const focusedAtStart=await chrome.eval(qk.sessionId,'document.activeElement?.id');
 await typeKey(qk.sessionId,'Enter','Enter',13,'\r');
 const rk=await probe(tk,25000);
 add('the-keyboard-can-refuse',focusedAtStart==='deny-once'&&noConnect(rk),{focusedAtStart,rk});
 await close(tk.targetId);

 }
 if(runs('options')){
 // ---- 8. the settings page: one list per connection method, and a form that does not undo what was decided elsewhere
 const X='https://x.example',Y='https://y.example',Z='https://z.example';
 await setSettings({enabled:true,mode:'helper',proxyUrl:'',allowedOrigins:[origin,X],proxyOrigins:[Y],deniedOrigins:[]});
 const form=await chrome.tab('chrome-extension://'+ID+'/options.html');
 await chrome.wait(form.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
 const read=()=>chrome.eval(form.sessionId,'({mode:document.getElementById("socket-proxy-mode-websocket").checked?"websocket":"helper",origins:document.getElementById("socket-proxy-origins").value,denied:document.getElementById("socket-proxy-denied").value,status:document.getElementById("socket-proxy-status").textContent,state:document.getElementById("socket-proxy-status").dataset.state,texts:[...new Set([...document.querySelectorAll("[data-mode-text]")].filter(n=>!n.hidden).map(n=>n.dataset.modeText))].join(),save:document.getElementById("socket-proxy-save").disabled})');
 const type=(selector,value)=>chrome.eval(form.sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');e.value='+JSON.stringify(value)+';e.dispatchEvent(new Event("input",{bubbles:true}));return true})()');
 let f=await read();
 add('settings-page-shows-the-helper-list',f.mode==='helper'&&f.origins===[origin,X].join('\n')&&f.texts==='helper',{f});
 await type('#socket-proxy-origins',[origin,X,Z].join('\n'));
 await click(form.sessionId,'#socket-proxy-mode-websocket');
 f=await read();
 add('settings-page-shows-the-proxy-list-in-custom-proxy-mode',f.mode==='websocket'&&f.origins===Y&&f.texts==='websocket',{f});
 await click(form.sessionId,'#socket-proxy-mode-helper');
 f=await read();
 add('switching-back-keeps-what-was-typed-for-the-helper-list',f.mode==='helper'&&f.origins===[origin,X,Z].join('\n'),{f});
 await click(form.sessionId,'#socket-proxy-mode-websocket');
 await type('#socket-proxy-url','ws://127.0.0.1:1/connect?host={host}&port={port}&token=SECRET-TOKEN');
 await type('#socket-proxy-origins',[Y,altOrigin].join('\n'));
 await click(form.sessionId,'#socket-proxy-save');
 await until(async()=>(await settingsNow())?.mode==='websocket');
 let st=await settingsNow();
 add('saving-in-custom-proxy-mode-changes-only-its-own-list',st.mode==='websocket'&&st.proxyOrigins.join()===[Y,altOrigin].join()&&st.allowedOrigins.join()===[origin,X,Z].join(),{st});
 // The token goes to the sites of the custom proxy's list only; a site that is allowed for the helper does not get it.
 const pa=await fixtureTab(origin,'bare=1');
 await chrome.wait(pa.sessionId,'typeof window.RufflePlayer?.config?.openInNewTab==="function"',20000);
 const cfgHelperOnly=await chrome.eval(pa.sessionId,'JSON.stringify(window.RufflePlayer?.config?.socketProxy??null)');
 const pb=await fixtureTab(altOrigin,'bare=1');
 await chrome.wait(pb.sessionId,'typeof window.RufflePlayer?.config?.openInNewTab==="function"',20000);
 const cfgProxySite=await chrome.eval(pb.sessionId,'JSON.stringify(window.RufflePlayer?.config?.socketProxy??null)');
 add('custom-proxy-token-goes-to-its-own-list-only',cfgProxySite.includes('SECRET-TOKEN')&&!cfgHelperOnly.includes('SECRET-TOKEN'),{cfgHelperOnly:cfgHelperOnly.replace(/SECRET-TOKEN/gu,'<token>'),cfgProxySite:cfgProxySite.replace(/SECRET-TOKEN/gu,'<token>')});
 await close(pa.targetId);await close(pb.targetId);

 // A form without edits follows changes made elsewhere (the popup, a question).
 await setSettings({...st,mode:'helper',proxyUrl:'',allowedOrigins:[origin],deniedOrigins:[X]});
 await until(async()=>(await read()).denied===X);
 f=await read();
 add('a-form-without-edits-follows-changes-made-elsewhere',f.denied===X&&f.mode==='helper'&&f.origins===origin&&f.status===T('timffle_updated_elsewhere'),{f});
 // A form with edits is never saved over them: the old view of the lists would undo "always deny".
 await type('#socket-proxy-origins',[origin,Z].join('\n'));
 await setSettings({...(await settingsNow()),deniedOrigins:[X,Z]});
 await until(async()=>(await read()).status===T('timffle_stale'));
 f=await read();
 add('a-form-with-edits-is-told-that-the-settings-changed',f.state==='error'&&f.status===T('timffle_stale'),{f});
 await click(form.sessionId,'#socket-proxy-save');
 await until(async()=>(await read()).status===T('timffle_changed_elsewhere'));
 st=await settingsNow();f=await read();
 add('a-stale-form-cannot-undo-always-deny',st.deniedOrigins.includes(Z)&&!st.allowedOrigins.includes(Z)&&!st.proxyOrigins.includes(Z)&&f.denied.split('\n').includes(Z)&&!f.origins.split('\n').includes(Z),{st,f});
 await close(form.targetId);
 await setSettings(null);

 }
 if(runs('dismissal')){
 // ---- 5. closing the question window is a refusal for this visit
 await setSettings(null);
 const t8=await fixtureTab(origin,'');
 const q8=await question();
 await close(q8.targetId);
 const r9=await probe(t8,25000);
 add('closing-the-question-refuses',noConnect(r9),{r9});
 await chrome.eval(t8.sessionId,'window.__probe=null');
 await chrome.send('Page.reload',{},t8.sessionId);
 const r10=await probe(t8,25000);
 add('closed-question-does-not-come-back-in-this-visit',noConnect(r10)&&(await promptTargets()).length===0,{r10});
 await close(t8.targetId);

 }
 if(runs('keepalive')){
 // ---- 6. the question survives the service worker's idle timeout (the window keeps it alive)
 await setSettings(null);
 const t9=await fixtureTab(origin,'');
 const q9=await question();
 // The page's own 30 s stall timer is the last event the service worker sees from it, so only a wait well past
 // 30 s + 30 s of idle time can tell a kept-alive worker from a stopped one.
 await delay(Number(process.env.ASK_IDLE_MS||75000));
 const stillThere=await chrome.eval(q9.sessionId,'!document.getElementById("prompt").hidden');
 await answerWith(q9,'allow-once');
 const closed=await until(async()=>(await promptTargets()).length===0,10000);
 add('question-is-still-answerable-after-a-long-wait',stillThere&&closed,{stillThere,closed});
 await close(t9.targetId);

 }
 if(runs('fonts')){
 // ---- 7. what the user decided about sockets never changes how the page's text is drawn. Ruffle's own font has no Chinese
 // glyphs, so device text must use the browser's fonts (canvas) whether the website is allowed, asked about, refused or has
 // sockets switched off (it used to be canvas only for "always allow": a game that was asked about lost its Chinese text).
 const rendererOf=async()=>{const p=await fixtureTab(origin,'bare=1');await chrome.wait(p.sessionId,'typeof window.RufflePlayer?.config?.openInNewTab==="function"',20000);const v=await chrome.eval(p.sessionId,'window.RufflePlayer.config.deviceFontRenderer??null');await close(p.targetId);return v;};
 const none={enabled:true,mode:'helper',proxyUrl:'',allowedOrigins:[],proxyOrigins:[],deniedOrigins:[]};
 const socketStates={'always-allow':{...none,allowedOrigins:[origin]},'ask-each-visit':none,'always-deny':{...none,deniedOrigins:[origin]},'sockets-off':{...none,enabled:false}};
 const renderers={};
 for(const [name,value] of Object.entries(socketStates)){await setSettings(value);renderers[name]=await rendererOf();}
 add('device-fonts-use-the-browsers-fonts-in-every-socket-state',Object.values(renderers).every(v=>v==='canvas'),{renderers});
 // An explicit choice of the user still wins (the default renderer is not sent to the page at all).
 await chrome.eval(opts.sessionId,'chrome.storage.sync.set({deviceFontRenderer:"embedded"})');
 const explicit=await rendererOf();
 await chrome.eval(opts.sessionId,'chrome.storage.sync.remove("deviceFontRenderer")');
 add('an-explicitly-chosen-device-font-renderer-still-wins',explicit!=='canvas',{explicit});
 }
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({results},null,2));
 console.log('RESULTS '+output);
}catch(e){results.push({name:'harness-error',pass:false,error:e.message});await fs.writeFile(path.join(output,'results.json'),JSON.stringify({results},null,2));console.error(e.stack);process.exitCode=1;}
finally{
 if(chrome)await chrome.close();for(const socket of tcpSockets)socket.destroy();for(const fn of cleanup.reverse())await fn();
 await delay(300);
}
