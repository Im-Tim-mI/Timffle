import flash.display.MovieClip;

@:keep class BodyB extends MovieClip {
    public function new() {
        addFrameScript(0, frame1);
        super();
        Test.out("BodyB ctor f=" + Test.f);
    }
    function frame1() {
        Test.out("BodyB frame1 f=" + Test.f);
        stop();
    }
}
