// Local test-only host. Never included in the delivery package.
import fs from 'node:fs';
const mode=process.argv[2];let buffered=Buffer.alloc(0),timer=null,closing=false;
function send(message){const data=Buffer.from(JSON.stringify(message));const size=Buffer.alloc(4);size.writeUInt32LE(data.length);fs.writeSync(1,Buffer.concat([size,data]));}
process.stdin.on('end',()=>{clearTimeout(timer);process.exit(0)});
process.stdin.on('data',data=>{buffered=Buffer.concat([buffered,data]);while(buffered.length>=4){const size=buffered.readUInt32LE();if(size>1048576)process.exit(2);if(buffered.length<size+4)break;const m=JSON.parse(buffered.subarray(4,size+4));buffered=buffered.subarray(size+4);
 if(m.type==='hello')send({type:'hello',version:mode==='incompatible'?'1.0.0':'1.3.0',protocol:mode==='incompatible'?1:2});
 else if(m.type==='open')timer=setTimeout(()=>send({type:'opened'}),600);
 else if(m.type==='send'){send({type:'sent'});send({type:'data',data:m.data});closing=true;}
 else if(m.type==='ack'&&closing)send({type:'closed'});
 else if(m.type==='close')process.exit(0);
}});
