package flash.system {
    import flash.errors.ScriptTimeoutError;
    import flash.events.Event;
    import flash.events.EventDispatcher;
    import flash.utils.setTimeout;

    // Timffle: a one-way message queue between two workers. Only the
    // primordial worker exists here (see Worker.as), so every channel
    // `Worker.current.createMessageChannel(...)` makes runs from the
    // primordial worker to itself, which Flash allows; the queue, the states
    // and the events behave as documented. `send()` copies the message (AMF3,
    // the shareable types by reference — Worker.copyForTransfer), queues it,
    // and the receiver gets one `channelMessage` per message on the next
    // event-loop turn (Flash delivers it on the receiving worker's loop,
    // never inside `send()`). `receive()` returns the oldest message, or
    // null when the queue is empty. `close()` switches the channel to
    // "closing" (a `channelState` event) and to "closed" (another one) once
    // the queue has been drained — at once when it is already empty.
    // `send()` or `receive()` on a closed channel: `Error #3738:
    // MessageChannel is closed.`; the "not a sender"/"not a receiver" errors
    // (#3736/#3737) cannot arise with one worker. Waiting — `receive(true)`
    // on an empty queue, `send()` with the queue at `queueLimit` — would
    // pause the primordial worker until a worker that can never exist acts;
    // in Flash that ends in `ScriptTimeoutError #1502` once the 15-second
    // script limit passes, and this player throws it at once instead of
    // freezing the page for 15 seconds first.
    [API("682")]
    [Ruffle(Abstract)]
    public final class MessageChannel extends EventDispatcher {
        private var _sender:Worker;
        private var _receiver:Worker;
        private var _queue:Array;
        private var _state:String;

        // Objects of this class are made by Worker.createMessageChannel (the
        // class is abstract, so no field initializer runs): set up here.
        internal function init(sender:Worker, receiver:Worker):void {
            this._sender = sender;
            this._receiver = receiver;
            this._queue = [];
            this._state = MessageChannelState.OPEN;
        }

        private static function closedError():Error {
            return new Error("Error #3738: MessageChannel is closed.", 3738);
        }

        private static function timeoutError():ScriptTimeoutError {
            return new ScriptTimeoutError("Error #1502: A script has executed for longer than the default timeout period of 15 seconds.", 1502);
        }

        public function get messageAvailable():Boolean {
            return this._queue != null && this._queue.length > 0;
        }

        public function get state():String {
            return this._state == null ? MessageChannelState.OPEN : this._state;
        }

        override public function addEventListener(type:String, listener:Function, useCapture:Boolean = false, priority:int = 0, useWeakReference:Boolean = false):void {
            super.addEventListener(type, listener, useCapture, priority, useWeakReference);
        }

        override public function removeEventListener(type:String, listener:Function, useCapture:Boolean = false):void {
            super.removeEventListener(type, listener, useCapture);
        }

        public function send(arg:*, queueLimit:int = -1):void {
            if (this.state != MessageChannelState.OPEN) {
                throw closedError();
            }
            if (queueLimit >= 0 && this._queue.length >= queueLimit) {
                throw timeoutError();
            }
            this._queue.push(Worker.copyForTransfer(arg));
            var self:MessageChannel = this;
            setTimeout(function():void {
                self.dispatchEvent(new Event(Event.CHANNEL_MESSAGE));
            }, 0);
        }

        public function receive(blockUntilReceived:Boolean = false):* {
            if (this.state == MessageChannelState.CLOSED) {
                throw closedError();
            }
            if (this._queue.length == 0) {
                if (blockUntilReceived && this.state == MessageChannelState.OPEN) {
                    throw timeoutError();
                }
                return null;
            }
            var message:* = this._queue.shift();
            if (this.state == MessageChannelState.CLOSING && this._queue.length == 0) {
                this.setState(MessageChannelState.CLOSED);
            }
            return message;
        }

        public function close():void {
            if (this.state != MessageChannelState.OPEN) {
                return;
            }
            this.setState(MessageChannelState.CLOSING);
            if (this._queue.length == 0) {
                this.setState(MessageChannelState.CLOSED);
            }
        }

        private function setState(state:String):void {
            this._state = state;
            this.dispatchEvent(new Event(Event.CHANNEL_STATE));
        }

        override public function toString():String {
            return "[object MessageChannel]";
        }
    }
}
