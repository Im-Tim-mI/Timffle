// Local-only Timffle WebSocket <-> TCP bridge. Uses ws (MIT) for RFC6455.
// No payload, credentials, query strings, or auth tokens are logged.
import http from 'node:http';
import net from 'node:net';
import dns from 'node:dns/promises';
import { timingSafeEqual, randomBytes } from 'node:crypto';
import { domainToASCII, pathToFileURL } from 'node:url';
import fs from 'node:fs/promises';
import path from 'node:path';
import { WebSocketServer } from './vendor/ws/wrapper.mjs';

const blocked4 = new net.BlockList();
for (const [ip,bits] of [['0.0.0.0',8],['10.0.0.0',8],['100.64.0.0',10],['127.0.0.0',8],['169.254.0.0',16],['172.16.0.0',12],['192.0.0.0',24],['192.0.2.0',24],['192.168.0.0',16],['198.18.0.0',15],['198.51.100.0',24],['203.0.113.0',24],['224.0.0.0',4],['240.0.0.0',4]]) blocked4.addSubnet(ip,bits,'ipv4');
const global6 = new net.BlockList(); global6.addSubnet('2000::',3,'ipv6');
const blocked6 = new net.BlockList();
for (const [ip,bits] of [['2001::',32],['2001:db8::',32],['2002::',16]]) blocked6.addSubnet(ip,bits,'ipv6');
export function isPublicAddress(address) {
 const family=net.isIP(address);
 if(family===4) return !blocked4.check(address,'ipv4');
 if(family===6) return global6.check(address,'ipv6')&&!blocked6.check(address,'ipv6');
 return false;
}
export function normalizeHost(value) {
 if(typeof value!=='string'||!value||value.length>253||/[\s/@?#%\\]/.test(value)) throw new Error('Invalid destination');
 let host=value.toLowerCase();
 if(host.startsWith('[')&&host.endsWith(']')) host=host.slice(1,-1);
 if(net.isIP(host)) return host;
 host=domainToASCII(host).replace(/\.$/,'');
 if(!host||host.length>253||!host.split('.').every(s=>/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(s))) throw new Error('Invalid destination');
 return host;
}
export function normalizeOrigin(value) {
 const u=new URL(value);
 if(!['http:','https:','chrome-extension:'].includes(u.protocol)||u.username||u.password||u.search||u.hash||!u.hostname||(u.pathname&&u.pathname!=='/')) throw new Error('An exact origin is required');
 return u.protocol==='chrome-extension:' ? 'chrome-extension://'+u.hostname : u.origin;
}
function equalToken(a,b) {const x=Buffer.from(a??''),y=Buffer.from(b);return x.length===y.length&&timingSafeEqual(x,y);}
function deny(socket,code) {if(!socket.destroyed) socket.end('HTTP/1.1 '+code+' Rejected\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');}

export async function createRelay({port=18770,token,origins=[],allowPrivateHosts=[],connectTimeoutMs=20000,maxConnections=16,lookup=dns.lookup,connect=net.connect,log=()=>{}}={}) {
 if(typeof token!=='string'||token.length<32) throw new Error('A token of at least 32 characters is required');
 const allowedOrigins=new Set(origins.map(normalizeOrigin));
 if(!allowedOrigins.size) throw new Error('At least one allowed website origin is required');
 const privateHosts=new Set(allowPrivateHosts.map(normalizeHost));
 const wss=new WebSocketServer({noServer:true,perMessageDeflate:false,maxPayload:1024*1024});
 const rawSockets=new Set(), tunnels=new Set(); let seq=0;
 const server=http.createServer((req,res)=>{res.writeHead(404,{'Content-Length':'0','Connection':'close'});res.end();});
 server.on('connection',s=>{rawSockets.add(s);s.on('close',()=>rawSockets.delete(s));s.on('error',()=>{});});
 server.on('clientError',(_e,s)=>deny(s,400));
 server.on('upgrade',async(req,socket,head)=>{
  socket.on('error',()=>{});
  let targetHost,targetPort;
  try {
   const bound=server.address().port;
   if(!['127.0.0.1:'+bound,'localhost:'+bound].includes(req.headers.host)) return deny(socket,403);
   const origin=req.headers.origin;
   if(typeof origin!=='string'||!allowedOrigins.has(origin)) return deny(socket,403);
   const u=new URL(req.url,'http://127.0.0.1');
   if(u.pathname!=='/connect'||[...u.searchParams.keys()].some(k=>!['host','port','token'].includes(k))||['host','port','token'].some(k=>u.searchParams.getAll(k).length!==1)) return deny(socket,400);
   if(!equalToken(u.searchParams.get('token'),token)) return deny(socket,401);
   targetHost=normalizeHost(u.searchParams.get('host'));
   const p=u.searchParams.get('port');
   if(!/^[0-9]{1,5}$/.test(p)||+p<1||+p>65535) return deny(socket,400);
   targetPort=+p;
   if(req.method!=='GET'||req.headers.upgrade?.toLowerCase()!=='websocket'||req.headers['sec-websocket-version']!=='13'||!(/^[+/0-9A-Za-z]{22}==$/.test(req.headers['sec-websocket-key']??''))) return deny(socket,400);
  }catch{return deny(socket,400);}
  if(tunnels.size>=maxConnections)return deny(socket,503);
  const id=++seq, tunnel={socket,tcp:null,ws:null,done:false,timer:null};tunnels.add(tunnel);
  const finish=()=>{if(tunnel.done)return;tunnel.done=true;clearTimeout(tunnel.timer);tunnels.delete(tunnel);tunnel.tcp?.destroy();};
  const reject=(code)=>{if(tunnel.done)return;deny(socket,code);finish();log({id,event:'rejected',code});};
  socket.once('close',()=>{finish();tunnel.ws?.terminate();});
  tunnel.timer=setTimeout(()=>reject(504),connectTimeoutMs);
  try {
   const addresses=net.isIP(targetHost)?[{address:targetHost,family:net.isIP(targetHost)}]:await lookup(targetHost,{all:true,verbatim:true});
   if(tunnel.done)return;
   if(!addresses.length||(!privateHosts.has(targetHost)&&addresses.some(a=>!isPublicAddress(a.address))))return reject(403);
   // Pin a validated DNS result. Never resolve the hostname again when connecting.
   const address=addresses[0];
   const tcp=connect({host:address.address,family:address.family,port:targetPort});tunnel.tcp=tcp;tcp.pause();tcp.setNoDelay(true);
   tcp.once('error',()=>{if(!tunnel.ws)reject(502);else tunnel.ws.close(1011,'TCP error');});
   tcp.once('close',()=>{if(!tunnel.ws)reject(502);else tunnel.ws.close(1000,'TCP closed');});
   tcp.once('connect',()=>{
    if(tunnel.done){tcp.destroy();return;}
    clearTimeout(tunnel.timer);
    // Critical: no WebSocket OPEN/101 until the destination TCP connect succeeds.
    try {wss.handleUpgrade(req,socket,head,ws=>{
     tunnel.ws=ws;let alive=true;
     const heartbeat=setInterval(()=>{if(!alive){ws.terminate();return;}alive=false;ws.ping();},30000);heartbeat.unref();
     ws.on('pong',()=>{alive=true;});
     ws.on('error',()=>{ws.terminate();finish();});
     ws.on('close',()=>{clearInterval(heartbeat);finish();log({id,event:'closed'});});
     ws.on('message',(data,isBinary)=>{if(!isBinary){ws.close(1003,'Binary frames required');return;}if(!tcp.write(data))ws.pause();});
     tcp.on('drain',()=>{if(ws.readyState===ws.OPEN)ws.resume();});
     tcp.on('data',data=>{tcp.pause();if(ws.readyState===ws.OPEN)ws.send(data,{binary:true},err=>{if(err){ws.terminate();finish();}else tcp.resume();});});
     log({id,event:'connected',host:targetHost,port:targetPort});tcp.resume();
    });}catch{reject(400);}
   });
  }catch{reject(502);}
 });
 await new Promise((resolve,reject)=>{server.once('error',reject);server.listen(port,'127.0.0.1',resolve);});
 return {port:server.address().port, async close(){for(const t of tunnels){t.ws?.terminate();t.tcp?.destroy();clearTimeout(t.timer);}for(const s of rawSockets)s.destroy();await new Promise(r=>server.close(r));wss.close();}};
}

async function main(){
 const args=process.argv.slice(2);let port=18770,configFile=path.resolve('connection.json'),newToken=false;const origins=[],allowPrivateHosts=[];
 for(let i=0;i<args.length;i++){switch(args[i]){case '--port':port=Number(args[++i]);break;case '--origin':origins.push(args[++i]);break;case '--allow-private-host':allowPrivateHosts.push(args[++i]);break;case '--config':configFile=path.resolve(args[++i]);break;case '--new-token':newToken=true;break;case '--help':console.log('node relay.mjs --origin http://mole.61.com.tw [--origin https://another.example] [--port 18770] [--config connection.json] [--new-token]\nOptional private destination only: --allow-private-host exact-host\nThe token in the config file is reused on later starts; --new-token replaces it.\nStop: Ctrl+C. Settings/token are in the protected local config file; do not share it.');return;default:throw new Error('Unknown option');}}
 if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Invalid listen port');
 // Reuse the saved token so the extension settings only need to be entered once.
 let token,savedUrl;
 if(!newToken){try{const saved=JSON.parse(await fs.readFile(configFile,'utf8'));const t=new URL(saved.proxyUrl.replace('{host}','h').replace('{port}','1')).searchParams.get('token');if(/^[0-9a-f]{64}$/.test(t??'')){token=t;savedUrl=saved.proxyUrl;}}catch{}}
 token??=randomBytes(32).toString('hex');
 const relay=await createRelay({port,token,origins,allowPrivateHosts,log:event=>console.log(JSON.stringify(event))});
 const config={enabled:true,proxyUrl:'ws://127.0.0.1:'+relay.port+'/connect?host={host}&port={port}&token='+token,allowedOrigins:origins.map(normalizeOrigin)};
 try{await fs.writeFile(configFile,JSON.stringify(config,null,2)+'\n',{mode:0o600});await fs.chmod(configFile,0o600);}catch(e){await relay.close();throw e;}
 console.log('Timffle local bridge listening on 127.0.0.1:'+relay.port);console.log('Extension settings: '+configFile);
 console.log(savedUrl===config.proxyUrl?'Proxy URL unchanged: extension settings saved earlier still work.':'New proxy URL: paste proxyUrl from the settings file into the extension options.');
 console.log('No packet contents are recorded. Keep this terminal running.');
 const stop=async()=>{await relay.close();process.exit(0);};process.once('SIGINT',stop);process.once('SIGTERM',stop);
}
if(process.argv[1]&&import.meta.url===pathToFileURL(path.resolve(process.argv[1])).href)main().catch(()=>{console.error('Cannot start relay: check options, allowed origins, listen port and config directory.');process.exitCode=1;});
