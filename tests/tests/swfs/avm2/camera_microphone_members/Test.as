package {
import flash.display.Sprite;
import flash.utils.getQualifiedClassName;
import flash.media.AudioDeviceManager;
import flash.media.Camera;
import flash.media.Microphone;
import flash.media.MicrophoneEnhancedOptions;
import flash.media.Video;

// Flash Player on a machine without a camera, a microphone or audio output
// device selection: no devices, null device getters, the player-created
// classes cannot be instantiated, and AudioDeviceManager keeps its
// user-invoked-action restriction.
public class Test extends Sprite {
    public function Test() {
        trace("== Camera");
        trace("Camera.isSupported = " + Camera.isSupported);
        trace("Camera.names = " + Camera.names + " (length " + Camera.names.length + ")");
        trace("Camera.names is a new Array each time: " + (Camera.names !== Camera.names));
        trace("Camera.getCamera() = " + Camera.getCamera());
        trace("Camera.getCamera(\"0\") = " + Camera.getCamera("0"));
        try {
            new Camera();
            trace("new Camera() did not throw");
        } catch (e:Error) {
            trace("new Camera() threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        var video:Video = new Video();
        video.attachCamera(Camera.getCamera());
        trace("Video.attachCamera(getCamera()) ok, videoWidth = " + video.videoWidth);

        trace("== Microphone");
        trace("Microphone.isSupported = " + Microphone.isSupported);
        trace("Microphone.names = " + Microphone.names + " (length " + Microphone.names.length + ")");
        trace("Microphone.getMicrophone() = " + Microphone.getMicrophone());
        trace("Microphone.getMicrophone(0) = " + Microphone.getMicrophone(0));
        trace("Microphone.getEnhancedMicrophone() = " + Microphone.getEnhancedMicrophone());
        try {
            new Microphone();
            trace("new Microphone() did not throw");
        } catch (e:Error) {
            trace("new Microphone() threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }

        trace("== MicrophoneEnhancedOptions");
        var options:MicrophoneEnhancedOptions = new MicrophoneEnhancedOptions();
        trace("echoPath = " + options.echoPath);
        trace("isVoiceDetected = " + options.isVoiceDetected);
        trace("mode = " + options.mode);
        trace("nonLinearProcessing = " + options.nonLinearProcessing);
        trace("autoGain = " + options.autoGain);
        options.autoGain = true;
        trace("autoGain after set = " + options.autoGain);

        trace("== AudioDeviceManager");
        trace("AudioDeviceManager.isSupported = " + AudioDeviceManager.isSupported);
        var manager:AudioDeviceManager = AudioDeviceManager.audioDeviceManager;
        trace("audioDeviceManager = " + manager);
        trace("audioDeviceManager is a singleton: " + (AudioDeviceManager.audioDeviceManager === manager));
        trace("deviceNames = " + manager.deviceNames + " (length " + manager.deviceNames.length + ")");
        trace("selectedDeviceIndex = " + manager.selectedDeviceIndex);
        try {
            manager.selectedDeviceIndex = 0;
            trace("set selectedDeviceIndex did not throw");
        } catch (e:Error) {
            trace("set selectedDeviceIndex (no user action) threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        trace("selectedDeviceIndex after set = " + manager.selectedDeviceIndex);
        try {
            new AudioDeviceManager();
            trace("new AudioDeviceManager() did not throw");
        } catch (e:Error) {
            trace("new AudioDeviceManager() threw " + getQualifiedClassName(e) + " #" + e.errorID);
        }
        trace("hasEventListener(audioOutputChange) = " + manager.hasEventListener("audioOutputChange"));
    }
}
}
