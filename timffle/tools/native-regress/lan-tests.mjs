// A website on the local network may connect back to its own address (helper 1.4.0), end to end: headless Chrome with
// the extension and the PRODUCTION helper (built without the localtest tag), web and echo servers on this machine only.
// It never touches a real game server or the internet.
//   node lan-tests.mjs <unpacked extension dir> <production helper binary> [<helper older than 1.4.0>]
// The pages come from a private IPv4 address of this machine (192.168/16 first, then 172.16/12, then 10/8); without one
// the run is skipped. TEST_LOCALE as in ask-tests.mjs; LAN_ONLY=A,C,H runs only those scenarios; LAN_OUT=<dir> is where
// the results go (default: a new browser-lan-<time> folder next to this file, which git ignores).
//   A  an always-allowed website on a LAN address reaches its own address (Flash, and the page's socket)
//   B  ... but not this computer (loopback, by address and by name)
//   C  ... nor another LAN address, a link-local or a shared (CGNAT) one: "blocked" at once, before any dial
//   D  the same server opened by a name gets no exception
//   E  a lanHost that the page adds to its own bridge messages is never honoured
//   F  the question for an unlisted LAN website names its address (the old text for a name or this computer)
//   G  with an older helper the site's own address sends the visitor to the installer; every other answer stays
//   H  the helper binary itself, spoken to as Chrome does: no relaxation without lanHost, the exception with it
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {readFileSync} from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';
import {execFileSync,spawn} from 'node:child_process';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {loadTexts,norm} from './catalog.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const [extensionDir,helper,oldHelper]=process.argv.slice(2);
assert.ok(extensionDir&&helper,'Usage: node lan-tests.mjs extension-dir production-helper-binary [old-helper-binary]');
const manifest=JSON.parse(await fs.readFile(path.join(extensionDir,'manifest.json'),'utf8'));
const locale=process.env.TEST_LOCALE||'en',T=loadTexts(extensionDir,locale);
const digest=crypto.createHash('sha256').update(Buffer.from(manifest.key,'base64')).digest('hex').slice(0,32);
const ID=[...digest].map(c=>'abcdefghijklmnop'[parseInt(c,16)]).join('');
assert.equal(ID,'eandddnbchclalbjkhfelhjhpijifcog');
// The first helper that knows the exception; an older one keeps answering "blocked" for the site's own address.
const LAN_HELPER='1.4.0';
const atLeast=(version,min)=>{const a=String(version).split('.').map(Number),b=min.split('.').map(Number);if(a.length!==3||a.some(n=>!Number.isInteger(n)))return false;for(let i=0;i<3;i++)if(a[i]!==b[i])return a[i]>b[i];return true;};

// This machine's addresses on a private network, the most LAN-like first; the extension knows only these three ranges.
const RANGES=[[0xc0a80000,16],[0xac100000,12],[0x0a000000,8]];
const rangeOf=a=>{const n=a.split('.').reduce((x,o)=>x*256+Number(o),0);return RANGES.findIndex(([base,bits])=>n>>>(32-bits)===base>>>(32-bits));};
const privates=[...new Set(Object.values(os.networkInterfaces()).flat().filter(i=>i&&i.family==='IPv4'&&!i.internal&&rangeOf(i.address)>=0).map(i=>i.address))].sort((a,b)=>rangeOf(a)-rangeOf(b));
if(!privates.length){console.log('SKIPPED: this machine has no private IPv4 address (192.168/16, 172.16/12 or 10/8) to serve the pages from');process.exit(0);}
// `other` is a second private address of this machine (e.g. a container bridge): a live echo server there shows that nothing
// connects. Without one, an address that need not exist stands in (the policy refuses before any dial).
const priv=privates[0],other=privates.find(a=>a!==priv);
const NOWHERE=['10.254.254.254','172.31.254.254'].find(a=>a!==priv);
// With no IPv6 route beyond the machine's own links, a dial to a global or ULA IPv6 address fails at once ("unreachable")
// and no packet leaves the machine: that answer shows that the helper accepted the address and dialed. Elsewhere those checks are skipped.
const ipv6Offline=(()=>{try{return readFileSync('/proc/net/ipv6_route','utf8').trim().split('\n').map(l=>l.trim().split(/\s+/)).every(([dest,,,,,,,,flags,dev])=>dev==='lo'||(parseInt(flags,16)&0x200)!==0||/^fe[89ab]|^ff/.test(dest));}catch{return false;}})();
const PUBLIC6='2606:4700:4700::1111',ULA6='fd00::1';
const NAME='timffle-lan.test';

