import flash.Lib;
import flash.net.Socket;
import flash.events.Event;
import flash.events.IOErrorEvent;
import flash.events.ProgressEvent;
import flash.events.SecurityErrorEvent;
import flash.external.ExternalInterface;
import flash.utils.ByteArray;
class SocketProbe {
 static var lines:Array<String>=[];
 static var done=false;
 static var received=0;
 static function log(s:String){lines.push(s);Lib.trace(s);}
 static function finish(){if(done)return;done=true;log("done");if(ExternalInterface.available)ExternalInterface.call("socketProbeDone",lines.join("\n"));}
 static function main(){
  var p=Lib.current.loaderInfo.parameters;
  var host=Std.string(p.host);var port=Std.parseInt(p.port);var timeout=Std.parseInt(p.timeout);
  var started=flash.Lib.getTimer();
  var s=new Socket();s.timeout=timeout==null?1000:timeout;
  s.addEventListener(Event.CONNECT,function(_){log("~connect_ms="+(flash.Lib.getTimer()-started));log("connect="+s.connected);s.writeByte(0);s.writeByte(1);s.writeByte(255);s.writeByte(42);s.writeByte(128);s.writeByte(10);s.flush();});
  s.addEventListener(ProgressEvent.SOCKET_DATA,function(_){while(s.bytesAvailable>0){log("byte="+s.readUnsignedByte());received++;}});
  s.addEventListener(Event.CLOSE,function(_){log("close="+s.connected);finish();});
  s.addEventListener(IOErrorEvent.IO_ERROR,function(e:IOErrorEvent){log("ioError="+e.errorID+" connected="+s.connected);finish();});
  s.addEventListener(SecurityErrorEvent.SECURITY_ERROR,function(e:SecurityErrorEvent){log("securityError="+e.errorID);finish();});
  log("before="+s.connected);s.connect(host,port);log("after="+s.connected);
  haxe.Timer.delay(function(){if(!done){log("watchdog");finish();}},7000);
 }
}
