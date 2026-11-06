package flash.sampler {
    import flash.utils.Dictionary;

    // Timffle: a sample of an object allocation. Only the sampler creates these, and this
    // release player has no sampler (see flash/sampler.as), so no instance ever carries an
    // object; the members behave as documented for one that does: `object` is a weak
    // reference (undefined once the object was collected -- or never set), `size` the
    // recorded allocation size.
    public final class NewObjectSample extends Sample {
        public const id:Number;
        public const type:Class;

        // Weak-keyed dictionary holding the sampled object, so the sample does not keep it alive.
        private var _object:Dictionary = new Dictionary(true);
        private var _size:Number = 0;

        public function get object():* {
            for (var key:* in this._object) {
                return key;
            }
            return undefined;
        }

        public function get size():Number {
            return this._size;
        }
    }
}
