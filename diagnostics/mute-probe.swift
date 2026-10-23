// mute-probe — samples the default OUTPUT device's mute flag, volume scalar,
// and running state at 200 ms for 300 s. Goal: determine whether macOS's
// native dictation mute manifests as a device-level mute/volume change
// (which would let us distinguish "dictation over playing media" from
// "dictation with nothing playing").

import CoreAudio
import Foundation

let systemObject = AudioObjectID(kAudioObjectSystemObject)

func defaultOutput() -> AudioObjectID {
    var dev = AudioObjectID(0)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(systemObject, &a, 0, nil, &size, &dev) == noErr else { return 0 }
    return dev
}

func uintProp(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector) -> UInt32 {
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeOutput,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return 999 }
    return v
}

func floatProp(_ dev: AudioObjectID, _ sel: AudioObjectPropertySelector) -> Float32 {
    var v = Float32(-1)
    var size = UInt32(MemoryLayout<Float32>.size)
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeOutput,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return -1 }
    return v
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss.SSS"
let output = defaultOutput()
print("output device: \(output)")

var prev = ""
for tick in 0..<1500 {
    let mute = uintProp(output, kAudioDevicePropertyMute)
    let vol = floatProp(output, kAudioDevicePropertyVolumeScalar)
    var run: UInt32 = 0
    do {
        var size = UInt32(MemoryLayout<UInt32>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                           mScope: kAudioObjectPropertyScopeGlobal,
                                           mElement: kAudioObjectPropertyElementMain)
        _ = AudioObjectGetPropertyData(output, &a, 0, nil, &size, &run)
    }
    let state = "mute=\(mute == 999 ? -1 : Int(mute)) vol=\(vol >= 0 ? String(format: "%.2f", vol) : "?") running=\(run)"
    if state != prev || tick % 50 == 0 {
        print("\(df.string(from: Date()))  \(state)")
        fflush(stdout)
    }
    prev = state
    usleep(200_000)
}
print("mute probe done")
