import flash.net.URLStream;
import flash.net.LocalConnection;
class R3StreamState {
 static function main() {
  Out.start("r3stream_state");
  var s = new URLStream();
  Out.line("connected=" + s.connected + " endian=" + s.endian + " encoding=" + s.objectEncoding);
  for (f in [function() { var n=s.bytesAvailable; }, function() { s.readByte(); }, function() { s.close(); }]) {
   try { f(); Out.line("accepted"); } catch(e:flash.errors.Error) { Out.line("error=" + e.errorID); }
  }
  var lc = new LocalConnection();
  for (f in [function() { lc.connect(""); }, function() { lc.send("x", ""); }]) {
   try { f(); Out.line("accepted"); } catch(e:flash.errors.Error) { Out.line("error=" + e.errorID); }
  }
  var e=new flash.events.AsyncErrorEvent("asyncError",false,false,"",new flash.errors.Error("x",42));
  Out.line("asyncErrorID=" + e.errorID);
  Out.line("done"); Out.finish();
 }
}
