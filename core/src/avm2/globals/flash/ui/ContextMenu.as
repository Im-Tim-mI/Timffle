package flash.ui {
    import flash.display.NativeMenu;
    import flash.net.URLRequest;

    public final class ContextMenu extends NativeMenu {
        [Ruffle(NativeAccessible)]
        private var _customItems:Array;

        private var _clipboardMenu:Boolean;

        [Ruffle(NativeAccessible)]
        private var _builtInItems:ContextMenuBuiltInItems = new ContextMenuBuiltInItems();

        private var _clipboardItems:ContextMenuClipboardItems = new ContextMenuClipboardItems();

        // Timffle: the `link` of the menu (`URLRequest`); when set, Flash shows the link
        // context menu for the object instead of the normal one. Stored here; the player's
        // native menu does not yet add the link items (see CHANGES-FROM-RUFFLE).
        private var _link:URLRequest = null;

        public function ContextMenu() {
            super();
            this.customItems = new Array();
        }

        public function get customItems():Array {
            return this._customItems;
        }

        public function set customItems(value:Array):void {
            this._customItems = value;
        }

        public function hideBuiltInItems():void {
            if (this._builtInItems) {
                this._builtInItems.forwardAndBack = false;
                this._builtInItems.loop = false;
                this._builtInItems.play = false;
                this._builtInItems.print = false;
                this._builtInItems.quality = false;
                this._builtInItems.rewind = false;
                this._builtInItems.save = false;
                this._builtInItems.zoom = false;
            }
        }

        public function get builtInItems():ContextMenuBuiltInItems {
            return this._builtInItems;
        }

        public function set builtInItems(value:ContextMenuBuiltInItems):void {
            this._builtInItems = value;
        }

        public function get clipboardItems():ContextMenuClipboardItems {
            return this._clipboardItems;
        }

        public function set clipboardItems(value:ContextMenuClipboardItems):void {
            this._clipboardItems = value;
        }

        public function get clipboardMenu():Boolean {
            return this._clipboardMenu;
        }

        public function set clipboardMenu(value:Boolean):void {
            this._clipboardMenu = value;
        }

        public function get link():URLRequest {
            return this._link;
        }

        public function set link(value:URLRequest):void {
            this._link = value;
        }

        // Timffle: "a copy of the specified ContextMenu object; the copy inherits all the
        // properties of the original": the custom items are cloned one by one (a new Array
        // of new ContextMenuItems, so editing the copy leaves the original alone), the
        // built-in and clipboard item sets are cloned, the clipboardMenu flag and the link
        // are carried over.
        [API("668")]
        override public function clone():NativeMenu {
            var menu:ContextMenu = new ContextMenu();
            var items:Array = new Array();
            if (this._customItems != null) {
                for (var i:int = 0; i < this._customItems.length; i++) {
                    var item:ContextMenuItem = this._customItems[i];
                    items.push(item != null ? item.clone() : null);
                }
            }
            menu.customItems = items;
            menu.builtInItems = this._builtInItems != null ? this._builtInItems.clone() : null;
            menu.clipboardItems = this._clipboardItems != null ? this._clipboardItems.clone() : null;
            menu.clipboardMenu = this._clipboardMenu;
            menu.link = this._link;
            return menu;
        }

        // Timffle: this player always shows a context menu for the SWF (Player::prepare_context_menu
        // builds it for every frontend: the desktop and web players render it, like desktop
        // Flash Player and the browser plug-in), so the class is supported.
        public static function get isSupported():Boolean {
            return true;
        }
    }
}
