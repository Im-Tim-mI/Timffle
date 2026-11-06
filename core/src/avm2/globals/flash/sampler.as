// Timffle: Flash Player's release build has no sampler (the memory/CPU profiler only exists
// in the debugger player). The AVM's sampler functions check for it first and, without it,
// do nothing (startSampling, stopSampling, pauseSampling, clearSamples, sampleInternalAllocs,
// setSamplerCallback) and answer as Flash Player 32 release measured
// (timffle/difftest/src/S3Misc.hx): getSampleCount -1, getSize 0, the getInvocationCount
// family -1, getSamples undefined, getMemberNames / getLexicalScopes / getSavedThis /
// getMasterString null, isGetterSetter false.
package flash.sampler {
    public function clearSamples():void {
    }

    public function getGetterInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public function getInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public function getLexicalScopes(fun:Function):Array {
        return null;
    }

    public function getMasterString(str:String):String {
        return null;
    }

    public function getMemberNames(obj:Object, instanceNames:Boolean = false):Object {
        return null;
    }

    public function getSampleCount():Number {
        return -1;
    }

    // Native so the result stays `undefined` (an AS `Object` return would turn it into null).
    public native function getSamples():Object;

    public function getSavedThis(fun:Function):Object {
        return null;
    }

    public function getSetterInvocationCount(obj:Object, name:QName):Number {
        return -1;
    }

    public function getSize(param1:*):Number {
        return 0;
    }

    public function isGetterSetter(obj:Object, name:QName):Boolean {
        return false;
    }

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
