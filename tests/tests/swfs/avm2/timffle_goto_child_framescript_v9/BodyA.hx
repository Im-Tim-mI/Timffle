import flash.display.MovieClip;

@:keep class BodyA extends MovieClip {
    public function new() {
        addFrameScript(0, frame1);
        super();
        Test.out("BodyA ctor f=" + Test.f);
    }
    function frame1() {
        Test.out("BodyA frame1 f=" + Test.f);
        stop();
    }
}
