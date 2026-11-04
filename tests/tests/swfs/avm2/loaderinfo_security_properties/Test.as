package {
import flash.display.Loader;
import flash.display.LoaderInfo;
import flash.display.Sprite;
import flash.events.Event;
import flash.net.URLRequest;
import flash.system.Security;

// LoaderInfo.sameDomain / childAllowsParent / parentAllowsChild /
// isURLInaccessible, the sandbox bridges, getLoaderInfoByDefinition and
// Security.allowDomain argument checking. The child SWF (Child.as) reports
// its side when it is constructed.
public class Test extends Sprite {
    static var loader:Loader = new Loader();

    public function Test() {
        var self:Test = this;
        trace("--- root loaderInfo");
        dumpTrust("root", this.loaderInfo);
        trace("root.loader: " + this.loaderInfo.loader);
        trace("root.parentSandboxBridge: " + this.loaderInfo.parentSandboxBridge);
        trace("root.childSandboxBridge: " + this.loaderInfo.childSandboxBridge);

        trace("--- Security.allowDomain arguments");
        tryIt("Security.allowDomain('*')", function():void { Security.allowDomain("*"); });
        tryIt("Security.allowInsecureDomain('x.example')", function():void { Security.allowInsecureDomain("x.example"); });
        tryIt("Security.allowDomain(null)", function():void { Security.allowDomain(null); });
        tryIt("Security.allowDomain(1)", function():void { Security.allowDomain(1); });
        tryIt("Security.allowInsecureDomain('a', [])", function():void { Security.allowInsecureDomain("a", []); });

        trace("--- getLoaderInfoByDefinition");
        tryIt("getLoaderInfoByDefinition(this)", function():void {
            trace("result: " + LoaderInfo.getLoaderInfoByDefinition(self));
        });

        trace("--- contentLoaderInfo before load");
        var info:LoaderInfo = loader.contentLoaderInfo;
        tryIt("sameDomain", function():void { trace("sameDomain: " + info.sameDomain); });
        trace("isURLInaccessible: " + info.isURLInaccessible);
        tryIt("parent sets parentSandboxBridge", function():void {
            info.parentSandboxBridge = { greeting: "hello from parent" };
            trace("parentSandboxBridge.greeting: " + info.parentSandboxBridge.greeting);
        });
        tryIt("parent sets childSandboxBridge", function():void {
            info.childSandboxBridge = { oops: true };
        });
        trace("childSandboxBridge: " + info.childSandboxBridge);
        tryIt("root content sets its own parentSandboxBridge", function():void {
            self.loaderInfo.parentSandboxBridge = {};
        });
        tryIt("root content sets its own childSandboxBridge", function():void {
            self.loaderInfo.childSandboxBridge = { fromRoot: true };
            trace("root.childSandboxBridge.fromRoot: " + self.loaderInfo.childSandboxBridge.fromRoot);
        });

        info.addEventListener(Event.COMPLETE, function(e:Event):void {
            trace("--- contentLoaderInfo on complete");
            dumpTrust("child", info);
            trace("childSandboxBridge.reply: " + (info.childSandboxBridge ? info.childSandboxBridge.reply : null));
            tryIt("parent clears parentSandboxBridge", function():void {
                info.parentSandboxBridge = null;
                trace("parentSandboxBridge: " + info.parentSandboxBridge);
            });
            trace("done");
        });
        loader.load(new URLRequest("child.swf"));
        addChild(loader);
    }

    static function dumpTrust(label:String, info:LoaderInfo):void {
        trace(label + ".sameDomain: " + info.sameDomain);
        trace(label + ".childAllowsParent: " + info.childAllowsParent);
        trace(label + ".parentAllowsChild: " + info.parentAllowsChild);
        trace(label + ".isURLInaccessible: " + info.isURLInaccessible);
    }

    static function tryIt(label:String, f:Function):void {
        try {
            f();
            trace(label + ": ok");
        } catch (e:Error) {
            trace(label + ": " + e.name + " #" + e.errorID);
        }
    }
}
}
