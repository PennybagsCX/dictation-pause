// correlation-probe — samples localspeechrecognition presence + default
// OUTPUT device "running somewhere" at 200 ms for 300 s, to map which
// process edge coincides with the native dictation mute (output drop).

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

func outputRunning(_ dev: AudioObjectID) -> Bool {
    guard dev != 0 else { return false }
    var v: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                                       mScope: kAudioObjectPropertyScopeGlobal,
                                       mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(dev, &a, 0, nil, &size, &v) == noErr else { return false }
    return v != 0
}

func speechProcPresent() -> Bool {
    let count = Int(proc_listallpids(nil, 0))
    guard count > 0 else { return false }
    var pids = [pid_t](repeating: 0, count: count + 64)
    let written = proc_listallpids(&pids, Int32(pids.count))
    guard written > 0 else { return false }
    for pid in pids.prefix(Int(written)) where pid > 0 {
        var path = [CChar](repeating: 0, count: 4096)
        let name: String
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            name = String(cString: path).split(separator: "/").last.map(String.init) ?? ""
        } else {
            var n = [CChar](repeating: 0, count: 64)
            proc_name(pid, &n, UInt32(n.count))
            name = String(cString: n)
        }
        if name == "localspeechrecognition" { return true }
    }
    return false
}

let df = DateFormatter()
df.dateFormat = "HH:mm:ss.SSS"
let output = defaultOutput()

var prevSpeech = true
var prevOut = false
for tick in 0..<1500 { // 300 s at 200 ms
    let speech = speechProcPresent()
    let out = outputRunning(output)
    if speech != prevSpeech || out != prevOut || tick % 50 == 0 {
        print("\(df.string(from: Date()))  speech=\(speech ? 1 : 0) output=\(out ? 1 : 0)")
        fflush(stdout)
    }
    prevSpeech = speech
    prevOut = out
    usleep(200_000)
}
print("correlation probe done")
