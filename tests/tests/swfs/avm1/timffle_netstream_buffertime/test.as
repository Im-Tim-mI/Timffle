// Timffle: NetStream.bufferTime of a connect(null) stream in AVM1, recorded with the
// real Flash Player 32: 0 until set, values below 0.1 (negative ones too) become 0.1,
// NaN becomes 4294967.295, and play() turns 0 into 0.1.
var nc = new NetConnection();
nc.connect(null);
var ns = new NetStream(nc);
trace("default bufferTime " + ns.bufferTime);
ns.setBufferTime(0.5); trace("setBufferTime(0.5) -> " + ns.bufferTime);
ns.setBufferTime(NaN); trace("setBufferTime(NaN) -> " + ns.bufferTime);
ns.setBufferTime(0); trace("setBufferTime(0) -> " + ns.bufferTime);
ns.setBufferTime(0.05); trace("setBufferTime(0.05) -> " + ns.bufferTime);
ns.setBufferTime(-1); trace("setBufferTime(-1) -> " + ns.bufferTime);
var ns2 = new NetStream(nc);
ns2.play("test.flv");
trace("after play " + ns2.bufferTime);
ns2.close();
