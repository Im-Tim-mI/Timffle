import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {loadTexts} from './catalog.mjs';
import {WebSocketServer} from '../../relay/vendor/ws/wrapper.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const [extensionDir,helper,mode='localtest']=process.argv.slice(2);
assert.ok(extensionDir&&helper,'Usage: node browser-auto-tests.mjs extension-dir helper-binary mode');
const manifest=JSON.parse(await fs.readFile(path.join(extensionDir,'manifest.json'),'utf8'));
const locale=process.env.TEST_LOCALE||'en',T=loadTexts(extensionDir,locale);
const digest=crypto.createHash('sha256').update(Buffer.from(manifest.key,'base64')).digest('hex').slice(0,32);
const ID=[...digest].map(c=>'abcdefghijklmnop'[parseInt(c,16)]).join('');
assert.equal(ID,'eandddnbchclalbjkhfelhjhpijifcog');
const output=path.join(root,'browser-'+mode+'-'+Date.now());
await fs.mkdir(output,{recursive:true,mode:0o700});
const results=[],cleanup=[],tcpSockets=new Set();let chrome;
const originalPrivate=process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;
if(mode==='localtest')process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE='1';else delete process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;
const add=(name,pass,detail={})=>{const r={name,pass,...detail};results.push(r);console.log(JSON.stringify(r));assert.ok(pass,name);};
const listen=async(server,host='127.0.0.1')=>{await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,host,resolve)});cleanup.push(()=>new Promise(r=>server.close(r)));return server.address().port;};
const echo=async(expected,host='127.0.0.1')=>{const stat={bytes:0,connections:0,closed:0};const port=await listen(net.createServer(s=>{stat.connections++;tcpSockets.add(s);s.on('error',()=>{});s.on('close',()=>{tcpSockets.delete(s);stat.closed++});let n=0;s.on('data',d=>{stat.bytes+=d.length;n+=d.length;s.write(d);if(expected&&n>=expected)s.end();});}),host);return {port,stat};};
const small=await echo(6),second=await echo(6),large=await echo(262144),held=await echo(0),drain=await echo(0);
let ipv6=null;try{ipv6=await echo(6,'::1');}catch{}
const unused=net.createServer();await new Promise(r=>unused.listen(0,'127.0.0.1',r));const refused=unused.address().port;await new Promise(r=>unused.close(r));
const swf=await fs.readFile(path.join(root,'NativeProbe.swf'));
const web=http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');if(u.pathname==='/NativeProbe.swf'){res.setHeader('Content-Type','application/x-shockwave-flash');res.end(swf);return;}
 const vars=new URLSearchParams({host:u.searchParams.get('host')??'127.0.0.1',port:u.searchParams.get('port')??String(small.port),timeout:u.searchParams.get('timeout')??'1500',size:u.searchParams.get('size')??'6',cancel:u.searchParams.get('cancel')??'-1'}).toString();
 res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><title>Native bridge regression</title><script>window.__probe=null;window.nativeProbeDone=s=>window.__probe=JSON.parse(s);window.RufflePlayer={config:{autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas",logLevel:"error"}};</script>'+(u.searchParams.has('bare')?'':('<embed src="/NativeProbe.swf" type="application/x-shockwave-flash" width="400" height="300" allowScriptAccess="always" flashvars="'+vars.replaceAll('&','&amp;')+'">')));});
const pagePort=await listen(web),origin='http://127.0.0.1:'+pagePort;
const wsHttp=http.createServer();const wss=new WebSocketServer({server:wsHttp});wss.on('connection',s=>s.on('message',(d,b)=>s.send(d,{binary:b})));const wsPort=await listen(wsHttp);cleanup.push(()=>new Promise(r=>wss.close(r)));
const realClick=async(sessionId,selector)=>{const r=await chrome.eval(sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()');for(const type of ['mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',clickCount:1},sessionId);};
const until=async(fn,ms=5000)=>{const end=Date.now()+ms;while(Date.now()<end){const v=await fn();if(v)return v;await delay(80);}return false;};
// Real helpers are installed by their own --install into a disposable HOME,
// and Chrome uses that HOME's default Google Chrome user data directory.
const work=path.join(output,'chrome');
const realHelper=['localtest','production'].includes(mode);
const installEnv={...process.env,HOME:path.join(work,'home'),XDG_DATA_HOME:path.join(work,'data'),XDG_CONFIG_HOME:path.join(work,'config')};delete installEnv.CHROME_CONFIG_HOME;
const installedHelper=path.join(work,'data','timffle-socket-helper','timffle-socket-helper');
const userDataDir=realHelper?path.join(work,'config','google-chrome'):path.join(work,'profile');
const runningHelper=realHelper?installedHelper:path.resolve(helper);
const countHelpers=()=>{const prefix=['delayed','incompatible'].includes(mode)?'mock-host.mjs '+mode:runningHelper;try{return execFileSync('pgrep',['-f',prefix+' chrome-extension://'+ID+'/'],{encoding:'utf8'}).trim().split(/\s+/).filter(Boolean).length;}catch{return 0;}};
try{
 if(realHelper){
  await fs.mkdir(installEnv.HOME,{recursive:true,mode:0o700});
  const out=execFileSync(path.resolve(helper),['--install'],{env:installEnv,encoding:'utf8'});
  const written=JSON.parse(await fs.readFile(path.join(userDataDir,'NativeMessagingHosts','timffle_socket_helper.json'),'utf8'));
  add('installer-registers-for-chrome',out.includes('installed')&&written.path===installedHelper&&JSON.stringify(written.allowed_origins)===JSON.stringify(['chrome-extension://'+ID+'/']),{written});
 }else if(mode!=='missing'){
  const hosts=path.join(userDataDir,'NativeMessagingHosts');await fs.mkdir(hosts,{recursive:true});
  await fs.writeFile(path.join(hosts,'timffle_socket_helper.json'),JSON.stringify({name:'timffle_socket_helper',description:'Isolated test host',path:path.resolve(helper),type:'stdio',allowed_origins:['chrome-extension://'+ID+'/']}));
 }
 chrome=new Chrome(work,{recordEvents:true,fontConfig:process.env.TEST_FONTCONFIG||undefined,userDataDir,locale});
 chrome.tab=async(url)=>{const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});for(const method of ['Page.enable','Runtime.enable','Network.enable'])await chrome.send(method,{},sessionId);await chrome.send('Page.navigate',{url},sessionId);return {targetId,sessionId};};
 const version=(await chrome.send('Browser.getVersion')).product;
 const loaded=await chrome.send('Extensions.loadUnpacked',{path:path.resolve(extensionDir)});add('stable-extension-id',loaded.id===ID,{id:loaded.id});
 const opts=await chrome.tab('chrome-extension://'+ID+'/options.html');
 await chrome.wait(opts.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
 const defaults=await chrome.eval(opts.sessionId,'({enabled:document.querySelector("#socket-proxy-enabled").checked,helper:document.querySelector("#socket-proxy-mode-helper").checked,urlHidden:document.querySelector("#socket-proxy-websocket-fields").hidden,origins:document.querySelector("#socket-proxy-origins").value})');
 add('zero-manual-configuration-defaults',defaults.enabled&&defaults.helper&&defaults.urlHidden&&defaults.origins===['mole','seer','hua','ddt'].flatMap(h=>['https://'+h+'.61.com.tw','http://'+h+'.61.com.tw']).join('\n'),{defaults});

 // A settings object saved by the Mole-only release (no defaultsVersion) follows the new defaults; a list saved by this release stays as saved.
 const optionsFor=async(stored)=>{
  await chrome.eval(opts.sessionId,'chrome.storage.local.set({socketProxySettings:'+JSON.stringify(stored)+'})');
  const tab=await chrome.tab('chrome-extension://'+ID+'/options.html');
  await chrome.wait(tab.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
  const v=await chrome.eval(tab.sessionId,'document.querySelector("#socket-proxy-origins").value');
  await chrome.send('Target.closeTarget',{targetId:tab.targetId});return v;};
 const legacy={enabled:true,mode:'helper',proxyUrl:'',allowedOrigins:['https://mole.61.com.tw','http://mole.61.com.tw']};
 const upgraded=await optionsFor(legacy);
 add('legacy-default-list-upgrades',upgraded===defaults.origins,{upgraded});
 const kept=await optionsFor({...legacy,defaultsVersion:2});
 add('list-saved-by-this-release-is-kept',kept==='https://mole.61.com.tw\nhttp://mole.61.com.tw',{kept});
 const custom=await optionsFor({...legacy,allowedOrigins:['https://mole.61.com.tw','http://mole.61.com.tw','https://x.example']});
 add('customized-list-is-kept',custom==='https://mole.61.com.tw\nhttp://mole.61.com.tw\nhttps://x.example',{custom});
 await chrome.eval(opts.sessionId,'chrome.storage.local.remove("socketProxySettings")');

 const status=await chrome.wait(opts.sessionId,'(()=>{const s=document.querySelector("#socket-helper-status");return s&&s.dataset.state&&s.dataset.state!=="checking"&&s.textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'?{text:s.textContent,state:s.dataset.state}:false})()',12000);
 const expectedGood=!['missing','incompatible'].includes(mode);add('helper-detection',expectedGood?status.state==='info'&&status.text===T('timffle_helper_installed',['1.2.0']):status.state==='error'&&status.text===T(mode==='incompatible'?'timffle_helper_incompatible':'timffle_helper_missing'),{status});
 await until(()=>countHelpers()===0);add('status-check-exits-helper',countHelpers()===0);

 // The notice that tells the visitor to install the helper: the settings page's button, the popup's notice and the install page.
 {
  const needsInstall=['missing','incompatible'].includes(mode);
  const wantStatus=T(mode==='incompatible'?'timffle_helper_incompatible':'timffle_helper_missing');
  const button=await chrome.eval(opts.sessionId,'(()=>{const b=document.querySelector("#socket-helper-install"),r=b.getBoundingClientRect();return {hidden:b.hidden,shown:getComputedStyle(b).display!=="none"&&r.width>0&&r.height>0,text:b.textContent}})()');
  add('options-install-button',button.hidden===!needsInstall&&button.shown===needsInstall&&button.text===T('timffle_helper_notice_button'),{button});
  const popup=await chrome.tab('chrome-extension://'+ID+'/popup.html');
  // Whether the notice is really on the page (drawn, with height), not only whether it lacks the "hidden" class; read once the page and its style sheets have loaded.
  const noticeJs='(()=>{const n=document.querySelector("#helper-notice");if(!n||document.readyState!=="complete")return false;const r=n.getBoundingClientRect();return getComputedStyle(n).display!=="none"&&r.height>0?{text:document.querySelector("#helper-notice-text").textContent,button:document.querySelector("#helper-notice-button").textContent,height:Math.round(r.height)}:false})()';
  if(needsInstall){
   const notice=await chrome.wait(popup.sessionId,noticeJs,12000);
   add('popup-notice',notice.text===T(mode==='incompatible'?'timffle_helper_notice_incompatible':'timffle_helper_notice_missing')&&notice.button===T('timffle_helper_notice_button'),{notice});
   const noticeShot=await chrome.send('Page.captureScreenshot',{format:'png'},popup.sessionId);await fs.writeFile(path.join(output,'popup-notice.png'),Buffer.from(noticeShot.data,'base64'));
   // Only a real click counts; it opens the install page in a tab of its own.
   await chrome.eval(popup.sessionId,'document.querySelector("#helper-notice-button").click()');
   await delay(600);
   const targetsAfterScriptClick=(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html');
   add('popup-script-click-ignored',targetsAfterScriptClick.length===0,{targetsAfterScriptClick});
   await realClick(popup.sessionId,'#helper-notice-button');
   const opened=await until(async()=>(await chrome.send('Target.getTargets')).targetInfos.find(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html'));
   add('popup-button-opens-install-page',!!opened,{opened});
   if(opened)await chrome.send('Target.closeTarget',{targetId:opened.targetId});
  }else{
   await delay(2500);
   add('popup-no-notice-when-helper-works',!(await chrome.eval(popup.sessionId,noticeJs)));
  }
  // After the button was used the popup has closed itself, as the real popup does.
  await chrome.send('Target.closeTarget',{targetId:popup.targetId}).catch(()=>{});
  if(needsInstall){
   const installPages=async()=>(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html');
   await chrome.eval(opts.sessionId,'document.querySelector("#socket-helper-install").click()');await delay(600);
   add('options-script-click-ignored',(await installPages()).length===0);
   await realClick(opts.sessionId,'#socket-helper-install');
   const opened=await until(async()=>(await installPages())[0]);
   add('options-button-opens-install-page',!!opened);
   if(opened)await chrome.send('Target.closeTarget',{targetId:opened.targetId});
  }
  const page=await chrome.tab('chrome-extension://'+ID+'/helper.html');
  const pageStatusJs='(()=>{const s=document.querySelector("#helper-page-status");return s&&s.dataset.state&&s.textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'?{text:s.textContent,state:s.dataset.state}:false})()';
  const shown=await chrome.wait(page.sessionId,pageStatusJs,12000);
  add('install-page-status',needsInstall?shown.state==='error'&&shown.text===wantStatus:shown.state==='info'&&shown.text===T('timffle_helper_installed',['1.2.0']),{shown});
  const content=await chrome.eval(page.sessionId,'({title:document.title,heading:document.querySelector("h1").textContent,steps:[...document.querySelectorAll(".helper-steps li")].map(li=>({text:li.textContent,code:li.querySelector("code")?.textContent,dir:li.querySelector("code")?.dir})),after:document.querySelector(".helper-steps").nextElementSibling.textContent,link:(()=>{const a=document.querySelector("a[href*=releases]");return {href:a.href,text:a.textContent,target:a.target,rel:a.rel}})(),dir:document.documentElement.dir,lang:document.documentElement.lang})');
  const stripTags=k=>T(k).replace(/<\/?\d>/g,'');
  add('install-page-texts',content.title===T('timffle_helper_page_title')&&content.heading===T('timffle_helper_page_heading')
   &&['windows','macos','linux'].every((system,i)=>content.steps[i]?.text===stripTags('timffle_helper_step_'+system))
   &&content.steps.map(x=>x.code).join('|')==='install-windows.cmd|install-macos.command|sh install-linux.sh'&&content.steps.every(x=>x.dir==='ltr')
   &&content.after===T('timffle_helper_step_after')
   &&content.link.href==='https://github.com/Im-Tim-mI/Timffle/releases/latest'&&content.link.target==='_blank'&&content.link.rel==='noopener noreferrer'&&content.link.text===T('timffle_helper_page_download').match(/<1>([^<]*)<\/1>/)[1],{content});
  await chrome.eval(page.sessionId,'document.querySelector("#helper-page-check").click()');
  const again=await chrome.wait(page.sessionId,pageStatusJs,12000);
  add('install-page-check-again',JSON.stringify(again)===JSON.stringify(shown),{again});
  // Coming back to the tab (after running the installer) looks again by itself: the line goes through "checking" and ends where it was.
  await chrome.eval(page.sessionId,'(()=>{const s=document.querySelector("#helper-page-status");window.__seen=[s.textContent];new MutationObserver(()=>window.__seen.push(s.textContent)).observe(s,{childList:true,characterData:true,subtree:true});document.dispatchEvent(new Event("visibilitychange"))})()');
  const back=await chrome.wait(page.sessionId,'(()=>{const s=document.querySelector("#helper-page-status");return window.__seen.includes('+JSON.stringify(T('timffle_helper_checking'))+')&&s.textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'?{seen:window.__seen,last:s.textContent}:false})()',12000);
  add('install-page-looks-again-when-the-tab-comes-back',back.last===shown.text,{back});
  const pageShot=await chrome.send('Page.captureScreenshot',{format:'png'},page.sessionId);await fs.writeFile(path.join(output,'helper-page.png'),Buffer.from(pageShot.data,'base64'));
  await chrome.send('Target.closeTarget',{targetId:page.targetId});
 }
 const shot=await chrome.send('Page.captureScreenshot',{format:'png'},opts.sessionId);await fs.writeFile(path.join(output,'options.png'),Buffer.from(shot.data,'base64'));
 const setOrigins=async(origins)=>{await chrome.eval(opts.sessionId,'(()=>{document.querySelector("#socket-proxy-origins").value='+JSON.stringify(origins.join('\n'))+';document.querySelector("#socket-proxy-form").requestSubmit();})()');await chrome.wait(opts.sessionId,'(async()=>{const x=(await chrome.storage.local.get("socketProxySettings")).socketProxySettings;return x&&JSON.stringify(x.allowedOrigins)==='+JSON.stringify(JSON.stringify(origins))+'})()');};
 await setOrigins([origin,'https://mole.61.com.tw','http://mole.61.com.tw']);
 await chrome.eval(opts.sessionId,'chrome.storage.sync.set({autostart:true,autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas"})');
 const settings=await chrome.eval(opts.sessionId,'(async()=>({local:(await chrome.storage.local.get("socketProxySettings")).socketProxySettings,synced:(await chrome.storage.sync.get("socketProxySettings")).socketProxySettings??null}))()');
 add('settings-local-not-synced',settings.local.mode==='helper'&&settings.synced===null&&settings.local.proxyUrl==='');
 const fixture=async(name,{host='127.0.0.1',port=small.port,size=6,timeout=1800,cancel=-1,site=origin}={},check)=>{
  const p=await chrome.tab(site+'/?'+new URLSearchParams({host,port,size,timeout,cancel}));const result=await chrome.wait(p.sessionId,'window.__probe',15000);add(name,check(result),{result});await chrome.send('Target.closeTarget',{targetId:p.targetId});return result;};
 const good=r=>r.status==='ok'&&r.badBytes===0&&r.events.filter(x=>x==='connect').length===1&&r.events.filter(x=>x==='close').length===1&&r.events.includes('after:false');
 const noConnect=r=>r.status==='ioError'&&r.connectMs===-1&&!r.events.includes('connect')&&!r.connected;
 if(mode==='localtest'){
  await fixture('dynamic-port-one',{},good);await fixture('dynamic-port-two',{port:second.port},good);await fixture('dns-hostname',{host:'localhost'},good);
  if(ipv6)await fixture('ipv6-placeholder',{host:'[::1]',port:ipv6.port},good);
  await fixture('large-ordered-binary-256k',{port:large.port,size:262144},r=>good(r)&&r.received===262144);
  await fixture('refused-never-connected',{port:refused},noConnect);
  await fixture('unapproved-origin',{site:'http://localhost:'+pagePort},noConnect);
  await fixture('local-close-no-remote-close-event',{port:held.port,cancel:100},r=>r.status==='cancelled'&&!r.connected&&r.events.filter(x=>x==='local-close').length===1&&!r.events.includes('close'));
  const bare=await chrome.tab(origin+'/?bare');await chrome.wait(bare.sessionId,'window.RufflePlayer?.config?.socketProxy?.length');
  const normal=await chrome.eval(bare.sessionId,'new Promise((resolve,reject)=>{const s=new WebSocket('+JSON.stringify('ws://127.0.0.1:'+wsPort)+');s.onopen=()=>s.send("native-unmodified");s.onmessage=e=>{const native=s instanceof WebSocket;s.close();resolve({value:e.data,native});};s.onerror=()=>reject(new Error("ws"));})');
  add('ordinary-websocket-unchanged',normal.value==='native-unmodified'&&normal.native);
  const base='ws://timffle-socket.invalid/connect?host=127.0.0.1&port=';
  const beforeBytes=drain.stat.bytes;
  const drained=await chrome.eval(bare.sessionId,'new Promise(resolve=>{const s=new WebSocket('+JSON.stringify(base+drain.port)+');s.onopen=()=>{s.send(new Uint8Array(262144));const queued=s.bufferedAmount;s.close();s.onclose=()=>resolve({queued,final:s.bufferedAmount});};s.onerror=()=>resolve({error:true});})');
  await until(()=>drain.stat.bytes-beforeBytes===262144);add('close-drains-queued-writes',drain.stat.bytes-beforeBytes===262144&&!drained.error&&drained.queued>0,{drained,bytes:drain.stat.bytes-beforeBytes});
  const flooded=await chrome.eval(bare.sessionId,'new Promise(resolve=>{const s=new WebSocket('+JSON.stringify(base+held.port)+');let errors=0;s.onerror=()=>errors++;s.onclose=()=>resolve({errors,state:s.readyState,buffered:s.bufferedAmount});s.onopen=()=>{try{s.send(new Uint8Array(2*1024*1024));}catch{};};})');
  add('send-queue-bounded',flooded.errors===1&&flooded.state===3&&flooded.buffered<=1048576,{flooded});
  const capped=await chrome.eval(bare.sessionId,'new Promise(resolve=>{window.__sockets=[];let open=0,error=0;for(let i=0;i<24;i++){const s=new WebSocket('+JSON.stringify(base+held.port)+');window.__sockets.push(s);s.onopen=()=>open++;s.onerror=()=>error++;}setTimeout(()=>resolve({open,error}),1500);})');
  add('native-process-cap',capped.open>0&&capped.open<=16&&capped.error>0&&countHelpers()<=16,{capped,processes:countHelpers()});
  await setOrigins(['https://mole.61.com.tw','http://mole.61.com.tw']);await until(()=>countHelpers()===0);add('settings-revocation-closes-sockets',countHelpers()===0);
  await setOrigins([origin,'https://mole.61.com.tw','http://mole.61.com.tw']);
  const nav=await chrome.tab(origin+'/?bare');await chrome.wait(nav.sessionId,'window.RufflePlayer?.config?.socketProxy?.length');await chrome.eval(nav.sessionId,'new Promise(resolve=>{window.__s=new WebSocket('+JSON.stringify(base+held.port)+');window.__s.onopen=()=>resolve(true);window.__s.onerror=()=>resolve(false);})');
  add('native-starts-on-demand',countHelpers()>0);await chrome.send('Page.navigate',{url:'about:blank'},nav.sessionId);await until(()=>countHelpers()===0);add('navigation-stops-native',countHelpers()===0);await chrome.send('Target.closeTarget',{targetId:bare.targetId});await chrome.send('Target.closeTarget',{targetId:nav.targetId});
 }else if(mode==='production'){
  const before=small.stat.connections;await fixture('production-private-address-blocked',{},noConnect);add('production-no-local-tcp',small.stat.connections===before);
 }else if(mode==='delayed'){
  await fixture('delayed-open-not-premature',{timeout:2000},r=>good(r)&&r.connectMs>=550);
  await fixture('timeout-before-open',{timeout:200},noConnect);
  const cancelPage=await chrome.tab(origin+'/?bare');await chrome.wait(cancelPage.sessionId,'window.RufflePlayer?.config?.socketProxy?.length');
  const cancelled=await chrome.eval(cancelPage.sessionId,'new Promise(resolve=>{const events=[];const s=new WebSocket("ws://timffle-socket.invalid/connect?host=127.0.0.1&port=1234");s.onopen=()=>events.push("open");s.onerror=()=>events.push("error");s.onclose=()=>events.push("close");setTimeout(()=>s.close(),100);setTimeout(()=>resolve({events,state:s.readyState}),900);})');
  add('cancel-before-open-stops-native',JSON.stringify(cancelled.events)==='["error","close"]'&&cancelled.state===3&&countHelpers()===0,{cancelled});await chrome.send('Target.closeTarget',{targetId:cancelPage.targetId});
 }else{
  const before=small.stat.connections;await fixture(mode+'-no-fake-connect',{},noConnect);add(mode+'-no-tcp',small.stat.connections===before);
  // The toolbar icon: a game that needed the helper and could not get it marks the tab it is in, until the page is left.
  const marked=()=>chrome.eval(opts.sessionId,'(async()=>{const out=[];for(const t of await chrome.tabs.query({})){const text=await chrome.action.getBadgeText({tabId:t.id});if(text)out.push({text,color:await chrome.action.getBadgeBackgroundColor({tabId:t.id})})}return out})()');
  const game=await chrome.tab(origin+'/?'+new URLSearchParams({host:'127.0.0.1',port:small.port,size:6,timeout:1800,cancel:-1}));
  await chrome.wait(game.sessionId,'window.__probe',15000);
  const needsInstall=['missing','incompatible'].includes(mode);
  const badge=needsInstall?await until(async()=>{const m=await marked();return m.length?m:false},5000):await marked();
  add(mode+'-badge-on-the-game-tab',needsInstall?badge.length===1&&badge[0].text==='!'&&JSON.stringify(badge[0].color)==='[217,48,37,255]':badge.length===0,{badge});
  if(needsInstall){
   await chrome.send('Page.navigate',{url:'about:blank'},game.sessionId);
   const cleared=await until(async()=>(await marked()).length===0,5000);
   add(mode+'-badge-ends-with-the-page',!!cleared);
  }
  await chrome.send('Target.closeTarget',{targetId:game.targetId});
 }
 const realWs=chrome.events.filter(e=>e.method==='Network.webSocketCreated').map(e=>e.params.url);
 if(mode==='localtest')add('network-observer-saw-native-websocket',realWs.some(s=>s==='ws://127.0.0.1:'+wsPort+'/'));
 add('no-network-websocket-to-helper-address',!realWs.some(s=>s.includes('timffle-socket.invalid')));
 await until(()=>countHelpers()===0);add('no-native-process-left',countHelpers()===0,{count:countHelpers()});
 if(realHelper){
  const out=execFileSync(path.resolve(helper),['--uninstall'],{env:installEnv,encoding:'utf8'});
  await chrome.send('Page.reload',{},opts.sessionId);
  const after=await chrome.wait(opts.sessionId,'(()=>{const s=document.querySelector("#socket-helper-status");return s&&s.dataset.state&&s.dataset.state!=="checking"&&s.textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'?{text:s.textContent,state:s.dataset.state}:false})()',12000);
  let left=[];try{left=await fs.readdir(path.join(work,'data','timffle-socket-helper'));}catch{}
  add('uninstall-unregisters-from-chrome',out.includes('removed')&&after.state==='error'&&left.length===0,{after,left});
 }
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({browser:version,mode,extensionVersion:manifest.version,results},null,2));
 console.log('RESULTS '+output);
}catch(e){results.push({name:'harness-error',pass:false,error:e.message});await fs.writeFile(path.join(output,'results.json'),JSON.stringify({mode,results},null,2));console.error(e.stack);process.exitCode=1;}
finally{
 if(chrome)await chrome.close();for(const socket of tcpSockets)socket.destroy();for(const client of wss.clients)client.terminate();for(const fn of cleanup.reverse())await fn();
 if(originalPrivate===undefined)delete process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;else process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE=originalPrivate;
 await delay(300);await fs.rm(path.join(output,'chrome'),{recursive:true,force:true});
}
