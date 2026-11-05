package {
    import flash.concurrent.Condition;
    import flash.concurrent.Mutex;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.system.MessageChannel;
    import flash.system.MessageChannelState;
    import flash.system.Worker;
    import flash.system.WorkerDomain;
    import flash.system.WorkerState;
    import flash.utils.ByteArray;
    import flash.utils.getQualifiedClassName;
    import flash.utils.getTimer;

    public class Test extends Sprite {
        private static function tryCall(name:String, fn:Function):void {
            try {
                fn();
                trace(name + ": no error");
            } catch (e:Error) {
                trace(name + ": " + getQualifiedClassName(e) + " " + e.message + " (" + e.errorID + ")");
            }
        }

        public function Test() {
            trace("// Worker / WorkerDomain");
            trace("Worker.isSupported: " + Worker.isSupported);
            trace("WorkerDomain.isSupported: " + WorkerDomain.isSupported);
            var worker:Worker = Worker.current;
            trace("Worker.current: " + worker);
            trace("Worker.current same object: " + (Worker.current == worker));
            trace("isPrimordial: " + worker.isPrimordial);
            trace("state: " + worker.state + " (" + (worker.state == WorkerState.RUNNING) + ")");
            trace("WorkerDomain.current: " + WorkerDomain.current);
            trace("WorkerDomain.current same object: " + (WorkerDomain.current == WorkerDomain.current));
            var workers:Vector.<Worker> = WorkerDomain.current.listWorkers();
            trace("listWorkers: " + workers.length + " " + (workers[0] == worker) + " fixed=" + workers.fixed);
            tryCall("createWorker(null)", function():void { WorkerDomain.current.createWorker(null); });
            trace("createWorker(bytes): " + WorkerDomain.current.createWorker(new ByteArray()));
            trace("createWorker(bytes, true): " + WorkerDomain.current.createWorker(new ByteArray(), true));
            tryCall("start()", function():void { worker.start(); });
            tryCall("terminate()", function():void { worker.terminate(); });
            var listener:Function = function(e:Event):void { trace("workerState"); };
            worker.addEventListener(Event.WORKER_STATE, listener);
            worker.removeEventListener(Event.WORKER_STATE, listener);
            trace("add/removeEventListener: no error");

            trace("// shared properties");
            tryCall("setSharedProperty(null, 1)", function():void { worker.setSharedProperty(null, 1); });
            tryCall("getSharedProperty(null)", function():void { worker.getSharedProperty(null); });
            trace("missing: " + worker.getSharedProperty("missing"));
            worker.setSharedProperty("n", 5);
            trace("n: " + worker.getSharedProperty("n"));
            worker.setSharedProperty("s", "text");
            trace("s: " + worker.getSharedProperty("s"));
            var original:Object = { a: 1, b: [1, 2] };
            worker.setSharedProperty("o", original);
            var copy:Object = worker.getSharedProperty("o");
            trace("o copied: " + (copy != original) + " a=" + copy.a + " b=" + copy.b);
            trace("o same copy twice: " + (worker.getSharedProperty("o") == copy));
            var mutex:Mutex = new Mutex();
            worker.setSharedProperty("m", mutex);
            trace("mutex by reference: " + (worker.getSharedProperty("m") == mutex));
            worker.setSharedProperty("w", worker);
            trace("worker by reference: " + (worker.getSharedProperty("w") == worker));
            worker.setSharedProperty("o", null);
            trace("o after null: " + worker.getSharedProperty("o"));
            worker.setSharedProperty("n", undefined);
            trace("n after undefined: " + worker.getSharedProperty("n"));

            trace("// MessageChannel");
            tryCall("createMessageChannel(null)", function():void { worker.createMessageChannel(null); });
            var channel:MessageChannel = worker.createMessageChannel(worker);
            trace("channel: " + channel + " / " + getQualifiedClassName(channel));
            trace("state: " + channel.state + " messageAvailable: " + channel.messageAvailable);
            channel.addEventListener(Event.CHANNEL_MESSAGE, function(e:Event):void {
                trace("channelMessage: available=" + channel.messageAvailable + " state=" + channel.state);
            });
            channel.addEventListener(Event.CHANNEL_STATE, function(e:Event):void {
                trace("channelState: " + channel.state);
            });
            channel.send({ x: 1 });
            channel.send("two");
            trace("after send: messageAvailable=" + channel.messageAvailable);
            trace("receive: x=" + channel.receive().x);
            tryCall("send over queueLimit", function():void { channel.send("three", 1); });
            trace("receive: " + channel.receive());
            trace("receive empty: " + channel.receive());
            trace("receive(false) empty: " + channel.receive(false));
            tryCall("receive(true) empty", function():void { channel.receive(true); });
            channel.send("late");
            trace("close with a queued message");
            channel.close();
            trace("state: " + channel.state);
            tryCall("send after close", function():void { channel.send("x"); });
            trace("receive after close: " + channel.receive());
            trace("state: " + channel.state);
            tryCall("receive when closed", function():void { channel.receive(); });
            tryCall("send when closed", function():void { channel.send("x"); });
            channel.close();
            trace("close again: no event");
            var empty:MessageChannel = worker.createMessageChannel(worker);
            empty.addEventListener(Event.CHANNEL_STATE, function(e:Event):void {
                trace("empty channelState: " + empty.state);
            });
            empty.close();
            trace("empty state: " + empty.state);

            trace("// Mutex");
            trace("Mutex.isSupported: " + Mutex.isSupported);
            tryCall("unlock without lock", function():void { mutex.unlock(); });
            mutex.lock();
            mutex.lock();
            trace("tryLock while owned: " + mutex.tryLock());
            mutex.unlock();
            mutex.unlock();
            mutex.unlock();
            tryCall("unlock fourth time", function():void { mutex.unlock(); });
            trace("tryLock fresh: " + mutex.tryLock());
            mutex.unlock();

            trace("// Condition");
            trace("Condition.isSupported: " + Condition.isSupported);
            tryCall("new Condition(null)", function():void { new Condition(null); });
            var condition:Condition = new Condition(mutex);
            trace("condition.mutex: " + (condition.mutex == mutex));
            tryCall("notify() unowned", function():void { condition.notify(); });
            tryCall("notifyAll() unowned", function():void { condition.notifyAll(); });
            tryCall("wait() unowned", function():void { condition.wait(); });
            mutex.lock();
            mutex.lock();
            tryCall("notify() owned", function():void { condition.notify(); });
            tryCall("notifyAll() owned", function():void { condition.notifyAll(); });
            tryCall("wait(-2)", function():void { condition.wait(-2); });
            tryCall("wait()", function():void { condition.wait(); });
            tryCall("wait(-1)", function():void { condition.wait(-1); });
            tryCall("wait(15000)", function():void { condition.wait(15000); });
            var start:int = getTimer();
            var elapsed:Boolean = condition.wait(5);
            trace("wait(5): " + elapsed + " took>=5ms: " + (getTimer() - start >= 5));
            trace("wait(0): " + condition.wait(0));
            mutex.unlock();
            mutex.unlock();
            tryCall("unlock after wait (lock depth restored)", function():void { mutex.unlock(); });
        }
    }
}