const output=process.env.LAN_OUT?path.resolve(process.env.LAN_OUT):path.join(root,'browser-lan-'+Date.now());
await fs.mkdir(output,{recursive:true,mode:0o700});
const results=[],cleanup=[],tcpSockets=new Set();let chrome,opts;
// Every check is recorded and the run goes on (exit code 1 if one failed): one wrong answer must not hide the others.
const add=(name,pass,detail={})=>{const r={name,pass:!!pass,...detail};results.push(r);console.log(JSON.stringify(r));};
const only=(process.env.LAN_ONLY||'').split(',').filter(Boolean);
const runs=(letter)=>only.length===0||only.includes(letter);
// The localtest build reads this; the production build must not, so it is never set for Chrome (H sets it on purpose).
const originalPrivate=process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;delete process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;

const listen=async(server,host)=>{await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,host,resolve)});cleanup.push(()=>new Promise(r=>server.close(r)));return server.address().port;};
// Echo servers end the connection after the 6 bytes that the probe SWF and the page sockets send.
const SIZE=6,PAYLOAD='lan-ok';
const echo=async(host)=>{const stat={connections:0};const port=await listen(net.createServer(s=>{stat.connections++;tcpSockets.add(s);s.on('error',()=>{});s.on('close',()=>tcpSockets.delete(s));let n=0;s.on('data',d=>{n+=d.length;s.write(d);if(n>=SIZE)s.end();});}),host);return {host,port,stat};};
const lanEcho=await echo(priv),loopEcho=await echo('127.0.0.1'),otherEcho=other?await echo(other):null;
const elsewhere=otherEcho??{host:NOWHERE,port:9,stat:{connections:0}};
const swf=await fs.readFile(path.join(root,'NativeProbe.swf'));
// The Host headers the page servers saw: the name of scenario D must reach the very server that the address reaches.
const hostsSeen=[];
const pages=(req,res)=>{hostsSeen.push(req.headers.host);const u=new URL(req.url,'http://x');
 if(u.pathname==='/NativeProbe.swf'){res.setHeader('Content-Type','application/x-shockwave-flash');res.end(swf);return;}
 const vars=new URLSearchParams({host:u.searchParams.get('host')??priv,port:u.searchParams.get('port')??String(lanEcho.port),timeout:u.searchParams.get('timeout')??'20000',size:String(SIZE),cancel:'-1'}).toString();
 res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><title>LAN regression</title><script>window.__probe=null;window.nativeProbeDone=s=>window.__probe=JSON.parse(s);window.RufflePlayer={config:{autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas",logLevel:"error"}};</script>'
  +(u.searchParams.has('bare')?'<p>no flash here</p>':'<embed src="/NativeProbe.swf" type="application/x-shockwave-flash" width="400" height="300" allowScriptAccess="always" flashvars="'+vars.replaceAll('&','&amp;')+'">'));};
// Two websites on the LAN address (one always allowed, one nobody has decided about), the same two by a name that the
// test browser maps to that address, and one on this computer.
const listedPort=await listen(http.createServer(pages),priv),askedPort=await listen(http.createServer(pages),priv),loopPort=await listen(http.createServer(pages),'127.0.0.1');
const lanOrigin='http://'+priv+':'+listedPort,nameOrigin='http://'+NAME+':'+listedPort;
const askOrigin='http://'+priv+':'+askedPort,askNameOrigin='http://'+NAME+':'+askedPort,loopOrigin='http://127.0.0.1:'+loopPort;
const until=async(fn,ms=8000)=>{const end=Date.now()+ms;while(Date.now()<end){const v=await fn();if(v)return v;await delay(80);}return false;};

// Talks to a helper binary the way Chrome does: the extension's origin as its argument, 4-byte little-endian length + JSON.
const native=(binary,env)=>{
 const p=spawn(binary,['chrome-extension://'+ID+'/'],{env,stdio:['pipe','pipe','ignore']});
 let buf=Buffer.alloc(0),ended=false;const queue=[],waiting=[];
 p.stdout.on('data',d=>{buf=Buffer.concat([buf,d]);while(buf.length>=4&&buf.length>=4+buf.readUInt32LE(0)){const n=buf.readUInt32LE(0),m=JSON.parse(buf.subarray(4,4+n));buf=buf.subarray(4+n);const w=waiting.shift();w?w(m):queue.push(m);}});
 p.stdout.on('end',()=>{ended=true;while(waiting.length)waiting.shift()(null);});
 p.stdin.on('error',()=>{});
 return {
  send(m){const b=Buffer.from(JSON.stringify(m)),h=Buffer.alloc(4);h.writeUInt32LE(b.length);p.stdin.write(Buffer.concat([h,b]));},
  next(ms=8000){if(queue.length)return Promise.resolve(queue.shift());if(ended)return Promise.resolve(null);return new Promise(resolve=>{const f=m=>{clearTimeout(t);resolve(m);};const t=setTimeout(()=>{const i=waiting.indexOf(f);if(i>=0)waiting.splice(i,1);resolve('timeout');},ms);waiting.push(f);});},
  end:()=>new Promise(r=>{p.stdin.end();if(p.exitCode!==null||p.signalCode!==null)return r();const t=setTimeout(()=>{p.kill();r();},3000);p.once('exit',()=>{clearTimeout(t);r();});}),
 };
};
// hello, then one open; the answers up to the end of that socket in short form ("error:blocked", "closed"...). An opened
// socket sends 6 bytes, acknowledges the echo and is closed by the echo server.
const openOnce=async(binary,open,env=process.env)=>{
 const h=native(binary,env),replies=[];
 try{
  h.send({type:'hello'});const hello=await h.next();
  h.send({type:'open',...open});
  for(;;){
   const m=await h.next();
   if(m===null||m==='timeout'){replies.push(String(m));break;}
   replies.push(m.type==='error'?'error:'+m.code:m.type==='data'?'data:'+Buffer.from(m.data,'base64').toString():m.type);
   if(m.type==='closed')break;
   if(m.type==='opened')h.send({type:'send',data:Buffer.from(PAYLOAD).toString('base64')});
   if(m.type==='data')h.send({type:'ack'});
  }
  return {hello,replies};
 }finally{await h.end();}
};
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
const BLOCKED=['error:blocked','closed'],ECHOED=['opened','sent','data:'+PAYLOAD,'closed'];

// The helper is installed by its own --install into a disposable HOME, as in the other lanes.
const work=path.join(output,'chrome');
const installEnv={...process.env,HOME:path.join(work,'home'),XDG_DATA_HOME:path.join(work,'data'),XDG_CONFIG_HOME:path.join(work,'config')};delete installEnv.CHROME_CONFIG_HOME;
const userDataDir=path.join(work,'config','google-chrome');
const installedHelper=path.join(work,'data','timffle-socket-helper','timffle-socket-helper');
const countHelpers=()=>{try{return execFileSync('pgrep',['-f',installedHelper+' chrome-extension://'+ID+'/'],{encoding:'utf8'}).trim().split(/\s+/).filter(Boolean).length;}catch{return 0;}};

const targets=async()=>(await chrome.send('Target.getTargets')).targetInfos;
const promptWindows=async()=>(await targets()).filter(t=>t.type==='page'&&t.url.startsWith('chrome-extension://'+ID+'/prompt.html'));
const attach=async(targetId,methods=['Page.enable','Runtime.enable'])=>{const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});for(const m of methods)await chrome.send(m,{},sessionId);return sessionId;};
const close=(targetId)=>chrome.send('Target.closeTarget',{targetId}).catch(()=>{});
// The tabs a scenario opened, closed when it ends.
const tabs=[];
const tab=async(url,keep=false)=>{const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});const sessionId=await attach(targetId);await chrome.send('Page.navigate',{url},sessionId);const t={targetId,sessionId};if(!keep)tabs.push(t);return t;};
const closeTabs=async()=>{for(const t of tabs.splice(0))await close(t.targetId);};
// A real (trusted) click on the middle of an element: the extension's windows ignore script-made clicks.
const click=async(sessionId,selector)=>{
 const r=await chrome.eval(sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');if(!e)return null;e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2,w:b.width,h:b.height}})()');
 assert.ok(r&&r.w>0&&r.h>0,'no visible element '+selector);
 for(const type of ['mouseMoved','mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',buttons:type==='mousePressed'?1:0,clickCount:type==='mouseMoved'?0:1},sessionId);
};
const shot=async(sessionId,name)=>{const s=await chrome.send('Page.captureScreenshot',{format:'png'},sessionId).catch(()=>null);if(s)await fs.writeFile(path.join(output,name),Buffer.from(s.data,'base64'));};
const setSettings=(value)=>chrome.eval(opts.sessionId,'chrome.storage.local.set({socketProxySettings:'+JSON.stringify(value)+'})');
// The service worker is stopped when idle; talk to it only briefly (an attached debugger keeps it alive).
const withServiceWorker=async(fn)=>{
 await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"wake"}).catch(()=>{})');
 const t=await until(async()=>(await targets()).find(x=>x.type==='service_worker'&&x.url.includes(ID)));
 assert.ok(t,'no service worker');
 const sessionId=await attach(t.targetId,['Runtime.enable']);
 try{return await fn(sessionId);}finally{await chrome.send('Target.detachFromTarget',{sessionId}).catch(()=>{});}
};

