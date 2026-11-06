package flash.display {
    import flash.net.URLRequest;
    import flash.system.LoaderContext;

    // Timffle: AVLoader loads AVStream (HTTP Live Streaming) content, a pipeline
    // that Flash Player does not ship. The real Flash Player 32 (standalone and
    // plug-in) answers `load()` with `Error #2037` (measured with
    // timffle/difftest/src/D51DisplayMisc.hx); everything else is the plain
    // Loader behaviour. This is Flash on a machine without the feature.
    [API("688")]
    public class AVLoader extends Loader {
        override public function load(request:URLRequest, ctx:LoaderContext = null):void {
            Error.throwError(Error, 2037);
        }
    }
}
