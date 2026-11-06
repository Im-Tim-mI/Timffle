package flash.display {
    import flash.events.EventDispatcher;

    // Timffle: real ShaderJob. `start(true)` runs the shader at once; `start(false)` queues it
    // and the result is written to `target` and `complete` dispatched after the current script
    // turn (still before the next frame, as measured on Flash Player 32). The shader's
    // parameters and inputs are copied when `start()` is called, so later changes do not reach
    // a queued job (Flash copies the Shader internally). A job can be started once: a second
    // `start()` throws ArgumentError #2172 even after it finished or was cancelled; `cancel()`
    // drops a queued job (no `complete`) and sets `progress` to 0.
    [API("662")]
    public class ShaderJob extends EventDispatcher {
        [Ruffle(NativeAccessible)]
        private var _shader:Shader;

        [Ruffle(NativeAccessible)]
        private var _target:Object;

        [Ruffle(NativeAccessible)]
        private var _width:int;

        [Ruffle(NativeAccessible)]
        private var _height:int;

        // Timffle: 0 = never started, 1 = queued or running, 2 = finished, 3 = cancelled.
        [Ruffle(NativeAccessible)]
        private var _state:int = 0;

        // Timffle: NaN before the first start(), 0 while queued (and after cancel()), 1 when done.
        [Ruffle(NativeAccessible)]
        private var _progress:Number = NaN;

        public function ShaderJob(shader:Shader = null, target:Object = null, width:int = 0, height:int = 0) {
            this._shader = shader;
            this._target = target;
            this._width = width;
            this._height = height;
        }

        public function cancel():void {
            if (this._state == 1) {
                this._state = 3;
            }
            this._progress = 0;
        }

        public native function start(waitForCompletion:Boolean = false):void;

        public function get height():int {
            return this._height;
        }

        public function set height(value:int):void {
            this._height = value;
        }

        public function get width():int {
            return this._width;
        }

        public function set width(value:int):void {
            this._width = value;
        }

        public function get progress():Number {
            return this._progress;
        }

        public function get shader():Shader {
            return this._shader;
        }

        public function set shader(value:Shader):void {
            this._shader = value;
        }

        public function get target():Object {
            return this._target;
        }

        public function set target(value:Object):void {
            this._target = value;
        }
    }
}
