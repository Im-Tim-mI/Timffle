// Timffle: when AVM1 downloads (LoadVars, XML, MovieClipLoader, loadMovie) are
// answered: a request made in the root's first frame after frame 1, one made in a
// later frame after that frame. output.txt was recorded with the real Flash Player 32
// (twice, same output). Sound.loadSound is synchronous on this platform.
var AT = 2;
var f = 0;
function lg(s) { trace("  " + s + " (f=" + f + ")"); }
_root.onEnterFrame = function() { f++; trace("enterFrame " + f); if (f == AT) go("f" + f); };
function go(w) {
  trace("go " + w);
  var lv = new LoadVars(); lv.onData = function(s) { lg("lv onData"); }; lv.load("a.txt");
  var x = new XML(); x.onData = function(s) { lg("xml onData"); }; x.load("a.txt");
  var mcl = new MovieClipLoader(); var l = {};
  l.onLoadStart = function() { lg("mcl start"); };
  l.onLoadComplete = function() { lg("mcl complete"); };
  l.onLoadInit = function() { lg("mcl init"); };
  mcl.addListener(l);
  var h = _root.createEmptyMovieClip("h" + f, 10 + f);
  mcl.loadClip("b.swf", h);
  var h2 = _root.createEmptyMovieClip("g" + f, 30 + f);
  h2.loadMovie("b.swf");
  var s = new Sound(); s.onLoad = function(ok) { lg("snd onLoad " + ok); }; s.loadSound("a.mp3", false);
  trace("go done");
}
if (AT == 0) go("f0");
