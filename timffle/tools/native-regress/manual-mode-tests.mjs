import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import net from 'node:net';
import http from 'node:http';
import dns from 'node:dns/promises';
import {randomBytes} from 'node:crypto';
import {Chrome,delay} from './chrome-cdp-native.mjs';
import {createRelay} from '../../relay/relay.mjs';
const root=path.dirname(new URL(import.meta.url).pathname),extDir=process.argv[2],legacy=process.argv.includes('--legacy');
const output=path.join(root,process.env.OUT_NAME||(legacy?'browser-legacy':'browser-fixed'));
await fs.mkdir(output,{recursive:true});const cleanup=[],results=[];let chrome;
const listen=async server=>{await new Promise(r=>server.listen(0,'127.0.0.1',r));cleanup.push(()=>new Promise(r=>server.close(r)));return server.address().port;};
const active=new Set();
async function echo(){return listen(net.createServer(s=>{active.add(s);s.on('close',()=>active.delete(s));s.on('error',()=>{});s.on('data',d=>s.end(d));}));}
const ep1=await echo(),ep2=await echo();
const tmp=net.createServer();await new Promise(r=>tmp.listen(0,'127.0.0.1',r));const refused=tmp.address().port;await new Promise(r=>tmp.close(r));
const swf=await fs.readFile(path.join(root,'fixtures/SocketProbe.swf'));
const pageServer=http.createServer((req,res)=>{const u=new URL(req.url,'http://localhost');if(u.pathname.endsWith('.swf')){res.setHeader('Content-Type','application/x-shockwave-flash');res.end(swf);return;}const vars=new URLSearchParams({host:u.searchParams.get('host')??'127.0.0.1',port:u.searchParams.get('port')??String(ep1),timeout:u.searchParams.get('timeout')??'1500'}).toString();res.setHeader('Content-Type','text/html');res.end('<!doctype html><meta charset="utf-8"><title>Socket integration</title><script>window.__probe=null;window.socketProbeDone=s=>window.__probe=s;window.RufflePlayer={config:{autoplay:"on",unmuteOverlay:"hidden",allowScriptAccess:true,preferredRenderer:"canvas",logLevel:"error"}};</script><embed src="/SocketProbe.swf" type="application/x-shockwave-flash" width="400" height="300" allowScriptAccess="always" flashvars="'+vars.replaceAll('&','&amp;')+'">');});
const pagePort=await listen(pageServer),origin='http://127.0.0.1:'+pagePort;
const token=randomBytes(32).toString('hex');
const relay=await createRelay({port:0,token,origins:[origin,'http://localhost:'+pagePort],allowPrivateHosts:['127.0.0.1','localhost','slow.test'],lookup:async(h,o)=>h==='slow.test'?(await delay(600),[{address:'127.0.0.1',family:4}]):dns.lookup(h,o)});cleanup.push(()=>relay.close());
const template='ws://127.0.0.1:'+relay.port+'/connect?host={host}&port={port}&token='+token;
const good=['before=false','after=false','connect=true','byte=0','byte=1','byte=255','byte=42','byte=128','byte=10','close=false','done'].join('\n');
const bad=['before=false','after=false','ioError=2031 connected=false','done'].join('\n');
try{
 chrome=new Chrome(output);const version=await chrome.send('Browser.getVersion');
 const {id}=await chrome.send('Extensions.loadUnpacked',{path:extDir});
 const options=await chrome.tab('chrome-extension://'+id+'/options.html');
 await chrome.wait(options.sessionId,'!!globalThis.chrome?.storage');
 const setStorage=(area,values)=>chrome.eval(options.sessionId,'chrome.storage.'+area+'.set('+JSON.stringify(values)+')');
 const base={autostart:true,autoplay:'on',unmuteOverlay:'hidden',allowScriptAccess:true,preferredRenderer:'canvas',deviceFontRenderer:'canvas'};
 await setStorage('sync',base);
 const settings={enabled:true,mode:'websocket',proxyUrl:template,allowedOrigins:[origin],deniedOrigins:[],defaultsVersion:2};
 if(!legacy){
  // data-state is set only after the options script loaded settings and bound its submit handler.
  await chrome.wait(options.sessionId,'(()=>{const s=document.querySelector("#socket-proxy-status"),b=document.querySelector("#socket-proxy-save");return !!s&&!!s.dataset.state&&!!b&&!b.disabled})()');
  await chrome.eval(options.sessionId,'(()=>{document.querySelector("#socket-proxy-mode-websocket").checked=true;document.querySelector("#socket-proxy-enabled").checked=true;document.querySelector("#socket-proxy-url").value='+JSON.stringify(template)+';document.querySelector("#socket-proxy-origins").value='+JSON.stringify(origin)+';document.querySelector("#socket-proxy-form").requestSubmit();return true})()');
  await chrome.wait(options.sessionId,'(async()=>{const s=(await chrome.storage.local.get("socketProxySettings")).socketProxySettings;return !!s?.enabled})()');
  assert.deepEqual(await chrome.eval(options.sessionId,'(async()=> (await chrome.storage.local.get("socketProxySettings")).socketProxySettings)()'),settings);
  assert.equal(await chrome.eval(options.sessionId,'(async()=>"socketProxySettings" in (await chrome.storage.sync.get()))()'),false);
  assert.equal(await chrome.eval(options.sessionId,'document.querySelector("#socket-proxy-url").type'),'password');
  await chrome.eval(options.sessionId,'document.querySelector("#socket-proxy-url").value="http://invalid/";document.querySelector("#socket-proxy-form").requestSubmit();');
  await chrome.wait(options.sessionId,'document.querySelector("#socket-proxy-status").dataset.state === "error"');
  assert.deepEqual(await chrome.eval(options.sessionId,'(async()=> (await chrome.storage.local.get("socketProxySettings")).socketProxySettings)()'),settings);
  await chrome.eval(options.sessionId,'document.querySelector("#socket-proxy-url").value='+JSON.stringify(template)+';document.querySelector("#socket-proxy-form").requestSubmit();document.querySelector("#socket-proxy-form").scrollIntoView();');
  await delay(200);const shot=await chrome.send('Page.captureScreenshot',{format:'png'},options.sessionId);await fs.writeFile(path.join(output,'proxy-options.png'),Buffer.from(shot.data,'base64'));
  results.push({name:'settings-ui-save-local-masked-validation',pass:true});
 }
 const run=async(name,host,port,timeout=1500,expected=good,pageOrigin=origin)=>{
  if(legacy){const proxyUrl=template.replace('{host}',encodeURIComponent(host)).replace('{port}',String(port));await setStorage('sync',{...base,socketProxy:[{host,port,proxyUrl}]});}
  const {sessionId,targetId}=await chrome.tab(pageOrigin+'/?'+new URLSearchParams({host,port,timeout}));
  const text=await chrome.wait(sessionId,'window.__probe',15000);const clean=text.split('\n').filter(x=>!x.startsWith('~')).join('\n');
  const m=text.match(/~connect_ms=(\d+)/),elapsed=m?+m[1]:null;
  const pass=clean===expected&&(name!=='delayed-open'||elapsed>=500);
  const result={name,pass,elapsed,text};results.push(result);console.log(JSON.stringify(result));
  await fs.writeFile(path.join(output,name+'.txt'),text);await chrome.send('Target.closeTarget',{targetId});return result;
 };
 await run('dynamic-port-one','127.0.0.1',ep1);
 await run('dynamic-port-two','127.0.0.1',ep2);
 await run('dynamic-hostname','localhost',ep1);
 await run('delayed-open','slow.test',ep1,2000);
 await run('refused-no-fake-connect','127.0.0.1',refused,1000,bad);
 await run('timeout-no-fake-connect','slow.test',ep1,250,bad);
 if(!legacy){
  await run('unapproved-origin','127.0.0.1',ep1,1500,bad,'http://localhost:'+pagePort);
  // Exact mappings must win even when a wildcard appears first in the array.
  const wildcard={host:'*',port:0,proxyUrl:template.replace('token='+token,'token=wrong')};
  const exact={host:'127.0.0.1',port:ep1,proxyUrl:template};
  await setStorage('sync',{socketProxy:[wildcard,exact]});
  await run('exact-mapping-priority','127.0.0.1',ep1);
 }
 await fs.writeFile(path.join(output,'results.json'),JSON.stringify({browser:version.product,results},null,2));
 if(!legacy)assert.ok(results.every(x=>x.pass),'Chrome socket tests failed');
} catch(e){console.error(e.message);process.exitCode=1;}
finally{
 if(chrome){const safe=JSON.stringify(chrome.events).replaceAll(token,'[REDACTED]');await fs.writeFile(path.join(output,'events.json'),safe);await chrome.close();await delay(300);await fs.rm(path.join(output,'profile'),{recursive:true,force:true});}
 for(const s of active)s.destroy();for(const fn of cleanup.reverse())await fn();
}
