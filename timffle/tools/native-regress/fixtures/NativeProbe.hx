import flash.Lib;
import flash.net.Socket;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.external.ExternalInterface;
class NativeProbe {
 static var done=false;
 static var events:Array<String>=[];
 static var read=0;
 static var bad=0;
 static var connectedAt=-1;
 static var began=0;
 static var socket:Socket;
 static function finish(status:String) {
  if(done)return;done=true;
  var result={status:status,events:events,received:read,badBytes:bad,connectMs:connectedAt,elapsed:Lib.getTimer()-began,connected:socket.connected};
  if(ExternalInterface.available) ExternalInterface.call("nativeProbeDone",haxe.Json.stringify(result));
 }
 static function main() {
  var p=Lib.current.loaderInfo.parameters;
  var port=Std.parseInt(p.port),timeout=Std.parseInt(p.timeout),size=Std.parseInt(p.size),cancel=Std.parseInt(p.cancel);
  if(size==null)size=6;
  socket=new Socket();socket.timeout=timeout==null?2000:timeout;
  began=Lib.getTimer();
  socket.addEventListener(Event.CONNECT,function(_) {
   connectedAt=Lib.getTimer()-began;events.push("connect");
   for(i in 0...size)socket.writeByte((i*37+11)&255);
   socket.flush();
  });
  socket.addEventListener(ProgressEvent.SOCKET_DATA,function(_) {
   while(socket.bytesAvailable>0){var v:Int=cast socket.readUnsignedByte();if(v!=((read*37+11)&255))bad++;read++;}
  });
  socket.addEventListener(Event.CLOSE,function(_){events.push("close");finish(read==size&&bad==0?"ok":"closed");});
  socket.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent){events.push("ioError:"+e.errorID);finish("ioError");});
  socket.addEventListener(SecurityErrorEvent.SECURITY_ERROR,function(e:SecurityErrorEvent){events.push("securityError:"+e.errorID);finish("securityError");});
  events.push("before:"+socket.connected);socket.connect(Std.string(p.host),port);events.push("after:"+socket.connected);
  if(cancel!=null&&cancel>=0)haxe.Timer.delay(function(){if(!done){try{socket.close();events.push("local-close");}catch(e:Dynamic){events.push("local-close-error");}haxe.Timer.delay(function(){finish("cancelled");},300);}},cancel);
  haxe.Timer.delay(function(){finish("watchdog");},10000);
 }
}
