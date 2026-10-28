import flash.display.MovieClip;

@:keep class BodyC extends MovieClip {
    public function new() {
        addFrameScript(0, frame1);
        super();
        Test.out("BodyC ctor f=" + Test.f);
    }
    function frame1() {
        Test.out("BodyC frame1 f=" + Test.f);
        stop();
    }
}
