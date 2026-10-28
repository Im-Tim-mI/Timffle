import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import crypto from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {loadTexts} from './catalog.mjs';
import {startFakeGitHub} from './fake-github.mjs';
import {WebSocketServer} from '../../relay/vendor/ws/wrapper.mjs';

const root=path.dirname(new URL(import.meta.url).pathname);
const [extensionDir,helper,mode='localtest']=process.argv.slice(2);
assert.ok(extensionDir&&helper,'Usage: node browser-auto-tests.mjs extension-dir helper-binary mode');
const HELPER_VERSION='1.4.0';
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
// The run stops at the first failed check; KEEP_GOING=1 records every check and goes on (exit code 1 if one failed), e.g. to see
// everything that a build without some feature fails.
const keepGoing=!!process.env.KEEP_GOING;
const add=(name,pass,detail={})=>{const r={name,pass:!!pass,...detail};results.push(r);console.log(JSON.stringify(r));if(!keepGoing)assert.ok(pass,name);};
// A part of the run that goes on to the next one after an error when KEEP_GOING is set.
const part=async(name,fn)=>{try{await fn();}catch(e){if(!keepGoing)throw e;add(name+'-harness-error',false,{error:e.message});}};
const listen=async(server,host='127.0.0.1')=>{await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(0,host,resolve)});cleanup.push(()=>new Promise(r=>server.close(r)));return server.address().port;};
const echo=async(expected,host='127.0.0.1')=>{const stat={bytes:0,connections:0,closed:0};const port=await listen(net.createServer(s=>{stat.connections++;tcpSockets.add(s);s.on('error',()=>{});s.on('close',()=>{tcpSockets.delete(s);stat.closed++});let n=0;s.on('data',d=>{stat.bytes+=d.length;n+=d.length;s.write(d);if(expected&&n>=expected)s.end();});}),host);return {port,stat};};
const small=await echo(6),second=await echo(6),large=await echo(262144),held=await echo(0),drain=await echo(0);
let ipv6=null;try{ipv6=await echo(6,'::1');}catch{}
const unused=net.createServer();await new Promise(r=>unused.listen(0,'127.0.0.1',r));const refused=unused.address().port;await new Promise(r=>unused.close(r));
const swf=await fs.readFile(path.join(root,'NativeProbe.swf'));
// Page loads per `tag` (a parameter only the tests add): a reload of the page counts one more.
const loads=new Map();
const pages=(req,res)=>{const u=new URL(req.url,'http://localhost');if(u.pathname==='/NativeProbe.swf'){res.setHeader('Content-Type','application/x-shockwave-flash');res.end(swf);return;}
 const tag=u.searchParams.get('tag');if(tag!==null&&u.pathname==='/')loads.set(tag,(loads.get(tag)??0)+1);
 const vars=new URLSearchParams({host:u.searchParams.get('host')??'127.0.0.1',port:u.searchParams.get('port')??String(small.port),timeout:u.searchParams.get('timeout')??'1500',size:u.searchParams.get('size')??'6',cancel:u.searchParams.get('cancel')??'-1'}).toString();
 res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><title>Native bridge regression</title><script>window.__probe=null;window.nativeProbeDone=s=>window.__probe=JSON.parse(s);window.RufflePlayer={config:{autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas",logLevel:"error"}};</script>'+(u.searchParams.has('bare')?'':('<embed src="/NativeProbe.swf" type="application/x-shockwave-flash" width="400" height="300" allowScriptAccess="always" flashvars="'+vars.replaceAll('&','&amp;')+'">')));};
const web=http.createServer(pages);
const pagePort=await listen(web),origin='http://127.0.0.1:'+pagePort;
// The same pages as three more websites: one on the always-denied list, one nobody has decided about, one a game tab may go to.
const otherPort=await listen(http.createServer(pages));
const deniedOrigin='http://127.0.0.1:'+otherPort,askOrigin='http://localhost:'+pagePort,elsewhere='http://localhost:'+otherPort;
const wsHttp=http.createServer();const wss=new WebSocketServer({server:wsHttp});wss.on('connection',s=>s.on('message',(d,b)=>s.send(d,{binary:b})));const wsPort=await listen(wsHttp);cleanup.push(()=>new Promise(r=>wss.close(r)));
// The helper's installers are downloaded from GitHub; the test browser is sent to this stand-in instead (see fake-github.mjs).
const github=await startFakeGitHub(path.join(output,'tls'));cleanup.push(()=>github.close());
const downloads=path.join(output,'downloads');await fs.mkdir(downloads,{recursive:true});
const realClick=async(sessionId,selector)=>{const r=await chrome.eval(sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()');for(const type of ['mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',clickCount:1},sessionId);};
const until=async(fn,ms=5000)=>{const end=Date.now()+ms;while(Date.now()<end){const v=await fn();if(v)return v;await delay(80);}return false;};
// How long a download (or the error page of a failed one) may take: Chrome needed more than 8 s to finish a 48-byte file on a busy machine. The wait ends as soon as the file is there.
const DOWNLOAD_WAIT_MS=30000;
// Real helpers are installed by their own --install into a disposable HOME,
// and Chrome uses that HOME's default Google Chrome user data directory.
const work=path.join(output,'chrome');
const realHelper=['localtest','production'].includes(mode);
const installEnv={...process.env,HOME:path.join(work,'home'),XDG_DATA_HOME:path.join(work,'data'),XDG_CONFIG_HOME:path.join(work,'config')};delete installEnv.CHROME_CONFIG_HOME;
const installedHelper=path.join(work,'data','timffle-socket-helper','timffle-socket-helper');
const userDataDir=realHelper?path.join(work,'config','google-chrome'):path.join(work,'profile');
const runningHelper=realHelper?installedHelper:path.resolve(helper);
// Installing the helper while the browser runs (the modes with a stand-in helper): Chrome reads the native messaging host's
// manifest again whenever it starts the helper, so writing it is what the installer does. The working stand-in is the mock
// host under a name of this run's own, so that its processes can be counted.
const hostManifest=path.join(userDataDir,'NativeMessagingHosts','timffle_socket_helper.json');
const workingMode='installed-'+process.pid,workingHelper=path.join(output,'working-helper.sh');
const registerHost=async(binary)=>{await fs.mkdir(path.dirname(hostManifest),{recursive:true});await fs.writeFile(hostManifest,JSON.stringify({name:'timffle_socket_helper',description:'Isolated test host',path:binary,type:'stdio',allowed_origins:['chrome-extension://'+ID+'/']}));};
const installHelper=async()=>{await fs.writeFile(workingHelper,"#!/bin/sh\nexec node '"+path.join(root,'mock-host.mjs')+"' "+workingMode+' "$@"\n',{mode:0o755});await registerHost(workingHelper);};
const removeHelper=async()=>{if(mode==='missing')await fs.rm(hostManifest,{force:true});else await registerHost(path.resolve(helper));};
const countOf=(prefix)=>{try{return execFileSync('pgrep',['-f',prefix+' chrome-extension://'+ID+'/'],{encoding:'utf8'}).trim().split(/\s+/).filter(Boolean).length;}catch{return 0;}};
const countHelpers=()=>countOf(['delayed','incompatible'].includes(mode)?'mock-host.mjs '+mode:runningHelper)+countOf('mock-host.mjs '+workingMode);
// Filled in below, where the systems and the downloads are known; used by the game-tab part at the end.
let noticeApi;
try{
 if(realHelper){
  await fs.mkdir(installEnv.HOME,{recursive:true,mode:0o700});
  const out=execFileSync(path.resolve(helper),['--install'],{env:installEnv,encoding:'utf8'});
  const written=JSON.parse(await fs.readFile(path.join(userDataDir,'NativeMessagingHosts','timffle_socket_helper.json'),'utf8'));
  add('installer-registers-for-chrome',out.includes('installed')&&written.path===installedHelper&&JSON.stringify(written.allowed_origins)===JSON.stringify(['chrome-extension://'+ID+'/']),{written});
 }else if(mode!=='missing')await registerHost(path.resolve(helper));
 chrome=new Chrome(work,{recordEvents:true,fontConfig:process.env.TEST_FONTCONFIG||undefined,userDataDir,locale,args:github.args});
 chrome.tab=async(url)=>{const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});for(const method of ['Page.enable','Runtime.enable','Network.enable'])await chrome.send(method,{},sessionId);await chrome.send('Page.navigate',{url},sessionId);return {targetId,sessionId};};
 const version=(await chrome.send('Browser.getVersion')).product;
 await chrome.send('Browser.setDownloadBehavior',{behavior:'allow',downloadPath:downloads,eventsEnabled:true});
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
 const expectedGood=!['missing','incompatible'].includes(mode);add('helper-detection',expectedGood?status.state==='info'&&status.text===T('timffle_helper_installed',[HELPER_VERSION]):status.state==='error'&&status.text===T(mode==='incompatible'?'timffle_helper_incompatible':'timffle_helper_missing'),{status});
 await until(()=>countHelpers()===0);add('status-check-exits-helper',countHelpers()===0);

 // The notice that tells the visitor to install the helper, and the button that downloads the installer for the visitor's system:
 // the settings page's button, the popup's notice and the install page. Downloads go to the stand-in for GitHub (fake-github.mjs).
 {
  const needsInstall=['missing','incompatible'].includes(mode);
  const wantStatus=T(mode==='incompatible'?'timffle_helper_incompatible':'timffle_helper_missing');
  const RELEASE='https://github.com/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/';
  // What each system gets: the label under the button, and the file (the table of src/helper-download.ts, written out again on purpose).
  const SYSTEMS=[
   {id:'windows-x64',label:'Windows 64-bit',file:'timffle-helper-windows-x64.exe',meta:{platform:'Windows',architecture:'x86',bitness:'64'}},
   {id:'windows-arm64',label:'Windows ARM64',file:'timffle-helper-windows-arm64.exe',meta:{platform:'Windows',architecture:'arm',bitness:'64'}},
   {id:'windows-x86',label:'Windows 32-bit',file:'timffle-helper-windows-x86.exe',meta:{platform:'Windows',architecture:'x86',bitness:'32'}},
   {id:'macos-arm64',label:'macOS Apple silicon',file:'timffle-helper-macos-arm64.zip',meta:{platform:'macOS',architecture:'arm',bitness:'64'}},
   {id:'macos-x64',label:'macOS Intel',file:'timffle-helper-macos-x64.zip',meta:{platform:'macOS',architecture:'x86',bitness:'64'}},
   {id:'linux-x64',label:'Linux x64',file:'timffle-helper-linux-x64.tar.gz',meta:{platform:'Linux',architecture:'x86',bitness:'64'}},
   {id:'linux-arm64',label:'Linux ARM64',file:'timffle-helper-linux-arm64.tar.gz',meta:{platform:'Linux',architecture:'arm',bitness:'64'}},
  ];
  // This test browser's own system: what its buttons download without any pretending.
  const own=SYSTEMS.find(x=>x.id===({linux:{x64:'linux-x64',arm64:'linux-arm64'},darwin:{x64:'macos-x64',arm64:'macos-arm64'},win32:{x64:'windows-x64',arm64:'windows-arm64',ia32:'windows-x86'}}[process.platform]??{})[process.arch]);
  assert.ok(own,'this test needs a system the helper has an installer for');
  const saved=()=>chrome.events.filter(e=>e.method==='Browser.downloadProgress'&&e.params.state==='completed').map(e=>e.params.filePath);
  // The release files only: a tab opened on github.com also asks for the site's icon.
  const requested=()=>github.requests.filter(r=>r.host==='github.com'&&r.url.startsWith('/Im-Tim-mI/')).map(r=>r.url);
  const waitSaved=async(file,count)=>!!await until(()=>saved().filter(f=>path.basename(f)===file).length>=count,DOWNLOAD_WAIT_MS);
  // What the install page shows, read the same way for every system.
  const INSTALL_PAGE_JS='({title:document.title,heading:document.querySelector("h1").textContent,lead:document.querySelector(".helper-state").nextElementSibling.textContent,groups:[...document.querySelectorAll(".helper-systems > li")].map(li=>({family:li.dataset.family,links:[...li.querySelectorAll(".helper-files li")].map(item=>{const a=item.querySelector("a");return {label:a.textContent,href:a.href,target:a.target,rel:a.rel,current:a.getAttribute("aria-current"),file:item.querySelector("code").textContent,fileDir:item.querySelector("code").dir}}),text:li.querySelector("p").textContent,code:li.querySelector("p code")?.textContent,codeDir:li.querySelector("p code")?.dir})),after:document.querySelector(".helper-systems").nextElementSibling.textContent,link:(()=>{const a=document.querySelector("#helper-releases");return {href:a.href,text:a.textContent,target:a.target,rel:a.rel}})(),dir:document.documentElement.dir,lang:document.documentElement.lang})';
  // The installers in the order the page lists them for a visitor on `ownId`: each group starts with that visitor's own, which is marked.
  const arrange=(ownId)=>['windows','macos','linux'].map(f=>{const group=SYSTEMS.filter(x=>x.id.startsWith(f));return [...group.filter(x=>x.id===ownId),...group.filter(x=>x.id!==ownId)];});
  const linuxCommandFor=(system)=>{const file=system&&system.id.startsWith('linux')?system.file:'timffle-helper-linux-x64.tar.gz';return 'tar xzf '+file+' && ./'+file.replace(/\.tar\.gz$/,'');};
  const forget=async(file)=>{await fs.rm(path.join(downloads,file),{force:true});};
  // A real click, then the wait for one more saved copy of the file (counting the earlier ones, so an old download is not taken for this one).
  const clickAndWaitForFile=async(sessionId,selector,file)=>{const had=saved().filter(f=>path.basename(f)===file).length;await realClick(sessionId,selector);return waitSaved(file,had+1);};
  // What Chrome tells a page about the system it runs on (navigator.userAgentData), as for a person on another system.
  const systemUA=(meta)=>({userAgent:'Mozilla/5.0 (test) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/155.0.0.0 Safari/537.36',userAgentMetadata:{brands:[{brand:'Chromium',version:'155'},{brand:'Google Chrome',version:'155'}],fullVersion:'155.0.0.0',platform:meta.platform,platformVersion:'10.0.0',architecture:meta.architecture,model:'',mobile:false,bitness:meta.bitness,wow64:false}});
  // A tab that Chrome believes runs on another system, as a person on that system would see it.
  const tabAs=async(url,meta)=>{
   const {targetId}=await chrome.send('Target.createTarget',{url:'about:blank'});const {sessionId}=await chrome.send('Target.attachToTarget',{targetId,flatten:true});
   for(const method of ['Page.enable','Runtime.enable'])await chrome.send(method,{},sessionId);
   await chrome.send('Emulation.setUserAgentOverride',systemUA(meta),sessionId);
   await chrome.send('Page.navigate',{url},sessionId);return {targetId,sessionId};};
  const pagesOnGitHub=async()=>(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&/github\.com|githubusercontent/.test(t.url));
  const button=await chrome.eval(opts.sessionId,'(()=>{const b=document.querySelector("#socket-helper-install"),r=b.getBoundingClientRect(),d=document.querySelector("#socket-helper-download"),f=document.querySelector("#socket-helper-for"),m=document.querySelector("#socket-helper-more");const shown=e=>getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;return {hidden:b.hidden,shown:getComputedStyle(b).display!=="none"&&r.width>0&&r.height>0,text:b.textContent,line:shown(d),forText:f.textContent,forShown:shown(f),more:{text:m.textContent,href:m.href,target:m.target,shown:shown(m)}}})()');
  add('options-install-button',button.hidden===!needsInstall&&button.shown===needsInstall&&button.text===T('timffle_helper_notice_button')&&button.line===needsInstall&&(!needsInstall||(button.forText===T('timffle_helper_download_for',[own.label])&&button.forShown&&button.more.text===T('timffle_helper_download_more')&&button.more.href==='chrome-extension://'+ID+'/helper.html'&&button.more.target==='_blank'&&button.more.shown)),{button});
  const popup=await chrome.tab('chrome-extension://'+ID+'/popup.html');
  // Whether the notice is really on the page (drawn, with height), not only whether it lacks the "hidden" class; read once the page and its style sheets have loaded.
  const noticeJs='(()=>{const n=document.querySelector("#helper-notice");if(!n||document.readyState!=="complete")return false;const r=n.getBoundingClientRect();const f=document.querySelector("#helper-notice-for"),m=document.querySelector("#helper-notice-more"),b=document.querySelector("#helper-notice-button");const shown=e=>getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;return getComputedStyle(n).display!=="none"&&r.height>0?{text:document.querySelector("#helper-notice-text").textContent,button:b.textContent,buttonShown:shown(b),forText:f.textContent,forShown:shown(f),more:{text:m.textContent,href:m.href,target:m.target,rel:m.rel,shown:shown(m)},height:Math.round(r.height)}:false})()';
  if(needsInstall){
   const notice=await chrome.wait(popup.sessionId,noticeJs,12000);
   add('popup-notice',notice.text===T(mode==='incompatible'?'timffle_helper_notice_incompatible':'timffle_helper_notice_missing')&&notice.button===T('timffle_helper_notice_button')&&notice.buttonShown,{notice});
   add('popup-notice-names-the-system-and-the-other-installers',notice.forText===T('timffle_helper_download_for',[own.label])&&notice.forShown&&notice.more.text===T('timffle_helper_download_more')&&notice.more.href==='chrome-extension://'+ID+'/helper.html'&&notice.more.target==='_blank'&&notice.more.rel==='noopener noreferrer'&&notice.more.shown,{notice});
   const noticeShot=await chrome.send('Page.captureScreenshot',{format:'png'},popup.sessionId);await fs.writeFile(path.join(output,'popup-notice.png'),Buffer.from(noticeShot.data,'base64'));
   // Only a real click counts, and it downloads at once: no page opens first.
   await chrome.eval(popup.sessionId,'document.querySelector("#helper-notice-button").click()');
   await delay(900);
   add('popup-script-click-ignored',github.requests.length===0&&saved().length===0,{requests:github.requests.length,saved:saved()});
   add('popup-button-downloads-the-installer',await clickAndWaitForFile(popup.sessionId,'#helper-notice-button',own.file)&&JSON.stringify(requested())===JSON.stringify(['/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/'+own.file]),{requested:requested(),saved:saved()});
   const body=await fs.readFile(path.join(downloads,own.file),'utf8').catch(()=>null);
   add('popup-download-is-the-file-of-the-release',body==='fake installer '+own.file,{body});
   const after=await chrome.eval(popup.sessionId,'document.querySelector("#helper-notice-text").textContent');
   add('popup-says-the-download-started',after===T('timffle_helper_download_started'),{after});
   // The tab that fetched the file closes by itself: nothing of GitHub stays open, and the install page was not opened.
   await until(async()=>(await pagesOnGitHub()).length===0,5000);
   add('popup-leaves-no-tab-behind',(await pagesOnGitHub()).length===0&&!(await chrome.send('Target.getTargets')).targetInfos.some(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html'),{pages:(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page').map(t=>t.url.slice(0,80))});
   // A double click is one download.
   await forget(own.file);await delay(2300);const before=requested().length;
   await realClick(popup.sessionId,'#helper-notice-button');await realClick(popup.sessionId,'#helper-notice-button');
   await delay(1500);
   add('popup-double-click-is-one-download',requested().length-before===1,{extra:requested().length-before});
   // The link to the other installers opens the install page in a tab of its own.
   await realClick(popup.sessionId,'#helper-notice-more');
   const opened=await until(async()=>(await chrome.send('Target.getTargets')).targetInfos.find(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html'));
   add('popup-link-opens-the-install-page',!!opened);
   if(opened)await chrome.send('Target.closeTarget',{targetId:opened.targetId});
   await forget(own.file);
  }else{
   await delay(2500);
   add('popup-no-notice-when-helper-works',!(await chrome.eval(popup.sessionId,noticeJs)));
  }
  await chrome.send('Target.closeTarget',{targetId:popup.targetId}).catch(()=>{});
  if(needsInstall){
   // The same for every system the helper has an installer for, as seen by a person on that system; and systems it has none for.
   if(mode==='missing'){
    for(const system of SYSTEMS){
     const tab=await tabAs('chrome-extension://'+ID+'/popup.html',system.meta);
     const n=await chrome.wait(tab.sessionId,noticeJs,12000);
     const had=saved().filter(f=>path.basename(f)===system.file).length;
     await realClick(tab.sessionId,'#helper-notice-button');
     const done=await waitSaved(system.file,had+1);
     add('popup-downloads-for-'+system.id,n.forText===T('timffle_helper_download_for',[system.label])&&n.buttonShown&&done,{forText:n.forText,saved:saved().map(f=>path.basename(f)),requested:requested().slice(-1)});
     add('popup-asks-github-for-'+system.id,requested().at(-1)==='/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/'+system.file);
     await chrome.send('Target.closeTarget',{targetId:tab.targetId}).catch(()=>{});await forget(system.file);
    }
    for(const [name,meta] of [['chromeos',{platform:'Chrome OS',architecture:'x86',bitness:'64'}],['android',{platform:'Android',architecture:'arm',bitness:'64'}],['unknown-processor',{platform:'macOS',architecture:'',bitness:''}]]){
     const tab=await tabAs('chrome-extension://'+ID+'/popup.html',meta);
     const n=await chrome.wait(tab.sessionId,noticeJs,12000);
     const was=requested().length;
     add('popup-without-installer-for-'+name,n.text===T('timffle_helper_notice_missing')&&!n.buttonShown&&!n.forShown&&n.more.shown&&n.more.href==='chrome-extension://'+ID+'/helper.html',{n});
     await chrome.send('Target.closeTarget',{targetId:tab.targetId}).catch(()=>{});
     add('popup-without-installer-for-'+name+'-downloads-nothing',requested().length===was);
    }
    // The install page for visitors on other systems: their installer first in its group and marked, and the Linux line with the command for their processor.
    for(const system of [SYSTEMS[1],SYSTEMS[3],SYSTEMS[4],SYSTEMS[6]]){
     const tab=await tabAs('chrome-extension://'+ID+'/helper.html',system.meta);
     await chrome.wait(tab.sessionId,'document.querySelectorAll(".helper-files li").length===7',12000);
     const c=await chrome.eval(tab.sessionId,INSTALL_PAGE_JS);
     const arranged=arrange(system.id);
     add('install-page-for-'+system.id,c.groups.every((g,k)=>JSON.stringify(g.links.map(l=>l.label+(l.current?'*':'')))===JSON.stringify(arranged[k].map(x=>x.label+(x.id===system.id?'*':''))))&&c.groups[2].code===linuxCommandFor(system),{groups:c.groups.map(g=>g.links.map(l=>l.label+(l.current?'*':''))),code:c.groups[2].code});
     await chrome.send('Target.closeTarget',{targetId:tab.targetId}).catch(()=>{});
    }
    // A system without an installer (Chrome OS): nothing is marked on the install page, the settings page offers no button but the way to the install page.
    {
     const tab=await tabAs('chrome-extension://'+ID+'/helper.html',{platform:'Chrome OS',architecture:'x86',bitness:'64'});
     await chrome.wait(tab.sessionId,'document.querySelectorAll(".helper-files li").length===7',12000);
     const c=await chrome.eval(tab.sessionId,INSTALL_PAGE_JS);
     add('install-page-for-a-system-without-installer',c.groups.every((g,k)=>g.links.every(l=>l.current===null)&&JSON.stringify(g.links.map(l=>l.label))===JSON.stringify(SYSTEMS.filter(x=>x.id.startsWith(['windows','macos','linux'][k])).map(x=>x.label)))&&c.groups[2].code===linuxCommandFor(undefined),{groups:c.groups.map(g=>g.links.map(l=>l.label+(l.current?'*':'')))});
     await chrome.send('Target.closeTarget',{targetId:tab.targetId}).catch(()=>{});
     const options=await tabAs('chrome-extension://'+ID+'/options.html',{platform:'Chrome OS',architecture:'x86',bitness:'64'});
     await chrome.wait(options.sessionId,'(()=>{const s=document.querySelector("#socket-helper-status");return s&&s.dataset.state&&s.dataset.state!=="checking"&&document.querySelector("#socket-helper-status").textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'})()',12000);
     const o=await chrome.eval(options.sessionId,'(()=>{const shown=e=>getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;const b=document.querySelector("#socket-helper-install"),d=document.querySelector("#socket-helper-download"),f=document.querySelector("#socket-helper-for"),m=document.querySelector("#socket-helper-more");return {button:shown(b),line:shown(d),label:shown(f),more:shown(m)}})()');
     add('options-for-a-system-without-installer',o.button===false&&o.line===true&&o.label===false&&o.more===true,{o});
     await chrome.send('Target.closeTarget',{targetId:options.targetId}).catch(()=>{});
    }
    // A release that is not there (not published yet, or private): nothing is saved, and the tab that was opened for it stays and shows GitHub's own page.
    github.setStatus(404);
    {
     const tab=await chrome.tab('chrome-extension://'+ID+'/popup.html');
     await chrome.wait(tab.sessionId,noticeJs,12000);
     const had=saved().length;
     await realClick(tab.sessionId,'#helper-notice-button');
     const page404=await until(async()=>(await pagesOnGitHub())[0],DOWNLOAD_WAIT_MS);
     await delay(500);
     add('popup-release-not-found-saves-nothing-and-shows-githubs-page',!!page404&&saved().length===had&&/github\.com/.test(page404.url),{page:page404&&page404.url,saved:saved().length-had});
     if(page404)await chrome.send('Target.closeTarget',{targetId:page404.targetId});
     await chrome.send('Target.closeTarget',{targetId:tab.targetId}).catch(()=>{});
    }
    github.setStatus(200);
   }
   const installPages=async()=>(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html');
   const requestsBefore=github.requests.length;
   await chrome.eval(opts.sessionId,'document.querySelector("#socket-helper-install").click()');await delay(900);
   add('options-script-click-ignored',github.requests.length===requestsBefore&&(await installPages()).length===0);
   add('options-button-downloads-the-installer',await clickAndWaitForFile(opts.sessionId,'#socket-helper-install',own.file)&&requested().at(-1)==='/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/'+own.file,{requested:requested().slice(-2),saved:saved().map(f=>path.basename(f))});
   const optionsAfter=await chrome.eval(opts.sessionId,'(()=>{const s=document.querySelector("#socket-helper-status");return {text:s.textContent,state:s.dataset.state}})()');
   add('options-says-the-download-started',optionsAfter.text===T('timffle_helper_download_started')&&optionsAfter.state==='info',{optionsAfter});
   await forget(own.file);
   await realClick(opts.sessionId,'#socket-helper-more');
   const openedFromOptions=await until(async()=>(await installPages())[0]);
   add('options-link-opens-the-install-page',!!openedFromOptions);
   if(openedFromOptions)await chrome.send('Target.closeTarget',{targetId:openedFromOptions.targetId});
  }
  // "Install the socket helper first": the window that opens when a page needs a TCP connection and the helper is not there (src/helper-prompt.ts).
  // The first-use question is a window of the same page; the ones the tests answered are left out, and the helper windows are
  // remembered with the time they were first seen (the extension opens at most 3 of them a minute).
  const promptPages=async()=>(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&t.url.startsWith('chrome-extension://'+ID+'/prompt.html?id='));
  const questionIds=new Set(),windowSeen=new Map();
  const noticeWindows=async()=>{const w=(await promptPages()).filter(t=>!questionIds.has(t.targetId));for(const t of w)if(!windowSeen.has(t.targetId))windowSeen.set(t.targetId,Date.now());return w;};
  // Waits until one more window may open: fewer than 3 seen in the last minute (seen a little after they opened, so on the safe side).
  const windowBudget=async()=>{while([...windowSeen.values()].filter(at=>Date.now()-at<61000).length>=3)await delay(500);};
  const closeNoticeWindows=async()=>{for(const w of await noticeWindows())await chrome.send('Target.closeTarget',{targetId:w.targetId}).catch(()=>{});await until(async()=>(await noticeWindows()).length===0,5000);};
  const noticeRead='(()=>{const shown=e=>!!e&&!e.hidden&&getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;const q=s=>document.querySelector(s);const b=q("#helper-download"),o=q("#helper-more"),c=q("#helper-close"),f=q("#helper-for");if(document.readyState!=="complete"||!shown(q("#helper"))||!shown(b))return false;const r=document.documentElement;return {title:q("#helper-title").textContent,origin:q("#helper-origin").textContent,embedded:shown(q("#helper-embedded")),text:q("#helper-text").textContent,safe:q("#helper .detail").textContent,question:shown(q("#prompt")),expired:shown(q("#expired")),download:b.textContent,label:{shown:shown(f),text:f.textContent},more:{shown:shown(o),text:o.textContent},close:{shown:shown(c),text:c.textContent},focused:document.activeElement&&document.activeElement.id,pageTitle:document.title,dir:r.dir}})()';
  const attach=async(target)=>{const {sessionId}=await chrome.send('Target.attachToTarget',{targetId:target.targetId,flatten:true});for(const method of ['Page.enable','Runtime.enable'])await chrome.send(method,{},sessionId);return sessionId;};
  const installPageTabs=async()=>(await chrome.send('Target.getTargets')).targetInfos.filter(t=>t.type==='page'&&t.url==='chrome-extension://'+ID+'/helper.html');
  // The parts of the window that wait for the helper: the step line for this system's installer, the waiting line, "Continue", and the
  // line at the top (what is wrong; once the helper is there, that it is).
  // False until the window shows them.
  const WAIT_READ='(()=>{const q=s=>document.querySelector(s),shown=e=>!!e&&!e.hidden&&getComputedStyle(e).display!=="none"&&e.getBoundingClientRect().width>0;const w=q("#helper-wait"),c=q("#helper-continue"),s=q("#helper-step");if(window.__old||document.readyState!=="complete"||!shown(q("#helper"))||!w||!w.dataset.state)return false;const code=s&&s.querySelector("code");return {state:w.dataset.state,wait:w.textContent,waitShown:shown(w),role:w.getAttribute("role"),live:w.getAttribute("aria-live"),step:{shown:shown(s),text:s&&s.textContent.replace(/\\s+/g," ").trim(),code:code&&code.textContent,codeDir:code&&code.dir},next:{shown:shown(c),text:c&&c.textContent,disabled:c&&c.disabled,ready:c&&(c.dataset.ready??null),recommended:!!c&&c.classList.contains("recommended")},problem:q("#helper-text").textContent,problemShown:shown(q("#helper-text")),problemRole:q("#helper-text").getAttribute("role"),download:shown(q("#helper-download")),focused:document.activeElement&&document.activeElement.id}})()';
  const READY_READ='(()=>{const v='+WAIT_READ+';return v&&v.state==="ready"?v:false})()';
  // This feature's texts, or null in a build without them (a KEEP_GOING run against an older build).
  const TT=(key,subs)=>{try{return T(key,subs);}catch{return null;}};
  const TP=(key,subs)=>{try{return T.plain(key,subs);}catch{return null;}};
  // The step line for a system's installer; a system without one (`undefined`) gets none.
  const stepShows=(step,system)=>!!step&&(system===undefined?step.shown===false:step.shown&&step.text===TP(system.id.startsWith('windows')?'timffle_helper_step_windows':system.id.startsWith('macos')?'timffle_helper_step_macos':'timffle_helper_step_linux',[linuxCommandFor(system)])&&(!system.id.startsWith('linux')||step.code===linuxCommandFor(system)&&step.codeDir==='ltr'));
  const waits=(v,system)=>!!v&&v.state==='waiting'&&v.waitShown&&v.wait===TT('timffle_helper_waiting')&&v.role==='status'&&v.live==='polite'&&v.next.shown&&v.next.disabled===true&&v.next.text===TT('timffle_helper_continue')&&v.next.ready!=='true'&&!v.next.recommended&&stepShows(v.step,system);
  // Ready: the line at the top says the helper is there (it said what was wrong), the waiting line is gone, "Continue" is lit up.
  const isReady=(v,version)=>!!v&&v.state==='ready'&&!v.waitShown&&v.problemShown&&v.problem===TT('timffle_helper_ready',[version])&&v.problemRole==='status'&&v.next.shown&&v.next.disabled===false&&v.next.ready==='true'&&v.next.recommended&&v.next.text===TT('timffle_helper_continue');
  // What the extension's pages ask the service worker (status checks, "Continue"), heard by a listener of the test's own; the attached
  // debugger keeps the service worker alive until done().
  const ear=async()=>{
   await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"wake"}).catch(()=>{})');
   const t=await until(async()=>(await chrome.send('Target.getTargets')).targetInfos.find(x=>x.type==='service_worker'&&x.url.startsWith('chrome-extension://'+ID+'/')),5000);
   assert.ok(t,'no service worker');
   const {sessionId}=await chrome.send('Target.attachToTarget',{targetId:t.targetId,flatten:true});await chrome.send('Runtime.enable',{},sessionId);
   await chrome.eval(sessionId,'(()=>{if(!self.__heard){self.__heard=[];chrome.runtime.onMessage.addListener((m,s)=>{if(m&&typeof m.type==="string"&&m.type.startsWith("socket_helper"))self.__heard.push({type:m.type,page:s.url?new URL(s.url).pathname:"",at:Date.now()})})}return true})()');
   return {now:()=>chrome.eval(sessionId,'Date.now()'),
    // When `page` sent `type` since `at` (the service worker's clock).
    heard:(at,type,page)=>chrome.eval(sessionId,'self.__heard.filter(x=>x.at>='+at+'&&x.type==='+JSON.stringify(type)+'&&x.page==='+JSON.stringify(page)+').map(x=>x.at)'),
    done:()=>chrome.send('Target.detachFromTarget',{sessionId}).catch(()=>{})};
  };
  // The first-use question for a website nobody has decided about, once its input guard has passed; it is not one of the helper windows.
  const question=async()=>{const t=await until(async()=>(await promptPages()).find(w=>!windowSeen.has(w.targetId)),15000);if(!t)return null;questionIds.add(t.targetId);const sessionId=await attach(t);const asks=await chrome.wait(sessionId,'!document.getElementById("prompt").hidden',8000).catch(()=>false);if(!asks){questionIds.delete(t.targetId);return null;}await delay(900);return {...t,sessionId};};
  // A real click with the pointer moved onto the element first (the question counts "Allow" only so).
  const movedClick=async(sessionId,selector)=>{const r=await chrome.eval(sessionId,'(()=>{const e=document.querySelector('+JSON.stringify(selector)+');e.scrollIntoView({block:"center"});const b=e.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()');for(const type of ['mouseMoved','mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:r.x,y:r.y,button:'left',buttons:type==='mousePressed'?1:0,clickCount:type==='mouseMoved'?0:1},sessionId);};
  // A game page that opens a Flash socket; `tag` counts its loads.
  const gameUrl=(site,tag)=>site+'/?'+new URLSearchParams({host:'127.0.0.1',port:small.port,size:6,timeout:15000,cancel:-1,tag});
  const tabOf=(tag)=>chrome.eval(opts.sessionId,'chrome.tabs.query({}).then(ts=>{const t=ts.find(t=>{try{return new URL(t.url).searchParams.get("tag")==='+JSON.stringify(tag)+'}catch{return false}});return t?{id:t.id,windowId:t.windowId,active:t.active}:null})');
  const settingsNow=()=>chrome.eval(opts.sessionId,'chrome.storage.local.get("socketProxySettings").then(x=>x.socketProxySettings)');
  const putSettings=(value)=>chrome.eval(opts.sessionId,'chrome.storage.local.set({socketProxySettings:'+JSON.stringify(value)+'})');
  noticeApi={
   windows:noticeWindows,
   // The window that is open for a page of `site`: what it says, and each of its buttons, ending with the window closed by its own button.
   async exercise(site){
    const target=await until(async()=>(await noticeWindows())[0],10000);
    add('notice-window-opens-when-a-page-needs-tcp-and-the-helper-is-missing',!!target&&(await noticeWindows()).length===1,{windows:(await noticeWindows()).map(w=>w.url.slice(0,70))});
    const sessionId=await attach(target);
    const view=await chrome.wait(sessionId,noticeRead,12000);
    const wantText=T(mode==='incompatible'?'timffle_helper_notice_incompatible':'timffle_helper_notice_missing');
    add('notice-window-says-what-is-wrong-and-for-whom',view.title===T('timffle_helper_prompt_title')&&view.origin===site&&!view.embedded&&view.text===wantText&&view.safe===T('timffle_helper_page_safe')&&!view.question&&!view.expired&&view.pageTitle===T('timffle_helper_prompt_title'),{view});
    add('notice-window-offers-the-installer-for-this-system',view.download===T('timffle_helper_notice_button')&&view.label.shown&&view.label.text===T('timffle_helper_download_for',[own.label])&&view.more.shown&&view.more.text===T('timffle_helper_download_more')&&view.close.shown&&view.close.text===T('timffle_close'),{view});
    add('notice-window-has-the-safe-button-focused',view.focused==='helper-close',{focused:view.focused});
    // While the helper is not there: the step for this system's installer, the line that says the window waits, "Continue" off.
    const waiting=await chrome.wait(sessionId,WAIT_READ,8000).catch(()=>null);
    add('notice-window-waits-for-the-installation',waits(waiting,own),{waiting});
    // With a real window (CHROME_HEADED=1 CHROME_WINDOW_SIZE=none, e.g. under xvfb-run) the size it was opened with decides; headless Chrome forces its own.
    const fit=await chrome.eval(sessionId,'({innerWidth,innerHeight,scrollHeight:document.documentElement.scrollHeight,outerWidth,outerHeight})');
    if(process.env.CHROME_HEADED&&process.env.CHROME_WINDOW_SIZE==='none')add('notice-window-fits-its-window-without-scrolling',fit.scrollHeight<=fit.innerHeight,{fit});else console.log(JSON.stringify({info:'notice-window',fit}));
    const shot=await chrome.send('Page.captureScreenshot',{format:'png'},sessionId);await fs.writeFile(path.join(output,'notice-window.png'),Buffer.from(shot.data,'base64'));
    // Nothing happens before the moment the window ignores input has passed, and a script's click never counts.
    await delay(1000);
    const requestsBefore=github.requests.length,savedBefore=saved().length;
    await chrome.eval(sessionId,'document.querySelector("#helper-download").click()');
    await delay(900);
    add('notice-window-script-click-ignored',github.requests.length===requestsBefore&&saved().length===savedBefore,{requests:github.requests.length-requestsBefore,saved:saved().length-savedBefore});
    const asked=requested().length;
    add('notice-window-button-downloads-the-installer',await clickAndWaitForFile(sessionId,'#helper-download',own.file)&&JSON.stringify(requested().slice(asked))===JSON.stringify(['/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/'+own.file]),{requested:requested().slice(asked),saved:saved().map(f=>path.basename(f))});
    add('notice-window-download-is-the-file-of-the-release',await fs.readFile(path.join(downloads,own.file),'utf8').catch(()=>null)==='fake installer '+own.file);
    // The download changes neither the problem line nor the waiting line (which already says what happens next).
    await delay(600);
    const afterDownload=await chrome.eval(sessionId,WAIT_READ).catch(()=>null);
    add('notice-window-keeps-its-lines-after-the-download',!!afterDownload&&afterDownload.problem===wantText&&waits(afterDownload,own),{afterDownload});
    // The tab that fetched the file closes by itself; the window stays, and the install page was not opened.
    await until(async()=>(await pagesOnGitHub()).length===0,5000);
    add('notice-window-leaves-no-tab-behind',(await pagesOnGitHub()).length===0&&(await installPageTabs()).length===0&&(await noticeWindows()).length===1);
    // A double click is one download.
    await forget(own.file);await delay(2300);const before=requested().length;
    await realClick(sessionId,'#helper-download');await realClick(sessionId,'#helper-download');await delay(1500);
    add('notice-window-double-click-is-one-download',requested().length-before===1,{extra:requested().length-before});
    await forget(own.file);
    // The way to the other installers opens the install page in a tab of the browser, and the window stays.
    await realClick(sessionId,'#helper-more');
    const opened=await until(async()=>(await installPageTabs())[0]);
    add('notice-window-link-opens-the-install-page',!!opened&&(await noticeWindows()).length===1);
    if(opened)await chrome.send('Target.closeTarget',{targetId:opened.targetId});
    // Its own button closes it.
    await realClick(sessionId,'#helper-close');
    add('notice-window-closes-with-its-button',!!await until(async()=>(await noticeWindows()).length===0,5000));
   },
   // A page load is told once, whether or not its window is still there; the next page load's window replaces one that is still open
   // (it may be behind the browser's own); the window ignores clicks and Escape in its first moment.
   async pageLoads(game,site,port){
    const trySocket=()=>chrome.eval(game.sessionId,'new Promise(resolve=>{const s=new WebSocket("ws://timffle-socket.invalid/connect?host=127.0.0.1&port='+port+'");s.onerror=()=>resolve("error");s.onopen=()=>resolve("open");setTimeout(()=>resolve("timeout"),4000)})');
    const w2=await until(async()=>(await noticeWindows())[0],10000);
    add('notice-window-opens-again-for-another-page-load',!!w2&&(await noticeWindows()).length===1);
    // The same page load needs a connection again while its window is open: no second window, and not another one in place of it.
    await trySocket();await delay(1200);
    const same=await noticeWindows();
    add('notice-window-same-page-load-keeps-its-one-window',same.length===1&&same[0].targetId===w2.targetId,{windows:same.length});
    // The page is reloaded with the window still open: the old window is replaced by the new page load's, one window in all.
    await chrome.send('Page.reload',{},game.sessionId);await chrome.wait(game.sessionId,'window.__probe',15000);
    const w3=await until(async()=>{const w=await noticeWindows();return w.length===1&&w[0].targetId!==w2.targetId?w[0]:false;},10000);
    add('notice-window-next-page-load-replaces-the-window-that-is-still-open',!!w3,{windows:(await noticeWindows()).length});
    if(w3){
     const s=await attach(w3);
     await chrome.wait(s,noticeRead,12000);
     // The window's own page is loaded again, which starts its first moment again: clicks and Escape in it must do nothing.
     const inMoment=async(act)=>{
      for(let attempt=0;attempt<5;attempt++){
       try{
        await chrome.send('Page.reload',{},s);
        const ready=await chrome.wait(s,'(()=>{const d=document.getElementById("helper-download");return document.readyState==="complete"&&d&&!d.hidden&&document.body.dataset.wait==="1"})()',8000).catch(()=>false);
        if(!ready)continue;
        await act();
        // Only a press inside the moment counts as a test (a slow machine may have let it pass).
        if(await chrome.eval(s,'document.body.dataset.wait==="1"'))return true;
       }catch(e){return 'the window is gone: '+e.message;}
      }
      return false;
     };
     const escape=()=>chrome.send('Input.dispatchKeyEvent',{type:'keyDown',key:'Escape',code:'Escape',windowsVirtualKeyCode:27},s);
     const requestsBefore=github.requests.length,savedBefore=saved().length;
     const early={download:await inMoment(()=>realClick(s,'#helper-download')),more:await inMoment(()=>realClick(s,'#helper-more')),close:await inMoment(()=>realClick(s,'#helper-close')),escape:await inMoment(escape)};
     await delay(1200);
     const windowsLeft=(await noticeWindows()).length;
     add('notice-window-ignores-clicks-and-escape-in-its-first-moment',Object.values(early).every(v=>v===true)&&github.requests.length===requestsBefore&&saved().length===savedBefore&&(await installPageTabs()).length===0&&windowsLeft===1,{early,requests:github.requests.length-requestsBefore,saved:saved().length-savedBefore,installPages:(await installPageTabs()).length,windows:windowsLeft});
     // After the moment the same keys count, but not a key that only repeats: one held down for the game keeps repeating into the window that has just taken the focus.
     await chrome.wait(s,'document.body.dataset.wait!=="1"',5000);
     const repeatKey=(key,vk,text)=>chrome.send('Input.dispatchKeyEvent',{type:'keyDown',key,code:key,windowsVirtualKeyCode:vk,text,autoRepeat:true},s).catch(()=>{});
     await repeatKey('Escape',27);
     await repeatKey('Enter',13,'\r');
     await delay(800);
     add('notice-window-ignores-a-key-that-only-repeats',(await noticeWindows()).length===1&&github.requests.length===requestsBefore&&saved().length===savedBefore&&(await installPageTabs()).length===0,{windows:(await noticeWindows()).length,requests:github.requests.length-requestsBefore,saved:saved().length-savedBefore});
     for(const [key,vk] of [['Escape',27],['Enter',13]])await chrome.send('Input.dispatchKeyEvent',{type:'keyUp',key,code:key,windowsVirtualKeyCode:vk},s).catch(()=>{});
     await escape();
     add('notice-window-closes-with-escape-after-the-moment',!!await until(async()=>(await noticeWindows()).length===0,5000));
    }
    // Its page load was told: the window is closed and a connection from the same page does not bring it back.
    await trySocket();await delay(1500);
    add('notice-window-not-again-for-the-same-page-load',(await noticeWindows()).length===0);
   },
   // The window of the page loaded with `tag`: it waits, asking the service worker every 2 s; once the helper is installed it says so by
   // itself and lights "Continue" up without taking the focus, and stops asking; a script's click does nothing; a real one reloads the
   // page, brings its tab to the front and closes the window. The page load after it connects and gets no window.
   async continueReloads(game,tag,label){
    const target=await until(async()=>(await noticeWindows())[0],10000);
    if(!target){add(label+'-continue-window-opens',false);return;}
    const s=await attach(target),sw=await ear();
    try{
     const before=await chrome.wait(s,WAIT_READ,12000).catch(()=>null);
     add(label+'-window-waits-with-continue-off',waits(before,own),{before});
     const t0=await sw.now();await delay(6500);
     const polls=await sw.heard(t0,'socket_helper_status','/prompt.html'),still=await chrome.eval(s,WAIT_READ).catch(()=>null);
     // What a check finds meanwhile: not a helper this extension can use.
     const status=await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"socket_helper_status"})').catch(e=>({error:e.message}));
     add(label+'-window-checks-every-2-seconds-and-keeps-waiting',polls.length>=2&&polls.length<=5&&waits(still,own)&&status.installed!==true,{polls:polls.slice(1).map((at,i)=>at-polls[i]),status});
     const flipped=Date.now();await installHelper();
     const ready=await chrome.wait(s,READY_READ,15000).catch(()=>null),took=Date.now()-flipped;
     add(label+'-window-turns-ready-by-itself-after-the-installation',isReady(ready,HELPER_VERSION)&&took<=8000&&!!before&&ready.focused===before.focused,{took,ready});
     const shot=await chrome.send('Page.captureScreenshot',{format:'png'},s);await fs.writeFile(path.join(output,'notice-window-ready-'+label+'.png'),Buffer.from(shot.data,'base64'));
     const t1=await sw.now();await delay(5000);
     const later=await sw.heard(t1,'socket_helper_status','/prompt.html');
     add(label+'-window-stops-checking-once-ready',later.length===0,{later:later.length});
     const first=await chrome.eval(game.sessionId,'performance.timeOrigin');
     await chrome.eval(s,'document.querySelector("#helper-continue")?.click()');await delay(1500);
     add(label+'-continue-script-click-ignored',(await noticeWindows()).length===1&&loads.get(tag)===1&&await chrome.eval(game.sessionId,'performance.timeOrigin')===first,{loads:loads.get(tag)});
     // Another tab in front of the game's in its window; the window gets the focus back first, as a real click on it gives it.
     const tab=await tabOf(tag);
     const filler=await chrome.eval(opts.sessionId,'chrome.tabs.create({windowId:'+tab.windowId+',url:"about:blank",active:true}).then(t=>t.id)');
     const behind=await tabOf(tag);
     await chrome.send('Page.bringToFront',{},s);await chrome.wait(s,'document.hasFocus()',5000).catch(()=>{});await delay(300);
     const pressed=await sw.now();
     await realClick(s,'#helper-continue');
     const gone=await until(async()=>(await noticeWindows()).length===0,8000);
     const reloaded=await until(()=>loads.get(tag)===2,15000);
     const fresh=await chrome.wait(game.sessionId,'performance.timeOrigin!=='+first+'&&document.readyState==="complete"',15000).catch(()=>false);
     const front=await tabOf(tag),asked=await sw.heard(pressed,'socket_helper_continue','/prompt.html');
     add(label+'-continue-reloads-the-game-page-and-closes-the-window',!!gone&&!!reloaded&&!!fresh&&loads.get(tag)===2&&asked.length===1,{gone:!!gone,loads:loads.get(tag),asked:asked.length});
     add(label+'-continue-brings-the-game-tab-to-the-front',behind?.active===false&&front?.active===true,{behind,front});
     await chrome.eval(opts.sessionId,'chrome.tabs.remove('+filler+')').catch(()=>{});
     const r=await chrome.wait(game.sessionId,'window.__probe',25000).catch(()=>null);await delay(1500);
     add(label+'-reloaded-page-connects-and-gets-no-window',!!r&&good(r)&&(await noticeWindows()).length===0,{r});
    }finally{await sw.done();}
   },
   // Whether a page that needs TCP gets the window, end to end, while one more window may open: never for an always-denied website, with
   // sockets off, or after "Deny" in the first-use question; after "Allow" it opens (so it could have opened for the others), and that
   // window goes on as in continueReloads.
   async triggers(){
    await closeNoticeWindows();await windowBudget();
    const saved=await settingsNow();
    const none=async(name,url)=>{const t=await chrome.tab(url);const r=await chrome.wait(t.sessionId,'window.__probe',25000).catch(()=>null);await delay(2000);const w=await noticeWindows();add(name,!!r&&noConnect(r)&&w.length===0,{windows:w.length,r});await chrome.send('Target.closeTarget',{targetId:t.targetId}).catch(()=>{});};
    await putSettings({...saved,deniedOrigins:[deniedOrigin]});await delay(500);
    await none('missing-always-denied-website-gets-no-window',gameUrl(deniedOrigin,'denied'));
    await putSettings({...saved,enabled:false});await delay(500);
    await none('missing-sockets-off-gets-no-window',gameUrl(origin,'off'));
    await putSettings(saved);await delay(500);
    {
     const t=await chrome.tab(gameUrl(askOrigin,'deny'));
     const q=await question();
     if(q)await movedClick(q.sessionId,'#deny-once');
     const r=await chrome.wait(t.sessionId,'window.__probe',25000).catch(()=>null);await delay(2000);
     const w=await noticeWindows();
     add('missing-deny-in-the-question-gets-no-window',!!q&&!!r&&noConnect(r)&&w.length===0,{asked:!!q,r,windows:w.length});
     await chrome.send('Target.closeTarget',{targetId:t.targetId}).catch(()=>{});
    }
    const game=await chrome.tab(gameUrl(askOrigin,'allow'));
    const q=await question();
    if(q)await movedClick(q.sessionId,'#allow-once');
    const r=await chrome.wait(game.sessionId,'window.__probe',25000).catch(()=>null);
    add('missing-allow-in-the-question-opens-the-window',!!q&&!!r&&noConnect(r)&&!!await until(async()=>(await noticeWindows()).length===1,10000),{asked:!!q,r});
    await noticeApi.continueReloads(game,'allow','missing');
    await chrome.send('Target.closeTarget',{targetId:game.targetId}).catch(()=>{});
   },
   // A protocol-1 helper answers, but the window waits for one that fits; installing it makes the window ready, and Continue reloads.
   async incompatible(){
    await closeNoticeWindows();await removeHelper();await windowBudget();
    const game=await chrome.tab(gameUrl(origin,'incompatible'));
    await chrome.wait(game.sessionId,'window.__probe',25000).catch(()=>null);
    await noticeApi.continueReloads(game,'incompatible','incompatible');
    await chrome.send('Target.closeTarget',{targetId:game.targetId}).catch(()=>{});
   },
   // The step line for other systems; "Continue" only from the window's own page; and "Continue" for a tab that has gone to another
   // website meanwhile closes the window only.
   async leftSite(){
    await closeNoticeWindows();await removeHelper();await windowBudget();
    const tag='left',game=await chrome.tab(gameUrl(origin,tag));
    await chrome.wait(game.sessionId,'window.__probe',25000).catch(()=>null);
    const target=await until(async()=>(await noticeWindows())[0],10000);
    add('missing-window-opens-for-an-always-allowed-website',!!target);
    if(!target)return;
    const s=await attach(target),id=new URL(target.url).searchParams.get('id');
    await chrome.wait(s,WAIT_READ,12000).catch(()=>null);
    // The window's page loaded again as a person on another system sees it (Chrome OS has no installer, so no step line).
    for(const [name,system,meta] of [['windows-x64',SYSTEMS[0]],['macos-arm64',SYSTEMS[3]],['linux-arm64',SYSTEMS[6]],['chromeos',undefined,{platform:'Chrome OS',architecture:'x86',bitness:'64'}]]){
     await chrome.send('Emulation.setUserAgentOverride',systemUA(system?system.meta:meta),s);
     await chrome.eval(s,'window.__old=1').catch(()=>{});await chrome.send('Page.reload',{},s);
     const v=system?await chrome.wait(s,'(()=>{const v='+WAIT_READ+';return v&&v.download?v:false})()',12000).catch(()=>null):await chrome.wait(s,WAIT_READ,12000).then(()=>delay(1500)).then(()=>chrome.eval(s,WAIT_READ)).catch(()=>null);
     add('notice-window-step-line-for-'+name,waits(v,system),{step:v&&v.step,state:v&&v.state});
    }
    const first=await chrome.eval(game.sessionId,'performance.timeOrigin');
    const fromOptions=await chrome.eval(opts.sessionId,'chrome.runtime.sendMessage({type:"socket_helper_continue",id:'+JSON.stringify(id)+'}).then(r=>String(r),e=>"error: "+e.message)');
    const otherId=await chrome.eval(s,'chrome.runtime.sendMessage({type:"socket_helper_continue",id:"00000000-0000-4000-8000-000000000000"}).then(r=>String(r),e=>"error: "+e.message)');
    await delay(1500);
    add('continue-is-only-for-the-window-that-shows-it',(await noticeWindows()).length===1&&loads.get(tag)===1&&await chrome.eval(game.sessionId,'performance.timeOrigin')===first&&fromOptions!=='true'&&otherId!=='true',{fromOptions,otherId});
    await chrome.send('Page.navigate',{url:elsewhere+'/?bare=1&tag=away'},game.sessionId);
    await until(()=>loads.get('away')===1,10000);await chrome.wait(game.sessionId,'location.href.includes("tag=away")&&document.readyState==="complete"',10000).catch(()=>{});
    const away=await chrome.eval(game.sessionId,'performance.timeOrigin');
    await installHelper();
    const ready=await chrome.wait(s,READY_READ,15000).catch(()=>null);
    add('missing-window-turns-ready-while-its-tab-is-on-another-website',isReady(ready,HELPER_VERSION),{ready});
    await chrome.send('Page.bringToFront',{},s);await delay(800);
    if(ready)await realClick(s,'#helper-continue');
    const gone=await until(async()=>(await noticeWindows()).length===0,8000);
    await delay(2500);
    add('continue-does-not-reload-a-tab-that-went-to-another-website',!!ready&&!!gone&&loads.get('away')===1&&loads.get(tag)===1&&await chrome.eval(game.sessionId,'performance.timeOrigin')===away,{gone:!!gone,loads:{away:loads.get('away'),game:loads.get(tag)}});
    await chrome.send('Target.closeTarget',{targetId:game.targetId}).catch(()=>{});
   },
   // The install page notices the installation by itself (it asks every 3 s while it is shown and the helper is not there) without
   // touching its line or its button while nothing changes, never shows "checking" for it, and stops asking once the helper is there.
   async installPage(){
    await removeHelper();
    const page=await chrome.tab('chrome-extension://'+ID+'/helper.html');
    await chrome.send('Page.bringToFront',{},page.sessionId);
    const first=await chrome.wait(page.sessionId,pageStatusJs,12000).catch(()=>null);
    await delay(1000);
    const sw=await ear();
    try{
     const visible=await chrome.eval(page.sessionId,'(()=>{const s=document.querySelector("#helper-page-status"),b=document.querySelector("#helper-page-check");window.__lines=[];new MutationObserver(()=>window.__lines.push(s.textContent)).observe(s,{childList:true,characterData:true,subtree:true});new MutationObserver(()=>window.__lines.push("button disabled: "+b.disabled)).observe(b,{attributes:true,attributeFilter:["disabled"]});return document.visibilityState})()');
     const t0=await sw.now();await delay(7500);
     const quiet=await chrome.eval(page.sessionId,'window.__lines.splice(0)'),asked=await sw.heard(t0,'socket_helper_status','/helper.html');
     add(mode+'-install-page-checks-by-itself-without-touching-its-line',!!first&&first.state==='error'&&first.text===wantStatus&&quiet.length===0&&asked.length>=2&&asked.length<=4,{first,visible,quiet,asked:asked.slice(1).map((at,i)=>at-asked[i])});
     const flipped=Date.now();await installHelper();
     const after=await chrome.wait(page.sessionId,'(()=>{const s=document.querySelector("#helper-page-status");return s.dataset.state==="info"&&s.textContent==='+JSON.stringify(T('timffle_helper_installed',[HELPER_VERSION]))+'})()',15000).catch(()=>false),took=Date.now()-flipped;
     const lines=await chrome.eval(page.sessionId,'window.__lines.splice(0)');
     add(mode+'-install-page-notices-the-installation-by-itself',after&&took<=8000&&!lines.includes(T('timffle_helper_checking')),{took,lines});
     const t1=await sw.now();await delay(7500);
     const later=await sw.heard(t1,'socket_helper_status','/helper.html');
     add(mode+'-install-page-stops-checking-once-the-helper-is-there',later.length===0,{later:later.length});
    }finally{await sw.done();await chrome.send('Target.closeTarget',{targetId:page.targetId}).catch(()=>{});}
   },
  };
  const page=await chrome.tab('chrome-extension://'+ID+'/helper.html');
  const pageStatusJs='(()=>{const s=document.querySelector("#helper-page-status");return s&&s.dataset.state&&s.textContent!=='+JSON.stringify(T('timffle_helper_checking'))+'?{text:s.textContent,state:s.dataset.state}:false})()';
  const shown=await chrome.wait(page.sessionId,pageStatusJs,12000);
  add('install-page-status',needsInstall?shown.state==='error'&&shown.text===wantStatus:shown.state==='info'&&shown.text===T('timffle_helper_installed',[HELPER_VERSION]),{shown});
  await chrome.wait(page.sessionId,'document.querySelectorAll(".helper-files li").length===7');
  const content=await chrome.eval(page.sessionId,INSTALL_PAGE_JS);
  const stripTags=(k,subs)=>T(k,subs).replace(/<\/?\d>/g,'');
  const command=linuxCommandFor(own);
  const order=SYSTEMS.filter(x=>x.id.startsWith('windows')).map(x=>x.id).concat(SYSTEMS.filter(x=>x.id.startsWith('macos')).map(x=>x.id),SYSTEMS.filter(x=>x.id.startsWith('linux')).map(x=>x.id));
  const listed=content.groups.flatMap(g=>g.links);
  const arranged=arrange(own.id);
  add('install-page-texts',content.title===T('timffle_helper_page_title')&&content.heading===T('timffle_helper_page_heading')&&content.lead===T('timffle_helper_page_downloads')
   &&content.groups.map(g=>g.family).join('|')==='windows|macos|linux'
   &&content.groups[0].text===T('timffle_helper_step_windows')&&content.groups[1].text===T('timffle_helper_step_macos')&&content.groups[2].text===stripTags('timffle_helper_step_linux',[command])
   &&content.groups[2].code===command&&content.groups[2].codeDir==='ltr'
   &&content.after===T('timffle_helper_step_after')
   &&content.link.href==='https://github.com/Im-Tim-mI/Timffle-Helper/releases/tag/v1.4.0'&&content.link.target==='_blank'&&content.link.rel==='noopener noreferrer'&&content.link.text===T('timffle_helper_page_download').match(/<1>([^<]*)<\/1>/)[1],{content});
  add('install-page-lists-every-installer-for-its-system',content.groups.every((g,i)=>JSON.stringify(g.links.map(l=>l.label))===JSON.stringify(arranged[i].map(x=>x.label))&&g.links.every((l,k)=>l.href===RELEASE+arranged[i][k].file&&l.file===arranged[i][k].file&&l.fileDir==='ltr'&&l.target==='_blank'&&l.rel==='noopener noreferrer'&&l.current===(arranged[i][k].id===own.id?'true':null))),{groups:content.groups.map(g=>g.links.map(l=>l.label+(l.current?'*':'')))});
  assert.equal(listed.length,order.length);
  // A link on the install page downloads that file (a real click, as the other buttons).
  const linuxLink=await chrome.eval(page.sessionId,'(()=>{const a=document.querySelector(\'.helper-files a[href$="timffle-helper-linux-arm64.tar.gz"]\');a.scrollIntoView({block:"center"});const b=a.getBoundingClientRect();return {x:b.x+b.width/2,y:b.y+b.height/2}})()');
  const hadArm=saved().filter(f=>path.basename(f)==='timffle-helper-linux-arm64.tar.gz').length;
  for(const type of ['mousePressed','mouseReleased'])await chrome.send('Input.dispatchMouseEvent',{type,x:linuxLink.x,y:linuxLink.y,button:'left',clickCount:1},page.sessionId);
  add('install-page-link-downloads-that-file',await waitSaved('timffle-helper-linux-arm64.tar.gz',hadArm+1)&&requested().at(-1)==='/Im-Tim-mI/Timffle-Helper/releases/download/v1.4.1/timffle-helper-linux-arm64.tar.gz');
  await forget('timffle-helper-linux-arm64.tar.gz');
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
  // Always-allowed pages that connected through a working helper: no "install the helper" window.
  add('localtest-no-helper-window-when-the-helper-works',(await noticeApi.windows()).length===0);
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
  const before=small.stat.connections;
  const wantsWindow=['missing','incompatible'].includes(mode);
  // The first page: no TCP connection is made. It needed one and the helper is not there, so the window that says so opens; the page's
  // tab stays open while that window is looked at (a window goes with its tab) and is closed by its own button.
  const first=await chrome.tab(origin+'/?'+new URLSearchParams({host:'127.0.0.1',port:small.port,size:6,timeout:1800,cancel:-1}));
  const firstResult=await chrome.wait(first.sessionId,'window.__probe',15000);
  add(mode+'-no-fake-connect',noConnect(firstResult),{result:firstResult});add(mode+'-no-tcp',small.stat.connections===before);
  if(wantsWindow)await noticeApi.exercise(origin);
  await chrome.send('Target.closeTarget',{targetId:first.targetId});
  // The toolbar icon: a game that needed the helper and could not get it marks the tab it is in, until the page is left.
  const marked=()=>chrome.eval(opts.sessionId,'(async()=>{const out=[];for(const t of await chrome.tabs.query({})){const text=await chrome.action.getBadgeText({tabId:t.id});if(text)out.push({text,color:await chrome.action.getBadgeBackgroundColor({tabId:t.id})})}return out})()');
  const game=await chrome.tab(origin+'/?'+new URLSearchParams({host:'127.0.0.1',port:small.port,size:6,timeout:1800,cancel:-1}));
  await chrome.wait(game.sessionId,'window.__probe',15000);
  const needsInstall=['missing','incompatible'].includes(mode);
  const badge=needsInstall?await until(async()=>{const m=await marked();return m.length?m:false},5000):await marked();
  add(mode+'-badge-on-the-game-tab',needsInstall?badge.length===1&&badge[0].text==='!'&&JSON.stringify(badge[0].color)==='[217,48,37,255]':badge.length===0,{badge});
  if(needsInstall){
   await noticeApi.pageLoads(game,origin,small.port);
   await chrome.send('Page.navigate',{url:'about:blank'},game.sessionId);
   const cleared=await until(async()=>(await marked()).length===0,5000);
   add(mode+'-badge-ends-with-the-page',!!cleared);
  }
  await chrome.send('Target.closeTarget',{targetId:game.targetId});
  // The window waits for the installation and "Continue" reloads the game (the stand-in helper is installed while the browser runs).
  if(mode==='missing'){await part('triggers',()=>noticeApi.triggers());await part('left-site',()=>noticeApi.leftSite());}
  if(mode==='incompatible')await part('incompatible-continue',()=>noticeApi.incompatible());
  if(wantsWindow)await part('install-page-refresh',()=>noticeApi.installPage());
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
 const failed=results.filter(r=>!r.pass);
 if(failed.length){process.exitCode=1;console.log('FAILED '+failed.length+' of '+results.length+' checks: '+failed.map(r=>r.name).join(' '));}
 console.log('RESULTS '+output);
}catch(e){results.push({name:'harness-error',pass:false,error:e.message});await fs.writeFile(path.join(output,'results.json'),JSON.stringify({mode,results},null,2));console.error(e.stack);process.exitCode=1;}
finally{
 if(chrome)await chrome.close();for(const socket of tcpSockets)socket.destroy();for(const client of wss.clients)client.terminate();for(const fn of cleanup.reverse())await fn();
 if(originalPrivate===undefined)delete process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE;else process.env.TIMFFLE_SOCKET_HELPER_ALLOW_PRIVATE=originalPrivate;
 // Chrome may still write into its profile for a moment after it was closed: remove again instead of failing the run.
 await delay(300);await fs.rm(path.join(output,'chrome'),{recursive:true,force:true,maxRetries:8,retryDelay:250});
}
