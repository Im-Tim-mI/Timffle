package flash.text.engine {
    import flash.events.EventDispatcher;
    import flash.geom.Rectangle;

    // Timffle: real class. Regions are built by `TextLine.mirrorRegions` from
    // the content elements of the line that have an `eventMirror`; they are
    // read-only in Flash Player, so the fields are filled by the engine only.
    [API("662")]
    public final class TextLineMirrorRegion {
        internal var _bounds:Rectangle;
        internal var _element:ContentElement;
        internal var _mirror:EventDispatcher;
        internal var _nextRegion:TextLineMirrorRegion;
        internal var _previousRegion:TextLineMirrorRegion;
        internal var _textLine:TextLine;

        public function get bounds():Rectangle {
            return this._bounds;
        }

        public function get element():ContentElement {
            return this._element;
        }

        public function get mirror():EventDispatcher {
            return this._mirror;
        }

        public function get nextRegion():TextLineMirrorRegion {
            return this._nextRegion;
        }

        public function get previousRegion():TextLineMirrorRegion {
            return this._previousRegion;
        }

        public function get textLine():TextLine {
            return this._textLine;
        }
    }
}
