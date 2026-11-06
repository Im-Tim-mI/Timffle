package flash.system {
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
    // "closing" at once and to "closed" once the queue has been drained (at
    // once when it is already empty); one `channelState` event follows on
    // the next event-loop turn, after the pending `channelMessage` events
    // (Flash Player 32, measured). `send()` on a closing or closed channel and
    // `receive()` on a closed one: `Error #3738: MessageChannel is closed.`;
    // the "not a sender"/"not a receiver" errors (#3736/#3737) cannot arise
    // with one worker. Measured on Flash's primordial worker talking to
    // itself: `receive(true)` on an empty queue freezes for the 15-second
    // script limit and then returns null (this player returns null at once),
    // and `send()` with the queue already at `queueLimit` returns at once
    // without queueing the message.
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
                return;
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
                return null;
            }
            var message:* = this._queue.shift();
            if (this.state == MessageChannelState.CLOSING && this._queue.length == 0) {
                this._state = MessageChannelState.CLOSED;
            }
            return message;
        }

        public function close():void {
            if (this.state != MessageChannelState.OPEN) {
                return;
            }
            this._state = this._queue.length == 0 ? MessageChannelState.CLOSED : MessageChannelState.CLOSING;
            var self:MessageChannel = this;
            setTimeout(function():void {
                self.dispatchEvent(new Event(Event.CHANNEL_STATE));
            }, 0);
        }

        override public function toString():String {
            return "[object MessageChannel]";
        }
    }
}
