package {
    import flash.display.Sprite;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.system.AuthorizedFeaturesLoader;
    import flash.utils.ByteArray;

    public class Test extends Sprite {
        public function Test() {
            var loader:AuthorizedFeaturesLoader = new AuthorizedFeaturesLoader();
            trace("authorizedFeatures: " + loader.authorizedFeatures);
            loader.addEventListener(ErrorEvent.ERROR, function(e:ErrorEvent):void {
                trace("error: " + e.type + " " + e.text + " bubbles=" + e.bubbles + " cancelable=" + e.cancelable);
                trace("authorizedFeatures after: " + loader.authorizedFeatures);
            });
            loader.addEventListener(Event.COMPLETE, function(e:Event):void {
                trace("complete (unexpected)");
            });
            loader.loadAuthorizedFeatures();
            trace("loadAuthorizedFeatures returned synchronously, authorizedFeatures: " + loader.authorizedFeatures);

            try {
                loader.loadAuthorizedFeaturesFromData(null);
            } catch (e:Error) {
                trace("loadAuthorizedFeaturesFromData(null): " + e);
            }
            var data:ByteArray = new ByteArray();
            data.writeUTFBytes("not a token");
            loader.loadAuthorizedFeaturesFromData(data);
            trace("loadAuthorizedFeaturesFromData returned synchronously");
        }
    }
}
