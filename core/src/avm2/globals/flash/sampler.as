// Timffle: Flash Player's release build has no sampler (the memory/CPU profiler only exists
// in the debugger player). The AVM's sampler functions check for it first and, without it,
// do nothing (startSampling, stopSampling, pauseSampling, clearSamples, sampleInternalAllocs,
// setSamplerCallback), count nothing (getSampleCount 0, getSize 0, getInvocationCount family
// -1 = "not counted") and give no samples (getSamples undefined). The reflective functions
// that do not need the profiler are real: getMemberNames, isGetterSetter, getSavedThis and
// getLexicalScopes inspect the object/closure; getMasterString is null because this player
// never shares a string's buffer between a string and its substrings (Flash's "dependent"
// strings), so no string has a master.
package flash.sampler {
    public function clearSamples():void {
    }

    public function getGetterInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public function getInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public native function getLexicalScopes(fun:Function):Array;

    public function getMasterString(str:String):String {
        return null;
    }

    public native function getMemberNames(obj:Object, instanceNames:Boolean = false):Object;

    public function getSampleCount():Number {
        return 0;
    }

    public function getSamples():Object {
        return undefined;
    }

    public native function getSavedThis(fun:Function):Object;

    public function getSetterInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public function getSize(param1:*):Number {
        return 0;
    }

    public native function isGetterSetter(obj:Object, name:QName):Boolean;

    public function pauseSampling():void {
    }

    public function sampleInternalAllocs(everything:Boolean):void {
    }

    public function setSamplerCallback(fun:Function):void {
    }

    public function startSampling():void {
    }

    public function stopSampling():void {
    }
}
