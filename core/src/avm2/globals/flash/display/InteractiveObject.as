package flash.display {
    import flash.accessibility.AccessibilityImplementation;
    import flash.geom.Rectangle;
    import flash.ui.ContextMenu;

    [Ruffle(Abstract)]
    public class InteractiveObject extends DisplayObject {
        private var _accessibilityImpl:AccessibilityImplementation = null;
        private var _needsSoftKeyboard:Boolean = false;
        private var _softKeyboardInputAreaOfInterest:Rectangle = null;

        // Timffle: the player has no screen-reader bridge (Capabilities.hasAccessibility is
        // false), so like Flash Player on such a machine the implementation is kept but never
        // consulted.
        public function get accessibilityImplementation():AccessibilityImplementation {
            return this._accessibilityImpl;
        }
        public function set accessibilityImplementation(value:AccessibilityImplementation):void {
            this._accessibilityImpl = value;
        }

        public native function get mouseEnabled():Boolean;
        public native function set mouseEnabled(value:Boolean):void;

        // Timffle: soft-keyboard members behave like Flash Player on a machine without a
        // virtual keyboard (measured on Flash Player 32): the flag and the rectangle are
        // stored as given (same Rectangle object comes back), requestSoftKeyboard() moves the
        // focus to the object when needsSoftKeyboard is true and always returns false because
        // no keyboard is raised.
        [API("670")]
        public function get needsSoftKeyboard():Boolean {
            return this._needsSoftKeyboard;
        }
        [API("670")]
        public function set needsSoftKeyboard(value:Boolean):void {
            this._needsSoftKeyboard = value;
        }

        [API("670")]
        public function requestSoftKeyboard():Boolean {
            if (this._needsSoftKeyboard && this.stage) {
                this.stage.focus = this;
            }
            return false;
        }

        [API("670")]
        public function get softKeyboardInputAreaOfInterest():Rectangle {
            return this._softKeyboardInputAreaOfInterest;
        }
        [API("670")]
        public function set softKeyboardInputAreaOfInterest(value:Rectangle):void {
            this._softKeyboardInputAreaOfInterest = value;
        }

        public native function get doubleClickEnabled():Boolean;
        public native function set doubleClickEnabled(value:Boolean):void;

        public native function get contextMenu():ContextMenu;
        public native function set contextMenu(cm:ContextMenu):void;

        public native function get tabEnabled():Boolean;
        public native function set tabEnabled(value:Boolean):void;

        public native function get tabIndex():int;
        public native function set tabIndex(index:int):void;

        public native function get focusRect():Object;
        public native function set focusRect(value:Object):void;
    }
}
