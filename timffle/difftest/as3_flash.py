#!/usr/bin/env python3
"""Run a Ruffle AS3 regression test (tests/tests/swfs/avm2/<name>/Test.as) in the real
Flash Player 32 (Wine) and collect its trace() lines through the difftest server, so the
test's output.txt can be recorded with Flash (run it twice; the result has no final newline,
add one when it becomes output.txt).

usage: as3probe.py <test-dir> [delay_ms] [timeout_s]

The copy of Test.as gets every `trace(` rewritten to `Report.trace(`; Report.as collects
the lines and POSTs them to the harness `delay_ms` after the first line (default 4000),
then quits the player. Flash's own trace output is not available in the release
projector, which is why the lines go through the harness.
Env: DIFFTEST (difftest dir, with server.py running on DIFFTEST_HTTP_PORT), ASC_JAR (asc.jar
of Ruffle's test tools), PLAYERGLOBAL_ABC (playerglobal_import.abc from ruffle_core's build
OUT_DIR), FLASH_EXE, WINE_DIR, WINEPREFIX (see runner.py). Files next to Test.as other than
.as/.txt/.toml/.swf (for example test.flv) are served from bin/ under the same name.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

test_dir = os.path.abspath(sys.argv[1])
delay = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
timeout = int(sys.argv[3]) if len(sys.argv) > 3 else 60
name = os.path.basename(test_dir.rstrip("/"))
D = os.environ["DIFFTEST"]
port = os.environ.get("DIFFTEST_HTTP_PORT", "18765")
asc = os.environ["ASC_JAR"]
pg = os.environ["PLAYERGLOBAL_ABC"]

REPORT = '''package {
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.net.URLLoader;
    import flash.net.URLRequest;
    import flash.net.URLRequestMethod;
    import flash.system.fscommand;
    import flash.utils.setTimeout;

    public class Report {
        public static const BASE:String = "http://127.0.0.1:%(port)s";
        public static const TEST:String = "%(name)s";
        private static var lines:Array = [];
        private static var started:Boolean = false;
        private static var finished:Boolean = false;

        public static function trace(...args):void {
            lines.push(args.join(" "));
            if (!started) {
                started = true;
                setTimeout(done, %(delay)d);
            }
        }

        public static function done():void {
            if (finished) {
                return;
            }
            finished = true;
            var req:URLRequest = new URLRequest(BASE + "/report?runner=flash&test=" + TEST);
            req.method = URLRequestMethod.POST;
            req.contentType = "text/plain";
            req.data = lines.join("\\n");
            var l:URLLoader = new URLLoader();
            l.addEventListener(Event.COMPLETE, quit);
            l.addEventListener(IOErrorEvent.IO_ERROR, quit);
            l.load(req);
        }

        private static function quit(e:Event):void {
            fscommand("quit");
        }
    }
}
'''

# swf version from test.toml
swf_version = 32
toml = os.path.join(test_dir, "test.toml")
if os.path.exists(toml):
    m = re.search(r"swf_version\s*=\s*(\d+)", open(toml).read())
    if m:
        swf_version = int(m.group(1))

tmp = tempfile.mkdtemp(prefix="as3probe-")
scripts = []
for f in os.listdir(test_dir):
    if f.endswith(".as"):
        src = open(os.path.join(test_dir, f)).read()
        src = re.sub(r"(?<![\w.])trace\(", "Report.trace(", src)
        open(os.path.join(tmp, f), "w").write(src)
        if f != "Test.as":
            scripts.append(f)
open(os.path.join(tmp, "Report.as"), "w").write(REPORT % dict(port=port, name=name, delay=delay))
cmd = ["java", "-jar", asc, "-AS3", "-md", "-import", pg, "-in", "Report.as"]
for s in scripts:
    cmd += ["-in", s]
cmd += ["-swf", "Test,550,400,24", "Test.as"]
r = subprocess.run(cmd, cwd=tmp, capture_output=True, text=True)
if r.returncode != 0 or not os.path.exists(os.path.join(tmp, "Test.swf")):
    print(r.stdout, r.stderr)
    sys.exit("asc failed")
swf = bytearray(open(os.path.join(tmp, "Test.swf"), "rb").read())
swf[3] = swf_version
os.makedirs(os.path.join(D, "bin"), exist_ok=True)
open(os.path.join(D, "bin", name + ".swf"), "wb").write(swf)
# assets the test loads by relative URL (served from bin/ by /t/flash/<file>)
for f in os.listdir(test_dir):
    if not f.endswith((".as", ".txt", ".toml", ".swf")):
        shutil.copy(os.path.join(test_dir, f), os.path.join(D, "bin", f))
shutil.rmtree(tmp)
print("built bin/%s.swf (%d bytes, swf v%d)" % (name, len(swf), swf_version))
r = subprocess.run([sys.executable, os.path.join(D, "runner.py"), "flash", name, str(timeout)])
res = os.path.join(D, "results", "flash", name + ".txt")
if os.path.exists(res):
    print(open(res).read())
else:
    print("NO RESULT")
