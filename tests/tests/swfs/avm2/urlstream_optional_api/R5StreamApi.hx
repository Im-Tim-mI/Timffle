import flash.net.URLStream;
class R5StreamApi {
 static function main() {
  Out.start("r5stream_api"); var s:Dynamic=new URLStream();
  for(f in [function(){Out.line("position="+s.position+" length="+s.length);},function(){s.stop();Out.line("stop ok");},function(){s.position=5;Out.line("position="+s.position);},function(){s.position=-1;Out.line("negative="+s.position);}]) {
   try { f(); } catch(e:flash.errors.Error) {Out.line("error="+e.errorID);}
  }
  var lc:Dynamic=new flash.net.LocalConnection();
  Out.line("perUser="+lc.isPerUser); lc.isPerUser=true; Out.line("perUser="+lc.isPerUser);
  Out.finish();
 }
}