// A page with the probe SWF, which opens a Flash socket to host:port as a game does.
const flashPage=(site,host,port,timeout=20000)=>tab(site+'/?'+new URLSearchParams({host,port,timeout}));
const probe=(t,ms=25000)=>chrome.wait(t.sessionId,'window.__probe',ms);
const good=r=>!!r&&r.status==='ok'&&r.badBytes===0&&r.events.filter(x=>x==='connect').length===1&&r.events.filter(x=>x==='close').length===1;
const noConnect=r=>!!r&&r.status==='ioError'&&r.connectMs===-1&&!r.events.includes('connect')&&!r.connected;
// A page without Flash on an always-allowed site: the extension's WebSocket stand-in is in place at once.
const barePage=async(site)=>{const t=await tab(site+'/?bare=1');await chrome.wait(t.sessionId,'window.RufflePlayer?.config?.socketProxy?.length>0',20000);return t;};
// A socket through the page's WebSocket stand-in (what Ruffle uses): the close reason is the bridge's error code ("blocked",
// "helper_incompatible"...), or "" after the echo server ended a connection that echoed the 6 bytes.
const viaPage=(t,host,port,ms=15000)=>chrome.eval(t.sessionId,'new Promise(resolve=>{const t0=performance.now(),events=[];let got="";const s=new WebSocket("ws://timffle-socket.invalid/connect?"+new URLSearchParams({host:'+JSON.stringify(host)+',port:'+JSON.stringify(String(port))+'}));s.binaryType="arraybuffer";s.onopen=()=>{events.push("open");s.send(new TextEncoder().encode('+JSON.stringify(PAYLOAD)+'))};s.onmessage=e=>{got+=new TextDecoder().decode(e.data)};s.onerror=()=>events.push("error");s.onclose=e=>resolve({events,got,code:e.code,reason:e.reason,clean:e.wasClean,ms:Math.round(performance.now()-t0)});setTimeout(()=>resolve({events,got,timeout:true}),'+ms+')})');
const echoed=r=>!!r&&r.events.join()==='open'&&r.got===PAYLOAD&&r.clean===true&&r.reason==='';
const blocked=r=>!!r&&r.reason==='blocked'&&!r.events.includes('open');
// Adds `lanHost` to the page's own bridge messages, the way the page-side WebSocket stand-in posts them (it runs in the
// page's world, so the page can change what it sends); records what was sent.
const forge=(t,lanHost)=>chrome.eval(t.sessionId,'(()=>{const post=MessagePort.prototype.postMessage;window.__forged=[];MessagePort.prototype.postMessage=function(m,transfer){if(m&&m.op==="open"){m={...m,lanHost:'+JSON.stringify(lanHost)+'};window.__forged.push(m);}return post.call(this,m,transfer)};return true})()');
const forged=(t)=>chrome.eval(t.sessionId,'window.__forged');
// The first-use question: the window, once its input guard has passed.
const question=async(ms=15000)=>{const t=await until(async()=>(await promptWindows())[0],ms);if(!t)return null;const sessionId=await attach(t.targetId);await chrome.wait(sessionId,'!document.getElementById("prompt").hidden',8000);await delay(900);return {...t,sessionId};};
const QUESTION_JS='({origin:document.getElementById("prompt-origin").textContent,what:document.querySelector("#prompt .what").textContent,warning:document.getElementById("prompt-warning").textContent,buttons:[...document.querySelectorAll("#prompt button[data-choice]")].map(b=>b.dataset.choice).join(),focus:document.activeElement?.id})';
// The "install the helper first" window, read once it shows its download button.
const NOTICE_JS='(()=>{const q=s=>document.querySelector(s),shown=e=>!!e&&!e.hidden&&getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;if(document.readyState!=="complete"||!shown(q("#helper"))||!shown(q("#helper-download")))return false;return {origin:q("#helper-origin").textContent,text:q("#helper-text").textContent,download:q("#helper-download").textContent,question:shown(q("#prompt"))}})()';
const text=(key,subs)=>{try{return T.plain(key,subs);}catch{return null;}};
const badges=()=>chrome.eval(opts.sessionId,'(async()=>{const out=[];for(const t of await chrome.tabs.query({})){const text=await chrome.action.getBadgeText({tabId:t.id});if(text)out.push({text,url:t.url})}return out})()');
const scenario=async(letter,fn)=>{if(!runs(letter))return;try{await fn();}catch(e){add(letter+'-harness-error',false,{error:e.message});console.error(e.stack);}finally{if(chrome)await closeTabs();}};

