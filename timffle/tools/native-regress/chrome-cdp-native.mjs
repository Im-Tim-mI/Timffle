import {spawn} from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
export const delay=ms=>new Promise(r=>setTimeout(r,ms));
export class Chrome {
 constructor(workdir,{recordEvents=true,fontConfig,userDataDir}={}){
  this.recordEvents=recordEvents;
  fs.mkdirSync(workdir,{recursive:true});this.next=0;this.pending=new Map();this.events=[];this.buf=Buffer.alloc(0);
  this.process=spawn('google-chrome',[...(process.env.CHROME_HEADED?[]:['--headless=new']),'--remote-debugging-pipe','--enable-unsafe-extension-debugging','--user-data-dir='+(userDataDir??path.join(workdir,'profile')),'--no-first-run','--no-default-browser-check','--disable-background-networking','--disable-component-update','--disable-sync','--disable-dev-shm-usage','--use-angle=swiftshader','--enable-unsafe-swiftshader',...(process.env.CHROME_WINDOW_SIZE==='none'?[]:['--window-size='+(process.env.CHROME_WINDOW_SIZE||'1280,900')]),'about:blank'],{env:fontConfig?{...process.env,FONTCONFIG_FILE:fontConfig}:process.env,stdio:['ignore','ignore',fs.openSync(path.join(workdir,'chrome-stderr.log'),'w'),'pipe','pipe']});
  this.process.stdio[4].on('data',d=>{this.buf=Buffer.concat([this.buf,d]);let i;while((i=this.buf.indexOf(0))!==-1){const m=JSON.parse(this.buf.subarray(0,i).toString());this.buf=this.buf.subarray(i+1);if(m.id){const p=this.pending.get(m.id);if(p){clearTimeout(p.timer);this.pending.delete(m.id);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);}}else if(this.recordEvents) this.events.push(m);}});
 }
 send(method,params={},sessionId){return new Promise((resolve,reject)=>{const id=++this.next;const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('Timeout '+method));},45000);this.pending.set(id,{resolve,reject,timer});this.process.stdio[3].write(JSON.stringify({id,method,params,...(sessionId?{sessionId}:{})})+'\0');});}
 async eval(s,expression){const r=await this.send('Runtime.evaluate',{expression,returnByValue:true,awaitPromise:true},s);if(r.exceptionDetails)throw new Error(r.exceptionDetails.text);return r.result?.value;}
 async tab(url){const {targetId}=await this.send('Target.createTarget',{url:'about:blank'});const {sessionId}=await this.send('Target.attachToTarget',{targetId,flatten:true});await this.send('Page.enable',{},sessionId);await this.send('Runtime.enable',{},sessionId);await this.send('Log.enable',{},sessionId);await this.send('Page.navigate',{url},sessionId);await this.send('Page.bringToFront',{},sessionId);return {targetId,sessionId};}
 async wait(s,fn,ms=15000){const end=Date.now()+ms;while(Date.now()<end){try{const r=await this.eval(s,fn);if(r)return r;}catch{}await delay(120);}throw new Error('Page condition timeout');}
 async close(){try{await this.send('Browser.close');}catch{this.process.kill();}}
}