let browserVersion,helperHello;
try{
 // ---- H. the production helper itself, as Chrome speaks to it: protocol 2 and version 1.4.0 or newer; a private address
 // only with the lanHost of that very address; nothing relaxes the policy otherwise (not even the localtest switch).
 await scenario('H',async()=>{
  const own={host:priv,port:lanEcho.port};
  let c=lanEcho.stat.connections;
  const plain=await openOnce(helper,own);helperHello=plain.hello;
  add('helper-speaks-protocol-2-and-is-'+LAN_HELPER+'-or-newer',plain.hello?.type==='hello'&&plain.hello.protocol===2&&atLeast(plain.hello.version,LAN_HELPER),{hello:plain.hello});
  add('helper-without-lanhost-refuses-a-private-address',same(plain.replies,BLOCKED)&&lanEcho.stat.connections===c,{replies:plain.replies});
  const switched=await openOnce(helper,own,{...process.env,TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE:'1'});
  add('production-helper-ignores-the-localtest-switch',same(switched.replies,BLOCKED)&&lanEcho.stat.connections===c,{replies:switched.replies});
  const mine=await openOnce(helper,{...own,lanHost:priv});
  add('helper-with-lanhost-reaches-that-address',same(mine.replies,ECHOED)&&lanEcho.stat.connections===c+1,{replies:mine.replies});
  c=lanEcho.stat.connections;
  for(const [label,host,target] of [['another-lan-address',elsewhere.host,elsewhere],['this-computer','127.0.0.1',loopEcho],['this-computer-by-name','localhost',loopEcho]]){
   const before=target.stat.connections,r=await openOnce(helper,{host,port:target.port,lanHost:priv});
   add('helper-with-lanhost-still-refuses-'+label,same(r.replies,BLOCKED)&&target.stat.connections===before,{host,replies:r.replies});
  }
  // A lanHost that is not one private LAN address is refused as a whole (the socket ends), not taken as "no lanHost".
  for(const [label,lanHost] of [['loopback','127.0.0.1'],['public','8.8.8.8'],['link-local','169.254.1.1'],['cgnat','100.64.0.1'],['multicast','224.0.0.1'],['v4-mapped','::ffff:'+priv],['brackets','['+ULA6+']'],['zone',ULA6+'%2'],['port',priv+':80'],['leading-zero',priv.replace(/\.(\d+)$/,'.0$1')],['name','localhost'],['url','http://'+priv+'/']]){
   const r=await openOnce(helper,{...own,lanHost});
   add('helper-refuses-lanhost-'+label,same(r.replies,['error:invalid','closed'])&&lanEcho.stat.connections===c,{lanHost,replies:r.replies});
  }
  if(ipv6Offline){
   // No IPv6 route here: "unreachable" means the helper dialed, "blocked" that the policy refused.
   const ula=await openOnce(helper,{host:ULA6,port:9,lanHost:ULA6});
   add('helper-with-an-ipv6-ula-lanhost-dials-that-address',same(ula.replies,['error:unreachable','closed']),{replies:ula.replies});
   const ulaOther=await openOnce(helper,{host:'fd00::2',port:9,lanHost:ULA6});
   add('helper-with-an-ipv6-ula-lanhost-refuses-another-ula-address',same(ulaOther.replies,BLOCKED),{replies:ulaOther.replies});
   const pub=await openOnce(helper,{host:PUBLIC6,port:9,lanHost:priv});
   add('helper-with-lanhost-still-dials-public-addresses',same(pub.replies,['error:unreachable','closed']),{replies:pub.replies});
  }else console.log(JSON.stringify({info:'this machine has IPv6 routes: the IPv6 dial checks are skipped (they would send packets)'}));
  if(oldHelper){
   const old=await openOnce(oldHelper,{...own,lanHost:priv});
   add('old-helper-ignores-lanhost-and-keeps-refusing',old.hello?.type==='hello'&&!atLeast(old.hello.version,LAN_HELPER)&&same(old.replies,BLOCKED)&&lanEcho.stat.connections===c,{hello:old.hello,replies:old.replies});
  }
 });

 if(['A','B','C','D','E','F','G'].some(runs)){
  await fs.mkdir(installEnv.HOME,{recursive:true,mode:0o700});
  const out=execFileSync(path.resolve(helper),['--install'],{env:installEnv,encoding:'utf8'});
  const written=JSON.parse(await fs.readFile(path.join(userDataDir,'NativeMessagingHosts','timffle_socket_helper.json'),'utf8'));
  add('helper-installed',out.includes('installed')&&written.path===installedHelper,{written});
  chrome=new Chrome(work,{recordEvents:false,fontConfig:process.env.TEST_FONTCONFIG||undefined,userDataDir,locale,args:['--host-resolver-rules=MAP '+NAME+' '+priv]});
  browserVersion=(await chrome.send('Browser.getVersion')).product;
  const loaded=await chrome.send('Extensions.loadUnpacked',{path:path.resolve(extensionDir)});add('stable-extension-id',loaded.id===ID,{id:loaded.id});
  opts=await tab('chrome-extension://'+ID+'/options.html',true);
  await chrome.wait(opts.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status");return s&&s.dataset.state})()');
  await chrome.eval(opts.sessionId,'chrome.storage.sync.set({autostart:true,autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas"})');
  // The LAN website and the same server by a name are always allowed; the "asked" sites are not listed at all.
  await setSettings({enabled:true,mode:'helper',proxyUrl:'',allowedOrigins:[lanOrigin,nameOrigin,...['mole','seer','hua','ddt'].flatMap(h=>['https://'+h+'.61.com.tw','http://'+h+'.61.com.tw'])],proxyOrigins:[],deniedOrigins:[],defaultsVersion:2});
  // Pages loaded before the extension has registered its page-world scripts never get Ruffle; wait for the registration.
  add('page-world-scripts-registered',!!await until(async()=>(await withServiceWorker(sw=>chrome.eval(sw,'chrome.scripting.getRegisteredContentScripts().then(r=>r.map(x=>x.id).sort().join())'))).includes('ruffle'),20000));
 }

 // ---- A. the LAN website, always allowed, reaches its own address: the game's Flash socket and the page's socket echo.
 await scenario('A',async()=>{
  const c=lanEcho.stat.connections;
  const game=await flashPage(lanOrigin,priv,lanEcho.port);
  const r=await probe(game);
  add('lan-website-flash-socket-reaches-its-own-address',good(r)&&lanEcho.stat.connections===c+1,{r,connections:lanEcho.stat.connections-c});
  const page=await barePage(lanOrigin);
  const s=await viaPage(page,priv,lanEcho.port);
  add('lan-website-socket-echoes-through-its-own-address',echoed(s)&&lanEcho.stat.connections===c+2,{s});
  if(ipv6Offline){
   // Public addresses stay reachable alongside the exception ("unreachable": the helper dialed; there is no route here).
   const p=await viaPage(page,PUBLIC6,9);
   add('lan-website-still-dials-public-addresses',p.reason==='unreachable',{p});
  }
 });

 // ---- B. ... but not this computer: loopback is refused by address and by name, and nothing connects.
 await scenario('B',async()=>{
  const page=await barePage(lanOrigin);
  for(const host of ['127.0.0.1','localhost']){
   const c=loopEcho.stat.connections,r=await viaPage(page,host,loopEcho.port);
   add('lan-website-cannot-reach-this-computer-'+(host==='localhost'?'by-name':'by-address'),blocked(r)&&loopEcho.stat.connections===c,{host,r});
  }
 });

 // ---- C. ... nor another address of the LAN (a live echo server on another private address of this machine when it has
 // one), nor link-local (cloud metadata) or shared (CGNAT) addresses: refused at once, by the policy, before any dial.
 await scenario('C',async()=>{
  const page=await barePage(lanOrigin);
  const c=elsewhere.stat.connections,r=await viaPage(page,elsewhere.host,elsewhere.port);
  add('lan-website-cannot-reach-another-lan-address',blocked(r)&&elsewhere.stat.connections===c,{host:elsewhere.host,live:!!otherEcho,r});
  for(const [label,host] of [['an-address-that-need-not-exist',NOWHERE],['link-local','169.254.169.254'],['cgnat','100.64.0.1']]){
   const x=await viaPage(page,host,9);
   add('lan-website-refused-at-once-for-'+label,blocked(x)&&x.ms<8000,{host,x});
  }
 });

 // ---- D. the same server, always allowed but opened by a name that resolves to the LAN address: no exception for names.
 await scenario('D',async()=>{
  const c=lanEcho.stat.connections;
  const page=await barePage(nameOrigin);
  const where=await chrome.eval(page.sessionId,'location.origin');
  add('the-name-reaches-the-same-server',where===nameOrigin&&hostsSeen.includes(NAME+':'+listedPort),{where});
  const s=await viaPage(page,priv,lanEcho.port);
  add('website-opened-by-a-name-gets-no-exception',blocked(s)&&lanEcho.stat.connections===c,{s});
  const game=await flashPage(nameOrigin,priv,lanEcho.port,1800);
  const r=await probe(game);
  add('website-opened-by-a-name-flash-socket-does-not-connect',noConnect(r)&&lanEcho.stat.connections===c,{r});
 });

 // ---- E. the page cannot supply the exception: a lanHost added to the page's own bridge messages changes nothing.
 await scenario('E',async()=>{
  const lan=await barePage(lanOrigin);await forge(lan,elsewhere.host);
  let c=elsewhere.stat.connections;
  const r1=await viaPage(lan,elsewhere.host,elsewhere.port);
  add('lan-website-cannot-claim-another-lan-address',blocked(r1)&&elsewhere.stat.connections===c,{host:elsewhere.host,r1});
  // The claimed address changes nothing for the site's own address either.
  c=lanEcho.stat.connections;
  const r2=await viaPage(lan,priv,lanEcho.port);
  add('a-claimed-lanhost-changes-nothing-for-the-own-address',echoed(r2)&&lanEcho.stat.connections===c+1,{r2});
  // Had the page's field reached the helper, it would answer "invalid" (no lanHost may be this computer), not "blocked".
  const loop=await barePage(lanOrigin);await forge(loop,'127.0.0.1');
  c=loopEcho.stat.connections;
  const r3=await viaPage(loop,'127.0.0.1',loopEcho.port);
  add('lan-website-cannot-claim-this-computer',blocked(r3)&&loopEcho.stat.connections===c,{r3});
  const named=await barePage(nameOrigin);await forge(named,priv);
  c=lanEcho.stat.connections;
  const r4=await viaPage(named,priv,lanEcho.port);
  add('website-opened-by-a-name-cannot-claim-the-lan-address',blocked(r4)&&lanEcho.stat.connections===c,{r4});
  // Positive control: the claims were really sent with the page's open messages.
  const sent=[...await forged(lan),...await forged(loop),...await forged(named)];
  add('the-claims-were-sent-by-the-page',sent.length===4&&sent.every(m=>m.op==='open'&&typeof m.lanHost==='string'),{sent});
 });

 // ---- F. the question for an unlisted website on a LAN address names that address and what an allowed site can reach;
 // a website opened by a name, or one on this computer, gets the old text (and no exception once allowed).
 await scenario('F',async()=>{
  const ask=async(site,choice)=>{
   const c=lanEcho.stat.connections;
   const game=await flashPage(site,priv,lanEcho.port);
   const q=await question();
   if(!q)return {view:null,r:null,connections:lanEcho.stat.connections-c};
   const view=await chrome.eval(q.sessionId,QUESTION_JS);
   await shot(q.sessionId,'question-'+new URL(site).hostname.replace(/[^0-9a-z]+/gi,'-')+'.png');
   await click(q.sessionId,'#'+choice);
   const r=await probe(game).catch(()=>null);
   await until(async()=>(await promptWindows()).length===0,5000);
   return {view,r,connections:lanEcho.stat.connections-c};
  };
  const lanText=text('timffle_prompt_what_lan',[priv]),oldText=text('timffle_prompt_what');
  const lan=await ask(askOrigin,'allow-once');
  add('question-for-a-lan-website-names-its-address',!!lan.view&&lan.view.origin===askOrigin&&lanText!==null&&norm(lan.view.what)===lanText,{view:lan.view,expected:lanText});
  add('question-for-a-lan-website-keeps-the-warning-and-the-safe-default',!!lan.view&&norm(lan.view.warning)===text('timffle_prompt_warning')&&lan.view.buttons==='deny-once,allow-once,deny-always,allow-always'&&lan.view.focus==='deny-once',{view:lan.view});
  add('allowing-the-lan-website-connects-to-its-own-address',good(lan.r)&&lan.connections===1,{r:lan.r,connections:lan.connections});
  for(const [label,site] of [['a-website-opened-by-a-name',askNameOrigin],['this-computer',loopOrigin]]){
   const x=await ask(site,'allow-once');
   add('question-for-'+label+'-keeps-the-old-text',!!x.view&&x.view.origin===site&&norm(x.view.what)===oldText,{view:x.view,expected:oldText});
   add('allowing-'+label+'-gives-no-exception',noConnect(x.r)&&x.connections===0,{r:x.r,connections:x.connections});
  }
 });

 // ---- G. an older helper (it ignores lanHost and answers "blocked"): the LAN website's own address sends the visitor to the
 // installer (helper_incompatible, the install window, the badge); every other answer reaches the page as it was.
 await scenario('G',async()=>{
  if(!oldHelper){console.log(JSON.stringify({info:'no older helper given: G skipped'}));return;}
  await until(()=>countHelpers()===0,10000);
  const out=execFileSync(path.resolve(oldHelper),['--install'],{env:installEnv,encoding:'utf8'});
  const installed=execFileSync(installedHelper,['--version'],{encoding:'utf8'}).trim();
  add('old-helper-installed-instead',out.includes('installed')&&!atLeast(installed.split(' ').pop(),LAN_HELPER),{installed});
  const c=lanEcho.stat.connections;
  const page=await barePage(lanOrigin);
  const r=await viaPage(page,priv,lanEcho.port);
  add('old-helper-lan-website-is-told-to-update-the-helper',r.reason==='helper_incompatible'&&lanEcho.stat.connections===c,{r});
  const w=await until(async()=>(await promptWindows())[0],10000);
  const notice=w?await attach(w.targetId):null;
  const view=notice?await chrome.wait(notice,NOTICE_JS,12000).catch(()=>null):null;
  add('old-helper-install-window-opens-for-the-lan-website',!!view&&view.origin===lanOrigin&&view.text===T('timffle_helper_notice_incompatible')&&view.download===T('timffle_helper_notice_button')&&!view.question,{view});
  if(w){await shot(notice,'install-window.png');await close(w.targetId);}
  const marks=await badges();
  add('old-helper-badge-on-the-lan-website-tab',marks.length===1&&marks[0].text==='!'&&marks[0].url.startsWith(lanOrigin+'/'),{marks});
  // Other refusals reach the page as "blocked", as before: no update is asked for and no window opens.
  const r2=await viaPage(page,elsewhere.host,elsewhere.port);
  const named=await barePage(nameOrigin);
  const r3=await viaPage(named,priv,lanEcho.port);
  await delay(1500);
  add('old-helper-other-refusals-stay-blocked',blocked(r2)&&blocked(r3)&&lanEcho.stat.connections===c&&(await promptWindows()).length===0,{r2,r3});
  if(ipv6Offline){
   const p=await viaPage(page,PUBLIC6,9);
   add('old-helper-lan-website-still-dials-public-addresses',p.reason==='unreachable',{p});
  }else console.log(JSON.stringify({info:'this machine has IPv6 routes: the public-address check of G is skipped'}));
 });

 if(chrome){await until(()=>countHelpers()===0,10000);add('no-helper-process-left',countHelpers()===0,{count:countHelpers()});}
}catch(e){add('harness-error',false,{error:e.message});console.error(e.stack);}
finally{
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({browser:browserVersion,extensionVersion:manifest.version,helper:helperHello,lan:priv,other:other??null,ipv6Offline,locale,results},null,2));
 if(chrome)await chrome.close();for(const socket of tcpSockets)socket.destroy();for(const fn of cleanup.reverse())await fn();
 if(originalPrivate!==undefined)process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE=originalPrivate;
 // Chrome may still write into its profile for a moment after it was closed: remove again instead of failing the run.
 await delay(300);await fs.rm(work,{recursive:true,force:true,maxRetries:8,retryDelay:250});
 const failed=results.filter(r=>!r.pass);
 console.log((failed.length?'FAILED '+failed.length+' of ':'PASSED ')+results.length+' checks; RESULTS '+output);
 if(failed.length)process.exitCode=1;
}
